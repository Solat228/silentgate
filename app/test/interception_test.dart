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

  // Раньше здесь проверялось, что по умолчанию не режется НИЧЕГО. Это утверждение
  // отменено осознанно: правило по сайту без запрета QUIC молча не работает, и
  // трафик утекал напрямую (см. `leak_audit_test.dart`). Набор `split` выше как
  // раз содержит правило по сайту, поэтому UDP:443 теперь режется сам.
  test('без явных настроек режется только QUIC — ради доменных правил', () {
    final r = rules(build());
    final rejects = r.where((x) => x['action'] == 'reject').toList();
    expect(rejects, hasLength(1));
    expect(rejects.single['network'], 'udp');
    expect((rejects.single['port'] as List).contains(443), isTrue);
  });

  test('без правил по сайтам не режется ничего', () {
    final cfg = SingboxConfigBuilder(
      options: const TunOptions(serverIps: ['203.0.113.7']),
    ).buildMap(const SplitTunnelConfig(
      mode: SplitMode.exceptSelected,
      apps: [AppRule('chrome.exe', byName: true, action: AppAction.tunnel)],
    ));
    expect(rules(cfg).any((x) => x['action'] == 'reject'), isFalse,
        reason: 'приложения матчатся по процессу — QUIC им безразличен');
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

  _ipv6Guards();
}

/// Выключенный IPv6 в туннеле раньше означал «IPv6 уходит мимо VPN».
void _ipv6Guards() {
  List<Map<String, dynamic>> rules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> build({required bool ipv6}) => SingboxConfigBuilder(
        options: TunOptions(ipv6: ipv6, serverIps: const ['203.0.113.7']),
      ).buildMap(const SplitTunnelConfig(mode: SplitMode.all));

  group('IPv6 без туннеля не утекает', () {
    test('выключенный IPv6 отвергается, а не пропускается мимо', () {
      final r = rules(build(ipv6: false));
      expect(
          r.any((x) => x['ip_version'] == 6 && x['action'] == 'reject'), isTrue,
          reason: 'иначе IPv6-трафик идёт через физический адаптер под реальным IP');
    });

    test('включённый IPv6 идёт в туннель как прежде', () {
      final r = rules(build(ipv6: true));
      expect(r.any((x) => x['ip_version'] == 6), isFalse);
    });

    test('оба ядра принимают конфиг с отказом IPv6', () async {
      // Поле `ip_version` появилось не во всех версиях одинаково, а конфиг
      // отвергается ЦЕЛИКОМ — на этом уже обжигались с DNS-действием
      // `predefined`. Проверяем обеими: 1.11.15 (Windows) и 1.13.14 (Android).
      final dir = Directory('build/emit')..createSync(recursive: true);
      final f = File('${dir.path}/no-ipv6.json')
        ..writeAsStringSync(SingboxConfigBuilder(
          options: const TunOptions(ipv6: false, serverIps: ['203.0.113.7']),
        ).buildJson(const SplitTunnelConfig(mode: SplitMode.all)));

      for (final exe in [
        File('../engine/windows/bin/sing-box.exe'),
        File(r'C:\dev\android\out\sing-box-1.13.14.exe'),
      ]) {
        if (!exe.existsSync()) continue;
        final r = await Process.run(exe.path, ['check', '-c', f.path]);
        expect(r.exitCode, 0,
            reason: '${exe.path} отверг конфиг: ${r.stdout}${r.stderr}');
      }
    });

    test('отказ стоит НИЖЕ адреса сервера', () {
      // Сервер может быть доступен по IPv6 — наверху правило убило бы связь.
      final r = rules(build(ipv6: false));
      final v6 = r.indexWhere((x) => x['ip_version'] == 6);
      final server = r.indexWhere((x) =>
          (x['ip_cidr'] as List?)?.any((c) => '$c'.startsWith('203.0.113.7')) ==
          true);
      expect(server, lessThan(v6));
    });
  });
}
