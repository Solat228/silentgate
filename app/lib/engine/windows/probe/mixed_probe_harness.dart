import 'dart:async';

import '../../../core/models/vpn_server.dart';
import '../../../core/platform/app_log.dart';
import '../../../core/probe/probe_harness.dart';
import 'singbox_harness_windows.dart';
import 'xray_harness_windows.dart';

/// Харнесс, раскладывающий кандидатов по ядрам: обычные серверы — в Xray,
/// hysteria2 — в sing-box. Наружу выглядит как один харнесс: [proxyPortFor]
/// принимает ИСХОДНЫЙ индекс кандидата, как и раньше.
///
/// Одно ядро на всех не годится: Xray не знает hysteria2, а гонять всё через
/// sing-box нельзя — вариации автонастройки (fragment/fingerprint) есть только у Xray.
class MixedProbeHarness implements ProbeHarness {
  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    final xrayIdx = <int>[];
    final singboxIdx = <int>[];
    for (var i = 0; i < entries.length; i++) {
      (entries[i].server.core == ProxyCore.singbox ? singboxIdx : xrayIdx).add(i);
    }

    // Однородный набор — обычный одиночный харнесс, без лишнего процесса.
    if (singboxIdx.isEmpty) return XrayHarnessWindows().start(entries);
    if (xrayIdx.isEmpty) return SingboxHarnessWindows().start(entries);

    final xray = await XrayHarnessWindows()
        .start([for (final i in xrayIdx) entries[i]]);

    // Если sing-box не поднялся (нет бинарника, антивирус его съел, плохой
    // конфиг у одного из hysteria2-узлов) — НЕ роняем всю проверку: обычные
    // серверы уже пингуются. Иначе одна битая ссылка обнуляла пинг всех 79.
    HarnessHandle? singbox;
    try {
      singbox = await SingboxHarnessWindows()
          .start([for (final i in singboxIdx) entries[i]]);
    } catch (e) {
      AppLog.e('Пинг hysteria2 пропущен: $e');
    }

    final ports = <int, int>{};
    for (var k = 0; k < xrayIdx.length; k++) {
      ports[xrayIdx[k]] = xray.proxyPortFor(k);
    }
    if (singbox != null) {
      for (var k = 0; k < singboxIdx.length; k++) {
        ports[singboxIdx[k]] = singbox.proxyPortFor(k);
      }
    }
    return _MixedHandle(ports, [xray, if (singbox != null) singbox]);
  }
}

class _MixedHandle implements HarnessHandle {
  final Map<int, int> _ports;
  final List<HarnessHandle> _parts;
  _MixedHandle(this._ports, this._parts);

  @override
  int proxyPortFor(int index) => _ports[index] ?? -1;

  /// Windows меряет через прокси-порт — готовой задержки нет.
  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {
    for (final p in _parts) {
      await p.stop();
    }
  }
}
