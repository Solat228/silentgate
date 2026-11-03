import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_service_presets.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/engine/windows/kill_switch_wfp.dart';
import 'package:silentgate/engine/windows/process_list_windows.dart';
import 'package:silentgate/engine/windows/tun/kill_switch_plan_file.dart';
import 'package:silentgate/engine/windows/tun/singbox_router_windows.dart';
import 'package:silentgate/engine/windows/tun/tun_helper.dart';
import 'package:silentgate/engine/windows/tun/tun_helper_state.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';

void main() {
  List<Map<String, dynamic>> routeRules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  group('TunHelper: быстрый старт < 2 с с Kill Switch и правилом по имени', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_ks_fast_open_');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('seedFromAppliedPlan + syncWatchedMatches сохраняют пути до первого тика и при reloadCore', () async {
      const watched = {'telegram.exe'};
      const tgPath = r'C:\Users\User\AppData\Roaming\Telegram Desktop\Telegram.exe';
      const applied = KillSwitchPlan(
        allowServerIps: {'203.0.113.10'},
        allowOwnBinaries: true,
        allowLoopback: true,
        allowLan: true,
        blockedAppPaths: [tgPath],
        blockedAppNames: ['Telegram.exe'],
        blockAll: false,
      );

      final matched = <String, RunningProcess>{};
      TunHelper.seedFromAppliedPlan(matched, watched, applied);
      expect(matched, isNotEmpty,
          reason: 'иначе на быстром SSD адаптер открывается за < 2 с до первого '
              'опроса процессов, и план для engageTunnelFilters выходит пустым');

      await KillSwitchPlanFile.write(
        tmp,
        enabled: true,
        sessionToken: 'tok-1',
        serverIps: const {'203.0.113.10'},
        blockAll: false,
        blockedAppPaths: const [],
        blockedAppNames: const ['Telegram.exe'],
        allowedAppPaths: const [],
        allowLan: true,
      );
      final rawPlan =
          KillSwitchPlanFile.read(tmp, tunnelLuid: 42, expectToken: 'tok-1');
      expect(rawPlan, isNotNull);
      // До материализации имён план пуст — ровно то, на чём ломался старт за < 2 с!
      expect(rawPlan!.isEmpty, isTrue);

      final tunnelPlan = rawPlan.withMaterializedAppPaths(matched.values);
      expect(tunnelPlan.isEmpty, isFalse);
      expect(tunnelPlan.blockedAppPaths, contains(tgPath));

      // После reloadCore процесс мог на миг пропасть из снимка, но уже известный
      // путь остаётся в накопителе (если имя всё ещё в списке наблюдения).
      TunHelper.syncWatchedMatches(matched, watched, const []);
      expect(matched, hasLength(1));

      // Снятие имени из правил вычищает его из накопителя.
      TunHelper.syncWatchedMatches(matched, const {}, const []);
      expect(matched, isEmpty);
    });
  });

  group('TunHelperState IPC и быстрый отказ без холостого перебора 9 стеков', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_tun_helper_state_');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('prepareLaunch выдаёт новый токен, сбрасывает старый снимок и сверяет launchId', () {
      final firstId = TunHelperState.prepareLaunch(tmp);
      expect(firstId, isNotEmpty);
      expect(TunHelperState.readLaunchId(tmp), firstId);

      TunHelperState.write(
        tmp,
        launchId: firstId,
        phase: TunHelperPhase.exited,
        reason: TunHelperExitReason.killSwitchTunnelFailed,
      );
      final snap = TunHelperState.read(tmp, firstId);
      expect(snap, isNotNull);
      expect(snap!.helperExited, isTrue);
      expect(snap.reason, TunHelperExitReason.killSwitchTunnelFailed);
      expect(snap.reason.isNonTunParameterFailure, isTrue);
      expect(TunHelperState.read(tmp, 'other-launch-id'), isNull);

      final secondId = TunHelperState.prepareLaunch(tmp);
      expect(secondId, isNot(firstId));
      expect(TunHelperState.read(tmp, secondId), isNull);
    });

    test('isNonTunParameterFailure отличает отказ Kill Switch от таймаута адаптера', () {
      expect(
        SingboxRouterWindows.isNonTunParameterFailure(
          TunStartException('kill switch fail', nonTunParameterFailure: true),
        ),
        isTrue,
      );
      expect(
        SingboxRouterWindows.isNonTunParameterFailure(
          TunStartException('Туннель не поднялся за 15 с.'),
        ),
        isFalse,
      );
    });
  });

  group('YouTube и QUIC (UDP:443) в режиме TUN', () {
    test('при доменных правилах запрет UDP:443 не зависит от сниффинга SNI постквантового QUIC', () {
      final cfg = const SingboxConfigBuilder(
        options: TunOptions(serverIps: ['203.0.113.10']),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('youtube.com', action: AppAction.tunnel),
          SiteRule('googlevideo.com', action: AppAction.tunnel),
        ],
      ));
      final quicReject = routeRules(cfg).firstWhere((r) =>
          r['network'] == 'udp' &&
          (r['port'] as List?)?.contains(443) == true &&
          r['action'] == 'reject');
      expect(quicReject.containsKey('domain_suffix'), isFalse,
          reason: 'многопакетный X25519MLKEM768 QUIC Initial не даёт sing-box '
              'вынуть SNI, и domain_suffix на UDP:443 молча пропускает пакет в ТСПУ');
    });

    test('blockTunnelQuic закрывает чёрную дыру SOCKS5 UDP:443 в SplitMode.all и exceptSelected, не трогая direct', () {
      final allCfg = const SingboxConfigBuilder(
        options: TunOptions(
          serverIps: ['203.0.113.10'],
          blockTunnelQuic: true,
        ),
      ).buildMap(const SplitTunnelConfig(mode: SplitMode.all));
      final allRules = routeRules(allCfg);
      final lanIdx = allRules.indexWhere(
          (r) => r['ip_is_private'] == true && r['outbound'] == 'direct');
      final quicIdx = allRules.indexWhere((r) =>
          r['network'] == 'udp' &&
          (r['port'] as List?)?.contains(443) == true &&
          r['action'] == 'reject');
      expect(lanIdx, isNonNegative);
      expect(quicIdx, greaterThan(lanIdx));

      final exceptCfg = const SingboxConfigBuilder(
        options: TunOptions(
          serverIps: ['203.0.113.10'],
          blockTunnelQuic: true,
        ),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.exceptSelected,
        apps: [AppRule('game.exe', byName: true, action: AppAction.direct)],
      ));
      final exceptRules = routeRules(exceptCfg);
      final directAppIdx = exceptRules.indexWhere((r) =>
          (r['process_name'] as List?)?.contains('game.exe') == true &&
          r['outbound'] == 'direct');
      final exceptQuicIdx = exceptRules.indexWhere((r) =>
          r['network'] == 'udp' &&
          (r['port'] as List?)?.contains(443) == true &&
          r['action'] == 'reject');
      expect(directAppIdx, isNonNegative);
      expect(exceptQuicIdx, greaterThan(directAppIdx),
          reason: 'приложение «Прямо» в exceptSelected обязано сохранить HTTP/3');
    });

    test('blockTunnelQuic в onlySelected без сайтов ограничивается только туннелируемыми приложениями', () {
      final onlyCfg = const SingboxConfigBuilder(
        options: TunOptions(
          serverIps: ['203.0.113.10'],
          blockTunnelQuic: true,
        ),
      ).buildMap(const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [AppRule('chrome.exe', byName: true, action: AppAction.tunnel)],
      ));
      final r = routeRules(onlyCfg);
      final rejects = r
          .where((x) =>
              x['network'] == 'udp' &&
              (x['port'] as List?)?.contains(443) == true &&
              x['action'] == 'reject')
          .toList();
      expect(rejects, hasLength(1));
      expect((rejects.single['process_name'] as List), ['chrome.exe'],
          reason: 'неотмеченные приложения идут в final: direct и сохраняют HTTP/3');
    });
  });

  group('Панельные профили «Авто …»: inbound нормализация и полные адреса серверов', () {
    test('normalizeOverridePorts включает udp и sniffing на существующем socks-inbound панели', () {
      final raw = jsonEncode({
        'inbounds': [
          {
            'tag': 'socks',
            'port': 2080,
            'listen': '127.0.0.1',
            'protocol': 'socks',
            'settings': {'auth': 'noauth'},
          },
        ],
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
      });
      final norm = jsonDecode(
        normalizeOverridePorts(raw, socksPort: 10808, httpPort: 10809).json,
      ) as Map<String, dynamic>;
      final socks = (norm['inbounds'] as List)
          .cast<Map>()
          .firstWhere((i) => i['protocol'] == 'socks');
      expect(socks['port'], 10808);
      expect((socks['settings'] as Map)['udp'], isTrue);
      expect((socks['sniffing'] as Map)['enabled'], isTrue);
    });

    test('extractFullConfigHosts собирает все внешние узлы балансировщика и пропускает петлю/служебные', () {
      final raw = jsonEncode({
        'outbounds': [
          {
            'tag': 'proxy-1',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {'address': '198.51.100.11', 'port': 443},
              ],
            },
          },
          {
            'tag': 'proxy-2',
            'protocol': 'trojan',
            'settings': {
              'servers': [
                {'address': 'edge-de.example.net', 'port': 443},
              ],
            },
          },
          {
            'tag': 'direct',
            'protocol': 'freedom',
            'settings': {'address': '127.0.0.1'},
          },
          {
            'tag': 'block',
            'protocol': 'blackhole',
          },
        ],
      });
      expect(
        extractFullConfigHosts(raw),
        ['198.51.100.11', 'edge-de.example.net'],
      );
    });
  });

  group('Пресет YouTube и смена способа захвата на живом соединении', () {
    test('пресет YouTube покрывает поддомены аватарок и плеера', () {
      final yt = SplitServicePresets.presetFor(ProbeService.youtube);
      expect(
        yt.domains,
        containsAll([
          'youtube.com',
          'googlevideo.com',
          'ytimg.com',
          'yt3.googleusercontent.com',
          'jnn-pa.googleapis.com',
          'youtubeembeddedplayer.googleapis.com',
          'youtube-nocookie.com',
        ]),
      );
    });

    test('captureChanged ловит переключение Системный прокси <-> TUN и смешанный режим', () {
      const proxy = AppSettings(captureMode: CaptureMode.systemProxy);
      const tun = AppSettings(captureMode: CaptureMode.tun);
      const mixed =
          AppSettings(captureMode: CaptureMode.tun, alsoSetSystemProxy: true);

      expect(proxy.captureChanged(tun), isTrue);
      expect(tun.captureChanged(proxy), isTrue);
      expect(tun.captureChanged(mixed), isTrue);
      expect(tun.captureChanged(tun.copyWith(tunMtu: 1400)), isFalse);
    });
  });
}
