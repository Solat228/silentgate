import 'dart:async';
import 'dart:io';

import '../../../core/platform/app_env.dart';
import '../../../core/platform/app_log.dart';
import '../../../core/platform/app_paths.dart';
import '../../../core/probe/probe_harness.dart';
import '../../../core/singbox/singbox_harness_config_builder.dart';
import '../singbox_process.dart';

/// Проброс-харнесс на sing-box — для серверов, которых не умеет Xray (hysteria2).
/// Как и Xray-харнесс: отдельный процесс, только 127.0.0.1, системный прокси не трогаем.
class SingboxHarnessWindows implements ProbeHarness {
  final SingboxHarnessConfigBuilder builder;

  // Диапазон портов свой, чтобы не пересекаться с Xray-харнессом (21000+).
  SingboxHarnessWindows({HarnessPorts? ports})
      : builder = SingboxHarnessConfigBuilder(
          ports: ports ?? HarnessPorts(base: 21500 + AppEnv.portOffset),
        );

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    final exe = SingboxProcess.locate();
    if (exe == null) {
      throw StateError('Не найден sing-box.exe — без него Hysteria2 не проверить');
    }

    final dir = await AppPaths.supportDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}singbox_harness.json');
    await file.writeAsString(builder.buildJson(entries));

    final process = SingboxProcess();
    await process.start(executable: exe, configPath: file.path);

    // Если ядро не поднялось — сказать об этом ВСЛУХ. sing-box валит весь конфиг
    // из-за одного плохого outbound'а, и раньше это выглядело как «все серверы
    // недоступны»: порт просто никогда не открывался, а причина из вывода ядра
    // никуда не попадала.
    final ok = await _waitReady(builder.portFor(0), process);
    if (!ok) {
      final tail = process.tail.trim();
      await process.stop();
      process.dispose();
      AppLog.e('sing-box-харнесс не запустился:\n$tail');
      throw StateError(tail.isEmpty
          ? 'sing-box-харнесс не запустился (вывод пуст)'
          : 'sing-box-харнесс не запустился:\n$tail');
    }
    return _SingboxHarnessHandle(process, builder);
  }

  /// true — порт открылся; false — ядро умерло или не успело за отведённое время.
  Future<bool> _waitReady(int port, SingboxProcess process) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (!process.isRunning) return false; // умерло на старте — ждать нечего
      try {
        final s = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 300));
        s.destroy();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    return false;
  }
}

class _SingboxHarnessHandle implements HarnessHandle {
  final SingboxProcess _process;
  final SingboxHarnessConfigBuilder _builder;
  _SingboxHarnessHandle(this._process, this._builder);

  @override
  int proxyPortFor(int index) => _builder.portFor(index);

  @override
  Future<void> stop() async {
    await _process.stop();
    _process.dispose();
  }
}
