import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// ВРЕМЕННЫЙ тест: выгружает конфиги режимов all / onlySelected с набором
/// правил владельца (5 приложений + 4 сайта) для сравнения. Ничего не поднимает.
void main() {
  const apps = [
    AppRule(r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        byName: true, action: AppAction.tunnel),
    AppRule(r'C:\Users\User\AppData\Roaming\Telegram Desktop\Telegram.exe',
        byName: true, action: AppAction.tunnel),
    AppRule(r'C:\Program Files\Discord\Discord.exe',
        byName: true, action: AppAction.tunnel),
    AppRule(r'C:\Program Files (x86)\Steam\steam.exe',
        byName: true, action: AppAction.direct),
    AppRule(r'C:\Games\bad.exe', byName: true, action: AppAction.block),
  ];
  const sites = [
    SiteRule('youtube.com', action: AppAction.tunnel),
    SiteRule('chatgpt.com', action: AppAction.tunnel),
    SiteRule('nalog.ru', action: AppAction.direct),
    SiteRule('ads.example', action: AppAction.block),
  ];

  final outDir = Directory('build/split-diff')..createSync(recursive: true);

  // Опции ровно как их строит WindowsEngine на живом подключении.
  TunOptions opts({bool ipv6 = false, bool tunnelDnsForAll = true}) => TunOptions(
        serverIps: const ['203.0.113.10'],
        serverDomains: const ['silentgate.lol'],
        directDnsUpstream: '192.168.1.1',
        stack: 'system',
        ipv6: ipv6,
        tunnelDnsForAll: tunnelDnsForAll,
      );

  void dump(String name, SplitMode mode,
      {bool ipv6 = false, bool tunnelDnsForAll = true}) {
    final json = SingboxConfigBuilder(
      xraySocksPort: 10808,
      options: opts(ipv6: ipv6, tunnelDnsForAll: tunnelDnsForAll),
    ).buildJson(SplitTunnelConfig(mode: mode, apps: apps, sites: sites));
    File('${outDir.path}/$name.json').writeAsStringSync(json);

    final cfg = jsonDecode(json) as Map<String, dynamic>;
    final route = cfg['route'] as Map;
    final dns = cfg['dns'] as Map?;
    final buf = StringBuffer();
    buf.writeln('=== $name ===');
    buf.writeln('route.final = ${route['final']}');
    var i = 0;
    for (final r in (route['rules'] as List).cast<Map>()) {
      buf.writeln('  [$i] ${jsonEncode(r)}');
      i++;
    }
    buf.writeln('dns.final = ${dns?['final']}');
    i = 0;
    for (final r in ((dns?['rules'] as List?) ?? const []).cast<Map>()) {
      buf.writeln('  dns[$i] ${jsonEncode(r)}');
      i++;
    }
    buf.writeln('dns.servers = ${jsonEncode(dns?['servers'])}');
    File('${outDir.path}/$name.txt').writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print(buf.toString());
  }

  test('dump all vs onlySelected', () {
    dump('all', SplitMode.all);
    dump('only', SplitMode.onlySelected);
    dump('all_ipv6', SplitMode.all, ipv6: true);
    dump('only_ipv6', SplitMode.onlySelected, ipv6: true);
    dump('only_dnslocal', SplitMode.onlySelected, tunnelDnsForAll: false);
    dump('except', SplitMode.exceptSelected);
  });
}
