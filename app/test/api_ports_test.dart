import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Раскладка портов локального API.
///
/// ⚠️ Порядок обязан быть детерминированным: скрипт хардкодит номер порта, и
/// «дышащая» между запусками раскладка увела бы запрос в другую страну — молча
/// и без единой ошибки.
void main() {
  group('Раскладка', () {
    test('управляющий порт и порт «Прямо» фиксированы', () {
      expect(ApiPorts.control, 10870);
      expect(ApiPorts.direct, 10819);
    });

    test('серверы получают порты по возрастанию ключа', () {
      // Ключи нарочно переданы НЕ по порядку: функция обязана отсортировать их
      // сама, тем же способом, что и ExitOutbounds.build.
      final keys = ['vless://c', 'vless://a', 'vless://b'];
      expect(ApiPorts.forServer(keys, 'vless://a'), 10820);
      expect(ApiPorts.forServer(keys, 'vless://b'), 10821);
      expect(ApiPorts.forServer(keys, 'vless://c'), 10822);
    });

    test('неизвестный ключ порта не получает', () {
      expect(ApiPorts.forServer(['vless://a'], 'vless://zzz'), isNull);
    });

    test('сверх диапазона порта нет', () {
      // 40 портов — 10820..10859. Сорок первый обязан вернуть null, а не 10860:
      // молча заехать в чужой диапазон хуже, чем честно отказать.
      final keys = [for (var i = 0; i < 41; i++) 'vless://${i.toString().padLeft(3, '0')}'];
      expect(ApiPorts.forServer(keys, keys[39]), 10859);
      expect(ApiPorts.forServer(keys, keys[40]), isNull);
    });

    test('пустой список никому ничего не даёт', () {
      expect(ApiPorts.forServer(const [], 'vless://a'), isNull);
    });
  });

  group('Гейт «канал API поднят»', () {
    // Раунд исправлений 1, находка 3: PortCheck и сборка конфига обязаны
    // решать «есть тут порты или нет» ОДИНАКОВО — иначе PortCheck проверяет
    // порты, которых конфиг не создаст, и стороннее приложение на любом из
    // 10820–10859 даёт ложный отказ подключения.
    test('выключен тумблер — гейт закрыт даже с токеном', () {
      expect(ApiPorts.exitsActive(enabled: false, token: 'secret'), isFalse);
    });

    test('пустой токен — гейт закрыт даже при включённом тумблере', () {
      expect(ApiPorts.exitsActive(enabled: true, token: ''), isFalse);
    });

    test('тумблер включён и токен задан — гейт открыт', () {
      expect(ApiPorts.exitsActive(enabled: true, token: 'secret'), isTrue);
    });
  });

  group('Теги инбаундов', () {
    test('тег выводится из ключа и стабилен', () {
      final a = apiExitInboundTag('vless://a');
      expect(a, apiExitInboundTag('vless://a'));
      expect(a, isNot(apiExitInboundTag('vless://b')));
      expect(a, startsWith('api-exit-'));
    });
  });

  group('Конфиг ядра', () {
    test('на каждый живой сервер есть inbound и правило', () {
      const keyA = 'vless://a';
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        apiExitServerKeys: const [keyA],
        apiToken: 'secret',
      );
      final cfg = builder.buildMap(const SplitTunnelConfig());
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      final mine = ins.firstWhere((i) => i['tag'] == apiExitInboundTag(keyA));
      expect(mine['listen'], '127.0.0.1');
      expect(mine['listen_port'], 10820);
      expect(mine['users'], [
        {'username': 'sg', 'password': 'secret'}
      ]);
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
      expect(
          rules.any((r) =>
              (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) == true &&
              r['outbound'] == exitTagFor(keyA)),
          isTrue,
          reason: 'нет правила inboundTag -> outboundTag');
    });

    test('⚠️ ссылка на НЕсобравшийся сервер порта не создаёт', () {
      // Сервер могли удалить из подписки, а его протокол может не подниматься
      // вторым туннелем. Оба случая обязаны привести к отсутствию порта, а не к
      // висячему тегу: висячий sing-box check пропускает молча, и трафик уходит
      // в route.final — то есть НЕ туда, куда целился скрипт.
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: const [], // outbound не собрался
        apiExitServerKeys: const ['vless://a'],
        apiToken: 'secret',
      );
      final cfg = builder.buildMap(const SplitTunnelConfig());
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => '${i['tag']}'.startsWith('api-exit-')), isFalse);
    });

    test('пустой токен инбаундов не создаёт', () {
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: [
          {'tag': exitTagFor('vless://a'), 'type': 'vless'},
        ],
        apiExitServerKeys: const ['vless://a'],
        apiToken: '',
      );
      final cfg = builder.buildMap(const SplitTunnelConfig());
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => '${i['tag']}'.startsWith('api-exit-')), isFalse,
          reason: 'пустой токен означает «канал не поднимается»');
    });

    // Раунд исправлений 1, находка 2: «правила приоритета сайтов
    // перехватывают трафик API-порта». Инвариант — трафик, пришедший в порт
    // конкретного сервера, уходит именно в этот сервер; исключение — только
    // блокировка пользователя.
    test('порт сервера НЕ перехватывается правилом приоритета сайтов', () {
      const keyA = 'vless://a';
      const keyB = 'vless://b';
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
          {'tag': exitTagFor(keyB), 'type': 'vless'},
        ],
        apiExitServerKeys: const [keyA],
        apiToken: 'secret',
      );
      // Конфликтующая пара доменов рождает правило `_addSitePriorityRules`
      // (домен БЕЗ привязки к inbound) — именно оно, будучи выше правила
      // API-порта, увело бы запрос в порт сервера A мимо A.
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('example.com', action: AppAction.tunnel, serverKey: keyB),
          SiteRule('sub.example.com', action: AppAction.direct),
        ],
      );
      final cfg = builder.buildMap(split);
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();

      final apiIdx = rules.indexWhere((r) =>
          (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) == true &&
          r['outbound'] == exitTagFor(keyA));
      final priorityIdx = rules.indexWhere(
          (r) => (r['domain_suffix'] as List?)?.contains('sub.example.com') == true);

      expect(apiIdx, greaterThanOrEqualTo(0));
      expect(priorityIdx, greaterThanOrEqualTo(0),
          reason: 'сценарий обязан реально породить конфликтующее правило '
              'приоритета сайтов, иначе тест ничего не проверяет');
      expect(apiIdx, lessThan(priorityIdx),
          reason: 'запрос в порт сервера A обязан уйти на A РАНЬШЕ, чем его '
              'успеет перехватить правило, рассчитанное на обычный трафик');
    });

    test('блок пользователя всё равно режет трафик порта сервера', () {
      const keyA = 'vless://a';
      final builder = SingboxConfigBuilder(
        options: const TunOptions(),
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        apiExitServerKeys: const [keyA],
        apiToken: 'secret',
      );
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('blocked.example', action: AppAction.block)],
      );
      final cfg = builder.buildMap(split);
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();

      final blockIdx = rules.indexWhere((r) =>
          r['action'] == 'reject' &&
          (r['domain_suffix'] as List?)?.contains('blocked.example') == true &&
          (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) == true);
      final routeIdx = rules.indexWhere((r) =>
          (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) == true &&
          r['outbound'] == exitTagFor(keyA));

      expect(blockIdx, greaterThanOrEqualTo(0),
          reason: 'блок обязан применяться и к порту сервера — иначе '
              'служебный вход стал бы способом обойти собственные запреты '
              'пользователя');
      expect(blockIdx, lessThan(routeIdx),
          reason: 'блок обязан сработать РАНЬШЕ маршрута на выход');
    });
  });
}
