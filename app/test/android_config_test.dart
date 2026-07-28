import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
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
      // `stack` из этого списка УБРАН: он про обработку пакетов из
      // дескриптора, а не про владельца интерфейса. Без него ядро берёт
      // стек, который на Android пытается привязать форвардер к интерфейсу
      // (`SO_BINDTODEVICE`) — прав нет, TCP не форвардится, а DNS при этом
      // работает, из-за чего дефект выглядит как «интернета нет частично».
      for (final key in const [
        'interface_name',
        'auto_route',
        'strict_route',
      ]) {
        expect(tun.containsKey(key), isFalse,
            reason: '$key не должен попадать в TUN-инбаунд на Android');
      }
    });

    test('стек задан явно — иначе форвардер упрётся в SO_BINDTODEVICE', () {
      expect(tun['stack'], 'gvisor');
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

  // ──────────────────────────────────────────────────────────────────────────
  // Правила приложений на Android были МЁРТВЫМИ: генератор писал process_name и
  // process_path_regex, которых на Android не существует (ядро получает от
  // VpnService только uid и отдаёт его как package_name). Совпадений не было
  // никогда, поэтому «Блок» молча пропускал трафик, а интерфейс показывал
  // блокировку.
  group('Конфиг Android: правила приложений — по ПАКЕТАМ', () {
    AppSettings withApps(SplitMode mode, List<AppRule> apps) => AppSettings(
          splitTunnel: SplitTunnelConfig(mode: mode, apps: apps),
        );

    List<Map<String, dynamic>> rulesOf(AppSettings s) =>
        (((_androidConfig(_fixtures['vless']!, settings: s)['route']
                as Map)['rules']) as List)
            .cast<Map<String, dynamic>>();

    test('«Блок» пишется package_name + reject и реально совпадает', () {
      final r = rulesOf(withApps(SplitMode.exceptSelected, const [
        AppRule('com.example.ads', action: AppAction.block),
      ]));
      final reject = r.firstWhere((x) => x['action'] == 'reject');
      expect((reject['package_name'] as List), contains('com.example.ads'));
    });

    test('правил в синтаксисе Windows нет ни одного', () {
      final r = rulesOf(withApps(SplitMode.exceptSelected, const [
        AppRule('com.example.direct', action: AppAction.direct),
        AppRule('com.example.tunnel', action: AppAction.tunnel),
        AppRule('com.example.ads', action: AppAction.block),
      ]));
      expect(r.any((x) => x.containsKey('process_name')), isFalse);
      expect(r.any((x) => x.containsKey('process_path_regex')), isFalse);
      expect(r.where((x) => x.containsKey('package_name')), hasLength(3));
    });

    test('«Прямо» и «Туннель» разводятся по разным outbound', () {
      final r = rulesOf(withApps(SplitMode.exceptSelected, const [
        AppRule('com.example.direct', action: AppAction.direct),
        AppRule('com.example.tunnel', action: AppAction.tunnel),
      ]));
      bool routed(String pkg, String out) => r.any((x) =>
          (x['package_name'] as List?)?.contains(pkg) == true &&
          x['outbound'] == out);
      expect(routed('com.example.direct', 'direct'), isTrue);
      expect(routed('com.example.tunnel', 'proxy'), isTrue);
    });
  });

  // include_package и exclude_package взаимоисключающие: раньше отдавались оба
  // (exclude всегда содержал хотя бы свой пакет), и VpnService.Builder бросал
  // UnsupportedOperationException — туннель не поднимался вовсе.
  group('Конфиг Android: пакетные списки не конфликтуют', () {
    Map<String, dynamic> tunIn(AppSettings s) =>
        (((_androidConfig(_fixtures['vless']!, settings: s)['inbounds']) as List)
            .first as Map)
            .cast<String, dynamic>();

    test('«только выбранные» → есть include, exclude отсутствует', () {
      final i = tunIn(const AppSettings(
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          apps: [AppRule('com.example.tunnel', action: AppAction.tunnel)],
        ),
      ));
      expect((i['include_package'] as List), contains('com.example.tunnel'));
      expect(i.containsKey('exclude_package'), isFalse,
          reason: 'два списка разом — отказ VpnService.Builder');
    });

    test('прочие режимы → есть exclude, include отсутствует', () {
      final i = tunIn(const AppSettings(
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.exceptSelected,
          apps: [AppRule('com.example.direct', action: AppAction.direct)],
        ),
      ));
      expect(i.containsKey('include_package'), isFalse);
      expect((i['exclude_package'] as List), isNotEmpty);
    });

    test('«только выбранные» без выбранных → откат к exclude со своим пакетом',
        () {
      // Пустой allowed-список означал бы «в туннель не идёт никто», а
      // VpnService без него тянет туда ВСЁ — включая нас самих.
      final i = tunIn(const AppSettings(
        splitTunnel: SplitTunnelConfig(mode: SplitMode.onlySelected),
      ));
      expect(i.containsKey('include_package'), isFalse);
      expect((i['exclude_package'] as List), contains('lol.silentgate'));
    });

    // ⚠️ Утечка, которую нашло ревью и не поймал живой тест. Правила из
    // МАРШРУТОВ в режиме «Всё через VPN» вырезаются, а из пакетных списков
    // вырезались не везде: сохранённое «Прямо»-приложение продолжало уезжать
    // в exclude_package, и VpnService выводил его из туннеля НА УРОВНЕ ОС —
    // трафик шёл под реальным IP. Увидеть было нечем: правил в конфиге нет,
    // списки в интерфейсе скрыты, схема маршрута рисует простую цепочку.
    test('«Всё через VPN»: в exclude_package НЕТ приложений пользователя', () {
      final i = tunIn(const AppSettings(
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.all,
          apps: [
            AppRule('com.example.direct', action: AppAction.direct),
            AppRule('com.example.block', action: AppAction.block),
          ],
          sites: [SiteRule('direct.example', action: AppAction.direct)],
        ),
      ));
      expect((i['exclude_package'] as List), ['lol.silentgate'],
          reason: 'мимо туннеля идём только мы сами, иначе это дыра под '
              'реальным IP, невидимая пользователю');
    });

    // «Блок» обязан попасть В туннель: ядро убивает его reject-правилом.
    // Вне туннеля ядро трафика не видит, правило не совпадает, блок молчит.
    test('«только выбранные»: заблокированный пакет ВХОДИТ в туннель', () {
      final s = const AppSettings(
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          apps: [
            AppRule('com.example.tunnel', action: AppAction.tunnel),
            AppRule('com.example.ads', action: AppAction.block),
          ],
        ),
      );
      final i = tunIn(s);
      expect((i['include_package'] as List), contains('com.example.ads'),
          reason: 'иначе reject-правилу не с чем совпадать');

      // И само reject-правило на месте.
      final rules = ((_androidConfig(_fixtures['vless']!, settings: s)['route']
              as Map)['rules'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        rules.any((r) =>
            r['action'] == 'reject' &&
            (r['package_name'] as List?)?.contains('com.example.ads') == true),
        isTrue,
      );
    });
  });

  // ⚠️ «Авто (лучший сервер)» на Android подключался к ПЕРВОМУ серверу списка:
  // движок брал `servers.first` и выбрасывал конфиг, собранный базой (там
  // балансировщик Xray либо `urltest` sing-box по ВСЕМ узлам).
  group('Автовыбор: группа outbound-ов встраивается целиком', () {
    Map<String, dynamic> withGroup(List<Map<String, dynamic>> group) =>
        SingboxConfigBuilder(
          options: const TunOptions(platformTun: true, serverIps: ['203.0.113.5']),
          proxyOutboundGroup: group,
        ).buildMap(const SplitTunnelConfig());

    test('узлы и urltest попадают в конфиг, тег proxy сохраняется', () {
      final cfg = withGroup([
        {'type': 'hysteria2', 'tag': 'node-0', 'server': '198.51.100.1', 'server_port': 443},
        {'type': 'hysteria2', 'tag': 'node-1', 'server': '198.51.100.2', 'server_port': 443},
        {'type': 'urltest', 'tag': 'proxy', 'outbounds': ['node-0', 'node-1']},
      ]);
      final outs = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      final tags = outs.map((o) => o['tag']).toList();
      expect(tags, containsAll(['node-0', 'node-1', 'proxy', 'direct']));
      expect(outs.firstWhere((o) => o['tag'] == 'proxy')['type'], 'urltest');
      // Один-единственный direct: два одноимённых outbound'а ядро отвергает.
      expect(tags.where((t) => t == 'direct').length, 1);
      expect((cfg['route'] as Map)['final'], 'proxy');
    });

    test('без группы поведение прежнее — переход в локальный SOCKS', () {
      final cfg = SingboxConfigBuilder(
        options: const TunOptions(platformTun: true),
      ).buildMap(const SplitTunnelConfig());
      final proxy = (cfg['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'socks');
    });
  });

  // Kill switch между попытками переподключения: туннель остаётся поднятым, но
  // никуда не ведёт. Раньше сервис гасился целиком, и на всё время попыток
  // (backoff до 20 с, до 8 попыток — это минуты) трафик шёл НАПРЯМУЮ, хотя
  // настройка была включена и печаталась в отчёте.
  group('Kill switch: заглушка совпадает с живым туннелем и ничего не выпускает', () {
    // Живые опции пользователя — НЕ дефолты. Прежние тесты сравнивали заглушку
    // с дефолтными опциями и потому не видели главного расхождения.
    const live = TunOptions(
      platformTun: true,
      mtu: 1280,
      ipv6: false,
      serverIps: ['203.0.113.5'],
      logOutput: '/data/x/singbox.log',
    );
    const split = SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: [AppRule('com.example.tunnel', action: AppAction.tunnel)],
    );

    Map<String, dynamic> build(TunOptions o) =>
        SingboxConfigBuilder(options: o).buildMap(split);

    test('TUN-инбаунд совпадает ПОЛЕ В ПОЛЕ с живым', () {
      // Разойдутся MTU или пакетные списки — VpnService пересоздаст интерфейс,
      // и на этот миг трафик уйдёт мимо VPN: ровно то окно, которое kill
      // switch и закрывает.
      final liveIn = (build(live)['inbounds'] as List).first as Map;
      final blackIn = (build(live.asBlackhole())['inbounds'] as List).first as Map;
      expect(blackIn, liveIn);
    });

    test('нет висячих ссылок на несуществующие outbound-ы', () {
      // sing-box check этого НЕ ловит (возвращает 0 и на висячем теге), а
      // ядро в рантайме отвергает конфиг целиком — туннель снимается, и
      // трафик идёт напрямую всё время попыток.
      final cfg = build(live.asBlackhole());
      final tags = (cfg['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => '${o['tag']}')
          .toSet();
      for (final r in (cfg['route'] as Map)['rules'] as List) {
        final out = (r as Map)['outbound'];
        if (out != null) expect(tags, contains('$out'));
      }
      final dns = cfg['dns'] as Map?;
      for (final srv in (dns?['servers'] as List? ?? const [])) {
        final d = (srv as Map)['detour'];
        if (d != null) expect(tags, contains('$d'));
      }
    });

    test('устаревшего outbound type: block нет — он удалён в 1.13', () {
      final outs = (build(live.asBlackhole())['outbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(outs.any((o) => o['type'] == 'block'), isFalse);
    });

    test('всё уходит в reject, правила пользователя не применяются', () {
      final cfg = build(live.asBlackhole());
      final rules = ((cfg['route'] as Map)['rules'] as List)
          .cast<Map<String, dynamic>>();
      expect(rules, hasLength(1));
      expect(rules.single['action'], 'reject');
      expect(rules.any((r) => r.containsKey('package_name')), isFalse,
          reason: 'правило «Прямо» выпустило бы трафик наружу');
    });
  });

  // ⚠️ Панельный профиль «Авто …» и правка из JSON-редактора МОЛЧА терялись:
  // признаком «поднимать Xray» был протокол первого сервера, а не факт полного
  // конфига. У панельного профиля protocol берётся с первого прокси-outbound-а
  // и обычно равен vless, который sing-box умеет, — значит собранный базой
  // конфиг выбрасывался, а в туннель встраивался ОДИН узел профиля.
  group('Признак «полный конфиг» отличается от «протокол умеет sing-box»', () {
    test('inbound для сервис-чипов есть — иначе они всегда красные', () {
      final tun = (_androidConfig(_fixtures['vless']!)['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      final probe = tun.firstWhere((i) => i['tag'] == 'probe-in');
      expect(probe['type'], 'mixed');
      expect(probe['listen'], '127.0.0.1',
          reason: 'наружу порт выставлять нельзя');
      expect(probe['listen_port'], 10809);
    });

    test('в туннеле-заглушке проб-инбаунда нет', () {
      // Kill switch: слушать порт, из которого всё равно ничего не выйдет,
      // незачем — и это лишняя поверхность.
      final tun = (SingboxConfigBuilder(
        options: const TunOptions(platformTun: true, blackhole: true),
      ).buildMap(const SplitTunnelConfig())['inbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(tun.any((i) => i['tag'] == 'probe-in'), isFalse);
    });
  });
}
