import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/dpi/dpi_bypass_lists.dart';
import 'package:silentgate/core/dpi/dpi_proxy_config_injector.dart';
import 'package:silentgate/core/dpi/dpi_strategy.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/net/api_secrets.dart';
import 'package:silentgate/core/net/api_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/network_loss_watch.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_router_config_builder.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/xray_exit_bridge.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/api_handlers.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';

class _TestEngine extends VpnEngine implements StandaloneApiPortsEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final VpnStatus _status = const VpnStatus.disconnected();
  int standaloneEnsureCalls = 0;
  bool _standaloneRunning = false;

  @override
  bool get standaloneApiPortsRunning => _standaloneRunning;

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}
  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;
  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();
  @override
  Stream<String> get blockedHostEvents => const Stream.empty();
  @override
  Stream<EngineNotice> get notices => const Stream.empty();
  @override
  VpnStatus get status => _status;

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}
  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> syncStandaloneApiPorts({
    required AppSettings settings,
    required Map<String, VpnServer> exitServers,
    required List<String> serverKeys,
    required List<String> autoPoolKeys,
  }) async {
    standaloneEnsureCalls++;
    _standaloneRunning = settings.apiEnabled &&
        settings.apiToken.isNotEmpty &&
        settings.apiKeepAliveWhenDisconnected;
  }

  @override
  Future<void> stopStandaloneApiPorts() async {
    _standaloneRunning = false;
  }

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}

/// Синтетический TLS 1.2 ClientHello с SNI `www.youtube.com` для проверки парсера и OOB-резки.
Uint8List _buildClientHelloWithSni(String host) {
  final hostBytes = ascii.encode(host);
  // server_name extension (0x0000)
  final sniListLen = 1 + 2 + hostBytes.length;
  final extPayloadLen = 2 + sniListLen;
  final ext = BytesBuilder()
    ..add([0x00, 0x00]) // type = server_name
    ..add([(extPayloadLen >> 8) & 0xFF, extPayloadLen & 0xFF])
    ..add([(sniListLen >> 8) & 0xFF, sniListLen & 0xFF])
    ..add([0x00]) // host_name type
    ..add([(hostBytes.length >> 8) & 0xFF, hostBytes.length & 0xFF])
    ..add(hostBytes);
  final extBytes = ext.toBytes();

  final hsBody = BytesBuilder()
    ..add([0x03, 0x03]) // client_version TLS 1.2
    ..add(List<int>.filled(32, 0x11)) // random
    ..add([0x00]) // session_id len = 0
    ..add([0x00, 0x02, 0x13, 0x01]) // cipher_suites (TLS_AES_128_GCM_SHA256)
    ..add([0x01, 0x00]) // compression_methods
    ..add([(extBytes.length >> 8) & 0xFF, extBytes.length & 0xFF])
    ..add(extBytes);
  final hsBodyBytes = hsBody.toBytes();

  final hs = BytesBuilder()
    ..add([0x01]) // HandshakeType = client_hello
    ..add([
      (hsBodyBytes.length >> 16) & 0xFF,
      (hsBodyBytes.length >> 8) & 0xFF,
      hsBodyBytes.length & 0xFF,
    ])
    ..add(hsBodyBytes);
  final hsBytes = hs.toBytes();

  final rec = BytesBuilder()
    ..add([0x16, 0x03, 0x01]) // TLS Handshake record
    ..add([(hsBytes.length >> 8) & 0xFF, hsBytes.length & 0xFF])
    ..add(hsBytes);
  return rec.toBytes();
}

void main() {
  group('1.18.7 Deliverable 1 — Импорт локальных файлов и списков в отдельную подписку', () {
    late Directory tmp;
    late AppState state;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('sg_1_18_7_import_');
      AppPaths.overrideRoot(tmp);
      state = AppState(engine: _TestEngine());
      await state.init();
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('импорт .txt по пути файла создаёт отдельную локальную подписку со всеми локациями и перечитывается при refresh', () async {
      final titleB64 = base64.encode(utf8.encode('Silentgate Local'));
      final file = File('${tmp.path}${Platform.pathSeparator}Silentgate.txt');
      file.writeAsStringSync([
        '#profile-title: base64:$titleB64',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.10:443?type=tcp&security=none#NL%201',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.11:443?type=tcp&security=none#DE%202',
        'hy2://pass@198.51.100.12:8443?sni=example.com#US%203',
      ].join('\r\n'));

      await state.importSource('"${file.path}"');

      expect(state.error, isNull);
      expect(state.subscriptions, hasLength(1));
      expect(state.subscriptions.single.isLocal, isTrue);
      expect(state.subscriptions.single.info.title, 'Silentgate Local');
      expect(state.servers, hasLength(3));
      expect(state.servers.every((s) => !state.isPinned(s)), isTrue,
          reason: 'локальная подписка не должна засорять общие закреплённые серверы');

      // Добавим 4-й сервер в тот же файл и вызовем refreshSubscription
      file.writeAsStringSync([
        '#profile-title: base64:$titleB64',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.10:443?type=tcp&security=none#NL%201',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.11:443?type=tcp&security=none#DE%202',
        'hy2://pass@198.51.100.12:8443?sni=example.com#US%203',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.13:443?type=tcp&security=none#FI%204',
      ].join('\n'));

      final refreshed = await state.refreshSubscription();
      expect(refreshed, isTrue);
      expect(state.servers, hasLength(4));
    });

    test('многострочный список и Base64-пакет не затирают друг друга, а создают отдельные локальные подписки', () async {
      await state.importSource([
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.21:443?type=tcp&security=none#PackA-1',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.22:443?type=tcp&security=none#PackA-2',
      ].join('\n'));

      final b64Pack = base64.encode(utf8.encode([
        '#profile-title: Второй пакет',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.31:443?type=tcp&security=none#PackB-1',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.32:443?type=tcp&security=none#PackB-2',
      ].join('\n')));
      await state.importSource(b64Pack);

      expect(state.subscriptions, hasLength(2));
      expect(state.subscriptions.last.info.title, 'Второй пакет');
      expect(state.allSubscriptionServers(), hasLength(4));
    });
  });

  group('1.18.7 Deliverable 3 — Защита NetworkLossWatch от ложных дропов ТСПУ', () {
    test('RU-мишени идут первыми, а noteFalseAlarm переводит в кулдаун и выключает сторож после лимита', () async {
      expect(NetworkLossWatch.defaultTargets.first, startsWith('http://77.88.'));

      var up = true;
      var losses = 0;
      final watch = NetworkLossWatch(
        every: const Duration(milliseconds: 15),
        missesToAct: 2,
        maxFalseAlarms: 2,
        cooldownAfterFalseAlarm: const Duration(milliseconds: 60),
        check: () async => up,
      );
      addTearDown(watch.stop);

      watch.start(onLoss: () => losses++);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(watch.seenUp, isTrue);

      up = false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(losses, 1);

      // Первая ложная тревога: туннель жив -> уходит в кулдаун, но ещё не остановлен
      expect(watch.noteFalseAlarm(), isFalse);
      expect(watch.isRunning, isTrue);

      // Вторая ложная тревога: частый прямой сторож отключается до конца сессии
      expect(watch.noteFalseAlarm(), isTrue);
      expect(watch.isRunning, isFalse);
    });
  });

  group('1.18.7 Deliverable 4 — Обход блокировок (Zapret / DPI) без петель и DNS-дедлока', () {
    test('DpiDesyncConfig режет TLS ClientHello ровно внутри SNI и вставляет MSG_OOB байт с чистым откатом', () {
      final hello = _buildClientHelloWithSni('www.youtube.com');
      final cfg = DpiDesyncConfig.fromPreset(DpiStrategyPreset.tlsrecSniOob);
      final segments = cfg.buildSegments(hello, socketSupportsOob: true);

      expect(segments.length, greaterThanOrEqualTo(2));
      expect(segments.any((s) => s.isOob), isTrue,
          reason: 'пресет tlsrecSniOob обязан формировать сегмент с срочным байтом MSG_OOB');

      // При откате без OOB склейка payload всех TLS-рекордов (каждый с 5-байтовым заголовком 0x16 0x03 ...)
      // обязана собрать точный исходный Handshake с неповреждённым именем хоста!
      final reassembledPayload = BytesBuilder();
      for (final seg in segments) {
        final clean = seg.bytesWithoutOob();
        expect(clean[0], 0x16, reason: 'каждый фрагмент tlsrecSniOob — валидный TLS Handshake record');
        final recLen = (clean[3] << 8) | clean[4];
        expect(clean.length, 5 + recLen);
        reassembledPayload.add(Uint8List.sublistView(clean, 5));
      }
      expect(reassembledPayload.toBytes(), hello.sublist(5));
      expect(ascii.decode(reassembledPayload.toBytes(), allowInvalid: true), contains('www.youtube.com'));
    });

    test('SingboxConfigBuilder не создаёт мёртвый DNS-сервер dns-exit для псевдо-выходов DPI', () {
      final dpiDirectTag = exitTagFor(kDpiBypassDirectKey);
      final dpiFallbackTag = exitTagFor(kDpiBypassFallbackKey);
      final builder = SingboxConfigBuilder(
        options: const TunOptions(dpiDnsViaVpn: true),
        exitOutbounds: [
          {
            'type': 'socks',
            'tag': dpiDirectTag,
            'server': '127.0.0.1',
            'server_port': 19001,
          },
          {
            'type': 'socks',
            'tag': dpiFallbackTag,
            'server': '127.0.0.1',
            'server_port': 19002,
          },
        ],
      );
      final split = const SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('youtube.com', action: AppAction.tunnel, serverKey: kDpiBypassFallbackKey),
          SiteRule('discord.com', action: AppAction.tunnel, serverKey: kDpiBypassDirectKey),
        ],
      );
      final cfg = builder.buildMap(split);
      final dnsServers = (cfg['dns']['servers'] as List).cast<Map<String, dynamic>>();
      expect(
        dnsServers.any((s) => s['detour'] == dpiDirectTag || s['detour'] == dpiFallbackTag),
        isFalse,
        reason: 'TCP 1.1.1.1:53 через LocalDpiBypassProxy вызывал таймаут резолва при заблокированном 1.1.1.1',
      );
    });

    test('DpiProxyConfigInjector привязывает правила к HTTP-инбаунду, исключая петлю при откате в SOCKS5', () {
      final baseXray = jsonEncode({
        'inbounds': [
          {'port': 10808, 'protocol': 'socks', 'tag': 'socks-in'},
          {'port': 10809, 'protocol': 'http', 'tag': 'http-in'},
        ],
        'outbounds': [
          {'protocol': 'vless', 'tag': 'proxy'},
          {'protocol': 'freedom', 'tag': 'direct'},
        ],
        'routing': {'rules': <Map<String, dynamic>>[]},
      });
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('youtube.com', action: AppAction.tunnel, serverKey: kDpiBypassFallbackKey),
        ],
      );
      final injected = jsonDecode(DpiProxyConfigInjector.inject(
        baseXray,
        singboxCore: false,
        effectiveSplit: split,
        httpPort: 10809,
        fallbackPort: 19102,
      )) as Map<String, dynamic>;

      final rules = (injected['routing']['rules'] as List).cast<Map<String, dynamic>>();
      expect(rules, isNotEmpty);
      expect(rules.first['inboundTag'], ['http-in'],
          reason: 'трафик отката на 10808 (socks-in) не должен повторно попадать в правило DPI');
    });
  });

  group('1.18.7 Deliverable 5 — Прокачанный API автоматизации и реальная валидация ядер', () {
    test('липкие порты (sticky) удерживают номер порта при удалении соседей и поддерживают ручной порт', () {
      final sticky1 = ApiPorts.assignStickyPorts(
        const ['vless://a', 'vless://b', 'vless://c'],
        const {},
      );
      expect(sticky1['vless://a'], 10820);
      expect(sticky1['vless://b'], 10821);
      expect(sticky1['vless://c'], 10822);

      // Удаляем vless://a — у vless://b и vless://c ОБЯЗАНЫ остаться 10821 и 10822!
      final mapAfterRemove = ApiPorts.resolvePortMap(
        const ['vless://b', 'vless://c'],
        assignedPorts: sticky1,
      );
      expect(mapAfterRemove['vless://b'], 10821);
      expect(mapAfterRemove['vless://c'], 10822);

      // Назначаем ручной порт 12500 для vless://b
      final customSticky = {...sticky1, 'vless://b': 12500};
      final mapCustom = ApiPorts.resolvePortMap(
        const ['vless://b', 'vless://c'],
        assignedPorts: customSticky,
      );
      expect(mapCustom['vless://b'], 12500);
      expect(mapCustom['vless://c'], 10822);
    });

    test('injectXrayExitBridges дедуплицирует одинаковые прокси-узлы между несколькими профилями «Авто»', () {
      Map<String, dynamic> sharedNode(String tag, int port) => {
            'protocol': 'vless',
            'tag': tag,
            'settings': {
              'vnext': [
                {
                  'address': '203.0.113.50',
                  'port': port,
                  'users': [
                    {'id': '11111111-2222-3333-4444-555555555555', 'encryption': 'none'}
                  ],
                }
              ],
            },
            'streamSettings': {'network': 'tcp', 'security': 'none'},
          };

      final panel1 = jsonEncode({
        'outbounds': [
          sharedNode('de-1', 443),
          sharedNode('nl-1', 8443),
          {'protocol': 'freedom', 'tag': 'direct'},
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['de-1', 'nl-1'],
              'strategy': {'type': 'leastPing'},
            }
          ],
          'rules': [
            {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'}
          ],
        },
        'burstObservatory': {
          'subjectSelector': ['de-1', 'nl-1'],
          'pingConfig': {'destination': 'https://cp.cloudflare.com/generate_204', 'interval': '1m'},
        },
      });

      final panel2 = jsonEncode({
        'outbounds': [
          sharedNode('de-copy', 443),
          sharedNode('nl-copy', 8443),
          {'protocol': 'freedom', 'tag': 'direct'},
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'yt_auto',
              'selector': ['de-copy', 'nl-copy'],
              'strategy': {'type': 'leastPing'},
            }
          ],
          'rules': [
            {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'yt_auto'}
          ],
        },
      });

      const key1 = 'vless://11111111-2222-3333-4444-555555555555@203.0.113.50:443#Auto1';
      const key2 = 'vless://11111111-2222-3333-4444-555555555555@203.0.113.50:444#Auto2';
      final s1 = VpnServer(
        rawLink: key1,
        protocol: 'vless',
        remark: '⚡ Авто Общий',
        address: '203.0.113.50',
        port: 443,
        id: '11111111-2222-3333-4444-555555555555',
        network: 'tcp',
        security: 'none',
        rawPanelConfig: panel1,
      );
      final s2 = VpnServer(
        rawLink: key2,
        protocol: 'vless',
        remark: '🎬 Авто YouTube',
        address: '203.0.113.50',
        port: 444,
        id: '11111111-2222-3333-4444-555555555555',
        network: 'tcp',
        security: 'none',
        rawPanelConfig: panel2,
      );

      final bridges = assignXrayExitBridgePorts({key1: s1, key2: s2});
      final xrayJson = injectXrayExitBridges(
        null,
        exitServers: {key1: s1, key2: s2},
        bridgePorts: bridges,
      );
      final decoded = jsonDecode(xrayJson) as Map<String, dynamic>;
      final vlessOutbounds = (decoded['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .where((o) => o['protocol'] == 'vless')
          .toList();

      expect(vlessOutbounds, hasLength(2),
          reason: '4 одинаковых узла из двух Авто-профилей обязаны схлопнуться в 2 общих exit-sh-* outbound');
      expect(vlessOutbounds.every((o) => '${o['tag']}'.startsWith('exit-sh-')), isTrue);

      final xrayExe = File('engine/windows/bin/xray.exe');
      if (Platform.isWindows && xrayExe.existsSync()) {
        final dir = Directory.systemTemp.createTempSync('sg_xray_dedup_check_');
        addTearDown(() {
          try {
            dir.deleteSync(recursive: true);
          } catch (_) {}
        });
        final cfgFile = File('${dir.path}${Platform.pathSeparator}xray.json')
          ..writeAsStringSync(xrayJson);
        final res = Process.runSync(xrayExe.path, ['run', '-test', '-config', cfgFile.path]);
        expect(res.exitCode, 0, reason: 'xray run -test failed: ${res.stdout}\n${res.stderr}');
      }
    });

    test('ExitRouterConfigBuilder (Умный Авто 10818 + DNS через выход + режимы пароля) проходит sing-box check', () {
      const keyA = 'vless://11111111-2222-3333-4444-555555555555@203.0.113.10:443#DE';
      const keyB = 'vless://11111111-2222-3333-4444-555555555555@203.0.113.11:443#NL';
      final outbounds = [
        {
          'type': 'vless',
          'tag': exitTagFor(keyA),
          'server': '203.0.113.10',
          'server_port': 443,
          'uuid': '11111111-2222-3333-4444-555555555555',
        },
        {
          'type': 'vless',
          'tag': exitTagFor(keyB),
          'server': '203.0.113.11',
          'server_port': 443,
          'uuid': '11111111-2222-3333-4444-555555555555',
        },
      ];

      for (final mode in ApiProxyAuthMode.values) {
        final json = ExitRouterConfigBuilder(
          serverKeys: const [keyA, keyB],
          token: 'ctrl-secret',
          exitOutbounds: outbounds,
          assignedPorts: const {keyA: 10825, keyB: 10826},
          autoPortEnabled: true,
          autoPoolKeys: const [keyA, keyB],
          authMode: mode,
          customUser: 'myuser',
          customPassword: 'mypassword',
          enableDnsViaExit: true,
          directDnsUpstream: '1.1.1.1',
        ).buildJson();

        final cfg = jsonDecode(json) as Map<String, dynamic>;
        final inbounds = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
        final autoIn = inbounds.firstWhere((i) => i['tag'] == apiAutoInboundTag);
        expect(autoIn['listen_port'], ApiPorts.auto);
        if (mode == ApiProxyAuthMode.none) {
          expect(autoIn.containsKey('users'), isFalse);
        } else if (mode == ApiProxyAuthMode.custom) {
          expect(autoIn['users'], [
            {'username': 'myuser', 'password': 'mypassword'}
          ]);
        } else {
          expect(autoIn['users'], [
            {'username': 'sg', 'password': 'ctrl-secret'}
          ]);
        }

        final sbExe = File('engine/windows/bin/sing-box.exe');
        if (Platform.isWindows && sbExe.existsSync()) {
          final dir = Directory.systemTemp.createTempSync('sg_sb_exit_check_');
          addTearDown(() {
            try {
              dir.deleteSync(recursive: true);
            } catch (_) {}
          });
          final cfgFile = File('${dir.path}${Platform.pathSeparator}sb.json')
            ..writeAsStringSync(json);
          final res = Process.runSync(sbExe.path, ['check', '-c', cfgFile.path]);
          expect(res.exitCode, 0,
              reason: 'sing-box check failed for $mode: ${res.stdout}\n${res.stderr}');
        }
      }
    });

    test('новые HTTP-эндпоинты (/v1/subscriptions, /v1/exits/configure, /v1/servers?scope=all) работают и проходят барьер секретов', () async {
      final dir = Directory.systemTemp.createTempSync('sg_api_new_ep_');
      AppPaths.overrideRoot(dir);
      final engine = _TestEngine();
      final state = AppState(engine: engine);
      await state.init();
      final probe = ProbeController();
      final settings = SettingsController();
      await settings.init();
      final handlers = AppStateApiHandlers(state, probe, settings);
      final server = LocalApiServer(token: 'tok123', handlers: handlers, port: 18793);
      await server.start();

      addTearDown(() async {
        await server.stop();
        AppPaths.resetForTests();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });

      await state.importSource([
        '#profile-title: Первая',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.41:443?type=tcp&security=none#DE-1',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.42:443?type=tcp&security=none#NL-1',
      ].join('\n'));
      await state.importSource([
        '#profile-title: Вторая',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.43:443?type=tcp&security=none#US-1',
        'vless://11111111-2222-3333-4444-555555555555@198.51.100.44:443?type=tcp&security=none#FI-1',
      ].join('\n'));

      await settings.update((s) => s.copyWith(
            apiEnabled: true,
            apiToken: 'tok123',
          ));

      Future<(int, Map<String, dynamic>)> call(String method, String path, [Map<String, dynamic>? body]) async {
        final c = HttpClient();
        final r = await c.openUrl(method, Uri.parse('http://127.0.0.1:18793$path'));
        r.headers.set('Authorization', 'Bearer tok123');
        if (body != null) {
          r.headers.set('Content-Type', 'application/json');
          r.write(jsonEncode(body));
        }
        final resp = await r.close();
        final text = await utf8.decoder.bind(resp).join();
        assertNoSecrets(text);
        return (resp.statusCode, jsonDecode(text) as Map<String, dynamic>);
      }

      final (stSubs, subsBody) = await call('GET', '/v1/subscriptions');
      expect(stSubs, 200);
      final subs = (subsBody['subscriptions'] as List).cast<Map<String, dynamic>>();
      expect(subs, hasLength(2));

      final (stAllSrv, allSrvBody) = await call('GET', '/v1/servers?scope=all');
      expect(stAllSrv, 200);
      final allSrvs = (allSrvBody['servers'] as List).cast<Map<String, dynamic>>();
      expect(allSrvs, hasLength(4));

      // Выдаём порты всем серверам и назначаем ручной порт первому серверу через API
      final firstSrvId = allSrvs.first['key'] as String;
      final (stCfg, _) = await call('POST', '/v1/exits/configure', {
        'mode': 'all_servers',
        'assignPorts': {firstSrvId: 12600},
        'keepAliveWhenDisconnected': true,
      });
      expect(stCfg, 200);

      final (stExits, exitsBody) = await call('GET', '/v1/exits');
      expect(stExits, 200);
      final exits = (exitsBody['exits'] as List).cast<Map<String, dynamic>>();
      expect(exits.first['kind'], 'auto');
      expect(exits.first['port'], ApiPorts.auto);
      expect(exits.any((e) => e['serverKey'] == firstSrvId && e['port'] == 12600), isTrue);
      expect(exits.last['kind'], 'direct');
    });
  });
}
