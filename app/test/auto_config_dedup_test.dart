import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/probe/cancel_token.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/tcp_ping.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Харнесс-пустышка: порт всегда -1, значит проб через прокси не будет и
/// движок пойдёт по пути «кандидат не прошёл». Нам важен не результат проб, а
/// то, СКОЛЬКО РАЗ движок берётся за один и тот же сервер.
class _FakeHarness implements ProbeHarness {
  _FakeHarness(this.log);
  final List<String> log;

  /// Порт есть, просто ядро «не поднялось» (-1) — это НЕ то же самое, что
  /// платформа без поддержки прокси-запросов: там подбор не начинается вовсе.
  @override
  bool get supportsProxyRequests => true;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    for (final e in entries) {
      log.add('${e.server.key}|${e.variant.label}');
    }
    return _FakeHandle();
  }
}

class _FakeHandle implements HarnessHandle {
  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  @override
  int proxyPortFor(int index) => -1;
  @override
  Future<int?> delayMs(int index) async => null;
  @override
  Future<void> stop() async {}
}

void main() {
  // ⚠️ Фаза 1 отсеивает серверы, не ответившие по TCP, — а `*.example` не
  // отвечает и отвечать не может. Без подмены отсев съедал бы ВСЕХ, перебор
  // вариаций не начинался бы вовсе, и тест зеленел бы, ничего не проверив.
  setUp(() {
    AutoConfigEngine.tcpProbe = (host, port, timeout) async => const PingResult(
          outcome: PingOutcome.ok,
          latencyMs: 42,
          latencyMethod: PingMethod.tcp,
        );
  });
  tearDown(() {
    AutoConfigEngine.tcpProbe = (host, port, timeout) =>
        TcpPing.measure(host, port, timeout: timeout);
  });

  VpnServer srv(String name) => ShareLinkParser.tryParse(
      'vless://00000000-0000-0000-0000-000000000000@$name.example:443'
      '?type=tcp&security=none#$name')!;

  test('вариации перебираются, пока сервер не прошёл', () async {
    final log = <String>[];
    final engine = AutoConfigEngine(harnessFactory: () => _FakeHarness(log));
    // fragment включён ⇒ у каждого сервера минимум две вариации.
    const settings = AppSettings(
      tryFragment: true,
      fingerprints: ['firefox'],
      autoConfigServices: {ProbeService.google},
    );

    await engine.run(
      servers: [srv('a'), srv('b')],
      settings: settings,
      cancel: CancelToken(),
    );

    // Ни один сервер не прошёл (порта нет), поэтому перебираются ВСЕ вариации —
    // это и есть смысл перебора. Проверяем, что вариаций действительно больше
    // одной: иначе тест на дедупликацию ничего не доказывал бы.
    final aTries = log.where((e) => e.startsWith(srv('a').key)).length;
    expect(aTries, greaterThan(1),
        reason: 'при неудаче обязаны пробоваться все вариации');
  });
}
