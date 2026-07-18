import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/platform/core_cleanup.dart';

import 'xray_paths.dart';

/// Запуск sing-box как **прокси-ядра** (обычные права).
///
/// Не путать с [TunHelper]: тот поднимает sing-box с TUN-адаптером и требует
/// администратора. Здесь sing-box слушает только 127.0.0.1, поэтому UAC не нужен.
class SingboxProcess {
  Process? _process;

  /// Последние строки вывода — чтобы показать реальную причину падения.
  final List<String> _tail = [];
  static const _tailMax = 30;

  String get tail => _tail.join('\n');

  /// Запущен И ещё жив: sing-box падает на старте от одной опечатки в конфиге,
  /// а «мы его стартовали» — недостаточный признак (порт так и не откроется,
  /// и это выглядело как «все серверы недоступны»).
  bool _exited = false;
  bool get isRunning => _process != null && !_exited;

  /// Путь к sing-box.exe: он лежит рядом с xray.exe (см. tools/fetch-singbox.ps1).
  static String? locate() {
    final loc = XrayPaths.locate();
    if (loc == null) return null;
    final path = '${loc.assetDir}${Platform.pathSeparator}sing-box.exe';
    return File(path).existsSync() ? path : null;
  }

  Future<void> start({required String executable, required String configPath}) async {
    if (_process != null) throw StateError('Ядро уже запущено');
    final proc = await Process.start(
      executable,
      ['run', '-c', configPath],
      workingDirectory: File(executable).parent.path,
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

  Future<int>? get exitCode => _process?.exitCode;

  Future<void> stop() async {
    final proc = _process;
    _process = null;
    if (proc == null) return;
    CoreCleanup.unregister(proc);
    proc.kill();
    await proc.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  void dispose() {}
}
