import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// НАСТОЯЩИЙ kill switch: фильтры Windows Filtering Platform.
///
/// ⚠️ ЗАЧЕМ ОН, ЕСЛИ KILL SWITCH УЖЕ «ЕСТЬ». Существующий ничего не блокирует:
/// он лишь не снимает TUN-адаптер, и пакетам некому ответить. Пока приложение
/// живо, этого хватает. Но стоит ему упасть — Windows снимает адаптер сама,
/// маршрут по умолчанию возвращается на физическую сеть, и трафик туннельных
/// приложений уходит под РЕАЛЬНЫМ адресом. Молча, без строки в журнале. Жалоба
/// владельца 19.08.2026 («kill switch включён, а меня выбивает под реальным
/// IP») упиралась именно в это.
///
/// ⚠️ СВОЙ ДРАЙВЕР НЕ НУЖЕН — проверено по документации Microsoft и исходникам
/// WireGuard for Windows (`tunnel/firewall/rules.go`). Драйверы у других
/// клиентов стоят ради раздельного туннелирования, а не ради блокировки. Права
/// администратора нужны: `FwpmEngineOpen0` откроется и без них (право
/// `FWPM_ACTRL_OPEN` выдано Everyone), а вот добавление объектов вернёт отказ.
/// Поэтому владельцем фильтров задуман ЭЛЕВЕЙТНУТЫЙ ПОМОЩНИК TUN
/// (`TunHelper.run`, задача Планировщика `/RL HIGHEST`), а не процесс
/// интерфейса: он элевейтнут и живёт ровно столько, сколько туннель.
///
/// ⚠️ ТРИ УСЛОВИЯ, ОШИБКА В КОТОРЫХ ОСТАВЛЯЕТ ЧЕЛОВЕКА БЕЗ ИНТЕРНЕТА:
///  1. Сессия ТОЛЬКО динамическая ([_sessionFlagDynamic]). Её объекты снимает
///     сама Windows при смерти процесса, включая аварийную — через RPC rundown.
///     Статическая переживёт крах, и снять её будет некому.
///  2. `FWPM_FILTER_FLAG_PERSISTENT` не использовать НИКОГДА: такой фильтр
///     переживает перезагрузку. У Proton для этого есть служба, у нас нет.
///  3. Слои обязаны включать IPv6. Без него трафик уходит мимо, и защита
///     становится украшением.
///
/// ⚠️ СОСТОЯНИЕ: пока здесь ТОЛЬКО РАЗВЕДКА ([probe]) — она ничего не
/// блокирует. Расстановка правил появится после того, как разведка подтвердит
/// в VM права и связывание. Порядок обратный обычному нарочно: цена ошибки
/// здесь — машина без сети, и «написал, потом проверю» тут не работает.
class KillSwitchWfp {
  /// Что именно разрешаем при поднятой блокировке.
  ///
  /// ⚠️ ЧИСТАЯ ФУНКЦИЯ НАМЕРЕННО: сами вызовы к системе в тестах дёргать
  /// нельзя (фильтры затрагивают сеть всей машины), а состав правил проверить
  /// обязательно — ошибка здесь либо оставляет дыру, либо рубит человеку сеть.
  @visibleForTesting
  static KillSwitchPlan planFor({
    required Set<String> serverIps,
    required List<String> tunnelAppPaths,
    required bool blockEverything,
  }) =>
      KillSwitchPlan(
        // ⚠️ Адреса серверов — всегда. Иначе туннель не поднимется заново:
        // ядру некуда будет постучаться, и блокировка станет вечной.
        allowServerIps: {...serverIps},
        // ⚠️ Свои бинари разрешаем ВСЕГДА, даже блокируя всё. Иначе приложение
        // не сможет ни проверить канал, ни обновить подписку, ни объяснить
        // человеку, что происходит: мёртвая сеть и молчащее окно.
        allowOwnBinaries: true,
        allowLoopback: true,
        allowLan: true,
        allowDhcpAndNdp: true,
        // Школа Mullvad (решение владельца 19.08.2026): исключения из туннеля
        // остаются исключениями и из блокировки. Режем либо всё, либо только
        // те приложения, что шли через VPN.
        blockedAppPaths: blockEverything ? const [] : List.of(tunnelAppPaths),
        blockAll: blockEverything,
      );

  /// РАЗВЕДКА: можно ли на этой машине ставить фильтры — без блокировки.
  ///
  /// Открывает динамическую сессию, начинает транзакцию, добавляет ПОДСЛОЙ
  /// (сам по себе он ничего не фильтрует) и **откатывает транзакцию**. То есть
  /// проверяются ровно те права, что нужны настоящим фильтрам, а система
  /// остаётся нетронутой.
  ///
  /// ⚠️ Служба авторизации перебирается, а не задаётся догадкой: разведка
  /// 19.08.2026 наткнулась на расхождение — один и тот же вызов на одной
  /// машине дал успех при `RPC_C_AUTHN_WINNT` и `ERROR_NOT_SUPPORTED` (50) при
  /// других значениях. Пусть отвечает машина, а не предположение.
  static KillSwitchProbe probe() {
    if (!Platform.isWindows) {
      return const KillSwitchProbe(canFilter: false, detail: 'не Windows');
    }
    final tried = <String>[];
    for (final authn in _authnCandidates) {
      final r = _probeWith(authn);
      tried.add('${authn.name}: ${r.detail}');
      if (r.canFilter) {
        return KillSwitchProbe(
          canFilter: true,
          authnService: authn.value,
          detail: 'права есть (${authn.name})',
        );
      }
    }
    return KillSwitchProbe(
      canFilter: false,
      detail: 'права не получены — ${tried.join('; ')}',
    );
  }

  static KillSwitchProbe _probeWith(_Authn authn) {
    final arena = Arena();
    Pointer<Void> engine = nullptr;
    try {
      final handle = arena<Pointer<Void>>();
      final session = arena<_FwpmSession0>();
      // ⚠️ ЕДИНСТВЕННЫЙ допустимый флаг. См. условие 1 в описании класса.
      session.ref.flags = _sessionFlagDynamic;

      var rc = _engineOpen(nullptr, authn.value, nullptr, session, handle);
      if (rc != 0) return KillSwitchProbe(canFilter: false, detail: 'open=$rc');
      engine = handle.value;

      rc = _txnBegin(engine, 0);
      if (rc != 0) return KillSwitchProbe(canFilter: false, detail: 'txn=$rc');

      // Подслой — самый дешёвый объект, требующий тех же прав, что и фильтр,
      // и НЕ влияющий на трафик сам по себе.
      final sub = arena<_FwpmSubLayer0>();
      sub.ref.keyData1 = _subLayerKeyData1;
      sub.ref.keyData2 = _subLayerKeyData2;
      sub.ref.keyData3 = _subLayerKeyData3;
      sub.ref.keyData4 = _subLayerKeyData4;
      sub.ref.displayName = _wide(arena, 'SilentGate kill switch (проверка)');
      sub.ref.weight = 0xFFFF;
      rc = _subLayerAdd(engine, sub, nullptr);

      // ⚠️ ОТКАТ В ЛЮБОМ СЛУЧАЕ: разведка не имеет права оставить после себя
      // ни одного объекта. Даже безобидный подслой — это след в системе.
      _txnAbort(engine);

      if (rc != 0) {
        return KillSwitchProbe(canFilter: false, detail: 'add=$rc');
      }
      return const KillSwitchProbe(canFilter: true, detail: 'ok');
    } catch (e) {
      return KillSwitchProbe(canFilter: false, detail: 'исключение: $e');
    } finally {
      if (engine != nullptr) _engineClose(engine);
      arena.releaseAll();
    }
  }

  static Pointer<Utf16> _wide(Arena arena, String s) =>
      s.toNativeUtf16(allocator: arena);

  // ── Связывание с fwpuclnt.dll ──────────────────────────────────────────────
  static final DynamicLibrary _fwp = DynamicLibrary.open('fwpuclnt.dll');

  static const int _sessionFlagDynamic = 0x00000001;

  /// Кандидаты службы авторизации: WinNT, «по умолчанию», без авторизации.
  static const _authnCandidates = <_Authn>[
    _Authn('RPC_C_AUTHN_WINNT', 10),
    _Authn('RPC_C_AUTHN_DEFAULT', 0xFFFFFFFF),
    _Authn('RPC_C_AUTHN_NONE', 0),
  ];

  // GUID подслоя разведки. Значение произвольное, но постоянное: так его
  // видно в `netsh wfp show state`, если он вдруг где-то останется.
  static const _subLayerKeyData1 = 0x5115AE47;
  static const _subLayerKeyData2 = 0x7A11;
  static const _subLayerKeyData3 = 0x4C21;
  static const _subLayerKeyData4 = 0x9E5D3A0B7C614F82;

  static final _engineOpen = _fwp.lookupFunction<
      Uint32 Function(Pointer<Utf16>, Uint32, Pointer<Void>,
          Pointer<_FwpmSession0>, Pointer<Pointer<Void>>),
      int Function(Pointer<Utf16>, int, Pointer<Void>, Pointer<_FwpmSession0>,
          Pointer<Pointer<Void>>)>('FwpmEngineOpen0');

  static final _engineClose = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('FwpmEngineClose0');

  static final _txnBegin = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('FwpmTransactionBegin0');

  static final _txnAbort = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('FwpmTransactionAbort0');

  static final _subLayerAdd = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<_FwpmSubLayer0>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<_FwpmSubLayer0>,
          Pointer<Void>)>('FwpmSubLayerAdd0');
}

/// Служба авторизации RPC для открытия движка фильтров.
class _Authn {
  final String name;
  final int value;
  const _Authn(this.name, this.value);
}

/// Итог разведки: можно ли на этой машине ставить фильтры.
class KillSwitchProbe {
  /// Удалось ли добавить объект (транзакция при этом откачена).
  final bool canFilter;

  /// Служба авторизации, на которой получилось. Пригодится боевому коду.
  final int? authnService;

  /// Человеческое пояснение с кодами возврата — для журнала.
  final String detail;

  const KillSwitchProbe({
    required this.canFilter,
    required this.detail,
    this.authnService,
  });

  @override
  String toString() => canFilter
      ? 'фильтры доступны: $detail'
      : 'фильтры недоступны: $detail';
}

/// Состав блокировки: что разрешено, что закрыто.
class KillSwitchPlan {
  final Set<String> allowServerIps;
  final bool allowOwnBinaries;
  final bool allowLoopback;
  final bool allowLan;
  final bool allowDhcpAndNdp;

  /// Пути приложений, которым закрываем сеть (режим «только отмеченные»).
  final List<String> blockedAppPaths;

  /// Блокировать всё подряд (режимы «Всё через VPN» и «кроме отмеченных»).
  final bool blockAll;

  const KillSwitchPlan({
    required this.allowServerIps,
    required this.allowOwnBinaries,
    required this.allowLoopback,
    required this.allowLan,
    required this.allowDhcpAndNdp,
    required this.blockedAppPaths,
    required this.blockAll,
  });

  /// Есть ли что блокировать вообще.
  bool get isEmpty => !blockAll && blockedAppPaths.isEmpty;
}

/// `FWPM_SESSION0`. Раскладка под x64; заполняем только флаги, остальное нулями.
///
/// ⚠️ Порядок и размеры полей — не украшение: ошибка сдвинет `flags`, сессия
/// окажется СТАТИЧЕСКОЙ, и её объекты переживут смерть процесса.
final class _FwpmSession0 extends Struct {
  @Uint32()
  external int keyData1;
  @Uint16()
  external int keyData2;
  @Uint16()
  external int keyData3;
  @Uint64()
  external int keyData4;

  external Pointer<Utf16> displayName;
  external Pointer<Utf16> displayDescription;

  @Uint32()
  external int flags;
  @Uint32()
  external int txnWaitTimeoutInMSec;
  @Uint32()
  external int processId;
  @Uint32()
  external int padA; // выравнивание x64, не удалять

  external Pointer<Void> sid;
  external Pointer<Utf16> username;

  @Int32()
  external int kernelMode;
  @Int32()
  external int padB; // выравнивание x64, не удалять
}

/// `FWPM_SUBLAYER0` — используется только разведкой и откатывается.
final class _FwpmSubLayer0 extends Struct {
  @Uint32()
  external int keyData1;
  @Uint16()
  external int keyData2;
  @Uint16()
  external int keyData3;
  @Uint64()
  external int keyData4;

  external Pointer<Utf16> displayName;
  external Pointer<Utf16> displayDescription;

  @Uint32()
  external int flags;
  @Uint32()
  external int padA; // выравнивание x64, не удалять

  external Pointer<Void> providerKey;

  @Uint64()
  external int providerDataSize;
  external Pointer<Void> providerData;

  @Uint16()
  external int weight;
  @Uint16()
  external int padB; // выравнивание x64, не удалять
  @Uint32()
  external int padC; // выравнивание x64, не удалять
}
