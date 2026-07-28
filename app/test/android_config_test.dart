import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';

/// Конфиг, который Android-движок отдаёт ядру.
///
/// Проверяется здесь, а не тулзой в `tool/`, по прозаичной причине: `dart run`
/// в этом проекте не работает — build hooks пакета `jni` тянут `dart:ui`,
/// недоступный вне Flutter. Тесты же исполняются полноценно.
///
/// Побочный эффект: каждый прогон кладёт конфиги в `build/android-config/`,
/// откуда их можно скормить настоящему ядру:
/// `sing-box check -c build/android-config/vless.json`.
const _fixtures = <String, VpnServer>{
  'vless': VpnServer(
    protocol: 'vless',
    remark: 'reality',
    address: 'example.com',
    port: 443,
    id: '11111111-2222-3333-4444-555555555555',
    flow: 'xtls-rprx-vision',
    network: 'tcp',
    security: 'reality',
    sni: 'www.google.com',
    fingerprint: 'chrome',
    publicKey: 'jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0',
    shortId: '0123abcd',
    rawLink: 'vless://fixture',
  ),
  'ws': VpnServer(
    protocol: 'vless',
    remark: 'ws-tls',
    address: 'example.com',
    port: 443,
    id: '11111111-2222-3333-4444-555555555555',
    network: 'ws',
    security: 'tls',
    sni: 'example.com',
    host: 'example.com',
    path: '/ws',
    rawLink: 'vless://fixture-ws',
  ),
  'trojan': VpnServer(
    protocol: 'trojan',
    remark: 'trojan',
    address: 'example.com',
    port: 443,
    id: 'secret',
    network: 'tcp',
    security: 'tls',
    sni: 'example.com',
    rawLink: 'trojan://fixture',
  ),
  'hysteria2': VpnServer(
    protocol: 'hysteria2',
    remark: 'hy2',
    address: 'example.com',
    port: 443,
    id: 'secret',
    network: 'quic',
    security: 'tls',
    sni: 'example.com',
    rawLink: 'hysteria2://fixture',
  ),
};

Map<String, dynamic> _androidConfig(
  VpnServer server, {
  AppSettings settings = const AppSettings(),
}) =>
    SingboxConfigBuilder(
      options: TunOptions.fromSettings(settings,
          serverIps: const ['93.184.216.34'], android: true),
      proxyOutbound: SingboxOutboundFactory.build(server),
    ).buildMap(settings.splitTunnel);

void main() {
  final outDir = Directory('build/android-config');

  setUpAll(() => outDir.createSync(recursive: true));

  group('Конфиг Android: выгрузка для проверки настоящим ядром', () {
    for (final entry in _fixtures.entries) {
      test('${entry.key} — конфиг собирается и выгружается', () {
        final map = _androidConfig(entry.value);
        File('${outDir.path}/${entry.key}.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(map));
        expect(map['outbounds'], isNotEmpty);
      });
    }
  });

  group('Конфиг Android: чего в нём быть НЕ должно', () {
    late Map<String, dynamic> tun;
    late List rules;

    setUp(() {
      final map = _androidConfig(_fixtures['vless']!);
      tun = (map['inbounds'] as List).first as Map<String, dynamic>;
      rules = (map['route'] as Map)['rules'] as List;
    });

    test('нет полей TUN, которых на Android не существует', () {
      // Туннель создаёт VpnService, а не ядро: имя интерфейса, автомаршруты,
      // strict_route и выбор стека — понятия Windows/Linux. Ядро 1.13
      // отвергает их для платформенного TUN, и подключение падает.
      for (final key in const [
        'interface_name',
        'auto_route',
        'strict_route',
        'stack',
      ]) {
        expect(tun.containsKey(key), isFalse,
            reason: '$key не должен попадать в TUN-инбаунд на Android');
      }
    });

    test('нет правил по именам процессов Windows', () {
      // process_name со значениями xray.exe/sing-box.exe на Android не
      // матчится никогда, а на API<29 ядро вообще не умеет искать процесс.
      final withProcess = rules.where((r) => (r as Map).containsKey('process_name'));
      expect(withProcess, isEmpty);
    });
  });

  group('Конфиг Android: что в нём быть ОБЯЗАНО', () {
    test('свой пакет исключён из туннеля — иначе петля', () {
      // Трафик самого приложения (подписка, пинг) обязан идти мимо VPN.
      final map = _androidConfig(_fixtures['vless']!);
      final tun = (map['inbounds'] as List).first as Map<String, dynamic>;
      expect(tun['exclude_package'], contains('lol.silentgate'));
    });

    test('прокси-outbound встроен, промежуточного SOCKS нет', () {
      // На Android ядро одно: SOCKS-переход к отдельному Xray отсутствует.
      final map = _androidConfig(_fixtures['vless']!);
      final proxy = (map['outbounds'] as List)
          .firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
      expect(proxy['type'], 'vless');
      expect(proxy['server'], 'example.com');
    });

    test('DNS резолвится через прокси, а не системным резолвером', () {
      // Фикс утечки DNS 0.11.1: final ВСЕГДА dns-proxy.
      final map = _androidConfig(_fixtures['vless']!);
      expect(((map['dns'] as Map)['final']), 'dns-proxy');
    });
  });
}
