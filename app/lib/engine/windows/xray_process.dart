import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/platform/core_cleanup.dart';

/// Запуск и остановка ядра xray.exe как дочернего процесса.
class XrayProcess {
  Process? _process;
  final _logController = StreamController<String>.broadcast();

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
  }) async {
    if (_process != null) {
      throw StateError('Ядро уже запущено');
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
    if (proc == null) return;
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
  }

  void dispose() {
    _logController.close();
  }
}
