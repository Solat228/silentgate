import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'app_env.dart';
import 'app_log.dart';
import 'app_paths.dart';

typedef _CreateMutexWC = IntPtr Function(
    Pointer<Void> attrs, Int32 initialOwner, Pointer<Utf16> name);
typedef _CreateMutexW = int Function(
    Pointer<Void> attrs, int initialOwner, Pointer<Utf16> name);

/// ИМЕНОВАННЫЙ МЬЮТЕКС — ЕДИНСТВЕННЫЙ СПОСОБ ДЛЯ УСТАНОВЩИКА УЗНАТЬ, ЧТО
/// ПРИЛОЖЕНИЕ ЗАПУЩЕНО.
///
/// ⚠️ ЭТО НЕ ТЕОРИЯ, А РАЗБОР ЖИВОГО ПРОГОНА (16.08.2026, VM `SG-Test`).
/// Обновление поверх ЗАПУЩЕННОГО приложения проваливалось: `SilentGateSetup`
/// возвращал код 5, версия на диске оставалась прежней, в списке программ —
/// прежней, и никакого внятного объяснения человек не получал. Причина
/// прозаична: `silentgate.exe` держит собственный образ открытым, заменить его
/// нельзя. А приложение с треем почти всегда запущено — ради трея его и делали,
/// то есть отказ приходился на САМЫЙ ЧАСТЫЙ сценарий обновления.
///
/// ⚠️ ПОЧЕМУ НЕ ХВАТИЛО ВСТРОЕННОГО МЕХАНИЗМА INNO. `CloseApplications` (Restart
/// Manager) закрывает приложение, посылая окну `WM_CLOSE`. У нас на `WM_CLOSE`
/// висит СВЁРТЫВАНИЕ В ТРЕЙ (`TrayWindow`) — процесс остаётся жив, файл
/// остаётся занят, и Restart Manager честно рапортует об успехе. Мьютекс от
/// поведения окна не зависит вовсе: он либо есть, либо нет.
///
/// Имя обязано совпадать с `AppMutex` в `installer/silentgate.iss` — там же
/// оставлена встречная пометка. Расхождение не поймает ни компилятор, ни
/// анализатор: установщик просто перестанет замечать запущенное приложение и
/// вернётся к молчаливому отказу, с которого всё началось.
class AppInstanceMutex {
  static const name = 'SilentGateAppMutex';

  static int _handle = 0;

  /// Взят ли мьютекс этим процессом (для тестов и диагностики).
  static bool get isHeld => _handle != 0;

  /// ⚠️ МЬЮТЕКС БЕРЁТ НЕ ВСЯКАЯ КОПИЯ, А ТОЛЬКО УСТАНОВЛЕННАЯ.
  ///
  /// Установщик по мьютексу решает, можно ли ЗАМЕНЯТЬ ФАЙЛЫ В `{app}`. Копии,
  /// которые этих файлов не держат, обязаны молчать — иначе они блокируют
  /// установку, к которой не имеют отношения:
  ///
  /// * **портативная** живёт на флешке или в чужой папке и к установленной
  ///   версии не относится вовсе (её признак — метка рядом с exe, см.
  ///   [AppPaths.portableMarker]);
  /// * **изолированная тестовая** (`SILENTGATE_PORT_OFFSET`) заводится именно
  ///   для того, чтобы не мешать установленной, — см. [AppEnv].
  static bool get shouldHold =>
      Platform.isWindows && AppEnv.portOffset == 0 && !_isPortable;

  static bool get _isPortable {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return File('$exeDir${Platform.pathSeparator}${AppPaths.portableMarker}')
          .existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Завести мьютекс. Идемпотентна; никогда не бросает.
  ///
  /// ⚠️ ОСВОБОЖДАТЬ НЕ НУЖНО И НЕЛЬЗЯ ЗАБЫВАТЬ ПОЧЕМУ: ядро само закрывает
  /// хендл при завершении процесса — в том числе при аварийном. Ручной
  /// `CloseHandle` в обработчике выхода дал бы обратное: приложение, упавшее
  /// без обработчика, оставило бы мьютекс «навсегда», и установщик отказывался
  /// бы работать при закрытом приложении. Пусть этим занимается только ОС.
  static void acquire() {
    if (_handle != 0 || !shouldHold) return;
    Pointer<Utf16>? namePtr;
    try {
      final createMutex = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<_CreateMutexWC, _CreateMutexW>('CreateMutexW');
      namePtr = name.toNativeUtf16();
      // initialOwner = 0: владение нам не нужно, нужен сам факт существования
      // объекта с этим именем — именно его проверяет установщик.
      _handle = createMutex(nullptr, 0, namePtr);
    } catch (e) {
      // Не повод не запускаться: без мьютекса приложение работает точно так же,
      // хуже становится только обновлению поверх.
      AppLog.w('Не удалось завести мьютекс для установщика: $e');
      _handle = 0;
    } finally {
      if (namePtr != null) calloc.free(namePtr);
    }
  }
}
