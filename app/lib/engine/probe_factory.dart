import 'dart:io';

import '../core/probe/icmp_pinger.dart';
import '../core/probe/probe_harness.dart';
import 'windows/icmp_ping_windows.dart';
import 'windows/probe/mixed_probe_harness.dart';

/// Проброс-харнесс под текущую платформу (пока только Windows).
/// Ядро выбирается по протоколу кандидата: hysteria2 — sing-box, остальное — Xray.
ProbeHarness createProbeHarness() {
  if (Platform.isWindows) return MixedProbeHarness();
  throw UnsupportedError('Проброс-харнесс реализован только для Windows');
}

/// ICMP-пингер под текущую платформу.
IcmpPinger createIcmpPinger() {
  if (Platform.isWindows) return IcmpPingWindows();
  throw UnsupportedError('ICMP реализован только для Windows');
}
