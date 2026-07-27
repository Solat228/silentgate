import 'dart:io';

import '../core/probe/icmp_pinger.dart';
import '../core/probe/probe_harness.dart';
import 'windows/icmp_ping_windows.dart';
import 'windows/probe/mixed_probe_harness.dart';

/// Есть ли на этой платформе проброс-харнесс — отдельный экземпляр ядра с
/// локальными http-inbound'ами, через который проверяется, реально ли сервер
/// проксирует трафик (фаза 2 пинга).
///
/// На Windows ядра запускаются процессами, поэтому поднять временный экземпляр
/// рядом с рабочим можно. На Android ядро — библиотека внутри процесса
/// приложения, и второй экземпляр рядом с живым туннелем не поднять. Там пинг
/// остаётся одной фазой (TCP), а не притворяется, что проверил больше.
bool get proxyProbeSupported => Platform.isWindows;

/// Проброс-харнесс под текущую платформу.
/// Ядро выбирается по протоколу кандидата: hysteria2 — sing-box, остальное — Xray.
ProbeHarness createProbeHarness() {
  if (Platform.isWindows) return MixedProbeHarness();
  throw UnsupportedError(
      'Проброс-харнесс на ${Platform.operatingSystem} не поддерживается — '
      'проверяйте proxyProbeSupported перед вызовом');
}

/// Поддерживается ли ICMP-пинг.
///
/// На Android сырые ICMP-сокеты без root недоступны, а разбор вывода
/// `/system/bin/ping` — отдельная задача плана.
bool get icmpSupported => Platform.isWindows;

/// ICMP-пингер под текущую платформу.
IcmpPinger createIcmpPinger() {
  if (Platform.isWindows) return IcmpPingWindows();
  throw UnsupportedError('ICMP на ${Platform.operatingSystem} не поддерживается');
}
