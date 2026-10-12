import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/xray/balancer_pick.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/ui/home_screen.dart';

/// «Авто» показывает узел, выбранный балансировщиком (решение владельца
/// 24.09.2026). Ответ `xray api bi -json` снят с настоящего Xray 26.3.27 на
/// стенде из `freedom`-выходов — без единого VPN-сервера.
void main() {
  const uuid = '00000000-0000-0000-0000-000000000000';
  final de = ShareLinkParser.tryParse(
      'vless://$uuid@203.0.113.10:443?type=tcp&security=none'
      '&encryption=none#DE')!;
  final nl = ShareLinkParser.tryParse(
      'vless://$uuid@203.0.113.20:8443?type=tcp&security=none'
      '&encryption=none#NL')!;

  group('parseBi', () {
    test('выбор стратегии — живой ответ ядра', () {
      const out = '{\n "balancer": {\n  "override": {},\n'
          '  "principleTarget": {"tag": ["proxy-a"]}\n }\n}';
      expect(BalancerPick.parseBi(out, 'balancer'), 'proxy-a');
    });

    test('ручная подмена важнее выбора стратегии', () {
      const out = '{"auto":{"override":{"target":"proxy-7"},'
          '"principleTarget":{"tag":["proxy-2"]}}}';
      expect(BalancerPick.parseBi(out, 'auto'), 'proxy-7');
    });

    test('⚠️ холодный старт: пустой тег — это «не выбрал», а не узел', () {
      // Живой ответ ядра, когда все замеры провалились: трафик в этот момент
      // идёт через fallbackTag, и выдавать "" за узел нельзя.
      const out = '{"balancer":{"override":{},"principleTarget":{"tag":[""]}}}';
      expect(BalancerPick.parseBi(out, 'balancer'), isNull);
    });

    test('чужой тег, мусор и пустота — null без исключения', () {
      const out = '{"balancer":{"principleTarget":{"tag":["proxy-a"]}}}';
      expect(BalancerPick.parseBi(out, 'auto'), isNull);
      expect(BalancerPick.parseBi('set balancer tag', 'balancer'), isNull);
      expect(BalancerPick.parseBi('', 'balancer'), isNull);
    });
  });

  group('mainBalancerTag', () {
    test('основной — тот, на кого указывает ПОСЛЕДНЕЕ правило', () {
      final cfg = {
        'routing': {
          'balancers': [
            {'tag': 'yt'},
            {'tag': 'auto'},
          ],
          'rules': [
            {'domain': ['geosite:youtube'], 'balancerTag': 'yt'},
            {'network': 'tcp,udp', 'balancerTag': 'auto'},
          ],
        },
      };
      expect(BalancerPick.mainBalancerTag(cfg), 'auto');
    });

    test('правил нет — первый балансировщик; балансировщиков нет — null', () {
      expect(
          BalancerPick.mainBalancerTag({
            'routing': {
              'balancers': [
                {'tag': 'b1'},
                {'tag': 'b2'},
              ],
            },
          }),
          'b1');
      expect(BalancerPick.mainBalancerTag({'routing': {}}), isNull);
      expect(BalancerPick.hasBalancer({}), isFalse);
    });
  });

  group('nodeOf', () {
    test('vless — из vnext, trojan — из servers', () {
      final cfg = {
        'outbounds': [
          {
            'tag': 'proxy-2',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {'address': '203.0.113.10', 'port': 443},
              ],
            },
          },
          {
            'tag': 'proxy-3',
            'protocol': 'trojan',
            'settings': {
              'servers': [
                {'address': 'node.example.com', 'port': '8443'},
              ],
            },
          },
        ],
      };
      expect(BalancerPick.nodeOf(cfg, 'proxy-2'),
          const ActiveNode(tag: 'proxy-2', address: '203.0.113.10', port: 443));
      expect(BalancerPick.nodeOf(cfg, 'proxy-3')!.address, 'node.example.com');
      expect(BalancerPick.nodeOf(cfg, 'proxy-9'), isNull);
    });

    test('наш «Авто (лучший)»: тег proxy-i ведёт на i-й сервер', () {
      final cfg = const XrayConfigBuilder().buildBalancerMap([de, nl]);
      final node = BalancerPick.nodeOf(cfg, 'proxy-1')!;
      expect(node.address, nl.address);
      expect(node.port, nl.port);
      expect(BalancerPick.mainBalancerTag(cfg), 'balancer');
    });
  });

  group('RoutingService — без него `xray api bi` не ответит', () {
    List services(Map cfg) => (cfg['api'] as Map)['services'] as List;

    test('наш балансировщик его включает', () {
      final cfg = const XrayConfigBuilder().buildBalancerMap([de, nl]);
      expect(services(cfg), containsAll(['StatsService', 'RoutingService']));
    });

    test('профиль панели с балансировщиком получает его при нормализации',
        () {
      final raw = jsonEncode({
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'routing': {
          'balancers': [
            {'tag': 'auto', 'selector': ['proxy']},
          ],
        },
      });
      final out = jsonDecode(ensureXrayStats(raw, apiPort: 10085)) as Map;
      expect(services(out), containsAll(['StatsService', 'RoutingService']));
    });

    test('конфиг без балансировщика RoutingService не получает', () {
      final raw = jsonEncode({
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
      });
      final out = jsonDecode(ensureXrayStats(raw, apiPort: 10085)) as Map;
      expect(services(out), isNot(contains('RoutingService')));
    });
  });

  group('имя узла для показа', () {
    test('находится по адресу и порту среди серверов подписки', () {
      const node =
          ActiveNode(tag: 'proxy-5', address: '203.0.113.20', port: 8443);
      expect(AppState.nodeNameFor(node, [de, nl]), nl.displayName);
    });

    test('не нашли — null, страну не выдумываем', () {
      const node =
          ActiveNode(tag: 'proxy-5', address: '203.0.113.99', port: 443);
      expect(AppState.nodeNameFor(node, [de, nl]), isNull);
      expect(AppState.nodeNameFor(null, [de, nl]), isNull);
    });

    test('порт тоже сверяется: тот же адрес, другой порт — другой узел', () {
      const node =
          ActiveNode(tag: 'proxy-5', address: '203.0.113.10', port: 8443);
      expect(AppState.nodeNameFor(node, [de, nl]), isNull);
    });

    test('подпись: «Авто» получает узел, обычный сервер — нет', () {
      expect(
          activeServerName(
            connected: true,
            connectedKey: null,
            servers: [de, nl],
            autoLabel: 'Авто',
            activeNode: 'NL',
          ),
          'Авто · NL');
      expect(
          activeServerName(
            connected: true,
            connectedKey: de.key,
            servers: [de, nl],
            autoLabel: 'Авто',
            activeNode: 'NL',
          ),
          de.displayName,
          reason: 'у обычного сервера узел один — приписка была бы враньём');
    });
  });
}
