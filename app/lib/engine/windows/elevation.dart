import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Запуск процесса с правами администратора через ShellExecuteEx("runas") — UAC-запрос.
/// `dart:io` Process.start не умеет elevate, поэтому используем WinAPI.
class Elevation {
  /// Возвращает true, если запуск инициирован (пользователь подтвердил UAC).
  /// [show] — показывать ли окно запускаемого процесса (для консольных операций типа
  /// восстановления сети полезно видеть вывод; для фонового TUN-хелпера — скрыть).
  static bool runElevated(String exePath, String params, {bool show = false}) {
    final pVerb = 'runas'.toNativeUtf16();
    final pFile = exePath.toNativeUtf16();
    final pParams = params.toNativeUtf16();
    final sei = calloc<SHELLEXECUTEINFO>();
    try {
      sei.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      sei.ref.lpVerb = pVerb;
      sei.ref.lpFile = pFile;
      sei.ref.lpParameters = pParams;
      sei.ref.nShow = show ? SW_SHOWNORMAL : SW_HIDE;
      final result = ShellExecuteEx(sei);
      return result != 0;
    } finally {
      free(pVerb);
      free(pFile);
      free(pParams);
      free(sei);
    }
  }
}
