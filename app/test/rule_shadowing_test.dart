import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/engine/android/android_engine.dart';

/// Стражи против ЧЕТЫРЁХ багов, найденных ревью маршрутизации 01.08.2026.
///
/// Общее у всех четырёх: правило видно в интерфейсе, лежит в конфиге и выглядит
/// рабочим — а не срабатывает никогда. Компилятор такое не ловит, `sing-box
/// check` тоже (конфиг валиден), поэтому проверка только здесь.
void main() {
  List<Map<String, dynamic>> routeRules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> dnsRules(Map<String, dynamic> cfg) =>
      ((cfg['dns'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  bool domain(Map<String, dynamic> r, String d) =>
      (r['domain_suffix'] as List?)?.contains(d) == true;

  int indexWhereRule(List<Map<String, dynamic>> rules,
          bool Function(Map<String, dynamic>) f) =>
      rules.indexWhere(f);

  Map<String, dynamic> build(SplitTunnelConfig split,
          {bool noRealIp = false,
          bool platformTun = false,
          int blockPagePort = 0}) =>
      SingboxConfigBuilder(
        options: TunOptions(
          serverIps: const ['203.0.113.10'],
          noRealIp: noRealIp,
          platformTun: platformTun,
          blockPagePort: blockPagePort,
        ),
      ).buildMap(split);

  group('Блок не теряется из-за галочки «важнее правил сайтов»', () {
    // Было: _addBlockRules звал _addActionRule с умолчанием overrideSites:false,
    // поэтому блок-правила строились ТОЛЬКО для приложений без галочки.
    // Приложение с блоком И галочкой пропадало из конфига целиком, трафик уходил
    // в базу — в «Только отмеченные» это полный интернет под реальным IP.
    for (final mode in [SplitMode.onlySelected, SplitMode.exceptSelected]) {
      test('Windows, режим ${mode.name}', () {
        final cfg = build(SplitTunnelConfig(mode: mode, apps: const [
          AppRule('evil.exe',
              byName: true, action: AppAction.block, overrideSites: true),
          AppRule('ok.exe', byName: true, action: AppAction.block),
        ]));
        final blocked = routeRules(cfg)
            .where((r) => r['action'] == 'reject')
            .expand((r) => (r['process_name'] as List?) ?? const [])
            .toSet();
        expect(blocked, containsAll(<String>['evil.exe', 'ok.exe']),
            reason: 'блокировка обязана попасть в конфиг при любой галочке');
      });
    }

    test('Android: пакет заводится в туннель И там же блокируется', () {
      final cfg = build(
        const SplitTunnelConfig(mode: SplitMode.onlySelected, apps: [
          AppRule('com.evil', action: AppAction.block, overrideSites: true),
        ]),
        platformTun: true,
      );
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      // Пакет обязан быть в туннеле — снаружи ядро его не увидит...
      expect((tun['include_package'] as List?) ?? const [], contains('com.evil'));
      // ...и там его обязан встретить reject, иначе он просто выйдет в базу.
      final rejected = routeRules(cfg)
          .where((r) => r['action'] == 'reject')
          .expand((r) => (r['package_name'] as List?) ?? const [])
          .toSet();
      expect(rejected, contains('com.evil'),
          reason: 'заведён в туннель без reject = блокировка молча разрешает');
    });
  });

  group('Поддомен не проигрывает родителю с другим действием', () {
    // Было: правила группируются по действию (блок → Прямо → Туннель), а
    // domain_suffix суффиксный — родитель «Прямо» поглощал поддомен «Туннель»,
    // и тот выходил под реальным IP.
    const split = SplitTunnelConfig(mode: SplitMode.exceptSelected, sites: [
      SiteRule('example.com', action: AppAction.direct, allowRealIp: true),
      SiteRule('secure.example.com', action: AppAction.tunnel),
    ]);

    test('в маршрутах поддомен выше родителя', () {
      final rules = routeRules(build(split));
      final child = indexWhereRule(rules, (r) => domain(r, 'secure.example.com'));
      final parent = indexWhereRule(rules, (r) => domain(r, 'example.com'));
      expect(child, isNonNegative);
      expect(parent, isNonNegative);
      expect(child, lessThan(parent),
          reason: 'иначе правило поддомена мертво — sing-box берёт первое совпадение');
      expect(rules[child]['outbound'], 'proxy');
    });

    test('DNS-зеркало повторяет тот же порядок', () {
      // Разойдись зеркало с маршрутом — сайт шёл бы в туннель, а имя
      // спрашивалось бы у резолвера провайдера. Это утечка DNS, не косметика.
      final rules = dnsRules(build(split));
      final child = indexWhereRule(rules, (r) => domain(r, 'secure.example.com'));
      final parent = indexWhereRule(rules, (r) => domain(r, 'example.com'));
      expect(child, isNonNegative);
      expect(parent, isNonNegative);
      expect(child, lessThan(parent));
      expect(rules[child]['server'], 'dns-proxy');
    });

    test('обратная пара тоже упорядочена, а не «повезло»', () {
      const rev = SplitTunnelConfig(mode: SplitMode.exceptSelected, sites: [
        SiteRule('example.com', action: AppAction.tunnel),
        SiteRule('cdn.example.com', action: AppAction.direct, allowRealIp: true),
      ]);
      final rules = routeRules(build(rev));
      final child = indexWhereRule(rules, (r) => domain(r, 'cdn.example.com'));
      final parent = indexWhereRule(rules, (r) => domain(r, 'example.com'));
      expect(child, lessThan(parent));
      expect(rules[child]['outbound'], 'direct');
    });

    test('поднятый поддомен уважает «не выходить под реальным IP»', () {
      const s = SplitTunnelConfig(mode: SplitMode.exceptSelected, sites: [
        SiteRule('example.com', action: AppAction.tunnel),
        // Галочка «разрешить реальный IP» НЕ поднята — значит через VPN.
        SiteRule('cdn.example.com', action: AppAction.direct),
      ]);
      final rules = routeRules(build(s, noRealIp: true));
      final child = indexWhereRule(rules, (r) => domain(r, 'cdn.example.com'));
      expect(rules[child]['outbound'], 'proxy',
          reason: 'защита стоит выше всех правил и не перебивается');
    });

    test('одинаковое действие лишних правил не плодит', () {
      const same = SplitTunnelConfig(mode: SplitMode.exceptSelected, sites: [
        SiteRule('example.com', action: AppAction.tunnel),
        SiteRule('a.example.com', action: AppAction.tunnel),
      ]);
      final hits = routeRules(build(same))
          .where((r) => domain(r, 'a.example.com'))
          .length;
      expect(hits, 1, reason: 'порядок тут ничего не меняет — поднимать нечего');
    });
  });

  group('Android: приложение «Прямо» не отменяет правила сайтов', () {
    // Было: exclude_package выводит пакет из туннеля на уровне ОС, ядро его
    // трафика не видит — и доменные правила по нему не срабатывают вовсе.
    const split = SplitTunnelConfig(mode: SplitMode.exceptSelected, apps: [
      AppRule('com.android.chrome', action: AppAction.direct, allowRealIp: true),
    ], sites: [
      SiteRule('youtube.com', action: AppAction.tunnel),
    ]);

    test('пакет остаётся в туннеле, а мимо VPN его уводит правило', () {
      final cfg = build(split, platformTun: true);
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      expect((tun['exclude_package'] as List?) ?? const [],
          isNot(contains('com.android.chrome')),
          reason: 'исключённый на уровне ОС пакет доменных правил не увидит');

      final rules = routeRules(cfg);
      final site = indexWhereRule(rules, (r) => domain(r, 'youtube.com'));
      final app = indexWhereRule(rules,
          (r) => (r['package_name'] as List?)?.contains('com.android.chrome') == true);
      expect(site, isNonNegative);
      expect(app, isNonNegative);
      expect(site, lessThan(app), reason: 'сайты выше приложений');
      expect(rules[app]['outbound'], 'direct');
    });

    test('без правил «Туннель»/«Блок» исключение на уровне ОС остаётся', () {
      // Терять правило «Прямо» по сайту не жалко — приложение и так идёт прямо,
      // а исключение на уровне ОС дешевле прогона через ядро.
      const light = SplitTunnelConfig(mode: SplitMode.exceptSelected, apps: [
        AppRule('com.android.chrome', action: AppAction.direct, allowRealIp: true),
      ], sites: [
        SiteRule('example.com', action: AppAction.direct, allowRealIp: true),
      ]);
      final cfg = build(light, platformTun: true);
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      expect((tun['exclude_package'] as List?) ?? const [],
          contains('com.android.chrome'));
    });

    test('галочка «важнее сайтов» возвращает исключение на уровне ОС', () {
      const over = SplitTunnelConfig(mode: SplitMode.exceptSelected, apps: [
        AppRule('com.android.chrome',
            action: AppAction.direct, allowRealIp: true, overrideSites: true),
      ], sites: [
        SiteRule('youtube.com', action: AppAction.tunnel),
      ]);
      final cfg = build(over, platformTun: true);
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      expect((tun['exclude_package'] as List?) ?? const [],
          contains('com.android.chrome'),
          reason: 'приложение и так обязано выигрывать у доменных правил');
    });
  });

  group('Заглушка не перехватывает чужой порт', () {
    test('блок только на 8443 не даёт заглушку на 80', () {
      // Было: список доменов заглушки собирался без учёта порта, и обычный
      // http://example.com показывал «сайт заблокирован» без всякой блокировки.
      const split = SplitTunnelConfig(mode: SplitMode.exceptSelected, sites: [
        SiteRule('example.com', port: 8443, action: AppAction.block),
      ]);
      final stub = routeRules(build(split, blockPagePort: 9091))
          .where((r) => r['override_port'] == 9091)
          .toList();
      expect(stub, isEmpty,
          reason: 'на 80-м порту этот домен пользователь не блокировал');
    });

    test('блок домена целиком заглушку даёт', () {
      const split = SplitTunnelConfig(mode: SplitMode.exceptSelected, sites: [
        SiteRule('ads.example', action: AppAction.block),
      ]);
      final stub = routeRules(build(split, blockPagePort: 9091))
          .where((r) => r['override_port'] == 9091)
          .toList();
      expect(stub, hasLength(1));
      expect(domain(stub.single, 'ads.example'), isTrue);
      expect(stub.single['port'], [80]);
    });
  });

  group('Локальные порты двух ядер', () {
    // На Windows Xray и sing-box — РАЗНЫЕ процессы, и одинаковый номер порта у
    // них безобиден. На Android оба ядра живут в ОДНОМ процессе, и
    // `SilentGateVpnService` поднимает Xray ПЕРВЫМ. Совпадение означало: sing-box
    // не может забиндить clash_api -> исключение -> `startTunnel` снимает туннель
    // целиком. «Авто (лучший сервер)» и панельные профили не подключались ВООБЩЕ,
    // а обычный VLESS работал (там Xray не поднимается) — поэтому на простом
    // тесте дефект был не виден.
    //
    // Сверяем КОНСТАНТЫ, а не строку конфига: смысл в том, чтобы новый локальный
    // порт нельзя было завести, не сверившись с обоими ядрами.
    test('не совпадают ни одной парой', () {
      const xray = XrayPorts();
      final used = <int, String>{};
      void claim(int port, String who) {
        expect(used.containsKey(port), isFalse,
            reason: 'порт $port уже занят «${used[port]}», а его просит «$who» — '
                'на Android это ОДИН процесс, и второй бинд валит туннель');
        used[port] = who;
      }

      claim(xray.socks, 'Xray socks');
      claim(xray.http, 'Xray http');
      claim(xray.api, 'Xray api (dokodemo)');
      claim(AndroidEngine.probeInboundPort, 'инбаунд проб');
      claim(AndroidEngine.clashApiPort, 'sing-box clash_api');
    });
  });

  group('Android: правила сайтов живут и в режиме «только отмеченные»', () {
    // Было: include_package строился ТОЛЬКО из split.apps, а он означает «в
    // туннель идут лишь эти пакеты». Значит правило по сайту для неотмеченного
    // приложения применить некому — ядро его трафика не видит. Зеркало той же
    // утечки, что чинили для exclude_package.
    const split = SplitTunnelConfig(mode: SplitMode.onlySelected, apps: [
      AppRule('com.messenger', action: AppAction.tunnel),
    ], sites: [
      SiteRule('youtube.com', action: AppAction.tunnel),
    ]);

    test('include_package не отсекает неотмеченные приложения', () {
      final cfg = build(split, platformTun: true);
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      expect(tun['include_package'], isNull,
          reason: 'с include в туннель не зайдёт браузер, и правило сайта мертво');
      // Смысл режима сохраняется маршрутизацией, а не списком пакетов.
      expect((cfg['route'] as Map)['final'], 'direct');
      final rules = routeRules(cfg);
      final site = indexWhereRule(rules, (r) => domain(r, 'youtube.com'));
      final app = indexWhereRule(
          rules, (r) => (r['package_name'] as List?)?.contains('com.messenger') == true);
      expect(site, isNonNegative);
      expect(app, isNonNegative);
      expect(site, lessThan(app), reason: 'сайты обязаны стоять выше приложений');
    });

    test('без правил «Туннель»/«Блок» по сайтам список пакетов остаётся', () {
      final cfg = build(
        const SplitTunnelConfig(mode: SplitMode.onlySelected, apps: [
          AppRule('com.messenger', action: AppAction.tunnel),
        ]),
        platformTun: true,
      );
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      expect(tun['include_package'], contains('com.messenger'),
          reason: 'отсекать на уровне ОС дешевле — отказываемся только ради сайтов');
    });

    test('блокировка сайта тоже поднимает отсечку', () {
      final cfg = build(
        const SplitTunnelConfig(mode: SplitMode.onlySelected, apps: [
          AppRule('com.messenger', action: AppAction.tunnel),
        ], sites: [
          SiteRule('ads.example', action: AppAction.block),
        ]),
        platformTun: true,
      );
      final tun = (cfg['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['type'] == 'tun');
      expect(tun['include_package'], isNull);
    });
  });
}
