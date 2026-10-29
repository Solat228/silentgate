import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/panel_direct_reroute.dart';
import 'package:silentgate/core/xray/xray_keys.dart';
import 'package:silentgate/core/xray/xray_outbound_factory.dart';

/// Ревью 29.10.2026: ключи Xray-JSON без учёта регистра (H3), слушатели `api`
/// и `metrics` (M1, L14), `masterKeyLog` (L15), запасной выход балансера (M3),
/// подстрока `private` (L7).
void main() {
  Map<String, dynamic> canon(Map<String, dynamic> m) =>
      jsonDecode(canonicalXrayJson(jsonEncode(m))) as Map<String, dynamic>;

  group('canonicalXrayValue (H3)', () {
    test('известные ключи приводятся к каноническому написанию', () {
      final c = canon({
        'Log': {'Access': 'C:/x.log', 'LogLevel': 'warning'},
        'Inbounds': [
          {'Protocol': 'socks', 'Listen': '0.0.0.0', 'Port': 1},
        ],
        'Routing': {
          'Rules': [
            {'OutboundTag': 'direct', 'IP': ['geoip:ru']},
          ],
        },
        'Api': {'Services': ['HandlerService']},
      });
      expect(c.keys, containsAll(['log', 'inbounds', 'routing', 'api']));
      expect((c['log'] as Map).keys, containsAll(['access', 'loglevel']));
      final inb = (c['inbounds'] as List).first as Map;
      expect(inb['listen'], '0.0.0.0');
      expect(inb['protocol'], 'socks');
      final rule = ((c['routing'] as Map)['rules'] as List).first as Map;
      expect(rule['outboundTag'], 'direct');
      expect(rule['ip'], ['geoip:ru']);
      expect((c['api'] as Map)['services'], ['HandlerService']);
    });

    test('ключи-данные не трогаются', () {
      final c = canon({
        'outbounds': [
          {
            'streamSettings': {
              'wsSettings': {
                'headers': {'Host': 'example.com', 'X-Custom': '1'},
              },
            },
          },
        ],
      });
      final h = (((c['outbounds'] as List).first as Map)['streamSettings']
          as Map)['wsSettings']['headers'] as Map;
      expect(h.keys, ['Host', 'X-Custom']);
    });

    test('заголовки Host и host вместе — не дубликат', () {
      final c = canon({
        'headers': {'Host': 'a', 'host': 'b'},
      });
      expect((c['headers'] as Map).keys, ['Host', 'host']);
    });

    test('ключ в двух написаниях — отказ', () {
      expect(
          () => canonicalXrayJson(jsonEncode({
                'log': {'access': 'x'},
                'Log': {'loglevel': 'warning'},
              })),
          throwsA(isA<XrayDuplicateKeyException>()));
      expect(
          () => canonicalXrayJson(
              '{"inbounds":[{"listen":"127.0.0.1","LISTEN":"0.0.0.0"}]}'),
          throwsA(isA<XrayDuplicateKeyException>()));
    });

    test('не JSON возвращается как есть', () {
      expect(canonicalXrayJson('не json'), 'не json');
    });

    test('после канонизации нормализатор видит журнал и слушателя', () {
      final raw = canonicalXrayJson(jsonEncode({
        'Log': {'Access': 'C:/Users/x/Startup/a.bat'},
        'Inbounds': [
          {'Protocol': 'socks', 'Listen': '0.0.0.0', 'Port': 1, 'Tag': 's'},
        ],
      }));
      final out = jsonDecode(
              normalizeOverridePorts(raw, socksPort: 10808, httpPort: 10809)
                  .json) as Map;
      expect((out['log'] as Map).containsKey('access'), isFalse);
      final socks = (out['inbounds'] as List).first as Map;
      expect(socks['listen'], '127.0.0.1');
      expect(socks['port'], 10808);
    });
  });

  group('слушатели и запись файлов (M1, L14, L15)', () {
    Map normalized(Map<String, dynamic> cfg) => jsonDecode(
        normalizeOverridePorts(jsonEncode(cfg),
                socksPort: 10808, httpPort: 10809)
            .json) as Map;

    test('api.listen снимается, служба остаётся', () {
      final out = normalized({
        'api': {'tag': 'api', 'listen': '0.0.0.0:8080', 'services': ['StatsService']},
      });
      expect((out['api'] as Map).containsKey('listen'), isFalse);
      expect((out['api'] as Map)['tag'], 'api');
    });

    test('ensureXrayStats снимает api.listen', () {
      final out = jsonDecode(ensureXrayStats(
          jsonEncode({
            'api': {'tag': 'api', 'listen': '0.0.0.0:8080'},
          }),
          apiPort: 10085)) as Map;
      expect((out['api'] as Map).containsKey('listen'), isFalse);
    });

    test('metrics без тега удаляется, с тегом теряет listen', () {
      expect(
          normalized({
            'metrics': {'listen': '0.0.0.0:9000'},
          }).containsKey('metrics'),
          isFalse);
      final tagged = normalized({
        'metrics': {'tag': 'metrics', 'listen': '0.0.0.0:9000'},
      })['metrics'] as Map;
      expect(tagged.containsKey('listen'), isFalse);
      expect(tagged['tag'], 'metrics');
    });

    test('masterKeyLog снимается на любой глубине и в любом написании', () {
      final out = normalized({
        'outbounds': [
          {
            'protocol': 'vless',
            'streamSettings': {
              'security': 'tls',
              'tlsSettings': {'serverName': 'a', 'masterKeyLog': 'C:/k.log'},
              'realitySettings': {'MasterKeyLog': 'C:/k2.log'},
            },
          },
        ],
      });
      expect(jsonEncode(out).toLowerCase(), isNot(contains('masterkeylog')));
      expect(jsonEncode(out), contains('serverName'));
    });

    test('outbound панели: masterKeyLog снят, ключи канонические', () {
      final server = VpnServer(
        protocol: 'vless',
        remark: 'p',
        rawLink: 'vless://00000000-0000-0000-0000-000000000000@203.0.113.10:443#p',
        address: '203.0.113.10',
        port: 443,
        id: '00000000-0000-0000-0000-000000000000',
        rawOutboundJson: jsonEncode({
          'Protocol': 'vless',
          'Tag': 'proxy',
          'StreamSettings': {
            'security': 'tls',
            'tlsSettings': {'serverName': 'a', 'masterKeyLog': 'C:/k.log'},
          },
        }),
      );
      final out = XrayOutboundFactory.build(server, tag: 'proxy').first;
      expect(jsonEncode(out).toLowerCase(), isNot(contains('masterkeylog')));
      expect(out['tag'], 'proxy');
      expect(out.containsKey('Tag'), isFalse);
      expect(out.containsKey('streamSettings'), isTrue);
    });
  });

  group('реврайт direct (M3, L7)', () {
    Map reroute(Map<String, dynamic> cfg) =>
        jsonDecode(rerouteDirectThroughVpn(jsonEncode(cfg))) as Map;

    test('fallbackTag "direct" у балансера уводится на прокси', () {
      final out = reroute({
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'proxy-1', 'protocol': 'vless'},
          {'tag': 'other', 'protocol': 'vless'},
        ],
        'routing': {
          'rules': <dynamic>[],
          'balancers': [
            {'tag': 'b', 'selector': ['proxy'], 'fallbackTag': 'direct'},
          ],
        },
      });
      final b = ((out['routing'] as Map)['balancers'] as List).first as Map;
      expect(b['fallbackTag'], 'proxy-1');
    });

    test('fallbackTag на freedom с другим именем тоже уводится', () {
      final out = reroute({
        'outbounds': [
          {'tag': 'ru-direct', 'protocol': 'freedom'},
          {'tag': 'x', 'protocol': 'trojan'},
        ],
        'routing': {
          'rules': <dynamic>[],
          'balancers': [
            {'tag': 'b', 'selector': ['nope'], 'fallbackTag': 'ru-direct'},
          ],
        },
      });
      final b = ((out['routing'] as Map)['balancers'] as List).first as Map;
      expect(b['fallbackTag'], 'x');
    });

    test('fallbackTag на прокси не трогается', () {
      final out = reroute({
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'p', 'protocol': 'vless'},
          {'tag': 'q', 'protocol': 'vless'},
        ],
        'routing': {
          'rules': <dynamic>[],
          'balancers': [
            {'tag': 'b', 'selector': ['p', 'q'], 'fallbackTag': 'q'},
          ],
        },
      });
      final b = ((out['routing'] as Map)['balancers'] as List).first as Map;
      expect(b['fallbackTag'], 'q');
    });

    test('домен с подстрокой private уходит в VPN', () {
      final out = reroute({
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless'},
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {
              'type': 'field',
              'domain': ['domain:privateinternetaccess.com', 'geosite:private'],
              'outboundTag': 'direct',
            },
          ],
        },
      });
      final rules = (out['routing'] as Map)['rules'] as List;
      final direct = rules
          .whereType<Map>()
          .where((r) => r['outboundTag'] == 'direct' && r['domain'] != null)
          .expand((r) => r['domain'] as List)
          .toList();
      expect(direct, ['geosite:private']);
      final proxied = rules
          .whereType<Map>()
          .where((r) => r['outboundTag'] == 'proxy' && r['domain'] != null)
          .expand((r) => r['domain'] as List)
          .toList();
      expect(proxied, ['domain:privateinternetaccess.com']);
    });

    test('ext:<файл>:private остаётся локальной сетью', () {
      final out = reroute({
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless'},
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {
              'type': 'field',
              'ip': ['ext:geoip.dat:private'],
              'outboundTag': 'direct',
            },
          ],
        },
      });
      final rules = (out['routing'] as Map)['rules'] as List;
      expect(
          rules.whereType<Map>().any((r) =>
              r['outboundTag'] == 'direct' &&
              (r['ip'] as List?)?.contains('ext:geoip.dat:private') == true),
          isTrue);
    });
  });
}
