import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/singbox/exit_outbounds.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Мульти-VPN: правило указывает, ЧЕРЕЗ КАКОЙ СЕРВЕР идти.
///
/// ⚠️ ГЛАВНОЕ, ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ, ЯДРО НЕ ЛОВИТ.
///
/// `sing-box check` принимает конфиг, где правило ссылается на НЕСУЩЕСТВУЮЩИЙ
/// outbound: код возврата 0, ни строчки вывода — проверено настоящим 1.11.15.
/// То же и для `detour` у DNS-сервера. Тегов при мульти-VPN становится много, и
/// одна опечатка молча отправляет сайт в `route.final`, то есть мимо сервера,
/// который выбрал пользователь. Значит проверять целостность ссылок обязаны мы.
void main() {
  // Ключи серверов — это share-ссылки; здесь достаточно любых стабильных строк.
  const keyDe = 'vless://de@ger.example:443';
  const keyUs = 'vless://us@usa.example:443';

  Map<String, dynamic> outboundFor(String key, String host) => {
        'type': 'vless',
        'tag': exitTagFor(key),
        'server': host,
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
      };

  /// Конфиг с двумя дополнительными серверами и правилами из задачи владельца.
  Map<String, dynamic> build({
    required SplitMode mode,
    List<SiteRule> sites = const [],
    List<AppRule> apps = const [],
    List<Map<String, dynamic>>? outbounds,
    TunOptions options = const TunOptions(),
    List<String> apiExitServerKeys = const [],
    List<String> apiOnlyExitKeys = const [],
    String apiToken = '',
  }) {
    final builder = SingboxConfigBuilder(
      options: options,
      exitOutbounds: outbounds ??
          [
            outboundFor(keyDe, '203.0.113.10'),
            outboundFor(keyUs, '203.0.113.20'),
          ],
      apiExitServerKeys: apiExitServerKeys,
      apiOnlyExitKeys: apiOnlyExitKeys,
      apiToken: apiToken,
    );
    return builder.buildMap(
      SplitTunnelConfig(mode: mode, sites: sites, apps: apps),
    );
  }

  List<Map<String, dynamic>> routeRules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> dnsRules(Map<String, dynamic> cfg) =>
      (((cfg['dns'] as Map?)?['rules'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Set<String> outboundTags(Map<String, dynamic> cfg) => {
        for (final o in (cfg['outbounds'] as List).cast<Map>())
          if (o['tag'] is String) o['tag'] as String,
      };

  Set<String> dnsServerTags(Map<String, dynamic> cfg) => {
        for (final s in (((cfg['dns'] as Map?)?['servers'] as List?) ?? const [])
            .cast<Map>())
          if (s['tag'] is String) s['tag'] as String,
      };

  /// Правила, решающие судьбу трафика ЦЕЛИКОМ.
  ///
  /// ⚠️ Отсекаем правила с `network`/`protocol`: это перехват обходных путей
  /// (запрет QUIC на UDP:443 у затуннелированных доменов, hijack-dns). Они
  /// стоят выше маршрутных и содержат те же домены, поэтому наивный поиск
  /// «первое правило с этим доменом» возвращал бы `reject` для совершенно
  /// исправного маршрута. На этом и споткнулась первая версия проверки.
  List<Map<String, dynamic>> mainRules(Map<String, dynamic> cfg) => routeRules(cfg)
      .where((r) => !r.containsKey('network') && !r.containsKey('protocol'))
      .toList();

  String? routeOf(Map<String, dynamic> cfg, String domain) {
    for (final r in mainRules(cfg)) {
      final ds = (r['domain_suffix'] as List?)?.cast<String>() ?? const [];
      if (ds.contains(domain)) {
        return r['action'] == 'reject' ? 'reject' : r['outbound'] as String?;
      }
    }
    return null;
  }

  String? dnsServerOf(Map<String, dynamic> cfg, String domain) {
    for (final r in dnsRules(cfg)) {
      final ds = (r['domain_suffix'] as List?)?.cast<String>() ?? const [];
      if (ds.contains(domain)) {
        return r['action'] == 'reject' ? 'reject' : r['server'] as String?;
      }
    }
    return null;
  }

  group('Целостность ссылок — то, что `sing-box check` пропускает молча', () {
    test('каждый outbound из правил маршрутизации существует', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
          SiteRule('whatsmyipaddress.com',
              action: AppAction.tunnel, serverKey: keyUs),
          SiteRule('dnsleak.com', action: AppAction.direct, allowRealIp: true),
        ],
      );
      final tags = outboundTags(cfg);
      for (final r in routeRules(cfg)) {
        final out = r['outbound'];
        if (out == null) continue; // reject / sniff / hijack-dns
        expect(tags, contains(out),
            reason: 'правило ссылается на несуществующий outbound "$out". '
                'Ядро такой конфиг ПРИНИМАЕТ, и трафик молча уходит в final');
      }
    });

    test('каждый server из DNS-правил и каждый detour существуют', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
          SiteRule('whatsmyipaddress.com',
              action: AppAction.tunnel, serverKey: keyUs),
        ],
      );
      final servers = dnsServerTags(cfg);
      final tags = outboundTags(cfg);
      for (final r in dnsRules(cfg)) {
        final srv = r['server'];
        if (srv == null) continue;
        expect(servers, contains(srv),
            reason: 'DNS-правило ссылается на несуществующий сервер "$srv"');
      }
      for (final s in (((cfg['dns'] as Map)['servers']) as List).cast<Map>()) {
        final d = s['detour'];
        if (d == null) continue;
        expect(d, isA<String>(),
            reason: 'detour обязан быть СТРОКОЙ: массив ядро отвергает целиком '
                '(cannot unmarshal array into Go value of type string)');
        expect(tags, contains(d),
            reason: 'detour "${s['tag']}" ведёт в несуществующий outbound "$d"');
      }
    });

    test('исчезнувший сервер не оставляет висячего тега, а падает в основной',
        () {
      // Правило ссылается на сервер, для которого outbound не собран: так
      // бывает, когда сервер пропал из подписки или его протокол не
      // поднимается вторым туннелем.
      final cfg = build(
        mode: SplitMode.onlySelected,
        outbounds: [outboundFor(keyUs, '203.0.113.20')],
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
        ],
      );
      expect(routeOf(cfg, '2ip.ru'), 'proxy',
          reason: 'висячий тег опаснее: ядро его принимает, а трафик уходит '
              'в final мимо всякого сервера');
      expect(outboundTags(cfg), isNot(contains(exitTagFor(keyDe))));
    });
  });

  /// ⚠️ РЕГРЕССИЯ ВОЛНЫ «ПОРТ ДЛЯ АКТИВНОГО СЕРВЕРА».
  ///
  /// Активный сервер стал получать собственный outbound, чтобы его порт из
  /// `GET /v1/exits` куда-то вёл. Но `exitOutbounds` — единственный источник
  /// правды о живых тегах, и правило «сайт через сервер X», где X и есть
  /// активный сервер, перестало идти тегом `proxy`: обычный трафик правила
  /// уходил ВТОРЫМ соединением к тому же узлу. Панель показывает удвоенный
  /// «онлайн», причём постоянно, а не «пока скрипт пользуется портом»; вдобавок
  /// второй канал — реконструкция sing-box из разобранных полей, а не панельный
  /// outbound Xray, то есть ведёт себя иначе основного.
  ///
  /// Проверка идёт на КОМБИНАЦИИ (активный + отмечен под порт + указан в
  /// правиле) — на составе ключей дефект не виден, там всё верно.
  group('⚠️ Порт API не перехватывает правила', () {
    const site = '2ip.ru';
    // Германия здесь играет активный сервер: его нет среди «серверов правил»,
    // но он есть среди «серверов портов» — ровно то, что делает AppState.
    Map<String, dynamic> withPort({List<String> apiOnly = const [keyDe]}) =>
        build(
          mode: SplitMode.onlySelected,
          sites: const [
            SiteRule(site, action: AppAction.tunnel, serverKey: keyDe),
          ],
          apiExitServerKeys: const [keyDe],
          apiOnlyExitKeys: apiOnly,
          apiToken: 'secret',
        );

    test('правило через АКТИВНЫЙ сервер идёт тегом proxy, а не вторым каналом',
        () {
      final cfg = withPort();
      expect(routeOf(cfg, site), 'proxy',
          reason: 'тег exit-… для активного сервера существует ради порта, но '
              'адресатом правила он быть не должен — иначе к одному узлу '
              'держатся два соединения');
      expect(dnsServerOf(cfg, site), 'dns-proxy',
          reason: 'резолвер обязан идти ТЕМ ЖЕ путём, что трафик: dns-exit-… '
              'здесь означал бы разъехавшиеся маршрут и резолв');
    });

    test('но САМ ПОРТ при этом работает — outbound и инбаунд на месте', () {
      final cfg = withPort();
      expect(outboundTags(cfg), contains(exitTagFor(keyDe)),
          reason: 'без outbound-а порт из /v1/exits вёл бы в никуда — ровно '
              'то, ради чего волна и делалась');
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => i['tag'] == apiExitInboundTag(keyDe)), isTrue);
      final rules = routeRules(cfg);
      expect(
          rules.any((r) =>
              (r['inbound'] as List?)?.contains(apiExitInboundTag(keyDe)) ==
                  true &&
              r['outbound'] == exitTagFor(keyDe)),
          isTrue,
          reason: 'трафик, пришедший в порт сервера, обязан уйти именно в него');
    });

    test('КОНТРОЛЬ: без пометки «только ради порта» правило уходит в exit-…',
        () {
      // Тест обязан отличать исправленный код от сломанного: это ровно то
      // поведение, которое волна и породила.
      final cfg = withPort(apiOnly: const []);
      expect(routeOf(cfg, site), exitTagFor(keyDe));
    });

    test('сервер правила, у которого ТОЖЕ есть порт, адресатом остаётся', () {
      // США здесь — не активный сервер: он и в правиле, и с портом. Прятать
      // его тег от правил нельзя, иначе «сайт через США» уехал бы в общий
      // туннель, то есть в другую страну.
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule(site, action: AppAction.tunnel, serverKey: keyUs),
        ],
        apiExitServerKeys: const [keyUs],
        apiOnlyExitKeys: const [],
        apiToken: 'secret',
      );
      expect(routeOf(cfg, site), exitTagFor(keyUs));
      expect(dnsServerOf(cfg, site), 'dns-${exitTagFor(keyUs)}');
    });

    test('режим «Всё через VPN»: правило активного сервера не появляется', () {
      // `_exitRulesOnly` строит правила выбора выхода даже в режиме «Всё через
      // VPN». Выход, живущий только ради порта, правил порождать не должен —
      // иначе тот же второй канал вернулся бы с другой стороны.
      final cfg = build(
        mode: SplitMode.all,
        sites: const [
          SiteRule(site, action: AppAction.tunnel, serverKey: keyDe),
        ],
        apiExitServerKeys: const [keyDe],
        apiOnlyExitKeys: const [keyDe],
        apiToken: 'secret',
      );
      expect(routeOf(cfg, site), isNull,
          reason: 'правило «через активный сервер» в этом режиме означает '
              '«через основной туннель», то есть ничего');
      // Контроль: тот же режим для НЕ активного сервера правило порождает —
      // значит проверка выше не проходит просто потому, что в режиме `all`
      // правил нет вовсе.
      final other = build(
        mode: SplitMode.all,
        sites: const [
          SiteRule(site, action: AppAction.tunnel, serverKey: keyUs),
        ],
      );
      expect(routeOf(other, site), exitTagFor(keyUs));
    });
  });

  group('Разведение по серверам', () {
    test('сайты одного действия, но разных серверов — РАЗНЫМИ правилами', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
          SiteRule('whatsmyipaddress.com',
              action: AppAction.tunnel, serverKey: keyUs),
          SiteRule('dnsleak.com', action: AppAction.direct, allowRealIp: true),
        ],
      );
      expect(routeOf(cfg, '2ip.ru'), exitTagFor(keyDe));
      expect(routeOf(cfg, 'whatsmyipaddress.com'), exitTagFor(keyUs));
      expect(routeOf(cfg, 'dnsleak.com'), 'direct');

      // ⚠️ Проверяем только МАРШРУТНЫЕ правила. Запрет QUIC перечисляет все
      // затуннелированные домены одним правилом — и это верно: он никого
      // никуда не отправляет, а лишь закрывает UDP:443, чтобы браузер на
      // HTTP/3 не оставил ядро без имени домена.
      for (final r in mainRules(cfg)) {
        final ds = (r['domain_suffix'] as List?)?.cast<String>() ?? const [];
        expect(ds.contains('2ip.ru') && ds.contains('whatsmyipaddress.com'),
            isFalse,
            reason: 'домены разных серверов склеились в одно правило — оба '
                'уехали бы туда, чей тег попал в правило');
      }
    });

    test('DNS зеркалит маршрут: каждый домен резолвится СВОИМ сервером', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
          SiteRule('whatsmyipaddress.com',
              action: AppAction.tunnel, serverKey: keyUs),
          SiteRule('dnsleak.com', action: AppAction.direct, allowRealIp: true),
        ],
      );
      // Иначе CDN вернёт адрес по стране РЕЗОЛВЕРА, и трафик пойдёт немецким
      // маршрутом на американский фронт. Такой дефект у нас уже был в 1.0.1.
      expect(dnsServerOf(cfg, '2ip.ru'), exitDnsTagFor(keyDe));
      expect(dnsServerOf(cfg, 'whatsmyipaddress.com'), exitDnsTagFor(keyUs));
      expect(dnsServerOf(cfg, 'dnsleak.com'), 'dns-local');
    });

    test('теги маршрута и резолвера согласованы между собой', () {
      // Оба имени образуются в exit_tags.dart, и построитель выводит имя
      // резолвера из имени outbound-а. Разойдись они — правило ссылалось бы на
      // несуществующий сервер, а ядро промолчало бы.
      expect(exitDnsTagFor(keyDe), 'dns-${exitTagFor(keyDe)}');
    });

    test('приложения разных серверов — тоже разными правилами', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        options: const TunOptions(platformTun: true),
        apps: const [
          AppRule('org.telegram.messenger',
              action: AppAction.tunnel, serverKey: keyDe),
          AppRule('com.instagram.android',
              action: AppAction.tunnel, serverKey: keyUs),
        ],
      );
      String? pkgRoute(String pkg) {
        for (final r in routeRules(cfg)) {
          final ps = (r['package_name'] as List?)?.cast<String>() ?? const [];
          if (ps.contains(pkg)) return r['outbound'] as String?;
        }
        return null;
      }

      expect(pkgRoute('org.telegram.messenger'), exitTagFor(keyDe));
      expect(pkgRoute('com.instagram.android'), exitTagFor(keyUs));
    });
  });

  group('Поддомен не должен проигрывать родителю с другого сервера', () {
    test('одинаковое действие, разные серверы — конфликт, поддомен поднимается',
        () {
      // До мульти-VPN конфликтом считалось только разное ДЕЙСТВИЕ. Здесь
      // действие одно («Туннель»), а адресаты разные — и суффиксное совпадение
      // отправило бы поддомен в чужую страну.
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule('example.com', action: AppAction.tunnel, serverKey: keyDe),
          SiteRule('sub.example.com',
              action: AppAction.tunnel, serverKey: keyUs),
        ],
      );
      final rules = mainRules(cfg);
      int idxOf(String d) => rules.indexWhere((r) =>
          ((r['domain_suffix'] as List?)?.cast<String>() ?? const []).contains(d));
      final child = idxOf('sub.example.com');
      final parent = idxOf('example.com');
      expect(child, greaterThanOrEqualTo(0));
      expect(parent, greaterThanOrEqualTo(0));
      expect(child, lessThan(parent),
          reason: 'ядро берёт ПЕРВОЕ совпадение, а domain_suffix суффиксный: '
              'родитель выше поглотил бы поддомен');
      expect(routeOf(cfg, 'sub.example.com'), exitTagFor(keyUs));
    });
  });

  group('Режим «Всё через VPN»', () {
    test('правила ВЫБОРА СЕРВЕРА действуют и там', () {
      // Сервер отвечает не на вопрос «идёт ли в туннель» (идёт, как и всё
      // остальное), а на вопрос «через какой».
      final cfg = build(
        mode: SplitMode.all,
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
        ],
      );
      expect(routeOf(cfg, '2ip.ru'), exitTagFor(keyDe));
      expect(dnsServerOf(cfg, '2ip.ru'), exitDnsTagFor(keyDe));
    });

    test('правила БЕЗ сервера режим не меняют — конфиг остаётся прежним', () {
      // Иначе конфиг поменялся бы у каждого, кто просто держит правила
      // сохранёнными, ничего не настраивая.
      final withRules = build(
        mode: SplitMode.all,
        outbounds: const [],
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel),
          SiteRule('dnsleak.com', action: AppAction.direct),
        ],
      );
      final clean = build(mode: SplitMode.all, outbounds: const []);
      expect(routeRules(withRules), equals(routeRules(clean)));
      expect(dnsRules(withRules), equals(dnsRules(clean)));
    });
  });

  group('Совместимость: без дополнительных серверов ничего не изменилось', () {
    test('конфиг идентичен тому, что был до мульти-VPN', () {
      const sites = [
        SiteRule('a.example', action: AppAction.tunnel),
        SiteRule('b.example', action: AppAction.direct, allowRealIp: true),
        SiteRule('c.example', action: AppAction.block),
      ];
      final none =
          build(mode: SplitMode.onlySelected, sites: sites, outbounds: const []);
      expect(routeOf(none, 'a.example'), 'proxy');
      expect(routeOf(none, 'b.example'), 'direct');
      expect(routeOf(none, 'c.example'), 'reject');
      expect(dnsServerTags(none), equals({'dns-proxy', 'dns-local'}));
    });

    test('serverKey у «Прямо» и «Блока» игнорируется', () {
      // «Прямо через Германию» — противоречие; правило, которое видно в
      // интерфейсе и ничего не делает, хуже отсутствующего.
      final cfg = build(
        mode: SplitMode.onlySelected,
        sites: const [
          SiteRule('d.example',
              action: AppAction.direct, allowRealIp: true, serverKey: keyDe),
          SiteRule('e.example', action: AppAction.block, serverKey: keyUs),
        ],
      );
      expect(routeOf(cfg, 'd.example'), 'direct');
      expect(routeOf(cfg, 'e.example'), 'reject');
    });
  });

  group('Пинг и подписка обязаны идти МИМО туннеля', () {
    // ⚠️ ЭТО СТЕРЕЖЁТ ЖАЛОБУ «пинг серверов стал через VPN».
    //
    // Мимо туннеля пинг уводят ДВА правила, и оба обязаны стоять ВЫШЕ любых
    // пользовательских: «свои процессы → direct» (пинг открывает сокет из
    // silentgate.exe, харнесс — из xray.exe/sing-box.exe) и «домены наших
    // серверов → dns-local» (иначе имя сервера резолвилось бы через туннель,
    // который к этому серверу ещё не построен). Стоит правилу пользователя
    // оказаться выше — и пинг молча уедет в туннель, показывая задержку
    // не сервера, а маршрута через другой сервер.
    test('правило «свои процессы» выше ВСЕХ пользовательских', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        options: const TunOptions(serverDomains: ['ger.example']),
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
          SiteRule('dnsleak.com', action: AppAction.direct, allowRealIp: true),
        ],
      );
      final rules = routeRules(cfg);
      final self = rules.indexWhere((r) =>
          ((r['process_name'] as List?)?.cast<String>() ?? const [])
              .contains('silentgate.exe'));
      expect(self, greaterThanOrEqualTo(0),
          reason: 'без этого правила весь пинг уйдёт в туннель');
      final firstUser = rules.indexWhere(
          (r) => r.containsKey('domain_suffix') || r.containsKey('package_name'));
      if (firstUser >= 0) {
        expect(self, lessThan(firstUser),
            reason: 'ядро берёт ПЕРВОЕ совпадение: пользовательское правило '
                'выше увело бы наш собственный трафик в туннель');
      }
    });

    test('домены наших серверов резолвятся локально и выше правил сайтов', () {
      final cfg = build(
        mode: SplitMode.onlySelected,
        options: const TunOptions(serverDomains: ['ger.example']),
        sites: const [
          SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe),
        ],
      );
      expect(dnsServerOf(cfg, 'ger.example'), 'dns-local',
          reason: 'адрес сервера нельзя спрашивать через туннель к нему же');
      final rules = dnsRules(cfg);
      int idx(String d) => rules.indexWhere((r) =>
          ((r['domain_suffix'] as List?)?.cast<String>() ?? const []).contains(d));
      expect(idx('ger.example'), lessThan(idx('2ip.ru')));
    });
  });

  group('Сервер, которого sing-box не умеет', () {
    // ⚠️ Панельный профиль «Авто» — это ГОТОВЫЙ КОНФИГ XRAY целиком, а выходы
    // разводит sing-box: собрать из него outbound он не может. Правило при этом
    // остаётся валидным и молча идёт основным туннелем. Владелец наступил на
    // это живьём: два сайта были помечены панельными профилями и «не работали»,
    // хотя строка в интерфейсе выглядела настроенной.
    test('фабрика честно отказывается от панельного профиля', () {
      const panel = VpnServer(
        protocol: 'panel',
        remark: 'Авто (YouTube)',
        address: 'panel.example',
        port: 443,
        id: '',
        rawLink: 'panel://%D0%90%D0%B2%D1%82%D0%BE',
      );
      expect(SingboxOutboundFactory.supports(panel), isFalse);
      final built = ExitOutbounds.build(servers: {'k': panel});
      expect(built.outbounds, isEmpty);
      expect(built.skipped.keys, contains('k'),
          reason: 'причина обязана попадать в журнал, а не теряться молча');
    });

    /// ⚠️ ТЕСТ ВЫШЕ БРАЛ ПРОФИЛЬ С ПРОТОКОЛОМ `panel` — ТАКИХ НЕ БЫВАЕТ.
    ///
    /// У настоящего панельного профиля `protocol` берётся с ПЕРВОГО outbound'а
    /// конфига и равен `vless`, то есть `SingboxOutboundFactory.supports`
    /// отвечает `true`. Отсекал профили не предикат, а совпадение: выдуманный
    /// протокол. Из-за этого выход собирался из ОДНОГО узла профиля — без
    /// балансировщика и `burstObservatory`, — а интерфейс и `docs/API.md`
    /// утверждали, что такие серверы показаны серым и порта не получают.
    test('⚠️ НАСТОЯЩИЙ панельный профиль: протокол vless, а выходом не годится',
        () {
      const panel = VpnServer(
        protocol: 'vless',
        remark: '🎬 Авто (YouTube)',
        address: 'node1.example',
        port: 443,
        id: '11111111-1111-1111-1111-111111111111',
        rawLink: 'panel://%D0%90%D0%B2%D1%82%D0%BE',
        rawPanelConfig: '{"outbounds":[],"routing":{"balancers":[]}}',
      );
      expect(panel.isPanelProfile, isTrue);
      expect(SingboxOutboundFactory.supports(panel), isTrue,
          reason: 'ровно поэтому одного `supports` и не хватало: протокол у '
              'профиля обычный');
      expect(canBeExitServer(panel), isFalse,
          reason: 'единственный ответчик обязан видеть профиль целиком, а не '
              'только его протокол');

      final built = ExitOutbounds.build(servers: {'k': panel});
      expect(built.outbounds, isEmpty,
          reason: 'иначе выход собрался бы из одного узла профиля, а скрипт '
              'думал бы, что ходит «через Авто»');
      expect(built.skipped['k'], contains('Авто'));
    });

    test('заглушка истёкшей подписки (0.0.0.0:1) выходом тоже не становится',
        () {
      const notice = VpnServer(
        protocol: 'vless',
        remark: 'Ваша подписка истекла!',
        address: '0.0.0.0',
        port: 1,
        id: '11111111-1111-1111-1111-111111111111',
        rawLink: 'vless://notice',
      );
      expect(notice.isNotice, isTrue);
      expect(canBeExitServer(notice), isFalse,
          reason: 'конфиг с таким выходом валиден и ведёт в никуда: ядро '
              'примет, а соединение отвергнется на сокете');
      expect(ExitOutbounds.build(servers: {'k': notice}).outbounds, isEmpty);
    });

    test('обычный сервер годится — контроль, что предикат не запрещает всё',
        () {
      const ok = VpnServer(
        protocol: 'vless',
        remark: 'Германия',
        address: 'ger.example',
        port: 443,
        id: '11111111-1111-1111-1111-111111111111',
        rawLink: keyDe,
      );
      expect(canBeExitServer(ok), isTrue);
      expect(exitServerRejection(ok), isNull);
      expect(ExitOutbounds.build(servers: {keyDe: ok}).outbounds, hasLength(1));
    });

    test('правило с таким сервером идёт ОСНОВНЫМ туннелем, а не в никуда', () {
      // Висячий тег был бы хуже: `sing-box check` его не ловит, и трафик ушёл
      // бы в route.final мимо любого туннеля.
      final cfg = build(
        mode: SplitMode.onlySelected,
        outbounds: const [],
        sites: const [
          SiteRule('rule34.xxx',
              action: AppAction.tunnel, serverKey: 'panel://x'),
        ],
      );
      expect(routeOf(cfg, 'rule34.xxx'), 'proxy');
      for (final r in routeRules(cfg)) {
        final out = r['outbound'];
        if (out is! String) continue;
        expect(out.startsWith('exit-'), isFalse,
            reason: 'висячих тегов в конфиге быть не должно');
      }
    });
  });

  group('Модель и миграция', () {
    test('serverKey переживает сохранение и чтение', () {
      const s = SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyDe);
      expect(SiteRule.fromJson(s.toJson()).serverKey, keyDe);
      const a = AppRule('org.telegram.messenger',
          action: AppAction.tunnel, serverKey: keyUs);
      expect(AppRule.fromJson(a.toJson()).serverKey, keyUs);
    });

    test('пустой serverKey равнозначен отсутствию', () {
      // Иначе в конфиг уехал бы тег без сервера — валидный для ядра и ни на
      // что не ссылающийся.
      expect(SiteRule.fromJson({'domain': 'x.ru', 'serverKey': ''}).serverKey,
          isNull);
      expect(SiteRule.fromJson({'domain': 'x.ru', 'serverKey': '  '}).serverKey,
          isNull);
    });

    test('правила ПЕРВОЙ редакции мульти-VPN переезжают на ключ сервера', () {
      // Тогда существовала отдельная сущность «выход», и правило ссылалось на
      // её идентификатор. Молча потерянное правило — это трафик, ушедший не в
      // ту страну, причём без следа в интерфейсе.
      final old = {
        'exits': [
          {'id': 'e1', 'name': 'Ger', 'serverKeys': [keyDe]},
        ],
        'splitTunnel': {
          'mode': 'onlySelected',
          'sites': [
            {'domain': '2ip.ru', 'action': 'tunnel', 'exitId': 'e1'},
          ],
          'apps': [
            {'path': 'Telegram.exe', 'action': 'tunnel', 'exitId': 'e1'},
          ],
        },
      };
      final s = AppSettings.fromJson(old);
      expect(s.splitTunnel.sites.single.serverKey, keyDe);
      expect(s.splitTunnel.apps.single.serverKey, keyDe);
    });

    test('тег сервера стабилен между запусками', () {
      // Он попадает в конфиг ядра и в правила; «плавающий» тег означал бы, что
      // после перезапуска правило ссылается в пустоту.
      expect(exitTagFor(keyDe), exitTagFor(keyDe));
      expect(exitTagFor(keyDe), isNot(exitTagFor(keyUs)));
      expect(exitTagFor(keyDe), matches(RegExp(r'^exit-[0-9a-f]{8}$')));
    });
  });
}
