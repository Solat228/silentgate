import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Петля резолва: чтобы дойти до VPN-сервера, нужен его адрес; а адрес
/// спрашивается через туннель, которого ещё нет. В логе владельца это дало
/// десятки строк «dns: exchange failed for …silentgate.lol», а снаружи —
/// «ничего не работает»: туннель поднят, трафика нет.
void main() {
  const domains = [
    'usa.silentgate.lol',
    'ws-nl.silentgate.lol',
    'spb3.silentgate.lol',
    'sub.silentgate.lol',
  ];

  Map<String, dynamic> build({
    List<String> serverDomains = domains,
    SplitTunnelConfig split = const SplitTunnelConfig(),
  }) =>
      SingboxConfigBuilder(
        options: TunOptions(
          serverIps: const ['77.110.126.51'],
          serverDomains: serverDomains,
        ),
      ).buildMap(split);

  List<Map<String, dynamic>> dnsRules(Map<String, dynamic> c) =>
      (((c['dns'] as Map)['rules']) as List).cast<Map<String, dynamic>>();

  test('имена нашей инфраструктуры резолвятся НАПРЯМУЮ', () {
    final r = dnsRules(build());
    final rule = r.firstWhere(
        (x) => (x['domain_suffix'] as List?)?.contains('usa.silentgate.lol') == true,
        orElse: () => {});
    expect(rule, isNotEmpty, reason: 'правила для серверов нет вовсе');
    expect(rule['server'], 'dns-local',
        reason: 'через туннель их резолвить нельзя — это и есть петля');
  });

  test('правило стоит ПЕРВЫМ — выше пользовательских', () {
    // Иначе домен сервера, случайно попавший под правило «Туннель», убил бы
    // подключение целиком.
    final r = dnsRules(build(
      split: const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('silentgate.lol', action: AppAction.tunnel)],
      ),
    ));
    final infra = r.indexWhere(
        (x) => (x['domain_suffix'] as List?)?.contains('usa.silentgate.lol') == true);
    expect(infra, 0, reason: 'инфраструктура обязана идти первой');
  });

  test('хост подписки тоже резолвится напрямую', () {
    // Иначе обновить подписку нельзя ровно тогда, когда серверы отвалились.
    final r = dnsRules(build());
    expect(
        r.any((x) =>
            (x['domain_suffix'] as List?)?.contains('sub.silentgate.lol') == true &&
            x['server'] == 'dns-local'),
        isTrue);
  });

  test('без списка имён лишнего правила не появляется', () {
    final r = dnsRules(build(serverDomains: const []));
    expect(r.any((x) => x['domain_suffix'] != null && x['server'] == 'dns-local'
        && (x['domain_suffix'] as List).any((d) => '$d'.contains('silentgate'))),
        isFalse);
  });

  test('конфиг с этим правилом принимают ОБА ядра', () async {
    final f = File('build/emit/dns-loop.json');
    await f.parent.create(recursive: true);
    await f.writeAsString(SingboxConfigBuilder(
      options: const TunOptions(
        serverIps: ['77.110.126.51'],
        serverDomains: domains,
      ),
    ).buildJson(const SplitTunnelConfig()));

    for (final exe in [
      r'C:\dev\android\out\sing-box-1.13.14.exe',
      '../engine/windows/bin/sing-box.exe',
    ]) {
      if (!File(exe).existsSync()) continue;
      final r = await Process.run(exe, ['check', '-c', f.path]);
      expect(r.exitCode, 0, reason: '$exe отверг конфиг:\n${r.stdout}${r.stderr}');
    }
  });
}
