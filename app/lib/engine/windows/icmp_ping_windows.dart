import 'dart:io';

import '../../core/probe/icmp_pinger.dart';
import '../../core/probe/ping_result.dart';
import '../../core/settings/app_settings.dart';

/// ICMP-пинг на Windows через системный `ping`. В Dart нет ICMP без raw-сокетов/прав,
/// поэтому парсим вывод ping. Парсер устойчив к локали (ru/en: «время=12мс» / «time=12ms»).
class IcmpPingWindows implements IcmpPinger {
  // «=12ms», «=12мс», «<1ms», «<1мс»
  static final _timeRe =
      RegExp(r'[=<]\s*(\d+)\s*(ms|мс)', caseSensitive: false);
  // «(0% потерь)» / «(0% loss)»
  static final _lossRe = RegExp(r'\((\d+)%');

  @override
  Future<PingResult> ping(String host,
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final result = await Process.run(
        'ping',
        ['-n', '1', '-w', '${timeout.inMilliseconds}', host],
      );
      final out = '${result.stdout}';

      final lossMatch = _lossRe.firstMatch(out);
      final loss =
          lossMatch != null ? double.tryParse(lossMatch.group(1)!) : null;

      final timeMatch = _timeRe.firstMatch(out);
      if (timeMatch != null) {
        return PingResult(
          outcome: PingOutcome.ok,
          latencyMs: int.parse(timeMatch.group(1)!),
          lossPct: loss,
          latencyMethod: PingMethod.icmp,
        );
      }
      return PingResult(
        outcome: PingOutcome.timeout,
        lossPct: loss,
        latencyMethod: PingMethod.icmp,
      );
    } catch (_) {
      return const PingResult(
          outcome: PingOutcome.failed, latencyMethod: PingMethod.icmp);
    }
  }
}
