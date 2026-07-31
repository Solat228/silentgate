import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Режим DNS «системный» под TUN оставлял конфиг БЕЗ dns-секции и БЕЗ перехвата.
/// Туннель при этом объявляет себя DNS-сервером адаптера, и запросы уходили на
/// адрес, где никто не слушает: ни одно имя не резолвилось, а сеть выглядела
/// живой — «всё зависает, прямого блока нет».
void main() {
  const split = SplitTunnelConfig(mode: SplitMode.onlySelected);

  Map<String, dynamic> build(DnsMode mode) => SingboxConfigBuilder(
        options: TunOptions(
          dnsMode: mode,
          dnsHijack: true,
          serverIps: const ['203.0.113.4'],
          directDnsUpstream: '192.168.1.1',
        ),
      ).buildMap(split);

  List<Map<String, dynamic>> rules(Map<String, dynamic> c) =>
      ((c['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  bool hijacks(Map<String, dynamic> c) =>
      rules(c).any((r) => r['action'] == 'hijack-dns');

  for (final mode in DnsMode.values) {
    test('перехват DNS есть в режиме ${mode.name}', () {
      expect(hijacks(build(mode)), isTrue,
          reason: 'без перехвата запросы уходят на 172.19.0.2, где никто не '
              'слушает, и не резолвится НИЧЕГО');
    });

    test('DNS-секция есть в режиме ${mode.name}', () {
      final dns = build(mode)['dns'];
      expect(dns, isNotNull,
          reason: 'туннель объявляет себя резолвером — отвечать обязан кто-то');
      expect((dns as Map)['servers'], isNotEmpty);
    });
  }

  test('в системном режиме резолв идёт апстримом системы, не через прокси', () {
    final dns = build(DnsMode.system)['dns'] as Map;
    expect(dns['final'], 'dns-local');
    final local = (dns['servers'] as List)
        .cast<Map>()
        .firstWhere((s) => s['tag'] == 'dns-local');
    expect(local['address'], 'udp://192.168.1.1');
    expect(local['detour'], 'direct');
  });

  test('перехваченный DNS не попадает под «приватные адреса → напрямую»', () {
    final r = rules(build(DnsMode.system));
    final hijack = r.indexWhere((x) => x['action'] == 'hijack-dns');
    final private = r.indexWhere((x) => x['ip_is_private'] == true);
    expect(hijack, greaterThanOrEqualTo(0));
    if (private >= 0) {
      expect(hijack, lessThan(private),
          reason: 'иначе DNS ловится правилом приватных адресов — ровно это и '
              'ломало резолв целиком');
    }
  });

  test('конфиг системного режима принимается обоими ядрами', () async {
    final f = File('build/emit/dns-system.json');
    await f.parent.create(recursive: true);
    await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(build(DnsMode.system)));
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
