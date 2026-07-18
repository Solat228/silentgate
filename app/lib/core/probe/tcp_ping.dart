import 'dart:async';
import 'dart:io';

import '../settings/app_settings.dart';
import 'ping_result.dart';

/// Чистый Dart TCP-пинг: время установления TCP-соединения до адреса сервера.
/// Кросс-платформенный (не требует Xray).
class TcpPing {
  static Future<PingResult> measure(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return PingResult(
        outcome: PingOutcome.ok,
        latencyMs: sw.elapsedMilliseconds,
        latencyMethod: PingMethod.tcp,
      );
    } on TimeoutException {
      return const PingResult(
          outcome: PingOutcome.timeout, latencyMethod: PingMethod.tcp);
    } catch (_) {
      return const PingResult(
          outcome: PingOutcome.failed, latencyMethod: PingMethod.tcp);
    }
  }
}
