import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/platform/core_cleanup.dart';

/// Запуск и остановка ядра xray.exe как дочернего процесса.
class XrayProcess {
  Process? _process;
  final _logController = StreamController<String>.broadcast();

  /// Файл, куда дублируется вывод ядра.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО ПОЯВИЛОСЬ. Хвост [_tail] живёт в памяти и умирает вместе с
  /// приложением, а `AppLog` про Xray писал только код возврата. Разбор
  /// жалобы «VPN сломался, весь интернет лёг» упирался в строчку «Ядро Xray
  /// остановилось (код 1)» — при том что код 1 у Xray означает и занятый порт,
  /// и отвергнутый конфиг, и десяток других вещей. У sing-box такой файл был с
  /// 0.9.0, у Xray его не было, и это стоило целого захода вслепую.
  IOSink? _logSink;

  /// Путь файла лога рядом с остальными: `%APPDATA%\SilentGate\xray.log`.
  static String logPathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}xray.log';

  /// Последние строки вывода ядра — чтобы показать РЕАЛЬНУЮ причину падения,
  /// а не «Ядро завершилось при запуске».
  final List<String> _tail = [];
  static const _tailMax = 30;

  /// Хвост лога ядра (для диагностики сбоя).
  String get tail => _tail.join('\n');

  /// Поток строк лога ядра (stdout/stderr) — для отладки.
  Stream<String> get logs => _logController.stream;

  /// Процесс запущен И ещё жив. Важно именно «жив»: раньше признак был просто
  /// «мы его стартовали», поэтому упавшее на старте ядро считалось работающим.
  bool _exited = false;
  bool get isRunning => _process != null && !_exited;

  /// Запускает `xray run -c <configPath>`. [assetDir] — каталог с geoip.dat/geosite.dat.
  Future<void> start({
    required String executable,
    required String configPath,
    required String assetDir,
    String? logPath,
  }) async {
    if (_process != null) {
      throw StateError('Ядро уже запущено');
    }
    if (logPath != null && logPath.isNotEmpty) {
      try {
        final f = File(logPath);
        // Файл РЕЖЕТСЯ, а не растёт бесконечно: singbox.log у владельца дорос
        // до 27 МБ и стал бесполезен — отчёт поддержки его уже не вмещает.
        if (await f.exists() && await f.length() > 2 * 1024 * 1024) {
          await f.delete();
        }
        _logSink = f.openWrite(mode: FileMode.append);
        _logSink!.writeln(
            '--- запуск Xray ${DateTime.now().toIso8601String()} (конфиг $configPath)');
      } catch (_) {
        // Не смогли открыть файл — работаем без него: диагностика не должна
        // мешать подключению.
        _logSink = null;
      }
    }
    final proc = await Process.start(
      executable,
      ['run', '-c', configPath],
      workingDirectory: assetDir,
      environment: {'XRAY_LOCATION_ASSET': assetDir},
    );
    _process = proc;
    _exited = false;
    // Windows не убивает детей вместе с родителем — регистрируем, чтобы
    // погасить при выходе и не оставить работающее ядро после закрытия.
    CoreCleanup.register(proc);
    unawaited(proc.exitCode.then((_) {
      _exited = true;
      CoreCleanup.unregister(proc);
    }));

    void onLine(String line) {
      _logController.add(line);
      _tail.add(line);
      if (_tail.length > _tailMax) _tail.removeAt(0);
      try {
        _logSink?.writeln(line);
      } catch (_) {
        // Файл мог быть удалён или занят — молчим, поток ядра важнее.
      }
    }

    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
  }

  /// Future, завершающийся при выходе процесса (код возврата).
  Future<int>? get exitCode => _process?.exitCode;

  Future<void> stop() async {
    final proc = _process;
    _process = null;
    final sink = _logSink;
    _logSink = null;
    if (proc == null) {
      await _closeSink(sink);
      return;
    }
    CoreCleanup.unregister(proc);
    proc.kill();
    // Дать процессу закрыться; если завис — не блокируемся навечно.
    await proc.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    // ⚠️ Пишем строку об остановке ПОСЛЕ ожидания: по ней в файле видно, что
    // ядро закрылось штатно, а не пропало вместе с приложением. Разница важна
    // при разборе «выключил и сразу включил».
    try {
      sink?.writeln('--- Xray остановлен ${DateTime.now().toIso8601String()}');
    } catch (_) {}
    await _closeSink(sink);
  }

  static Future<void> _closeSink(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  void dispose() {
    _logController.close();
  }
}
