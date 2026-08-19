import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// «ЖИВ ЛИ ЕЩЁ ИНТЕРФЕЙС» — ДЛЯ ЭЛЕВЕЙТНУТОГО ПОМОЩНИКА TUN.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ НУЖНО. Настоящий kill switch (фильтры WFP) держит
/// элевейтнутый помощник: он живёт столько же, сколько туннель, и его смерть —
/// штатный сигнал снять блокировку. Но помощник не связан с интерфейсом ничем:
/// закройте приложение — и он останется работать, а вместе с ним останется
/// стоять блокировка, которую снять уже некому. Машина без сети.
///
/// ⚠️ ПОЧЕМУ НЕ PID, КАК НАПРАШИВАЕТСЯ. Две причины, обе смертельные.
///  1. **Доставить PID помощнику нечем.** Он запускается задачей Планировщика,
///     а она запекает строку запуска ОДИН РАЗ, при создании
///     (`TunScheduledTask.install`). Номер процесса меняется с каждым запуском
///     приложения — в задаче он был бы от давно умершего.
///  2. **Windows переиспользует номера.** Дождавшись совпадения, помощник начал
///     бы следить за посторонним процессом: либо не выйдет никогда, либо решит,
///     что приложение умерло, и снимет защиту посреди сессии.
///
/// ⚠️ ПОЧЕМУ БРОШЕННЫЙ МЬЮТЕКС, А НЕ «ОБЪЕКТ ИСЧЕЗ». Именованный объект ядра
/// живёт, пока его держит хоть кто-то, — а помощник как раз держит. Ждать его
/// исчезновения бессмысленно: сам наблюдатель и не даст ему исчезнуть.
/// Мьютекс решает это ровно: приложение берёт его во ВЛАДЕНИЕ и не отпускает,
/// а когда владелец умирает — любой ожидающий получает `WAIT_ABANDONED`.
/// Именно «владелец умер», а не «объект пропал».
///
/// ⚠️ ИМЯ РОЖДАЕТСЯ НА СЕССИЮ И ПЕРЕДАЁТСЯ ФАЙЛОМ. В конфиг sing-box его не
/// положить: ядро отвергает конфиг целиком из-за одного незнакомого поля.
/// Поэтому имя пишется отдельным файлом рядом (`TunHelper.aliveFilePathFor`).
abstract final class AppAliveMutex {
  /// Дескриптор, взятый приложением. Ноль — не брали.
  static int _held = 0;

  /// Имя мьютекса этой сессии; пусто — не брали.
  static String _name = '';

  static String get name => _name;
  static bool get isHeld => _held != 0;

  /// ⚠️ ВЗЯТЬ ВО ВЛАДЕНИЕ (`initialOwner = TRUE`) И НЕ ОТПУСКАТЬ.
  ///
  /// Отпущенный мьютекс перестаёт быть признаком жизни: ожидающий немедленно
  /// получит `WAIT_OBJECT_0` и решит, что приложение умерло. Поэтому здесь нет
  /// и не должно быть `ReleaseMutex`, а дескриптор не закрывается — его
  /// закрывает сама Windows, когда процесс кончается. В том числе аварийно:
  /// на этом всё и держится.
  ///
  /// Возвращает имя для помощника; пустая строка — взять не удалось.
  static String acquire() {
    if (!Platform.isWindows) return '';
    if (_held != 0) return _name;
    final token = _token();
    // ⚠️ СНАЧАЛА `Global\`, ПОТОМ `Local\`. Помощник запускается задачей
    // Планировщика и может оказаться в ДРУГОЙ сессии; `Local\` там не виден.
    // Но создание в `Global\` требует привилегии, которой у обычного
    // пользователя может не быть, — поэтому не «или», а «сначала одно».
    for (final prefix in const ['Global\\', 'Local\\']) {
      final full = '$prefix$token';
      final arena = Arena();
      try {
        final h = _createMutex(nullptr, 1, full.toNativeUtf16(allocator: arena));
        if (h != 0) {
          _held = h;
          _name = full;
          return full;
        }
      } catch (_) {
        // Следующий префикс.
      } finally {
        arena.releaseAll();
      }
    }
    return '';
  }

  /// Сторона ПОМОЩНИКА: открыть мьютекс приложения по имени.
  ///
  /// ⚠️ `null` ЗНАЧИТ «ПРИЛОЖЕНИЯ НЕТ», И ЭТО НЕ ПОВОД ПРОДОЛЖАТЬ. Помощник,
  /// не сумевший открыть мьютекс, не имеет права поднимать блокировку: снять
  /// её будет некому. «Не знаю» здесь обязано вести себя как «нельзя».
  static AppAliveWatch? watch(String name) {
    if (!Platform.isWindows || name.isEmpty) return null;
    final arena = Arena();
    try {
      final h = _openMutex(_synchronize, 0, name.toNativeUtf16(allocator: arena));
      return h == 0 ? null : AppAliveWatch._(h);
    } catch (_) {
      return null;
    } finally {
      arena.releaseAll();
    }
  }

  /// Случайное имя сессии. Длины хватает, чтобы совпадение было невозможным на
  /// практике, — в отличие от номера процесса, который система переиспользует.
  /// Имя сессии — открыто для теста: проверить уникальность иначе нечем, а
  /// совпадение имён означало бы слежение за посторонним процессом.
  @visibleForTesting
  static String tokenForTest() => _token();

  static String _token() {
    final r = Random.secure();
    final b = List<int>.generate(12, (_) => r.nextInt(256));
    return 'SilentGateAlive-'
        '${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';
  }

  // ── Связывание ────────────────────────────────────────────────────────────
  static final DynamicLibrary _k32 = DynamicLibrary.open('kernel32.dll');

  static const int _synchronize = 0x00100000;

  static final _createMutex = _k32.lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
      int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');

  static final _openMutex = _k32.lookupFunction<
      IntPtr Function(Uint32, Int32, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>)>('OpenMutexW');

  static final _waitFor = _k32.lookupFunction<
      Uint32 Function(IntPtr, Uint32),
      int Function(int, int)>('WaitForSingleObject');

  static final _closeHandle = _k32.lookupFunction<Int32 Function(IntPtr),
      int Function(int)>('CloseHandle');
}

/// Наблюдение за жизнью интерфейса со стороны помощника.
class AppAliveWatch {
  int _handle;
  AppAliveWatch._(this._handle);

  /// Жив ли ещё интерфейс. Опрашивается без ожидания (таймаут 0), поэтому
  /// вписывается в обычный цикл помощника и ничего не тормозит.
  ///
  /// ⚠️ ЛЮБОЙ ИСХОД, КРОМЕ «ЗАНЯТО», СЧИТАЕМ СМЕРТЬЮ. `WAIT_ABANDONED` —
  /// владелец умер, не отпустив; `WAIT_OBJECT_0` — мьютекс достался нам, то
  /// есть владельца тоже нет (приложение его не отпускает по построению).
  /// Ошибка — состояние неизвестно, и трактовать неизвестность как «жив»
  /// нельзя: это оставило бы блокировку стоять.
  bool get appAlive {
    if (_handle == 0) return false;
    try {
      return AppAliveMutex._waitFor(_handle, 0) == _waitTimeout;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    final h = _handle;
    _handle = 0;
    if (h != 0) {
      try {
        AppAliveMutex._closeHandle(h);
      } catch (_) {}
    }
  }

  /// `WAIT_TIMEOUT` — мьютекс занят владельцем, то есть приложение живо.
  static const int _waitTimeout = 0x00000102;
}
