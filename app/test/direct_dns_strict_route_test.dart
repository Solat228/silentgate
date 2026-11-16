import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

class _RecordingTunRouter implements TunRouter {
  final List<String> events = [];
  int starts = 0;
  TunOptions? lastOptions;

  @override
  Future<void> start(
    SplitTunnelConfig split, {
    required int xraySocksPort,
    required TunOptions options,
    void Function(String message)? onProgress,
    bool Function()? abort,
    List<Map<String, dynamic>> exitOutbounds = const [],
    String xraySocksUser = '',
    String xraySocksPassword = '',
    List<String> apiExitServerKeys = const [],
    List<String> apiOnlyExitKeys = const [],
    String apiToken = '',
  }) async {
    starts++;
    lastOptions = options;
    events.add('start');
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }
}

final _srvA = VpnServer(
  protocol: 'vless',
  remark: 'node-a',
  address: '203.0.113.10',
  port: 443,
  id: '00000000-0000-0000-0000-000000000000',
  rawLink: 'vless://00000000-0000-0000-0000-000000000000@203.0.113.10:443#a',
);

final _srvB = VpnServer(
  protocol: 'vless',
  remark: 'node-b',
  address: '198.51.100.7',
  port: 443,
  id: '00000000-0000-0000-0000-000000000000',
  rawLink: 'vless://00000000-0000-0000-0000-000000000000@198.51.100.7:443#b',
);

void main() {
  group('directFallbackSafeWithStrictRoute', () {
    test('отклоняет локальные, приватные, CGNAT и ULA-адреса', () {
      for (final ip in [
        '192.168.1.1',
        '192.168.0.254',
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.1',
        '100.64.0.1',
        '100.127.255.1',
        '127.0.0.1',
        '169.254.1.1',
        '::1',
        'fe80::1',
        'fec0:0:0:ffff::1',
        'fd00::1',
        'fc00::1',
        '',
        'not-an-ip',
      ]) {
        expect(
          WindowsEngine.directFallbackSafeWithStrictRoute(ip),
          isFalse,
          reason: '$ip в локальной подсети режется WFP strict_route у silentgate.exe',
        );
      }
    });

    test('разрешает публичные/маршрутизируемые через default route адреса', () {
      for (final ip in [
        '192.0.2.1',
        '198.51.100.53',
        '203.0.113.53',
        '1.1.1.1',
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '2001:db8::53',
      ]) {
        expect(
          WindowsEngine.directFallbackSafeWithStrictRoute(ip),
          isTrue,
          reason: '$ip заходит в silentgate-tun и выпускается sing-box наружу',
        );
      }
    });
  });

  group('Фильтрация системного DNS и прямой запас в TUN', () {
    late Directory tmp;
    late _RecordingTunRouter router;
    late WindowsEngine engine;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_direct_dns_strict_');
      AppPaths.overrideRoot(tmp);
      router = _RecordingTunRouter();
      engine = WindowsEngine(tunRouter: router, recoverSystemProxy: false);
      engine.dnsReachableForTest = (_) async => true;
      engine.tunAliveForTest = () async => true;
    });

    tearDown(() async {
      await engine.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('fec0: и fe80: отбрасываются до сетевой пробы', () async {
      final probed = <String>[];
      engine.adapterDnsForTest = () => [
            'fec0:0:0:ffff::1',
            'fe80::1',
            '192.0.2.53',
          ];
      engine.dnsReachableForTest = (ip) async {
        probed.add(ip);
        return true;
      };

      final got = await engine.systemDnsServerForTest(allowIpv6: true);
      expect(got, '192.0.2.53');
      expect(probed, ['192.0.2.53']);
      expect(engine.secondaryDirectDns, isNull);
    });

    test('при allowIpv6: false IPv6-резолверы не попадают ни в основной, ни в запасной',
        () async {
      engine.adapterDnsForTest = () => ['192.168.1.1', 'fd00::1', '2001:db8::1'];

      final first = await engine.systemDnsServerForTest(allowIpv6: true);
      expect(first, '192.168.1.1');
      expect(engine.secondaryDirectDns, 'fd00::1');

      // Повторный вызов без IPv6 обязан вычистить и закэшированный IPv6-запас.
      final second = await engine.systemDnsServerForTest(allowIpv6: false);
      expect(second, '192.168.1.1');
      expect(engine.secondaryDirectDns, isNull);
    });

    test('strictRoute + LAN DNS: прямой форвардер НЕ перехватывает dns-local',
        () async {
      engine.adapterDnsForTest = () => ['192.168.1.1', '192.168.1.2'];
      final s = AppSettings.defaults.copyWith(
        captureMode: CaptureMode.tun,
        tunStrictRoute: true,
        killSwitch: false,
        noRealIp: false,
        tunWatchdogSeconds: 0,
        tunnelDnsForAll: false,
      );

      final ok = await engine.raiseTun(
        options: ConnectionOptions(settings: s),
        servers: [_srvA],
        apiKeys: const [],
        aborted: () => false,
        gen: 1,
      );

      expect(ok, isTrue);
      expect(router.lastOptions, isNotNull);
      expect(router.lastOptions!.directDnsUpstream, '192.168.1.1');
      expect(
        router.lastOptions!.directFallbackDnsPort,
        0,
        reason: 'под strict_route пакеты silentgate.exe к 192.168.1.1 режутся WFP; '
            'опрашивать роутер напрямую должен сам sing-box.exe',
      );
    });

    test('два публичных DNS + seamlessServerSwitch: порт форвардера сохраняется и TUN не сносится',
        () async {
      engine.adapterDnsForTest = () => ['198.51.100.53', '203.0.113.53'];
      engine.fallbackServers = [_srvA, _srvB];
      final s = AppSettings.defaults.copyWith(
        captureMode: CaptureMode.tun,
        tunStrictRoute: true,
        seamlessServerSwitch: true,
        killSwitch: false,
        noRealIp: false,
        tunWatchdogSeconds: 0,
        tunnelDnsForAll: false,
      );

      expect(
        await engine.raiseTun(
          options: ConnectionOptions(settings: s),
          servers: [_srvA],
          apiKeys: const [],
          aborted: () => false,
          gen: 1,
        ),
        isTrue,
      );
      final firstPort = router.lastOptions!.directFallbackDnsPort;
      expect(firstPort, greaterThan(0));
      expect(router.starts, 1);
      router.events.clear();

      expect(
        await engine.raiseTun(
          options: ConnectionOptions(settings: s),
          servers: [_srvB],
          apiKeys: const [],
          aborted: () => false,
          gen: 2,
        ),
        isTrue,
      );

      expect(
        router.events,
        isEmpty,
        reason: 'раньше перепривязка порта 0 меняла config.dns.servers[1].server_port '
            'и пересоздавала Wintun на каждом переключении сервера',
      );
      expect(router.starts, 1);
    });
  });
}

