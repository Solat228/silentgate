import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/platform/app_log.dart';

/// Запуск процесса с правами администратора.
///
/// `dart:io` Process.start возвышать не умеет, поэтому в общем случае идём
/// через `ShellExecuteEx("runas")` — это и есть запрос UAC.
class Elevation {
  /// Уже возвышен ли САМ процесс приложения.
  ///
  /// Проверяется один раз: в пределах жизни процесса значение не меняется.
  static bool? _elevatedCache;

  static bool get isElevated => _elevatedCache ??= _checkElevated();

  static bool _checkElevated() {
    final pToken = calloc<HANDLE>();
    final pElev = calloc<Uint32>();
    final pLen = calloc<Uint32>();
    try {
      if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, pToken) == 0) {
        return false;
      }
      try {
        // TokenElevation = 20; ненулевое значение = процесс возвышен.
        final ok = GetTokenInformation(
            pToken.value, TOKEN_INFORMATION_CLASS.TokenElevation,
            pElev.cast(), sizeOf<Uint32>(), pLen);
        return ok != 0 && pElev.value != 0;
      } finally {
        CloseHandle(pToken.value);
      }
    } catch (_) {
      return false;
    } finally {
      calloc.free(pToken);
      calloc.free(pElev);
      calloc.free(pLen);
    }
  }

  /// Запустить процесс с правами администратора, не морозя приложение.
  ///
  /// Возвращает true, если запуск состоялся.
  ///
  /// ⚠️ ДВА РАЗНЫХ ПУТИ, и это не оптимизация, а лечение живого дефекта.
  ///
  /// 1. Если приложение УЖЕ возвышено, `ShellExecuteEx` не нужен вовсе:
  ///    дочерний процесс и так унаследует права. Здесь берётся обычный
  ///    `Process.start` — без оболочки, без службы AppInfo, без брокера UAC.
  ///    Живой тест в VM (учётка администратора, приложение возвышено, запрос
  ///    согласия отключён политикой) показал ровно то, чего не должно быть:
  ///    `ShellExecuteEx` НЕ ВОЗВРАЩАЛСЯ 20 секунд и хелпер не запускался, хотя
  ///    тот же самый вызов из обычного консольного Dart-процесса отрабатывал за
  ///    29 мс и туннель поднимал. То есть дефект живёт в связке
  ///    «Flutter-процесс + брокер UAC», а не в самом FFI, и лечится он тем, что
  ///    в этом случае брокера в цепочке просто не остаётся.
  ///
  /// 2. Если приложение не возвышено, обойтись без UAC нельзя. Тогда вызов
  ///    уезжает в отдельный изолят, чтобы интерфейс жил и кнопка «Отключить»
  ///    отвечала. Зависший вызов утечёт вместе с изолятом — прервать FFI
  ///    нечем, — но приложение останется управляемым.
  static Future<bool> runElevatedAsync(
    String exePath,
    String params, {
    bool show = false,
    // Раньше было 20 с. Это меньше, чем нужно живому человеку, чтобы заметить
    // окно UAC (оно может открыться за другими окнами) и нажать «Да». Отказ по
    // такому таймауту — не отказ пользователя, а наша нетерпеливость.
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (isElevated) {
      // Права уже есть — запрашивать нечего.
      try {
        await Process.start(exePath, _splitArgs(params),
            mode: ProcessStartMode.detached);
        AppLog.i('Хелпер запущен напрямую (приложение уже с правами администратора)');
        return true;
      } catch (e) {
        AppLog.e('Не удалось запустить хелпер напрямую: $e');
        return false;
      }
    }

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

  /// Разбор строки параметров в список аргументов.
  ///
  /// `ShellExecuteEx` принимает параметры одной строкой, `Process.start` — уже
  /// разобранным списком. Кавычки вокруг путей обязаны сниматься здесь: иначе
  /// хелпер получит имя файла ВМЕСТЕ с кавычками и не найдёт конфиг.
  static List<String> _splitArgs(String params) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (final ch in params.split('')) {
      if (ch == '"') {
        quoted = !quoted;
      } else if (ch == ' ' && !quoted) {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
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
      // SEE_MASK_NOASYNC: документация требует этот флаг, когда вызов делается
      // из потока, который вскоре завершится, — иначе операция может не
      // довестись до конца. У нас ровно этот случай: изолят живёт только на
      // время вызова.
      sei.ref.fMask = 0x00000100;
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
