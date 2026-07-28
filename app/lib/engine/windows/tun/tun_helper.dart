import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/platform/app_paths.dart';
import '../../../core/platform/rotating_log.dart';
import '../xray_paths.dart';

/// Элевейтнутый TUN-хелпер: запускает sing-box как дочерний процесс и следит за
/// stop-файлом. Когда GUI (без прав) создаёт stop-файл — хелпер убивает sing-box и выходит.
/// Так решается остановка привилегированного процесса из непривилегированного GUI.
///
/// Два режима запуска:
///  * `--tun-task` — из задачи Планировщика (без UAC). Пути фиксированы в `%APPDATA%`.
///  * `--tun <config> [stop]` — прямой запуск через UAC (fallback, если задачи нет).
///
/// Весь вывод sing-box пишется в `singbox.log`: без него сбой ядра был невидим —
/// приложение показывало «Подключено» при отсутствующем туннеле.
class TunHelper {
  static const _maxLogBytes = 512 * 1024;

  static File _defaultStopFile() =>
      File('${Directory.systemTemp.path}${Platform.pathSeparator}silentgate_tun_stop');

  /// Путь stop-файла в папке данных пользователя.
  static String stopFilePathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}tun_stop';

  /// Путь конфига sing-box в папке данных пользователя.
  static String configPathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}singbox_config.json';

  /// Лог sing-box (читается приложением при сбое и по кнопке «Показать лог»).
  static String logPathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}singbox.log';

  /// Хвост лога sing-box — для показа реальной причины сбоя.
  /// Хвост лога sing-box.
  ///
  /// ⚠️ Файл читается С КОНЦА, а не целиком: при уровне лога `debug` он растёт
  /// на сотни мегабайт за сессию (наблюдалось 758 МБ), и `readAsString()`
  /// затягивал всё это в память — нажатие «Написать в поддержку» подвешивало
  /// приложение или роняло его по нехватке памяти.
  static const _tailBytes = 512 * 1024;

  /// Чтение делегировано [RotatingLog.tail] — тот же алгоритм нужен и
  /// прокси-ядру (`singbox_proxy.log`), а две копии этой логики неминуемо
  /// разъехались бы.
  static Future<String> tailLog({int lines = 40}) async => RotatingLog.tail(
        logPathFor(await AppPaths.supportDir()),
        lines: lines,
        tailBytes: _tailBytes,
      );

  /// Режим задачи Планировщика. Пути к конфигу/stop берём из ЯВНЫХ аргументов,
  /// если задача их передала (см. TunScheduledTask.install), иначе — из `%APPDATA%`.
  /// Явные пути важны на учётке с ОТДЕЛЬНЫМ админом: там задача бежит от админа, и
  /// его `%APPDATA%` — ЧУЖОЙ (иначе туннель поднимался бы по пустому конфигу, #7).
  static Future<void> runFromTask({String? configPath, String? stopPath}) async {
    final dir = await AppPaths.supportDir();
    await run(
      (configPath != null && configPath.isNotEmpty)
          ? configPath
          : configPathFor(dir),
      stopPath: (stopPath != null && stopPath.isNotEmpty)
          ? stopPath
          : stopFilePathFor(dir),
    );
  }

  /// Вызывается из main при `--tun`. Блокируется до остановки.
  static Future<void> run(String configPath, {String stopPath = ''}) async {
    final stopFile = stopPath.isNotEmpty ? File(stopPath) : _defaultStopFile();
    final loc = XrayPaths.locate();
    final singbox = loc != null
        ? '${loc.assetDir}${Platform.pathSeparator}sing-box.exe'
        : 'sing-box.exe';

    final log = await _openLog();
    _write(log, '--- запуск sing-box: $singbox run -c $configPath');

    _delete(stopFile);
    Process proc;
    try {
      proc = await Process.start(
        singbox,
        ['run', '-c', configPath],
        workingDirectory: loc?.assetDir,
      );
    } catch (e) {
      _write(log, 'НЕ УДАЛОСЬ ЗАПУСТИТЬ sing-box: $e');
      await log?.flush();
      await log?.close();
      return;
    }

    // Вывод ядра — в лог (иначе диагностировать сбой невозможно).
    proc.stdout.transform(utf8.decoder).listen((s) => _write(log, s, raw: true));
    proc.stderr.transform(utf8.decoder).listen((s) => _write(log, s, raw: true));

    var procExited = false;
    unawaited(proc.exitCode.then((code) {
      procExited = true;
      _write(log, '--- sing-box завершился, код $code');
    }));

    while (true) {
      if (procExited) break;
      if (stopFile.existsSync()) {
        _write(log, '--- получен stop-файл, останавливаю sing-box');
        proc.kill();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    try {
      proc.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _delete(stopFile);
    await log?.flush();
    await log?.close();
  }

  /// GUI: запросить остановку TUN — создать stop-файл по явному пути.
  static void requestStopAt(String stopPath) {
    try {
      File(stopPath).createSync(recursive: true);
    } catch (_) {}
    // Легаси-путь на случай, если работает хелпер старой версии.
    try {
      _defaultStopFile().createSync();
    } catch (_) {}
  }

  /// Удалить stop-файл перед новым запуском (оба расположения).
  static void clearStopAt(String stopPath) {
    try {
      final f = File(stopPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _delete(_defaultStopFile());
  }

  /// Обрезать разросшийся лог, не останавливая запись.
  static Future<void> _rotateLog(IOSink log) async {
    try {
      await log.flush();
      final f = File(logPathFor(await AppPaths.supportDir()));
      await f.writeAsString(
          '--- лог обрезан по достижении ${_maxLogBytes ~/ 1024} КБ ---\n');
    } catch (_) {
    } finally {
      _rotating = false;
    }
  }

  static Future<IOSink?> _openLog() async {
    try {
      final f = File(logPathFor(await AppPaths.supportDir()));
      // Простая ротация: пухлый лог начинаем заново.
      if (await f.exists() && await f.length() > _maxLogBytes) {
        await f.writeAsString('');
      }
      return f.openWrite(mode: FileMode.append);
    } catch (_) {
      return null;
    }
  }

  /// Сколько байт уже записано в текущий файл лога.
  ///
  /// ⚠️ Ротация «при открытии» одна не спасает: сессия TUN живёт часами, а на
  /// уровне `debug` sing-box пишет каждое соединение и каждый DNS-запрос — файл
  /// наблюдался размером 758 МБ, и отчёт поддержки, читавший его целиком,
  /// подвешивал приложение. Считаем объём на лету и обрезаем файл, не
  /// дожидаясь следующего запуска.
  static int _logBytes = 0;
  static bool _rotating = false;

  static void _write(IOSink? log, String text, {bool raw = false}) {
    if (log == null) return;
    try {
      final line = raw ? text : '[${DateTime.now().toIso8601String()}] $text\n';
      _logBytes += line.length;
      if (_logBytes > _maxLogBytes && !_rotating) {
        _rotating = true;
        _logBytes = 0;
        unawaited(_rotateLog(log));
      }
      log.write(line);
    } catch (_) {}
  }

  static void _delete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
