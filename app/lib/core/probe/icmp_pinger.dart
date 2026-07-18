import 'ping_result.dart';

/// Платформенный ICMP-пинг (на Windows — через системный ping.exe).
abstract class IcmpPinger {
  Future<PingResult> ping(String host, {Duration timeout});
}
