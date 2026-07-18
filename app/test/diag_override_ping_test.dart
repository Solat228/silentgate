// ВРЕМЕННАЯ диагностика #1.1: реально ли пингуется сервер с полным JSON-override,
// в котором balancer + burstObservatory (конфиг в стиле Happ burst).
//
// VPN НЕ включается и НИ ОДИН VPN-сервер не используется: outbound'ы — freedom,
// то есть проверяем именно обвязку (override → harness → balancer → observatory → выход),
// а не чужие серверы. Запускать с изолированным APPDATA:
//   $env:APPDATA="<temp>\isolated"; flutter test test/diag_override_ping_test.dart
@Tags(['diag'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/proxy_probe.dart';
import 'package:silentgate/engine/windows/probe/xray_harness_windows.dart';

/// Burst-конфиг «как из Happ»: свои inbounds, несколько proxy-outbound'ов под
/// балансировщиком и burstObservatory. Только outbound'ы — freedom (прямой выход).
const _burstJson = '''
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"tag": "socks-in", "port": 10808, "listen": "127.0.0.1", "protocol": "socks"},
    {"tag": "http-in", "port": 10809, "listen": "127.0.0.1", "protocol": "http"}
  ],
  "outbounds": [
    {"tag": "proxy-0", "protocol": "freedom", "settings": {"domainStrategy": "AsIs"}},
    {"tag": "proxy-1", "protocol": "freedom", "settings": {"domainStrategy": "AsIs"}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "balancers": [
      {"tag": "balancer", "selector": ["proxy"], "strategy": {"type": "leastPing"}}
    ],
    "rules": [
      {"type": "field", "inboundTag": ["socks-in", "http-in"], "balancerTag": "balancer"}
    ]
  },
  "burstObservatory": {
    "subjectSelector": ["proxy"],
    "pingConfig": {
      "destination": "http://www.gstatic.com/generate_204",
      "interval": "15s",
      "sampling": 3,
      "timeout": "5s"
    }
  },
  "stats": {},
  "policy": {"levels": {"0": {"statsUserUplink": true}}}
}
''';

void main() {
  test('#1.1 override с balancer+burstObservatory реально проксирует', () async {
    final dir = (await AppPaths.supportDir()).path;
    expect(dir.toLowerCase().contains('scratchpad'), isTrue,
        reason: 'APPDATA не изолирован — отказываюсь писать в $dir');

    final server = ShareLinkParser.tryParse(
      'vless://11111111-2222-3333-4444-555555555555@example.com:443'
      '?type=tcp&security=reality&pbk=K&sni=a.com&sid=ab&encryption=none#OV',
    )!.copyWith(rawJsonOverride: _burstJson);

    final handle =
        await XrayHarnessWindows().start([HarnessEntry(key: 'ov', server: server)]);
    try {
      final port = handle.proxyPortFor(0);
      final r = await ProxyProbe.check(
        port,
        'https://www.gstatic.com/generate_204',
        timeout: const Duration(seconds: 10),
      );
      // ignore: avoid_print
      print('override-harness порт=$port ok=${r.ok} code=${r.statusCode} rtt=${r.rttMs}');
      expect(r.ok, isTrue,
          reason: 'через override-конфиг с balancer трафик не пошёл');
    } finally {
      await handle.stop();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
