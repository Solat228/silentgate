import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/windows/kill_switch_wfp.dart';
import 'package:silentgate/engine/windows/process_list_windows.dart';
import 'package:silentgate/engine/windows/tun/tun_helper.dart';
import 'package:silentgate/engine/windows/wfp_rules.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// Вывод адресов серверов из туннеля НА УРОВНЕ ОС (`route_exclude_address`).
///
/// Зачем: правило «serverIps → direct» выбирает outbound уже ВНУТРИ ядра, а
/// `auto_route` затягивает в туннель и сокеты самого приложения. TCP-рукопожатие
/// фазы 1 пинга завершал локальный стек sing-box за 1–3 мс — активный сервер
/// «Германия» показывал 3 мс, чего физически быть не может. Исключение на
/// уровне интерфейса — единственный способ, чтобы `Socket.connect` дозванивался
/// до настоящего узла.
///
/// ⚠️ Цена ошибки в этих тестах — не косметика. `route_exclude_address` —
/// свойство САМОГО интерфейса: «задышавший» список (другой порядок, лишний
/// адрес) означает другой конфиг, а другой конфиг — пересоздание туннеля, то
/// есть моргание маршрута по умолчанию у всей машины и окно утечки.
void main() {
  const split = SplitTunnelConfig(mode: SplitMode.all);

  Map<String, dynamic> buildLive(TunOptions o) =>
      SingboxConfigBuilder(options: o).buildMap(split);

  /// TUN-инбаунд из готового конфига — ровно то, по чему система решает,
  /// пересоздавать ли интерфейс.
  Map<String, dynamic> tunInbound(Map<String, dynamic> cfg) =>
      (cfg['inbounds'] as List).cast<Map<String, dynamic>>().firstWhere(
            (i) => i['type'] == 'tun',
          );

  group('route_exclude_address: путь отката', () {
    test('пустой список серверов отдаёт РОВНО прежний конфиг', () {
      // Порядок нарочно не отсортирован: прежний код отдавал пользовательские
      // CIDR как есть, и путь отката обязан сохранить это байт в байт —
      // пересортировка была бы ДРУГИМ конфигом и пересозданием туннеля
      // у всех, у кого новая настройка выключена.
      const o = TunOptions(
        excludeCidrs: ['10.9.0.0/24', '10.8.0.0/24'],
        tunnelExcludeServerIps: [],
      );
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], ['10.9.0.0/24', '10.8.0.0/24'],
          reason: 'путь отката: без адресов серверов — прежний порядок, '
              'прежний состав');
    });

    test('без серверов и без пользовательских CIDR ключа нет вовсе', () {
      const o = TunOptions();
      final inbound = tunInbound(buildLive(o));
      expect(inbound.containsKey('route_exclude_address'), isFalse,
          reason: 'прежний конфиг ключа не имел — появившийся пустой ключ '
              'это уже другой интерфейс');
    });
  });

  group('route_exclude_address: адреса серверов', () {
    test('адреса серверов попадают в исключения, пользовательские не теряются',
        () {
      const o = TunOptions(
        excludeCidrs: ['10.9.0.0/24', '10.8.0.0/24'],
        tunnelExcludeServerIps: ['203.0.113.10', '198.51.100.7'],
      );
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], [
        '10.8.0.0/24',
        '10.9.0.0/24',
        '198.51.100.7/32',
        '203.0.113.10/32',
      ]);
    });

    test('IPv6-адрес сервера приводится к /128', () {
      const o = TunOptions(tunnelExcludeServerIps: ['2001:db8::1']);
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], ['2001:db8::1/128']);
    });

    test('результат не зависит от порядка входных адресов', () {
      // Страж против пересоздания туннеля: порядок приходит от резолва и от
      // порядка серверов в подписке, и без сортировки конфиг «дышал» бы между
      // сборками при том же содержимом.
      const a = TunOptions(
        excludeCidrs: ['10.9.0.0/24'],
        tunnelExcludeServerIps: ['203.0.113.10', '198.51.100.7', '2001:db8::1'],
      );
      const b = TunOptions(
        excludeCidrs: ['10.9.0.0/24'],
        tunnelExcludeServerIps: ['2001:db8::1', '198.51.100.7', '203.0.113.10'],
      );
      expect(
        SingboxConfigBuilder(options: a).buildJson(split),
        SingboxConfigBuilder(options: b).buildJson(split),
        reason: 'на побайтовом совпадении держится решение «туннель не '
            'пересоздавать»',
      );
    });

    test('дубликаты схлопываются — и между серверами, и с CIDR пользователя',
        () {
      const o = TunOptions(
        excludeCidrs: ['203.0.113.10/32'],
        tunnelExcludeServerIps: ['203.0.113.10', '203.0.113.10'],
      );
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], ['203.0.113.10/32'],
          reason: 'повторный адрес — тот же интерфейс, а не другой');
    });

    test('битый адрес отбрасывается, а не валит конфиг', () {
      const o = TunOptions(
        tunnelExcludeServerIps: ['not-an-ip', '203.0.113.10'],
      );
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], ['203.0.113.10/32'],
          reason: 'одна битая строка в route_exclude_address валит весь '
              'конфиг sing-box — туннель не поднялся бы вовсе');
    });

    test('fromSettings проносит список до конфига', () {
      final s = AppSettings.defaults
          .copyWith(captureMode: CaptureMode.tun, tunExcludeCidrs: []);
      final o = TunOptions.fromSettings(s,
          tunnelExcludeServerIps: const ['203.0.113.10']);
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], ['203.0.113.10/32']);
    });
  });

  group('kill switch', () {
    test('живой конфиг и заглушка дают ОДИНАКОВЫЙ TUN-инбаунд', () {
      // Заглушка kill switch обязана совпасть с живым интерфейсом поле в
      // поле — разойдись новый список хоть на адрес, `VpnService` пересоздаст
      // интерфейс, и на этот миг трафик пойдёт мимо VPN: ровно то окно,
      // ради закрытия которого заглушка существует.
      const o = TunOptions(
        excludeCidrs: ['10.9.0.0/24'],
        tunnelExcludeServerIps: ['203.0.113.10', '198.51.100.7'],
      );
      final live = tunInbound(buildLive(o));
      final hole = tunInbound(
          SingboxConfigBuilder(options: o.asBlackhole()).buildMap(split));
      expect(hole, live);
    });
  });

  group('охват (TunnelExcludeScope)', () {
    final allKnown = ['198.51.100.7', '203.0.113.10'];
    final sessionHosts = {
      'a.example': ['203.0.113.10', '198.51.100.7'],
      'b.example': ['198.51.100.7'],
    };

    test('allKnown отдаёт снимок «мимо туннеля» как есть', () {
      expect(
          WindowsEngine.tunnelExcludeIpsFor(
              TunnelExcludeScope.allKnown, allKnown, sessionHosts),
          same(allKnown),
          reason: 'тот же список, что и в serverIps: исключения меняются '
              'только вместе с ним, то есть не добавляют НОВЫХ поводов '
              'пересоздать туннель');
    });

    test('activeOnly кладёт только адреса текущей сессии — отсортированно', () {
      expect(
          WindowsEngine.tunnelExcludeIpsFor(
              TunnelExcludeScope.activeOnly, allKnown, sessionHosts),
          ['198.51.100.7', '203.0.113.10']);
      // И не зависит от порядка карты резолва.
      final reversed = {
        'b.example': ['198.51.100.7'],
        'a.example': ['198.51.100.7', '203.0.113.10'],
      };
      expect(
          WindowsEngine.tunnelExcludeIpsFor(
              TunnelExcludeScope.activeOnly, allKnown, reversed),
          ['198.51.100.7', '203.0.113.10']);
    });

    test('off отдаёт пустой список — прежнее поведение', () {
      expect(
          WindowsEngine.tunnelExcludeIpsFor(
              TunnelExcludeScope.off, allKnown, sessionHosts),
          isEmpty);
    });
  });

  group('хост панели', () {
    late Directory tmp;

    setUp(() {
      // Резолв читает кэш адресов с диска — в боевой %APPDATA% тесту нельзя.
      tmp = Directory.systemTemp.createTempSync('sg_tun_excl_');
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('адрес хоста панели в исключения НЕ попадает', () async {
      // Вывести панель из туннеля нельзя: у пользователя с заблокированной
      // панелью страница подписки перестала бы открываться ровно при
      // включённом VPN. Источник исключений — ТОЛЬКО объекты VpnServer
      // (tunnelBypassIps), а knownServerDomains (куда AppState подмешивает
      // хост панели) в них не участвует. Этот тест — страж границы.
      final e = _FakeEngine()
        ..fallbackServers = [_server('198.51.100.7', 'b')]
        ..knownServerDomains = ['panel.example', 'a.example'];
      final s = AppSettings.defaults
          .copyWith(captureMode: CaptureMode.tun, seamlessServerSwitch: true);
      final ips = await e.tunnelBypassIps({
        '203.0.113.10': ['203.0.113.10'],
      }, s);
      final exclude = WindowsEngine.tunnelExcludeIpsFor(
          TunnelExcludeScope.allKnown, ips, const {});
      expect(exclude, ['198.51.100.7', '203.0.113.10'],
          reason: 'ровно адреса серверов и ничего от панели: '
              'panel.example никто не резолвил и резолвить не должен');
    });
  });

  group('конфиг с серверами в route_exclude_address', () {
    test('домены инфраструктуры в исключения интерфейса не просачиваются', () {
      const o = TunOptions(
        serverDomains: ['panel.example'],
        tunnelExcludeServerIps: ['203.0.113.10'],
      );
      final inbound = tunInbound(buildLive(o));
      expect(inbound['route_exclude_address'], ['203.0.113.10/32'],
          reason: 'serverDomains живут в DNS-правилах, а не в интерфейсе');
    });
  });

  group('Универсальные правила по имени процесса и дочерние/версионные бинари', () {
    test(
        'правила byName для любой программы порождают regex на каталог <stem>/.<stem> и версионные .exe.old.<хэш>',
        () {
      const splitCfg = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [
          AppRule(
            r'C:\Users\User\AppData\Local\Programs\antigravity\Antigravity.exe',
            byName: true,
            action: AppAction.tunnel,
          ),
          AppRule(
            r'C:\Users\User\.gemini\bin\agy.exe.old.16d5df81',
            byName: true,
            action: AppAction.tunnel,
          ),
          AppRule(
            r'C:\Users\User\AppData\Local\Programs\cursor\Cursor.exe',
            byName: true,
            action: AppAction.tunnel,
          ),
        ],
      );
      final cfg = SingboxConfigBuilder(options: const TunOptions())
          .buildMap(splitCfg);
      final routeRules =
          ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();
      final regexRule = routeRules.firstWhere(
        (r) =>
            r['outbound'] == 'proxy' && r['process_path_regex'] is List,
      );
      final regexes =
          (regexRule['process_path_regex'] as List).cast<String>();
      expect(
        regexes,
        contains(r'(?i)[\\/]\.?antigravity[\\/].*\.exe(\.old\.[0-9a-z_-]+)?$'),
      );
      expect(
        regexes,
        contains(r'(?i)[\\/]\.?cursor[\\/].*\.exe(\.old\.[0-9a-z_-]+)?$'),
      );
      expect(
          regexes, contains(r'(?i)[\\/]agy\.exe(\.old\.[0-9a-z_-]+)?$'));
    });

    test(
        'KillSwitchPlan материализует language_server.exe и свежий agy.exe.old.<хэш>',
        () {
      const plan = KillSwitchPlan(
        allowServerIps: {},
        allowOwnBinaries: true,
        allowLoopback: true,
        allowLan: true,
        blockedAppPaths: [],
        blockedAppNames: ['Antigravity.exe', 'agy.exe.old.16d5df81'],
        blockAll: false,
      );
      final materialized = plan.withMaterializedAppPaths(const [
        RunningProcess(
          101,
          'language_server.exe',
          r'C:\Users\User\AppData\Local\Programs\antigravity\resources\bin\language_server.exe',
        ),
        RunningProcess(
          102,
          'agy.exe.old.b01ba04f',
          r'C:\Users\User\.gemini\bin\agy.exe.old.b01ba04f',
        ),
      ]);
      expect(
        materialized.blockedAppPaths,
        containsAll([
          r'C:\Users\User\AppData\Local\Programs\antigravity\resources\bin\language_server.exe',
          r'C:\Users\User\.gemini\bin\agy.exe.old.b01ba04f',
        ]),
      );
    });
  });

  group('Динамическое сохранение активных прямых UDP-потоков на старте TUN', () {
    test(
        'в режиме onlySelected активные UDP-потоки dota2.exe добавляются в route_exclude_address, а туннельные и QUIC игнорируются',
        () {
      const splitCfg = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [
          AppRule(
            r'C:\Telegram Desktop\Telegram.exe',
            byName: false,
            action: AppAction.tunnel,
          ),
          AppRule(
            r'C:\Users\User\AppData\Local\Programs\antigravity\Antigravity.exe',
            byName: true,
            action: AppAction.tunnel,
          ),
        ],
      );
      final rawJson = SingboxConfigBuilder(options: const TunOptions())
          .buildJson(splitCfg);
      final sanitized = TunHelper.sanitizeElevatedConfig(rawJson);

      final updatedJson = TunHelper.injectActiveDirectUdpExcludes(
        sanitized,
        const [
          // Активный матч Dota 2 (основной и резервный релеи Valve SDR) -> должны быть исключены
          ActiveUdpEndpoint(
            remoteIp: '155.133.252.53',
            remotePort: 27033,
            localPort: 50673,
            appIdPath:
                r'\device\harddiskvolume3\program files (x86)\steam\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe',
          ),
          ActiveUdpEndpoint(
            remoteIp: '162.254.198.103',
            remotePort: 27036,
            localPort: 50691,
            appIdPath:
                r'\device\harddiskvolume3\program files (x86)\steam\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe',
          ),
          // Туннельное приложение Telegram -> НЕ должно быть исключено
          ActiveUdpEndpoint(
            remoteIp: '149.154.167.91',
            remotePort: 1400,
            localPort: 55000,
            appIdPath: r'\device\harddiskvolume1\telegram desktop\telegram.exe',
          ),
          // QUIC (UDP:443) от прямого браузера -> НЕ должен быть исключён
          ActiveUdpEndpoint(
            remoteIp: '104.16.132.229',
            remotePort: 443,
            localPort: 55111,
            appIdPath:
                r'\device\harddiskvolume1\program files\mozilla firefox\firefox.exe',
          ),
          // Системный процесс svchost -> НЕ должен быть исключён
          ActiveUdpEndpoint(
            remoteIp: '20.190.159.4',
            remotePort: 3544,
            localPort: 55222,
            appIdPath: r'\device\harddiskvolume1\windows\system32\svchost.exe',
          ),
        ],
      );

      final updated = jsonDecode(updatedJson) as Map<String, dynamic>;
      final inbound = tunInbound(updated);
      expect(
        inbound['route_exclude_address'],
        ['155.133.252.53/32', '162.254.198.103/32'],
      );
    });
  });
}

VpnServer _server(String address, String name) => VpnServer(
      protocol: 'vless',
      remark: name,
      // Адрес литеральный (TEST-NET): резолв не имеет права ходить в сеть.
      address: address,
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@$address:443#$name',
    );

/// Минимальный движок: нужен только доступ к [VpnEngineBase.tunnelBypassIps].
class _FakeEngine extends VpnEngineBase {
  @override
  Future<void> startSession() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  Future<void> platformCleanup() async {}
}
