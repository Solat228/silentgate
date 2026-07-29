import 'dart:async';
import 'dart:isolate';

import '../../core/platform/app_log.dart';

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Запуск процесса с правами администратора через ShellExecuteEx("runas") — UAC-запрос.
/// `dart:io` Process.start не умеет elevate, поэтому используем WinAPI.
class Elevation {
  /// Возвращает true, если запуск инициирован (пользователь подтвердил UAC).
  /// [show] — показывать ли окно запускаемого процесса (для консольных операций типа
  /// восстановления сети полезно видеть вывод; для фонового TUN-хелпера — скрыть).
  /// Асинхронная обёртка с ЯВНЫМ пределом ожидания.
  ///
  /// ⚠️ `ShellExecuteEx` — синхронный вызов через FFI, и зовётся он на изоляте
  /// интерфейса. Пока он не вернулся, приложение стоит целиком: ни следующей
  /// комбинации автоподбора, ни сообщения об ошибке, ни реакции на «Отключить».
  /// Поймано живым тестом в VM: `app.log` обрывался на «пробую system, MTU 1500»
  /// и не двигался 90 секунд при дедлайне 12 — хелпер при этом не запускался
  /// вовсе, и пользователь видел просто зависшее «Подключение…».
  ///
  /// Здесь вызов уезжает в ОТДЕЛЬНЫЙ изолят. Зависший вызов утечёт вместе с
  /// ним (прервать FFI нельзя), но приложение останется живым и честно скажет,
  /// что прав получить не удалось.
  static Future<bool> runElevatedAsync(
    String exePath,
    String params, {
    bool show = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    AppLog.i('Запрашиваю права администратора: $exePath $params');
    try {
      final ok = await Isolate.run(() => runElevated(exePath, params, show: show))
          .timeout(timeout);
      AppLog.i('Права администратора: ${ok ? "получены" : "ОТКАЗ"}');
      return ok;
    } on TimeoutException {
      AppLog.e('Запрос прав администратора не ответил за '
          '${timeout.inSeconds} с — считаю отказом');
      return false;
    } catch (e) {
      AppLog.e('Запрос прав администратора сорвался: $e');
      return false;
    }
  }

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
