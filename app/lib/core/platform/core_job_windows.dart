import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'app_log.dart';

typedef _CreateJobObjectWC = IntPtr Function(
    Pointer<Void> attrs, Pointer<Utf16> name);
typedef _CreateJobObjectW = int Function(
    Pointer<Void> attrs, Pointer<Utf16> name);
typedef _SetInformationJobObjectC = Int32 Function(
    IntPtr job, Int32 infoClass, Pointer<Uint8> info, Uint32 length);
typedef _SetInformationJobObject = int Function(
    int job, int infoClass, Pointer<Uint8> info, int length);
typedef _OpenProcessC = IntPtr Function(
    Uint32 access, Int32 inherit, Uint32 pid);
typedef _OpenProcess = int Function(int access, int inherit, int pid);
typedef _AssignProcessToJobObjectC = Int32 Function(IntPtr job, IntPtr proc);
typedef _AssignProcessToJobObject = int Function(int job, int proc);
typedef _CloseHandleC = Int32 Function(IntPtr h);
typedef _CloseHandle = int Function(int h);
typedef _GetLastErrorC = Uint32 Function();
typedef _GetLastError = int Function();

/// Объект задания Windows (Job Object), в который кладутся ядра.
///
/// ⚠️ ЗАЧЕМ. Windows НЕ убивает дочерние процессы вместе с родителем. Ядро,
/// живое в момент аварии приложения, оставалось висеть: держало порты 10808 и
/// 10809, и следующий запуск упирался в «порт занят» чужим — то есть своим же —
/// процессом. `CoreCleanup` закрывал это наполовину: [CoreCleanup.killChildren]
/// работает только при ШТАТНОМ выходе, а `sweepOrphans` — только на следующем
/// старте и только если PowerShell отвечает.
///
/// Задание с флагом `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` закрывает это силами
/// самой ОС: хендл задания живёт, пока жив наш процесс, и при его смерти — в
/// том числе от «Завершить задачу» и от вылета — ядро убивает всех участников.
/// Никаких реестров и подбора по пути.
///
/// ⚠️ ХЕНДЛ НЕ ЗАКРЫВАЕТСЯ НИКОГДА, И ЭТО ЗАМЫСЕЛ. Закрыть его — значит убить
/// все ядра прямо сейчас. Его закрывает только ОС при завершении процесса.
///
/// ⚠️ В ЗАДАНИЕ КЛАДУТСЯ ТОЛЬКО ЯДРА, ЗАПУЩЕННЫЕ НАМИ ОБЫЧНЫМ ОБРАЗОМ. Установщик
/// обновления туда попасть не должен (он обязан пережить закрытие приложения),
/// поэтому процессы добавляются поштучно, а не через наследование задания.
/// TUN-ядро запускается с правами администратора через Планировщик — процесс
/// с более высоким уровнем целостности в наше задание не положить, и он живёт
/// своим путём (stop-файл).
///
/// ⚠️ Не вышло создать задание — ядро НЕ убивается (в отличие от того, как это
/// сделано у Clash Verge, откуда идея): у нас остаётся прежний `CoreCleanup`, и
/// отказ подключаться из-за вспомогательной страховки был бы хуже болезни.
abstract final class CoreJob {
  /// `JobObjectExtendedLimitInformation` из `JOBOBJECTINFOCLASS`.
  static const int extendedLimitInformationClass = 9;

  /// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
  static const int killOnJobClose = 0x2000;

  /// Размер `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` на x64.
  static const int extendedLimitInfoSize = 144;

  /// Смещение поля `BasicLimitInformation.LimitFlags` на x64: два
  /// `LARGE_INTEGER` перед ним.
  static const int limitFlagsOffset = 16;

  static int _job = 0;
  static bool _failed = false;

  /// Положить процесс [pid] в задание приложения. Никогда не бросает.
  ///
  /// Возвращает `true`, если процесс теперь умрёт вместе с приложением.
  static bool adopt(int pid) {
    if (!Platform.isWindows || _failed) return false;
    try {
      if (_job == 0) {
        _job = createKillOnCloseJob();
        if (_job == 0) {
          _failed = true;
          AppLog.w('Объект задания для ядер не создан — при аварии приложения '
              'ядра останутся жить до следующего запуска');
          return false;
        }
      }
      final ok = assignTo(_job, pid);
      if (!ok) {
        AppLog.w('Ядро (pid $pid) не помещено в объект задания — при аварии '
            'приложения оно останется жить до следующего запуска');
      }
      return ok;
    } catch (e) {
      _failed = true;
      AppLog.w('Объект задания для ядер недоступен: $e');
      return false;
    }
  }

  /// Структура `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` с одним флагом
  /// `KILL_ON_JOB_CLOSE`. Отдельно — чтобы раскладку проверял тест.
  @visibleForTesting
  static Uint8List extendedLimitInfo() {
    final b = Uint8List(extendedLimitInfoSize);
    ByteData.sublistView(b)
        .setUint32(limitFlagsOffset, killOnJobClose, Endian.little);
    return b;
  }

  /// Новое безымянное задание с `KILL_ON_JOB_CLOSE`; `0` — не вышло.
  @visibleForTesting
  static int createKillOnCloseJob() {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final create = k32.lookupFunction<_CreateJobObjectWC, _CreateJobObjectW>(
        'CreateJobObjectW');
    final setInfo =
        k32.lookupFunction<_SetInformationJobObjectC, _SetInformationJobObject>(
            'SetInformationJobObject');
    final job = create(nullptr, nullptr);
    if (job == 0) return 0;
    final info = extendedLimitInfo();
    final p = calloc<Uint8>(info.length);
    try {
      p.asTypedList(info.length).setAll(0, info);
      if (setInfo(job, extendedLimitInformationClass, p, info.length) == 0) {
        AppLog.w('SetInformationJobObject отказал (код ${_lastError(k32)})');
        _close(k32, job);
        return 0;
      }
    } finally {
      calloc.free(p);
    }
    return job;
  }

  /// Положить [pid] в задание [job].
  @visibleForTesting
  static bool assignTo(int job, int pid) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final open =
        k32.lookupFunction<_OpenProcessC, _OpenProcess>('OpenProcess');
    final assign = k32.lookupFunction<_AssignProcessToJobObjectC,
        _AssignProcessToJobObject>('AssignProcessToJobObject');
    // PROCESS_SET_QUOTA | PROCESS_TERMINATE — ровно то, что требует
    // AssignProcessToJobObject, без лишних прав.
    final h = open(0x0100 | 0x0001, 0, pid);
    if (h == 0) return false;
    try {
      return assign(job, h) != 0;
    } finally {
      _close(k32, h);
    }
  }

  /// Закрыть хендл задания. ТОЛЬКО для тестов: в приложении это убило бы ядра.
  @visibleForTesting
  static void closeForTests(int job) =>
      _close(DynamicLibrary.open('kernel32.dll'), job);

  static void _close(DynamicLibrary k32, int h) =>
      k32.lookupFunction<_CloseHandleC, _CloseHandle>('CloseHandle')(h);

  static int _lastError(DynamicLibrary k32) =>
      k32.lookupFunction<_GetLastErrorC, _GetLastError>('GetLastError')();
}
