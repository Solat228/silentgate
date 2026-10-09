import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_router_config_builder.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_harness_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';

/// Каждый вид конфига sing-box, который строит приложение, обязан приниматься
/// ОФИЦИАЛЬНОЙ сборкой ядра под Windows БЕЗ единого предупреждения.
///
/// ⚠️ ЗАЧЕМ «без предупреждения», а не просто «код 0». С 1.15.0 Windows
/// перешёл с sing-box 1.11.15 на 1.13.14. Официальная сборка 1.13 на
/// устаревшем поле не предупреждает, а ОТВЕРГАЕТ конфиг целиком
/// (`FATAL … set environment variable ENABLE_DEPRECATED_…`) — так случилось со
/// старым форматом DNS-серверов, который 1.11 и наш libbox на Android
/// принимали молча. А то, что в 1.13 только предупреждение, в 1.14 станет
/// ошибкой. Поэтому любое `deprecated` в выводе — уже провал.
///
/// Проверяются ВСЕ построители, а не один: каждый из них — отдельный путь к
/// ядру, и прежде дыры находились именно в «втором» пути.
void main() {
  final exe = File('../engine/windows/bin/sing-box.exe');

  final vless = ShareLinkParser.tryParse(
      'vless://11111111-2222-3333-4444-555555555555@exit.example.com:443'
      '?security=reality&sni=www.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
      '&sid=ab&fp=chrome&type=tcp#Exit')!;
  final hy2 = ShareLinkParser.tryParse('hysteria2://pwd@hy.example.com:8443'
      '?sni=hy.example.com&obfs=salamander&obfs-password=x#Hy2')!;
  final exitKey = vless.rawLink;
  final exitOut = {
    ...SingboxOutboundFactory.build(vless),
    'tag': exitTagFor(exitKey),
  };

  const split = SplitTunnelConfig(
    mode: SplitMode.exceptSelected,
    sites: [
      SiteRule('ads.example', action: AppAction.block),
      SiteRule('direct.example'),
      SiteRule('tunnel.example', action: AppAction.tunnel),
    ],
    apps: [AppRule('chrome.exe', action: AppAction.tunnel)],
  );

  final configs = <String, String>{
    'tun-обычный': SingboxConfigBuilder(
      options: const TunOptions(serverIps: ['203.0.113.10']),
    ).buildJson(split),
    'tun-всё-сразу': SingboxConfigBuilder(
      exitOutbounds: [exitOut],
      options: const TunOptions(
        serverIps: ['203.0.113.10'],
        serverDomains: ['panel.example.com'],
        dnsMode: DnsMode.custom,
        dnsServer: 'dns.google',
        directDnsUpstream: '192.0.2.53',
        tunnelDnsForAll: true,
        fallbackDnsPort: 10814,
        directFallbackDnsPort: 10815,
        blockQuic: true,
        blockEncryptedDns: true,
        noRealIp: true,
        clashApiPort: 10813,
        clashApiSecret: 'test',
      ),
    ).buildJson(SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      sites: [
        SiteRule('de.example',
            action: AppAction.tunnel, serverKey: exitKey),
        SiteRule('direct.example'),
      ],
    )),
    'tun-системный-dns': const SingboxConfigBuilder(
      options: TunOptions(dnsMode: DnsMode.system),
    ).buildJson(split),
    'tun-заглушка-kill-switch': SingboxConfigBuilder(
      options: const TunOptions().asBlackhole(),
    ).buildJson(split),
    'прокси-hysteria2': const SingboxProxyConfigBuilder(
      apiSecret: 's',
      user: 'u',
      password: 'p',
    ).buildJson([hy2]),
    'харнесс-пинга': const SingboxHarnessConfigBuilder()
        .withAuth('u', 'p')
        .buildJson([HarnessEntry(key: 'a', server: hy2)]),
    'только-прокси-выходы': ExitRouterConfigBuilder(
      serverKeys: [exitKey],
      token: 'tok',
      exitOutbounds: [exitOut],
      applyRules: true,
      split: split,
    ).buildJson(),
  };

  for (final MapEntry(key: name, value: json) in configs.entries) {
    test('официальное ядро Windows принимает «$name» без предупреждений',
        () async {
      if (!exe.existsSync()) {
        markTestSkipped('нет ${exe.path} — tools/fetch-singbox.ps1');
        return;
      }
      final f = File('build/singbox-guard/$name.json');
      await f.parent.create(recursive: true);
      await f.writeAsString(json);
      final r = await Process.run(exe.path, ['check', '-c', f.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(r.exitCode, 0, reason: '$name отвергнут:\n$out');
      expect(out.toLowerCase(), isNot(contains('deprecated')),
          reason: '$name: устаревшее поле — в 1.14 станет ошибкой:\n$out');
    });
  }

  test('ядро в поставке — 1.13.x (та же ветка, что libbox на Android)', () async {
    if (!exe.existsSync()) {
      markTestSkipped('нет ${exe.path}');
      return;
    }
    final r = await Process.run(exe.path, ['version']);
    expect('${r.stdout}', contains('sing-box version 1.13.'));
    final fetch = File('../tools/fetch-singbox.ps1').readAsStringSync();
    expect(fetch, contains(r"$ver = '1.13."));
  });
}
