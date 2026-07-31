import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// ВРЕМЕННЫЙ дамп конфигов для разбора DNS в режиме onlySelected.
void main() {
  const sites = [
    SiteRule('rutracker.org', action: AppAction.direct),
    SiteRule('youtube.com', action: AppAction.tunnel),
    SiteRule('ads.example', action: AppAction.block),
    SiteRule('gosuslugi.ru', action: AppAction.direct),
  ];
  const apps = [
    AppRule(r'C:\Chrome\chrome.exe', byName: true, action: AppAction.tunnel),
    AppRule(r'C:\Telegram\Telegram.exe', byName: true, action: AppAction.tunnel),
    AppRule(r'C:\Discord\Discord.exe', byName: true, action: AppAction.direct),
    AppRule(r'C:\Steam\steam.exe', byName: true, action: AppAction.direct),
    AppRule(r'C:\Bad\bad.exe', byName: true, action: AppAction.block),
  ];

  final outDir = Directory('build/dns-dump')..createSync(recursive: true);

  for (final tunnelDns in [false, true]) {
    for (final upstream in ['', '192.168.1.1']) {
      test('onlySelected tunnelDnsForAll=$tunnelDns upstream="$upstream"', () {
        final json = SingboxConfigBuilder(
          options: TunOptions(
            serverIps: const ['203.0.113.10'],
            serverDomains: const ['silentgate.lol'],
            tunnelDnsForAll: tunnelDns,
            directDnsUpstream: upstream.isEmpty ? null : upstream,
          ),
        ).buildJson(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites));
        final name =
            'only_${tunnelDns ? 'tunneldns' : 'localdns'}_${upstream.isEmpty ? 'nolocal' : 'withlocal'}.json';
        File('${outDir.path}/$name').writeAsStringSync(json);
        final cfg = jsonDecode(json) as Map<String, dynamic>;
        // ignore: avoid_print
        print('=== $name  dns.final=${(cfg['dns'] as Map)['final']} '
            'route.final=${(cfg['route'] as Map)['final']}');
        // ignore: avoid_print
        print(const JsonEncoder.withIndent('  ').convert(cfg['dns']));
      });
    }
  }

  test('all + tunnelDnsForAll=false (для сравнения)', () {
    final json = SingboxConfigBuilder(
      options: const TunOptions(
        serverIps: ['203.0.113.10'],
        serverDomains: ['silentgate.lol'],
        tunnelDnsForAll: false,
        directDnsUpstream: '192.168.1.1',
      ),
    ).buildJson(const SplitTunnelConfig(
        mode: SplitMode.all, apps: apps, sites: sites));
    File('${outDir.path}/all_localdns.json').writeAsStringSync(json);
    final cfg = jsonDecode(json) as Map<String, dynamic>;
    // ignore: avoid_print
    print('=== all  dns.final=${(cfg['dns'] as Map)['final']} '
        'route.final=${(cfg['route'] as Map)['final']}');
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(cfg['dns']));
  });
}
