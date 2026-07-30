import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// ВРЕМЕННЫЙ эмиттер конфигов для статической проверки ядрами. Удалить.
void main() {
  final out = Directory('build/leakcheck')..createSync(recursive: true);
  const enc = JsonEncoder.withIndent('  ');

  void emit(String name, Map<String, dynamic> cfg) {
    File('${out.path}/$name.json').writeAsStringSync(enc.convert(cfg));
  }

  const sites = [
    SiteRule('example.org', action: AppAction.direct),
    SiteRule('example.net', action: AppAction.tunnel),
    SiteRule('ads.example', action: AppAction.block),
  ];
  const apps = [
    AppRule(r'C:\Chrome\chrome.exe', byName: true, action: AppAction.tunnel),
  ];

  test('emit', () {
    emit(
        'no_ipv6_quic_doh',
        SingboxConfigBuilder(
          options: const TunOptions(
            serverIps: ['203.0.113.10'],
            ipv6: false,
            blockQuic: true,
            blockEncryptedDns: true,
            directDnsUpstream: '192.168.1.1',
          ),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    emit(
        'ipv6_dns_upstream',
        SingboxConfigBuilder(
          options: const TunOptions(
            serverIps: ['203.0.113.10'],
            directDnsUpstream: 'fe80:0:0:0:0:0:0:1',
          ),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    emit(
        'android_platform',
        SingboxConfigBuilder(
          probePort: 10809,
          proxyOutbound: const {
            'type': 'socks',
            'server': '203.0.113.10',
            'server_port': 1080,
            'version': '5',
          },
          options: const TunOptions(
            platformTun: true,
            serverIps: ['203.0.113.10'],
            ipv6: false,
            blockQuic: true,
            blockEncryptedDns: true,
            directDnsUpstream: '192.168.1.1',
          ),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            apps: [AppRule('com.android.chrome', action: AppAction.tunnel)],
            sites: sites)));

    emit(
        'blackhole',
        SingboxConfigBuilder(
          options: const TunOptions(serverIps: ['203.0.113.10']).asBlackhole(),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    emit(
        'defaults',
        SingboxConfigBuilder(
          options: TunOptions.fromSettings(const AppSettings(),
              serverIps: const ['203.0.113.10'],
              directDnsUpstream: '192.168.1.1'),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    // Что теряет asBlackhole() по сравнению с живыми опциями.
    const live = TunOptions(
      serverIps: ['203.0.113.10'],
      ipv6: false,
      blockQuic: true,
      blockEncryptedDns: true,
      blockPagePort: 18080,
      tunnelDnsForAll: false,
      mtu: 1400,
      platformTun: true,
    );
    final bh = live.asBlackhole();
    // ignore: avoid_print
    print('asBlackhole: blockPagePort=${bh.blockPagePort} '
        'blockQuic=${bh.blockQuic} blockEncryptedDns=${bh.blockEncryptedDns} '
        'tunnelDnsForAll=${bh.tunnelDnsForAll}');
    expect(true, isTrue);
  });
}
