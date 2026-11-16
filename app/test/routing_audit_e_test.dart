import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/xray/panel_direct_reroute.dart';

/// Находки аудита 25.10.2026, блок E (маршрутизация).
void main() {
  group('VLESS в sing-box', () {
    test('encryption ссылки не превращается в packet_encoding', () {
      const s = VpnServer(
        protocol: 'vless',
        remark: 'x',
        address: '203.0.113.10',
        port: 443,
        id: '00000000-0000-0000-0000-000000000000',
        encryption: 'mlkem768x25519plus.native.0rtt.abc',
        rawLink: '',
      );
      final out = SingboxOutboundFactory.build(s);
      expect(out.containsKey('packet_encoding'), isFalse,
          reason: 'sing-box принимает только xudp/packetaddr — иное роняет '
              'весь конфиг');
    });
  });

  group('реврайт direct панельного профиля', () {
    Map<String, dynamic> run(Map<String, dynamic> cfg) =>
        jsonDecode(rerouteDirectThroughVpn(jsonEncode(cfg)))
            as Map<String, dynamic>;

    List rules(Map<String, dynamic> cfg) =>
        (cfg['routing'] as Map)['rules'] as List;

    test('прямой выход с чужим именем тоже уводится в VPN', () {
      final out = run({
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless'},
          {'tag': 'DIRECT', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {'type': 'field', 'domain': ['geosite:ru'], 'outboundTag': 'DIRECT'},
          ]
        },
      });
      final ru = rules(out).firstWhere(
          (r) => (r['domain'] as List?)?.contains('geosite:ru') ?? false);
      expect(ru['outboundTag'], 'proxy');
    });

    test('смешанный список доменов разбивается: LAN прямо, остальное в VPN',
        () {
      final out = run({
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless'},
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {
              'type': 'field',
              'domain': ['geosite:private', 'geosite:ru'],
              'outboundTag': 'direct',
            },
          ]
        },
      });
      final byDomain = {
        for (final r in rules(out))
          if (r['domain'] is List) (r['domain'] as List).join(','): r,
      };
      expect(byDomain['geosite:private']?['outboundTag'], 'direct');
      expect(byDomain['geosite:ru']?['outboundTag'], 'proxy',
          reason: 'российские домены шли под реальным IP');
    });

    test('повторный проход не плодит правил', () {
      final cfg = {
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless'},
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {
              'type': 'field',
              'domain': ['geosite:private', 'geosite:ru'],
              'outboundTag': 'direct',
            },
          ]
        },
      };
      final once = rerouteDirectThroughVpn(jsonEncode(cfg));
      expect(rerouteDirectThroughVpn(once), once);
    });
  });
}
