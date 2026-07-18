import 'dart:async';
import 'dart:io';

import '../../../core/platform/app_env.dart';
import '../../../core/platform/app_paths.dart';
import '../../../core/probe/probe_harness.dart';
import '../../../core/xray/harness_config_builder.dart';
import '../xray_paths.dart';
import '../xray_process.dart';

/// Windows-реализация проброс-харнесса: отдельный процесс xray.exe с http-inbound'ами.
/// Не устанавливает системный прокси.
class XrayHarnessWindows implements ProbeHarness {
  final HarnessConfigBuilder builder;
  // Изолированная копия (SILENTGATE_PORT_OFFSET) занимает свой диапазон портов.
  XrayHarnessWindows({HarnessPorts? ports})
      : builder = HarnessConfigBuilder(
          ports: ports ?? HarnessPorts(base: 21000 + AppEnv.portOffset),
        );

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    final location = XrayPaths.locate();
    if (location == null) {
      throw StateError('Не найден xray.exe для проброс-харнесса');
    }

    final dir = await AppPaths.supportDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}harness_config.json');
    await file.writeAsString(builder.buildJson(entries));

    final process = XrayProcess();
    await process.start(
      executable: location.executable,
      configPath: file.path,
      assetDir: location.assetDir,
    );

    await _waitReady(builder.portFor(0));
    return _WindowsHarnessHandle(process, builder);
  }

  Future<void> _waitReady(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 300));
        s.destroy();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
  }
}

class _WindowsHarnessHandle implements HarnessHandle {
  final XrayProcess _process;
  final HarnessConfigBuilder _builder;
  _WindowsHarnessHandle(this._process, this._builder);

  @override
  int proxyPortFor(int index) => _builder.portFor(index);

  @override
  Future<void> stop() async {
    await _process.stop();
    _process.dispose();
  }
}
