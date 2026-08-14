import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/ipv6_support.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/engine/android/android_engine.dart';
import 'package:silentgate/engine/vpn_engine.dart';

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
      probePort: 10811,
      options: TunOptions.fromSettings(settings,
          serverIps: const ['93.184.216.34'], android: true),
      proxyOutbound: SingboxOutboundFactory.build(server),
    ).buildMap(settings.splitTunnel);

void main() {
  // Мок нативных каналов движка требует биндингов.
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(probe['listen_port'], 10811,
          reason: 'НЕ 10809: там при панельном профиле садится Xray, '
              'и совпадение порта не давало ядру стартовать вовсе');
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

  // ⚠️ ПОРТ 10085 ПОДНИМАЛСЯ НА ANDROID В РЕЖИМЕ «АВТО (ЛУЧШИЙ СЕРВЕР)».
  //
  // api-инбаунд Xray — `dokodemo-door` на 127.0.0.1 БЕЗ пароля (Xray его для
  // `api` не поддерживает в принципе). Счётчики оттуда читает только Windows,
  // Android берёт их из Clash API sing-box, — то есть на телефоне порт
  // открывался вхолостую, а видит его там любое установленное приложение
  // (loopback между приложениями не изолирован, детекторы VPN ищут этот порт
  // отдельной проверкой).
  //
  // Гейт `readsXrayStats` закрывал ОДИН путь из нескольких — `ensureXrayStats`
  // для панельного профиля. Конфиг автовыбора собирает ДРУГОЙ метод
  // (`buildBalancerMap`), и он клал инбаунд безусловно. Поэтому проверяются оба
  // построителя И место отправки: дефект жил не в построителе, а в том, что
  // мимо гейта шёл целый путь.
  group('api-инбаунд Xray не уезжает ядру на Android', () {
    List<Map<String, dynamic>> inboundsOf(String json) =>
        (((jsonDecode(json) as Map)['inbounds']) as List)
            .cast<Map<String, dynamic>>();

    List<Map<String, dynamic>> rulesOfXray(String json) =>
        ((((jsonDecode(json) as Map)['routing'] as Map)['rules']) as List)
            .cast<Map<String, dynamic>>();

    bool hasApi(String json) => inboundsOf(json)
        .any((i) => i['tag'] == 'api' || '${i['port']}' == '10085');

    String sent(String xrayJson, {bool readsXrayStats = false}) =>
        AndroidEngine.startArgs(
          tunJson: '{}',
          xrayJson: xrayJson,
          readsXrayStats: readsXrayStats,
        )['xray_config'] as String;

    const builder = XrayConfigBuilder();
    final auto = [_fixtures['vless']!, _fixtures['ws']!];

    test('одиночный сервер (buildMap)', () {
      final raw = builder.buildJson(_fixtures['vless']!);
      expect(hasApi(raw), isTrue, reason: 'предпосылка: построитель его кладёт');
      expect(hasApi(sent(raw)), isFalse);
    });

    test('«Авто (лучший сервер)» (buildBalancerMap) — тот же результат', () {
      // Именно этот путь и оставался открытым: гейт стоял на другом.
      final raw = builder.buildBalancerJson(auto);
      expect(hasApi(raw), isTrue, reason: 'предпосылка: построитель его кладёт');
      final out = sent(raw);
      expect(hasApi(out), isFalse);
      // Выгружаем, как и остальные конфиги этого файла: почищенный конфиг
      // обязан оставаться валидным для НАСТОЯЩЕГО ядра, и проверяется это
      // `xray.exe run -test -c build/android-config/balancer-no-api.json`.
      File('${outDir.path}/balancer-no-api.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonDecode(out)));
    });

    test('панельный профиль со СВОИМ api-инбаундом чистится тоже', () {
      // Конфиг приходит от панели целиком, и что в нём лежит, мы не выбираем.
      final raw = jsonEncode({
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'port': 10808},
          {'tag': 'api', 'protocol': 'dokodemo-door', 'port': 10085},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless'},
        ],
        'api': {'tag': 'api', 'services': ['StatsService']},
        'routing': {
          'rules': [
            {'type': 'field', 'inboundTag': ['api'], 'outboundTag': 'api'},
          ],
        },
      });
      final out = sent(raw);
      expect(hasApi(out), isFalse);
      expect((jsonDecode(out) as Map).containsKey('api'), isFalse,
          reason: 'секцию без инбаунда обслуживать некому');
    });

    test('правило api удаляется целиком, а не пустеет', () {
      // ⚠️ Правило с пустым `inboundTag` не сужается до нуля, а перестаёт
      // ограничивать что-либо: в api-хендлер ушёл бы ВЕСЬ трафик.
      final out = sent(builder.buildBalancerJson(auto));
      for (final r in rulesOfXray(out)) {
        expect(r['outboundTag'], isNot('api'));
        final tags = r['inboundTag'];
        if (tags is List) {
          expect(tags, isNotEmpty, reason: 'пустое условие подходит ко всему');
          expect(tags.contains('api'), isFalse);
        }
      }
    });

    test('остальное не задето: socks/http и балансировщик на месте', () {
      final out = sent(builder.buildBalancerJson(auto));
      final tags = inboundsOf(out).map((i) => i['tag']).toList();
      expect(tags, containsAll(['socks', 'http']));
      expect(
          rulesOfXray(out).any((r) => r['balancerTag'] == 'balancer'), isTrue);
      final outs = ((jsonDecode(out) as Map)['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['tag']);
      expect(outs, containsAll(['proxy-0', 'proxy-1', 'direct', 'block']));
    });

    test('там, где счётчики читают (Windows), конфиг не трогается', () {
      // Гейт один на добавление и на удаление: если платформа читает
      // statsquery, инбаунд обязан доехать нетронутым.
      final raw = builder.buildBalancerJson(auto);
      expect(sent(raw, readsXrayStats: true), raw);
    });

    test('сессия без Xray: ключа xray_config нет вовсе', () {
      expect(AndroidEngine.startArgs(tunJson: '{}').containsKey('xray_config'),
          isFalse);
    });
  });

  // ⚠️ ЗАГЛУШКА KILL SWITCH СОБИРАЛАСЬ ИЗ УМОЛЧАНИЙ, А НЕ ИЗ ЖИВОГО ТУННЕЛЯ.
  //
  // Опции живого туннеля лежат в памяти изолята, а туннель на Android изолят
  // переживает: свернул приложение — VPN работает, открыл заново — изолят
  // новый и полей нет (`adoptRunningTunnel`). Прежний код подставлял в этом
  // случае `const TunOptions(platformTun: true)` и пустой `SplitTunnelConfig`.
  //
  // Почему этого не поймал соседний страж «поле в поле»: он сравнивает
  // `build(live)` с `build(live.asBlackhole())` — ДВА конфига из ОДНОГО набора
  // опций. Он доказывает, что `asBlackhole()` ничего не теряет, и ничего не
  // говорит о том, какие опции движок туда подаёт. Поэтому здесь проверяется
  // сам движок, а не построитель.
  group('Kill switch после подхвата живого туннеля', () {
    const vpnChannel = MethodChannel('lol.silentgate/vpn');
    const eventsChannel = MethodChannel('lol.silentgate/vpn_events');

    // Настройки пользователя, при которых умолчания расходятся с живым
    // туннелем сразу двумя полями: MTU и пакетные списки.
    const userSettings = AppSettings(
      tunMtu: 1280,
      killSwitch: true,
      splitTunnel: SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [AppRule('com.example.messenger', action: AppAction.tunnel)],
      ),
    );

    const server = VpnServer(
      protocol: 'vless',
      remark: 'adopted',
      // Литеральный адрес: резолв в тесте не должен ходить в сеть.
      address: '203.0.113.5',
      port: 443,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink: 'vless://11111111-2222-3333-4444-555555555555@203.0.113.5:443',
    );

    late Directory tmp;
    final started = <String>[];

    setUp(() {
      // Свой каталог данных: движок пишет журнал и пароль Clash API, лезть в
      // боевой %APPDATA% тесту нельзя.
      tmp = Directory.systemTemp.createTempSync('sg_android_killswitch_');
      AppPaths.overrideRoot(tmp);
      started.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vpnChannel, (call) async {
        switch (call.method) {
          case 'isRunning':
            return true; // туннель поднят прошлым запуском интерфейса
          case 'start':
            started.add((call.arguments as Map)['config'] as String);
            return null;
          default:
            return null;
        }
      });
      // Подписка на события идёт из конструктора движка; без заглушки канал
      // ответил бы исключением и уронил тест на ровном месте.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(eventsChannel, (call) async => null);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(vpnChannel, null)
        ..setMockMethodCallHandler(eventsChannel, null);
      // Журнал пишется фоновой цепочкой — дать ей закончиться ДО того, как
      // каталог данных вернётся к боевому.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Map<String, dynamic> tunInboundOf(String json) =>
        (((jsonDecode(json) as Map)['inbounds']) as List).first
            as Map<String, dynamic>;

    test('заглушка совпадает с ЖИВЫМ туннелем, а не с умолчаниями', () async {
      final engine = AndroidEngine();
      await engine.adoptRunningTunnel();
      expect(engine.status.isConnected, isTrue, reason: 'предпосылка теста');

      // Интерфейс возвращает движку сессию: с неё живут автоповтор и kill
      // switch (см. armAdoptedSession).
      await engine.armAdoptedSession(
          [server], const ConnectionOptions(settings: userSettings));
      await engine.teardownCore(keepCapture: true);

      expect(started, hasLength(1), reason: 'туннель обязан быть удержан');

      // Эталон — TUN-инбаунд, который построил бы ЖИВОЙ конфиг из тех же
      // настроек. Сравниваем именно его: это ровно то, из чего VpnService
      // строит интерфейс, и любое расхождение = новый интерфейс.
      final live = SingboxConfigBuilder(
        options: TunOptions.fromSettings(userSettings,
            android: true, ipv6Available: await Ipv6Support.hasGlobalIpv6()),
      ).buildMap(userSettings.splitTunnel);

      expect(tunInboundOf(started.single), tunInboundOf(jsonEncode(live)));
      expect(tunInboundOf(started.single)['mtu'], 1280);
      expect(tunInboundOf(started.single)['include_package'],
          contains('com.example.messenger'),
          reason: 'иначе в заглушку зайдёт ВЕСЬ телефон, включая приложения, '
              'которые пользователь держал вне VPN, и останется без сети');
    });

    test('нет ни живых опций, ни сессии — туннель не подменяется наугад',
        () async {
      // Знать нечего: единственное честное действие — погасить, а не строить
      // «какой-нибудь» интерфейс поверх чужого.
      expect(
        AndroidEngine.blackholeInputs(
            live: null, liveSplit: null, session: null, ipv6Available: true),
        isNull,
      );
    });

    test('живые опции точнее сессии и берутся первыми', () {
      const live = TunOptions(platformTun: true, mtu: 1400);
      const liveSplit = SplitTunnelConfig(mode: SplitMode.exceptSelected);
      final got = AndroidEngine.blackholeInputs(
        live: live,
        liveSplit: liveSplit,
        session: const ConnectionOptions(settings: userSettings),
        ipv6Available: true,
      )!;
      expect(got.options.mtu, 1400);
      expect(got.split.mode, SplitMode.exceptSelected);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // ⚠️ УСТАРЕВШИЙ ЗАПУСК РУШИЛ РЕСУРС ЖИВОЙ СЕССИИ — КЛАСС, ЗАКРЫТЫЙ БЫЛ ТОЛЬКО
  // НА WINDOWS.
  //
  // Форвардер поднимается ВНУТРИ сборки `TunOptions`, то есть после резолва
  // серверов (таймаут 5 с на имя) и запроса DNS физической сети через нативный
  // канал. К этому моменту запуск мог устареть — а подъём начинался со снятия
  // ТОГО, ЧТО ЛЕЖИТ В ПОЛЕ, то есть форвардера уже НОВОЙ, живой сессии. Её
  // конфиг уже уехал ядру и в `dns.final` держит именно этот порт: при «весь
  // DNS через туннель» имена перестают резолвиться у ВСЕХ приложений телефона,
  // и само это не чинится. Достижимо просто — запуск A стоит в таймауте
  // резолва, человек жмёт «Отключить» и «Подключить», запуск B обгоняет A.
  //
  // Защит здесь три, и у каждой свой тест: гейт устаревшего запуска, поколение-
  // владелец и снятие ТОЛЬКО СВОЕГО на раннем выходе `startSession`.
  group('Запасной DNS: устаревший запуск не трогает чужой форвардер', () {
    const vpnChannel = MethodChannel('lol.silentgate/vpn');
    const eventsChannel = MethodChannel('lol.silentgate/vpn_events');
    const deviceChannel = MethodChannel('lol.silentgate/device');

    // «Весь DNS через туннель» — единственная настройка, при которой форвардер
    // вообще поднимается.
    const settings = AppSettings(tunnelDnsForAll: true);

    late Directory tmp;
    late AndroidEngine engine;

    setUp(() {
      // Свой каталог данных: движок пишет журнал и пароль Clash API.
      tmp = Directory.systemTemp.createTempSync('sg_android_fallback_dns_');
      AppPaths.overrideRoot(tmp);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(vpnChannel, (call) async => null);
      messenger.setMockMethodCallHandler(eventsChannel, (call) async => null);
      // Резолвер физической сети: без него форвардер честно не поднимается.
      messenger.setMockMethodCallHandler(deviceChannel,
          (call) async => call.method == 'directDns' ? '192.168.1.1' : null);
      engine = AndroidEngine();
    });

    tearDown(() async {
      await engine.dispose();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger
        ..setMockMethodCallHandler(vpnChannel, null)
        ..setMockMethodCallHandler(eventsChannel, null)
        ..setMockMethodCallHandler(deviceChannel, null);
      // Журнал пишется фоновой цепочкой — дать ей закончиться ДО возврата
      // каталога данных к боевому.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('поколение-владелец: снимается только СВОЙ, чужой остаётся жить',
        () async {
      expect(
          await engine.startFallbackDns(settings,
              viaXray: true, gen: 1, aborted: () => false),
          isNot(0),
          reason: 'предпосылка: форвардер запуска 1 поднят');
      final own = engine.fallbackDns!;

      // Пользователь переподключился: запуск 2 штатно снял прошлый и поднял
      // свой — так и должно быть, он не устарел.
      await engine.startFallbackDns(settings,
          viaXray: true, gen: 2, aborted: () => false);
      final fresh = engine.fallbackDns!;
      expect(identical(fresh, own), isFalse,
          reason: 'предпосылка: в поле уже форвардер ДРУГОГО запуска');
      expect(own.isRunning, isFalse);

      // И только теперь запуск 1 возвращается из своего долгого await и
      // сворачивается.
      await engine.releaseOwnFallbackDns(1);
      expect(engine.fallbackDns, same(fresh),
          reason: 'устаревший запуск снял форвардер ЖИВОЙ сессии: её dns.final '
              'указывает на порт, которого больше нет — и DNS всего телефона '
              'встаёт до переподключения');
      expect(fresh.isRunning, isTrue);

      // Своё поколение — снимает.
      await engine.releaseOwnFallbackDns(2);
      expect(engine.fallbackDns, isNull);
      expect(fresh.isRunning, isFalse);
    });

    test('гейт: устаревший запуск не гасит живого и не поднимает своего',
        () async {
      await engine.startFallbackDns(settings,
          viaXray: true, gen: 1, aborted: () => false);
      final live = engine.fallbackDns!;

      // Запуск 2 вернулся из резолва и обнаружил, что устарел.
      expect(
          await engine.startFallbackDns(settings,
              viaXray: true, gen: 2, aborted: () => true),
          0,
          reason: 'устаревший запуск не имеет права поднимать порт: его конфиг '
              'никуда не поедет, а гасить поднятое будет некому');
      expect(engine.fallbackDns, same(live),
          reason: 'гейт стоит ПОСЛЕ снятия из поля — значит первой же строкой '
              'убит форвардер живой сессии');
      expect(live.isRunning, isTrue);
    });
  });

  // Третья защита: ранние выходы `startSession` по `aborted()` не зовут
  // `cleanup()`, поэтому поднятый форвардер обязан сниматься там явно — и
  // именно СВОЙ. Проверяется на настоящем `startSession`: подмены здесь ровно
  // две — нативные каналы, которых в тесте нет физически.
  group('Запасной DNS: ранний выход startSession снимает свой форвардер', () {
    const vpnChannel = MethodChannel('lol.silentgate/vpn');
    const eventsChannel = MethodChannel('lol.silentgate/vpn_events');
    const deviceChannel = MethodChannel('lol.silentgate/device');

    // Полный Xray-JSON: только при нём `viaXray` истинно, а без него форвардер
    // не поднимается вовсе (его основной путь идёт через локальный SOCKS Xray).
    const xrayOverride = '{"inbounds":[{"tag":"socks","protocol":"socks",'
        '"port":10808,"settings":{"auth":"noauth","udp":true}}],'
        '"outbounds":[{"tag":"proxy","protocol":"freedom"}]}';

    const server = VpnServer(
      protocol: 'vless',
      remark: 'override',
      // Литеральный адрес: резолв в тесте не должен ходить в сеть.
      address: '203.0.113.5',
      port: 443,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink: 'vless://11111111-2222-3333-4444-555555555555@203.0.113.5:443',
      rawJsonOverride: xrayOverride,
    );

    // `myRulesOverridePanel: false` — иначе конфиг панели переписывается
    // реврайтом direct→VPN, а к этому тесту он отношения не имеет.
    const settings = AppSettings(
      tunnelDnsForAll: true,
      myRulesOverridePanel: false,
      splitTunnel: SplitTunnelConfig(mode: SplitMode.exceptSelected),
    );

    late Directory tmp;
    late AndroidEngine engine;
    final started = <String>[];
    var directDnsCalls = 0;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_android_stale_start_');
      AppPaths.overrideRoot(tmp);
      started.clear();
      directDnsCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(vpnChannel, (call) async {
        switch (call.method) {
          case 'isRunning':
            return true; // туннель поднят прошлым запуском интерфейса
          case 'start':
            started.add((call.arguments as Map)['config'] as String);
            return null;
          default:
            return null;
        }
      });
      messenger.setMockMethodCallHandler(eventsChannel, (call) async => null);
      messenger.setMockMethodCallHandler(deviceChannel, (call) async {
        if (call.method != 'directDns') return null;
        directDnsCalls++;
        // ⚠️ ВТОРОЙ вызов идёт УЖЕ ИЗ `startFallbackDns`: входной гейт он
        // прошёл, форвардер поднимется через несколько строк. Ровно в это окно
        // пользователь и успевает нажать «Отключить» → «Подключить», и именно
        // тут запуск становится устаревшим ПОСЛЕ подъёма порта.
        if (directDnsCalls == 2) engine.newGeneration();
        return '192.168.1.1';
      });
      engine = AndroidEngine();
    });

    tearDown(() async {
      await engine.dispose();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger
        ..setMockMethodCallHandler(vpnChannel, null)
        ..setMockMethodCallHandler(eventsChannel, null)
        ..setMockMethodCallHandler(deviceChannel, null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('порт не остаётся слушать, когда запуск устарел за время сборки',
        () async {
      await engine.adoptRunningTunnel();
      expect(engine.status.isConnected, isTrue, reason: 'предпосылка');
      await engine.armAdoptedSession(
          [server], const ConnectionOptions(settings: settings));
      expect(engine.session, isNotNull,
          reason: 'предпосылка: без сессии startSession выходит первой строкой');

      await engine.startSession();

      expect(directDnsCalls, greaterThanOrEqualTo(2),
          reason: 'предпосылка: подъём форвардера был начат');
      expect(started, isEmpty,
          reason: 'предпосылка: запуск устарел ДО отправки конфига сервису');
      expect(engine.fallbackDns, isNull,
          reason: 'форвардер устаревшего запуска остался слушать UDP-порт на '
              'петле — на Android он виден любому приложению, а гасить его '
              'больше некому');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // ⚠️ СТРАЖ ФОНОВОЙ ОБВЯЗКИ ЛОВИЛ ТРЕТЬ ТОГО, ЧТО ОБЕЩАЛ. Из `platformCleanup`
  // можно было удалить и `stopHealthWatch()`, и `await _stopFallbackDns()` —
  // весь набор тестов оставался зелёным: признак `backgroundWorkActive` смотрел
  // на таймер счётчиков и поле форвардера, но форвардер в тесте не поднимался
  // вовсе (`adoptRunningTunnel` его не заводит), а сторож канала в признак не
  // входил.
  //
  // Поэтому ниже у каждой подсистемы свой тест, и в каждом работает РОВНО ОДНА:
  // тогда снятие любой строки красит именно её тест, а не «какой-нибудь».
  group('platformCleanup: у каждой подсистемы свой страж', () {
    const vpnChannel = MethodChannel('lol.silentgate/vpn');
    const eventsChannel = MethodChannel('lol.silentgate/vpn_events');
    const deviceChannel = MethodChannel('lol.silentgate/device');

    const settings = AppSettings(tunnelDnsForAll: true);

    late Directory tmp;
    late _QuietHealthEngine engine;
    final calls = <String>[];

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_android_cleanup_');
      AppPaths.overrideRoot(tmp);
      calls.clear();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(vpnChannel, (call) async {
        calls.add(call.method);
        return call.method == 'isRunning' ? true : null;
      });
      messenger.setMockMethodCallHandler(eventsChannel, (call) async => null);
      messenger.setMockMethodCallHandler(deviceChannel,
          (call) async => call.method == 'directDns' ? '192.168.1.1' : null);
      engine = _QuietHealthEngine();
    });

    tearDown(() async {
      await engine.dispose();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger
        ..setMockMethodCallHandler(vpnChannel, null)
        ..setMockMethodCallHandler(eventsChannel, null)
        ..setMockMethodCallHandler(deviceChannel, null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Строка `_stopStatsPolling()`.
    test('счётчики трафика не тикают в мёртвый порт после отключения',
        () async {
      await engine.adoptRunningTunnel();
      expect(engine.backgroundWorkActive, isTrue,
          reason: 'предпосылка: подхват запускает опрос счётчиков');
      await engine.cleanup();
      expect(engine.backgroundWorkActive, isFalse);
    });

    // Строка `stopHealthWatch()`. Сторож вооружается здесь напрямую: после
    // подхвата живого туннеля он не вооружается вовсе (известный остаток
    // ревью), а через `startSession` в тест приехали бы сразу три подсистемы.
    test('сторож канала не остаётся ходить пробами после отключения', () async {
      engine.startHealthWatch(() => false);
      expect(engine.backgroundWorkActive, isTrue,
          reason: 'предпосылка: сторож вооружён');
      await engine.cleanup();
      expect(engine.backgroundWorkActive, isFalse,
          reason: 'проба раз в 45 с через мёртвый прокси — и «сторож вооружён» '
              'в журнале при выключенном VPN');
    });

    // Строка `await _stopFallbackDns()`.
    test('запасной DNS-форвардер не остаётся слушать порт после отключения',
        () async {
      await engine.startFallbackDns(settings,
          viaXray: true, gen: 1, aborted: () => false);
      final srv = engine.fallbackDns;
      expect(srv, isNotNull, reason: 'предпосылка: форвардер поднят');
      expect(engine.backgroundWorkActive, isTrue);
      await engine.cleanup();
      expect(engine.backgroundWorkActive, isFalse);
      expect(engine.fallbackDns, isNull);
      expect(srv!.isRunning, isFalse,
          reason: 'открытый UDP-порт на петле при выключенном VPN виден на '
              'Android любому приложению, а запросы пересылает провайдеру');
    });

    // Строка `await _stopService()`.
    test('нативному сервису уходит команда остановки', () async {
      await engine.cleanup();
      expect(calls, contains('stop'));
    });
  });
}

/// Сторож канала, который никуда не ходит: тесту важно только «вооружён или
/// снят», а настоящая проба била бы в сеть.
class _QuietHealth extends TunnelHealth {
  _QuietHealth() : super(proxyPort: 1, interval: const Duration(hours: 1));

  @override
  Future<bool> probeOnce() async => true;
}

/// Настоящий Android-движок с одной подменой — пробой сторожа.
class _QuietHealthEngine extends AndroidEngine {
  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) =>
      _QuietHealth();
}
