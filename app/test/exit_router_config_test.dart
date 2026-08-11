import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_router_config_builder.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';

/// Маршрутизатор выходов для режима «Только прокси» (задача 3b).
///
/// ⚠️ Он НАМЕРЕННО крошечный: ни `tun`-инбаунда, ни `dns`-секции здесь быть не
/// должно — в этом режиме ничего не перехватывается, трафик приходит только в
/// явно открытые порты серверов. Если тест когда-нибудь начнёт ждать `tun` —
/// это регресс архитектуры, а не улучшение.
void main() {
  const keyA = 'vless://a';
  const keyB = 'vless://b';

  group('Состав конфига', () {
    test('на каждый живой сервер — инбаунд и правило inbound -> outbound', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA, keyB],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
          {'tag': exitTagFor(keyB), 'type': 'vless'},
        ],
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();

      for (final key in [keyA, keyB]) {
        final tag = apiExitInboundTag(key);
        final inbound = ins.firstWhere((i) => i['tag'] == tag,
            orElse: () => throw StateError('нет инбаунда для $key'));
        expect(inbound['type'], 'mixed');
        expect(inbound['listen'], '127.0.0.1');
        expect(inbound['listen_port'], ApiPorts.forServer([keyA, keyB], key));
        expect(inbound['users'], [
          {'username': 'sg', 'password': 'secret'}
        ]);

        final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
        expect(
            rules.any((r) =>
                (r['inbound'] as List?)?.contains(tag) == true &&
                r['outbound'] == exitTagFor(key)),
            isTrue,
            reason: 'нет правила $tag -> ${exitTagFor(key)}');
      }
    });

    test('нет tun-инбаунда', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => i['type'] == 'tun'), isFalse);
    });

    test('нет dns-секции', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
      );
      final cfg = builder.buildMap();
      expect(cfg.containsKey('dns'), isFalse);
    });

    test('пустой токен — ни одного инбаунда', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: '',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins, isEmpty,
          reason: 'пустой токен означает «канал не поднимается»');
    });

    test('⚠️ сервер без живого outbound-а порта не получает', () {
      // Сервер могли удалить из подписки, или его протокол не поднимается
      // вторым туннелем. Оба случая обязаны привести к отсутствию порта, а не
      // к висячему тегу: `sing-box check` его не ловит, и трафик молча уходит
      // в route.final — то есть НЕ туда, куда целился скрипт.
      const builder = ExitRouterConfigBuilder(
        serverKeys: [keyA],
        token: 'secret',
        exitOutbounds: [], // outbound не собрался
      );
      final cfg = builder.buildMap();
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins, isEmpty);
    });

    test('route.final == direct', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
      );
      final cfg = builder.buildMap();
      expect(cfg['route']['final'], 'direct');
    });

    test('outbounds — переданные exitOutbounds плюс direct', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
      );
      final cfg = builder.buildMap();
      final outs = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(outs.any((o) => o['tag'] == exitTagFor(keyA)), isTrue);
      expect(outs.any((o) => o['tag'] == 'direct' && o['type'] == 'direct'),
          isTrue);
    });

    test('buildJson() — валидный JSON, равный buildMap()', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
      );
      final decoded = jsonDecode(builder.buildJson());
      expect(decoded, builder.buildMap());
    });
  });

  group('Правила раздельного туннелирования — по галочке (applyRules)', () {
    test('выключено по умолчанию — блок-правил нет вовсе', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        split: const SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          sites: [SiteRule('blocked.example', action: AppAction.block)],
        ),
      );
      final cfg = builder.buildMap();
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
      expect(rules.any((r) => r['action'] == 'reject'), isFalse);
    });

    test(
        'включено, но режим «Всё через VPN» — блок-правил всё равно нет '
        '(userRulesActive)', () {
      // Тот же гейт, что у TUN-построителя (`_userRulesActive` в
      // `singbox_config_builder.dart`): в режиме «Всё через VPN»
      // пользовательских правил нет вовсе, включая блок API-портов. Раньше
      // ExitRouterConfigBuilder этот гейт не проверял — блок включался бы там,
      // где такой же блок в TUN-конфиге не действует.
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        applyRules: true,
        split: const SplitTunnelConfig(
          mode: SplitMode.all,
          sites: [SiteRule('blocked.example', action: AppAction.block)],
        ),
      );
      final cfg = builder.buildMap();
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
      expect(rules.any((r) => r['action'] == 'reject'), isFalse);
    });

    test('включено — блок сайта режет трафик порта сервера, ВЫШЕ маршрута', () {
      final builder = ExitRouterConfigBuilder(
        serverKeys: const [keyA],
        token: 'secret',
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        applyRules: true,
        split: const SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          sites: [SiteRule('blocked.example', action: AppAction.block)],
        ),
      );
      final cfg = builder.buildMap();
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
      final tag = apiExitInboundTag(keyA);

      final blockIdx = rules.indexWhere((r) =>
          r['action'] == 'reject' &&
          (r['domain_suffix'] as List?)?.contains('blocked.example') == true &&
          (r['inbound'] as List?)?.contains(tag) == true);
      final routeIdx = rules.indexWhere((r) =>
          (r['inbound'] as List?)?.contains(tag) == true &&
          r['outbound'] == exitTagFor(keyA));

      expect(blockIdx, greaterThanOrEqualTo(0));
      expect(routeIdx, greaterThanOrEqualTo(0));
      expect(blockIdx, lessThan(routeIdx),
          reason: 'блок обязан сработать раньше маршрута на выход');
    });
  });
}
