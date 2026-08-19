/// НАСТОЯЩИЙ kill switch: фильтры Windows Filtering Platform.
///
/// ⚠️ ЗАЧЕМ ОН, ЕСЛИ KILL SWITCH УЖЕ «ЕСТЬ». Существующий ничего не блокирует:
/// он лишь не снимает TUN-адаптер, и пакетам некому ответить. Пока приложение
/// живо, этого хватает. Но стоит ЯДРУ умереть само — адаптер исчезает вместе с
/// ним, маршрут по умолчанию возвращается на физическую сеть, и трафик
/// туннельных приложений уходит под РЕАЛЬНЫМ адресом. Молча, без строки в
/// журнале. Жалоба владельца 19.08.2026 («kill switch включён, а меня выбивает
/// под реальным IP») упиралась именно в это.
///
/// ⚠️ СВОЙ ДРАЙВЕР НЕ НУЖЕН — проверено по документации Microsoft и исходникам
/// WireGuard for Windows (`tunnel/firewall/rules.go`). Драйверы у других
/// клиентов стоят ради раздельного туннелирования, а не ради блокировки. Права
/// администратора нужны: `FwpmEngineOpen0` откроется и без них (право
/// `FWPM_ACTRL_OPEN` выдано Everyone), а вот добавление объектов вернёт отказ.
///
/// ⚠️ ТРИ УСЛОВИЯ, ОШИБКА В КОТОРЫХ ОСТАВЛЯЕТ ЧЕЛОВЕКА БЕЗ ИНТЕРНЕТА:
///  1. Сессия ТОЛЬКО динамическая ([WfpConst.sessionFlagDynamic]). Её объекты
///     снимает сама Windows при смерти процесса, включая аварийную — через RPC
///     rundown. Статическая переживёт крах, и снять её будет некому.
///  2. `FWPM_FILTER_FLAG_PERSISTENT` не использовать НИКОГДА: такой фильтр
///     переживает перезагрузку. У Proton для этого есть служба, у нас нет.
///     ⚠️ Его значение РАВНО значению флага динамической сессии — обе единицы;
///     см. [WfpConst.filterFlagPersistent].
///  3. Слои обязаны включать IPv6. Без него трафик уходит мимо, и защита
///     становится украшением.
///
/// ⚠️ ЛИБО ВЕСЬ ПЛАН, ЛИБО НИЧЕГО. Любая осечка при постановке правил
/// откатывает транзакцию целиком. Наполовину поднятая блокировка — это ровно то
/// обещание без исполнения, на которое владелец и жаловался: интерфейс говорит
/// «защищено», а дыра открыта.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'wfp_layout.dart';
import 'wfp_rules.dart';

export 'wfp_rules.dart' show KillSwitchPlan;

class KillSwitchWfp {
  /// Что именно разрешаем при поднятой блокировке.
  ///
  /// ⚠️ ЧИСТАЯ ФУНКЦИЯ НАМЕРЕННО: сами вызовы к системе в тестах дёргать
  /// нельзя (фильтры затрагивают сеть всей машины), а состав правил проверить
  /// обязательно — ошибка здесь либо оставляет дыру, либо рубит человеку сеть.
  static KillSwitchPlan planFor({
    required Set<String> serverIps,
    required List<String> tunnelAppPaths,
    required bool blockEverything,
    List<String> ownBinaryPaths = const [],
    bool allowLan = true,
    int? tunnelInterfaceLuid,
  }) =>
      KillSwitchPlan(
        allowServerIps: {...serverIps},
        allowOwnBinaries: true,
        ownBinaryPaths: ownBinaryPaths,
        allowLoopback: true,
        allowLan: allowLan,
        tunnelInterfaceLuid: tunnelInterfaceLuid,
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

  /// ПОДНЯТЬ БЛОКИРОВКУ. Возвращает держатель: **пока он жив, фильтры стоят**.
  ///
  /// ⚠️ ФИЛЬТРЫ ЖИВУТ РОВНО СТОЛЬКО, СКОЛЬКО ОТКРЫТ ДЕСКРИПТОР ДВИЖКА. Это не
  /// побочный эффект, а несущая конструкция: сессия динамическая, поэтому и
  /// закрытие дескриптора, и смерть процесса — включая аварийную — снимают всё
  /// без нашего участия. Ничего «прибирать за собой при выходе» не нужно, и
  /// полагаться на такую приборку было бы нельзя.
  ///
  /// Возвращает `null`, если поднять не удалось; причина — в [KillSwitchProbe]
  /// внутри результата разведки и в тексте исключения.
  static KillSwitchHold? engage(KillSwitchPlan plan, {void Function(String)? log}) {
    void say(String s) => log?.call(s);
    if (!Platform.isWindows) {
      say('kill switch: не Windows, блокировка не ставится');
      return null;
    }
    final rules = buildWfpRules(plan);
    if (rules.isEmpty) {
      say('kill switch: блокировать нечего — систему не трогаем');
      return null;
    }

    final probeResult = probe();
    if (!probeResult.canFilter) {
      say('kill switch: $probeResult');
      return null;
    }

    final arena = Arena();
    final blobs = <Pointer<Pointer<Void>>>[];
    Pointer<Void> engine = nullptr;
    var committed = false;
    try {
      final handle = arena<Pointer<Void>>();
      final session = _zeroed(arena, WfpSessionOffsets.size);
      _W(session, WfpSessionOffsets.size)
        ..u32(WfpSessionOffsets.flags, WfpConst.sessionFlagDynamic)
        ..ptr(WfpSessionOffsets.displayData,
            'SilentGate kill switch'.toNativeUtf16(allocator: arena));

      var rc = _engineOpen(
          nullptr, probeResult.authnService!, nullptr, session, handle);
      if (rc != 0) {
        say('kill switch: движок не открылся, код $rc');
        return null;
      }
      engine = handle.value;

      rc = _txnBegin(engine, 0);
      if (rc != 0) {
        say('kill switch: транзакция не началась, код $rc');
        return null;
      }

      // Свой подслой с наибольшим весом: внутри него решают наши веса, а
      // снаружи он не спорит с чужими правилами — каждый подслой выносит свой
      // вердикт, и запрет любого из них перевешивает чужое разрешение.
      final sub = _zeroed(arena, WfpSubLayerOffsets.size);
      _W(sub, WfpSubLayerOffsets.size)
        ..guid(WfpSubLayerOffsets.subLayerKey, _subLayerKey)
        ..ptr(WfpSubLayerOffsets.displayData,
            'SilentGate kill switch'.toNativeUtf16(allocator: arena))
        ..u16(WfpSubLayerOffsets.weight, 0xFFFF);
      rc = _subLayerAdd(engine, sub, nullptr);
      if (rc != 0) {
        say('kill switch: подслой не создан, код $rc');
        return null;
      }

      final ids = <int>[];
      for (final rule in rules) {
        for (final layer in rule.layers) {
          final code = _addFilter(arena, engine, rule, layer, blobs, ids);
          if (code != 0) {
            // ⚠️ ЛИБО ВЕСЬ ПЛАН, ЛИБО НИЧЕГО: половина правил — это дыра,
            // выдающая себя за защиту.
            say('kill switch: правило «${rule.name}» отвергнуто, код $code — '
                'откатываю всё');
            return null;
          }
        }
      }

      rc = _txnCommit(engine);
      if (rc != 0) {
        say('kill switch: транзакция не применилась, код $rc');
        return null;
      }
      committed = true;
      say('kill switch поднят: правил ${rules.length}, фильтров ${ids.length}');
      final hold = KillSwitchHold._(engine, ids, rules.length);
      engine = nullptr; // держатель забрал владение
      return hold;
    } catch (e) {
      say('kill switch: исключение при подъёме — $e');
      return null;
    } finally {
      // ⚠️ ОТКАТ ДО ЗАКРЫТИЯ ДВИЖКА. Незакрытая транзакция при закрытии
      // дескриптора и так пропадёт, но откат явный — чтобы причина сбоя не
      // зависела от того, что решит сделать RPC-слой.
      if (!committed && engine != nullptr) {
        try {
          _txnAbort(engine);
        } catch (_) {}
      }
      for (final b in blobs) {
        try {
          _freeMemory(b);
        } catch (_) {}
      }
      if (engine != nullptr) _engineClose(engine);
      arena.releaseAll();
    }
  }

  /// Поставить один фильтр. Возвращает код возврата WFP (0 — успех).
  static int _addFilter(
    Arena arena,
    Pointer<Void> engine,
    WfpRule rule,
    WfpGuid layer,
    List<Pointer<Pointer<Void>>> blobs,
    List<int> ids,
  ) {
    final conds = rule.conditions;
    final condArray = conds.isEmpty
        ? nullptr
        : _zeroed(arena, WfpConditionOffsets.size * conds.length);

    for (var i = 0; i < conds.length; i++) {
      final c = conds[i];
      final base = WfpConditionOffsets.size * i;
      final w = _W(condArray, WfpConditionOffsets.size * conds.length)
        ..guid(base + WfpConditionOffsets.fieldKey, c.field)
        ..u32(base + WfpConditionOffsets.matchType, c.matchType);
      final valueAt = base + WfpConditionOffsets.conditionValue;

      switch (c.kind) {
        case WfpValueKind.appId:
          final out = arena<Pointer<Void>>();
          final rc = _getAppId(c.path.toNativeUtf16(allocator: arena), out);
          if (rc != 0) return rc;
          blobs.add(out);
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeByteBlob)
            ..ptr(valueAt + WfpValueOffsets.value, out.value);
        case WfpValueKind.v4Net:
          // ⚠️ АДРЕС И МАСКА — В ХОЗЯЙСКОМ ПОРЯДКЕ БАЙТ, не в сетевом. Это
          // требование самого WFP; записав сетевой порядок, получишь валидный
          // фильтр на совершенно другую подсеть.
          final m = _zeroed(arena, WfpConst.v4AddrAndMaskSize);
          final addr = (c.bytes[0] << 24) |
              (c.bytes[1] << 16) |
              (c.bytes[2] << 8) |
              c.bytes[3];
          final mask = c.number == 0
              ? 0
              : (0xFFFFFFFF << (32 - c.number)) & 0xFFFFFFFF;
          _W(m, WfpConst.v4AddrAndMaskSize)
            ..u32(0, addr & mask)
            ..u32(4, mask);
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeV4AddrMask)
            ..ptr(valueAt + WfpValueOffsets.value, m);
        case WfpValueKind.v6Net:
          // ⚠️ Структура УПАКОВАНА: 16 байт адреса + 1 байт длины префикса.
          final m = _zeroed(arena, WfpConst.v6AddrAndMaskSize);
          _W(m, WfpConst.v6AddrAndMaskSize)
            ..bytes(0, c.bytes)
            ..u8(16, c.number);
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeV6AddrMask)
            ..ptr(valueAt + WfpValueOffsets.value, m);
        case WfpValueKind.u64:
          // ⚠️ 64-битное значение лежит ПО УКАЗАТЕЛЮ (`UINT64 *uint64` в
          // объединении), в отличие от 8/16/32-битных, которые по значению.
          // Сверено с заголовком SDK `fwptypes.h`.
          final v = _zeroed(arena, 8);
          _W(v, 8).u64(0, c.number);
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeUint64)
            ..ptr(valueAt + WfpValueOffsets.value, v);
        case WfpValueKind.u32:
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeUint32)
            ..u32(valueAt + WfpValueOffsets.value, c.number);
        case WfpValueKind.u16:
          // Порт или тип ICMP. 8/16/32-битные значения лежат ПО ЗНАЧЕНИЮ, в
          // отличие от 64-битного, — см. объединение в `fwptypes.h`.
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeUint16)
            ..u16(valueAt + WfpValueOffsets.value, c.number);
        case WfpValueKind.u8:
          w
            ..u32(valueAt + WfpValueOffsets.type, WfpConst.typeUint8)
            ..u8(valueAt + WfpValueOffsets.value, c.number);
      }
    }

    final f = _zeroed(arena, WfpFilterOffsets.size);
    _W(f, WfpFilterOffsets.size)
      ..ptr(WfpFilterOffsets.displayData,
          rule.name.toNativeUtf16(allocator: arena))
      ..guid(WfpFilterOffsets.layerKey, layer)
      ..guid(WfpFilterOffsets.subLayerKey, _subLayerKey)
      ..u32(WfpFilterOffsets.weight + WfpValueOffsets.type, WfpConst.typeUint8)
      ..u64(WfpFilterOffsets.weight + WfpValueOffsets.value, rule.weight)
      ..u32(WfpFilterOffsets.numFilterConditions, conds.length)
      ..ptr(WfpFilterOffsets.filterCondition, condArray)
      ..u32(WfpFilterOffsets.action + WfpActionOffsets.type, rule.action);
    // ⚠️ Поле flags остаётся НУЛЁМ. Именно здесь жил бы
    // `FWPM_FILTER_FLAG_PERSISTENT`, переживающий перезагрузку.

    // ⚠️ НОМЕР ФИЛЬТРА ЗАПОМИНАЕМ ОБЯЗАТЕЛЬНО. Без него набор нельзя заменить
    // на месте, а заменять придётся: адаптер туннеля появляется ПОЗЖЕ подъёма
    // блокировки, и разрешение по его LUID дописывается вторым заходом.
    final idOut = arena<Uint64>();
    final rc = _filterAdd(engine, f, nullptr, idOut);
    if (rc == 0) ids.add(idOut.value);
    return rc;
  }

  static KillSwitchProbe _probeWith(_Authn authn) {
    final arena = Arena();
    Pointer<Void> engine = nullptr;
    try {
      final handle = arena<Pointer<Void>>();
      final session = _zeroed(arena, WfpSessionOffsets.size);
      // ⚠️ ЕДИНСТВЕННЫЙ допустимый флаг. См. условие 1 в описании библиотеки.
      _W(session, WfpSessionOffsets.size)
          .u32(WfpSessionOffsets.flags, WfpConst.sessionFlagDynamic);

      var rc = _engineOpen(nullptr, authn.value, nullptr, session, handle);
      if (rc != 0) return KillSwitchProbe(canFilter: false, detail: 'open=$rc');
      engine = handle.value;

      rc = _txnBegin(engine, 0);
      if (rc != 0) return KillSwitchProbe(canFilter: false, detail: 'txn=$rc');

      // Подслой — самый дешёвый объект, требующий тех же прав, что и фильтр,
      // и НЕ влияющий на трафик сам по себе.
      final sub = _zeroed(arena, WfpSubLayerOffsets.size);
      _W(sub, WfpSubLayerOffsets.size)
        ..guid(WfpSubLayerOffsets.subLayerKey, _probeSubLayerKey)
        ..ptr(WfpSubLayerOffsets.displayData,
            'SilentGate kill switch (проверка)'.toNativeUtf16(allocator: arena))
        ..u16(WfpSubLayerOffsets.weight, 0xFFFF);
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

  static Pointer<Uint8> _zeroed(Arena arena, int bytes) {
    final p = arena<Uint8>(bytes);
    p.asTypedList(bytes).fillRange(0, bytes, 0);
    return p;
  }

  // ── Связывание с fwpuclnt.dll ──────────────────────────────────────────────
  static final DynamicLibrary _fwp = DynamicLibrary.open('fwpuclnt.dll');

  /// Кандидаты службы авторизации: WinNT, «по умолчанию», без авторизации.
  static const _authnCandidates = <_Authn>[
    _Authn('RPC_C_AUTHN_WINNT', 10),
    _Authn('RPC_C_AUTHN_DEFAULT', 0xFFFFFFFF),
    _Authn('RPC_C_AUTHN_NONE', 0),
  ];

  /// Подслой боевой блокировки. Значение постоянное, чтобы его было видно в
  /// `netsh wfp show state`, если он вдруг где-то останется.
  static const _subLayerKey = WfpGuid(0x5115AE47, 0x7A11, 0x4C20,
      [0x9E, 0x5D, 0x3A, 0x0B, 0x7C, 0x61, 0x4F, 0x81]);

  /// ⚠️ Подслой разведки — ОТДЕЛЬНЫЙ. Общий ключ означал бы, что разведка,
  /// запущенная при поднятой блокировке, наткнётся на «уже существует» и
  /// доложит об отсутствии прав.
  static const _probeSubLayerKey = WfpGuid(0x5115AE47, 0x7A11, 0x4C21,
      [0x9E, 0x5D, 0x3A, 0x0B, 0x7C, 0x61, 0x4F, 0x82]);

  static final _engineOpen = _fwp.lookupFunction<
      Uint32 Function(Pointer<Utf16>, Uint32, Pointer<Void>, Pointer<Uint8>,
          Pointer<Pointer<Void>>),
      int Function(Pointer<Utf16>, int, Pointer<Void>, Pointer<Uint8>,
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

  static final _txnCommit = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('FwpmTransactionCommit0');

  static final _subLayerAdd = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>,
          Pointer<Void>)>('FwpmSubLayerAdd0');

  static final _filterAdd = _fwp.lookupFunction<
      Uint32 Function(
          Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Uint64>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>,
          Pointer<Uint64>)>('FwpmFilterAdd0');

  static final _filterDeleteById = _fwp.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('FwpmFilterDeleteById0');

  static final _getAppId = _fwp.lookupFunction<
      Uint32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>),
      int Function(Pointer<Utf16>,
          Pointer<Pointer<Void>>)>('FwpmGetAppIdFromFileName0');

  static final _freeMemory = _fwp.lookupFunction<
      Void Function(Pointer<Pointer<Void>>),
      void Function(Pointer<Pointer<Void>>)>('FwpmFreeMemory0');
}

/// Держатель поднятой блокировки.
///
/// ⚠️ ЖИВ ДЕРЖАТЕЛЬ — СТОЯТ ФИЛЬТРЫ. Освободить их можно только двумя
/// способами: вызвать [release] или дать процессу умереть. Второй способ
/// работает и при аварийном крахе, и это единственная причина, по которой
/// блокировку вообще можно доверить пользовательскому процессу.
class KillSwitchHold {
  Pointer<Void> _engine;

  /// Номера поставленных фильтров — нужны, чтобы заменить набор на месте.
  List<int> _ids;
  int _rules;
  var _released = false;

  KillSwitchHold._(this._engine, this._ids, this._rules);

  int get filtersInstalled => _ids.length;
  int get rulesInstalled => _rules;
  bool get isActive => !_released;

  /// ЗАМЕНИТЬ НАБОР ПРАВИЛ, НЕ ОПУСКАЯ БЛОКИРОВКУ.
  ///
  /// ⚠️ РАДИ ЧЕГО ЭТО ВООБЩЕ ЕСТЬ. Адаптера туннеля в момент первого подъёма
  /// НЕ СУЩЕСТВУЕТ — его создаёт ядро, которое ещё не запущено, и LUID взять
  /// неоткуда. Значит правило «пропускать всё, что идёт в туннель» физически
  /// нельзя поставить сразу: сначала поднимается базовый набор (блок + свои
  /// бинари + адреса серверов + loopback + DHCP), а когда туннель поднялся —
  /// набор заменяется на полный. И заменяется он при КАЖДОМ пересоздании
  /// туннеля: LUID новый каждый раз.
  ///
  /// ⚠️ ОДНОЙ ТРАНЗАКЦИЕЙ, А НЕ «СНЯТЬ, ПОТОМ ПОСТАВИТЬ». Два отдельных
  /// применения дали бы окно, в котором блокировки нет вовсе, — то есть ровно
  /// утечку, ради предотвращения которой всё и затевалось.
  bool reengage(KillSwitchPlan plan, {void Function(String)? log}) {
    void say(String s) => log?.call(s);
    if (_released || _engine == nullptr) {
      say('kill switch: замена набора невозможна — блокировка уже снята');
      return false;
    }
    final rules = buildWfpRules(plan);
    if (rules.isEmpty) {
      say('kill switch: пустой набор не заменяет собой поднятую блокировку');
      return false;
    }

    final arena = Arena();
    final blobs = <Pointer<Pointer<Void>>>[];
    var committed = false;
    try {
      var rc = KillSwitchWfp._txnBegin(_engine, 0);
      if (rc != 0) {
        say('kill switch: транзакция замены не началась, код $rc');
        return false;
      }
      for (final id in _ids) {
        // Осечка удаления не смертельна: лишний фильтр из прежнего набора
        // только строже. А вот бросать транзакцию из-за неё — значит остаться
        // со старым набором и без разрешения для туннеля.
        KillSwitchWfp._filterDeleteById(_engine, id);
      }
      final ids = <int>[];
      for (final rule in rules) {
        for (final layer in rule.layers) {
          final code =
              KillSwitchWfp._addFilter(arena, _engine, rule, layer, blobs, ids);
          if (code != 0) {
            say('kill switch: при замене отвергнуто «${rule.name}», код $code '
                '— откатываю, остаётся прежний набор');
            return false;
          }
        }
      }
      rc = KillSwitchWfp._txnCommit(_engine);
      if (rc != 0) {
        say('kill switch: замена не применилась, код $rc');
        return false;
      }
      committed = true;
      _ids = ids;
      _rules = rules.length;
      say('kill switch обновлён: правил ${rules.length}, фильтров ${ids.length}');
      return true;
    } catch (e) {
      say('kill switch: исключение при замене набора — $e');
      return false;
    } finally {
      if (!committed) {
        try {
          KillSwitchWfp._txnAbort(_engine);
        } catch (_) {}
      }
      for (final b in blobs) {
        try {
          KillSwitchWfp._freeMemory(b);
        } catch (_) {}
      }
      arena.releaseAll();
    }
  }

  /// Снять блокировку. Повторный вызов безопасен.
  void release() {
    if (_released) return;
    _released = true;
    final e = _engine;
    _engine = nullptr;
    if (e != nullptr) {
      try {
        KillSwitchWfp._engineClose(e);
      } catch (_) {}
    }
  }

  @override
  String toString() => 'kill switch ${_released ? 'снят' : 'держит'}: '
      'правил $_rules, фильтров ${_ids.length}';
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

  /// Служба авторизации, на которой получилось. Нужна боевому подъёму.
  final int? authnService;

  /// Человеческое пояснение с кодами возврата — для журнала.
  final String detail;

  const KillSwitchProbe({
    required this.canFilter,
    required this.detail,
    this.authnService,
  });

  @override
  String toString() =>
      canFilter ? 'фильтры доступны: $detail' : 'фильтры недоступны: $detail';
}

/// Запись полей по ПРОВЕРЕННЫМ смещениям.
///
/// ⚠️ ПОЧЕМУ НЕ `Struct` ИЗ dart:ffi. У GUID выравнивание 4, а не 8, и внутри
/// `FWPM_ACTION0` он лежит по смещению, не кратному восьми. Описав его полем
/// `Uint64` (как напрашивается), Dart выровнял бы структуру по 8 — и раскладка
/// разъехалась бы с ядром молча. Смещения взяты у компилятора
/// (`tools/wfp/wfp_layout_probe.c`) и стережутся тестом.
class _W {
  final ByteData _bd;
  _W(Pointer<Uint8> p, int len) : _bd = ByteData.sublistView(p.asTypedList(len));

  void u8(int off, int v) => _bd.setUint8(off, v);
  void u16(int off, int v) => _bd.setUint16(off, v, Endian.little);
  void u32(int off, int v) => _bd.setUint32(off, v, Endian.little);
  void u64(int off, int v) => _bd.setUint64(off, v, Endian.little);
  void ptr(int off, Pointer<NativeType> p) =>
      _bd.setUint64(off, p.address, Endian.little);

  void bytes(int off, List<int> b) {
    for (var i = 0; i < b.length; i++) {
      _bd.setUint8(off + i, b[i]);
    }
  }

  void guid(int off, WfpGuid g) {
    _bd.setUint32(off, g.d1, Endian.little);
    _bd.setUint16(off + 4, g.d2, Endian.little);
    _bd.setUint16(off + 6, g.d3, Endian.little);
    bytes(off + 8, g.d4);
  }
}
