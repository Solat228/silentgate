import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Обходные пути, из-за которых доменные правила «молча не работают».
void main() {
  List<Map<String, dynamic>> rules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  const split = SplitTunnelConfig(
    mode: SplitMode.exceptSelected,
    sites: [SiteRule('example.com', action: AppAction.tunnel)],
  );

  Map<String, dynamic> build({bool quic = false, bool dns = false}) =>
      SingboxConfigBuilder(
        options: TunOptions(
          blockQuic: quic,
          blockEncryptedDns: dns,
          serverIps: const ['203.0.113.7'],
        ),
      ).buildMap(split);

  test('по умолчанию ничего не режется', () {
    final r = rules(build());
    expect(r.any((x) => x['action'] == 'reject'), isFalse);
  });

  test('QUIC: отказ по UDP:443', () {
    final r = rules(build(quic: true));
    final quic = r.firstWhere((x) =>
        x['network'] == 'udp' && (x['port'] as List?)?.contains(443) == true);
    expect(quic['action'], 'reject');
  });

  // Порядок здесь не вкусовой: у hysteria2 транспорт — QUIC на UDP:443, и
  // запрет ВЫШЕ правила с IP сервера убил бы собственное подключение.
  test('запрет QUIC стоит НИЖЕ защиты от петли', () {
    final r = rules(build(quic: true));
    final serverRule = r.indexWhere((x) =>
        (x['ip_cidr'] as List?)?.any((c) => '$c'.startsWith('203.0.113.7')) ==
        true);
    final quicRule = r.indexWhere((x) => x['network'] == 'udp');
    expect(serverRule, isNonNegative);
    expect(serverRule, lessThan(quicRule),
        reason: 'иначе собственный hysteria2-сервер окажется заблокирован');
  });

  test('шифрованный DNS: 853 и известные резолверы по имени и по IP', () {
    final r = rules(build(dns: true));
    expect(
        r.any((x) =>
            x['network'] == 'tcp' &&
            (x['port'] as List?)?.contains(853) == true &&
            x['action'] == 'reject'),
        isTrue,
        reason: 'DoT');
    expect(
        r.any((x) =>
            x['network'] == 'udp' &&
            (x['port'] as List?)?.contains(853) == true),
        isTrue,
        reason: 'DoQ');
    final byName = r.firstWhere((x) =>
        (x['domain_suffix'] as List?)?.contains('cloudflare-dns.com') == true);
    expect(byName['port'], [443]);
    expect(byName['action'], 'reject');
    // Браузер умеет ходить к резолверу по голому IP — имени тогда нет вовсе.
    final byIp = r.firstWhere((x) =>
        (x['ip_cidr'] as List?)?.contains('1.1.1.1/32') == true);
    expect(byIp['action'], 'reject');
  });

  test('обычный DNS на 53 не задет: его перехватывают, а не режут', () {
    final r = rules(build(dns: true));
    expect(r.any((x) => x['action'] == 'hijack-dns'), isTrue);
    expect(
        r.any((x) =>
            x['action'] == 'reject' &&
            (x['port'] as List?)?.contains(53) == true),
        isFalse);
  });

  test('конфиг принимается настоящим ядром', () async {
    final exe = File('../engine/windows/bin/sing-box.exe');
    if (!exe.existsSync()) return; // ядра нет — проверять нечем

    final dir = Directory('build/emit')..createSync(recursive: true);
    final f = File('${dir.path}/interception.json');
    f.writeAsStringSync(SingboxConfigBuilder(
      options: const TunOptions(
        blockQuic: true,
        blockEncryptedDns: true,
        serverIps: ['203.0.113.7'],
      ),
    ).buildJson(split));

    final r = await Process.run(exe.path, ['check', '-c', f.path]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });
}
