import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/live_connection_rules_planner.dart';
import 'package:silentgate/core/net/live_connections.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/live_connections_sheet.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

void main() {
  group('LiveConnectionRulesPlanner (умный режим Авто и явные режимы)', () {
    const chromeYoutube = LiveConnectionEntry(
      id: 'c1',
      host: 'www.youtube.com',
      destinationIp: '142.250.74.14',
      destinationPort: 443,
      network: 'tcp',
      process: 'chrome.exe',
      processPath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      chains: ['proxy'],
      rule: 'final',
      uploadBytes: 100,
      downloadBytes: 2000,
      start: null,
      route: LiveRouteKind.vpn,
    );

    const langServerGoogle = LiveConnectionEntry(
      id: 'c2',
      host: 'play.googleapis.com',
      destinationIp: '172.217.117.4',
      destinationPort: 443,
      network: 'tcp',
      process: 'language_server.exe',
      processPath: r'C:\Tools\language_server.exe',
      chains: ['proxy'],
      rule: 'final',
      uploadBytes: 500,
      downloadBytes: 4000,
      start: null,
      route: LiveRouteKind.vpn,
    );

    const tgBareIp1 = LiveConnectionEntry(
      id: 'c3',
      host: '',
      destinationIp: '149.154.167.41',
      destinationPort: 443,
      network: 'tcp',
      process: 'Telegram.exe',
      processPath: r'C:\Users\Test\AppData\Roaming\Telegram Desktop\Telegram.exe',
      chains: ['proxy'],
      rule: 'final',
      uploadBytes: 234,
      downloadBytes: 374,
      start: null,
      route: LiveRouteKind.vpn,
    );

    const tgBareIp2 = LiveConnectionEntry(
      id: 'c4',
      host: '',
      destinationIp: '91.105.192.100',
      destinationPort: 443,
      network: 'tcp',
      process: 'Telegram.exe',
      processPath: r'C:\Users\Test\AppData\Roaming\Telegram Desktop\Telegram.exe',
      chains: ['proxy'],
      rule: 'final',
      uploadBytes: 210,
      downloadBytes: 410,
      start: null,
      route: LiveRouteKind.vpn,
    );

    const chromeBareIp = LiveConnectionEntry(
      id: 'c5',
      host: '',
      destinationIp: '1.1.1.1',
      destinationPort: 443,
      network: 'udp',
      process: 'chrome.exe',
      processPath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      chains: ['direct'],
      rule: 'final',
      uploadBytes: 50,
      downloadBytes: 50,
      start: null,
      route: LiveRouteKind.direct,
    );

    test('Авто: браузеры идут по доменам, а мессенджер на голых IP - по процессу', () {
      final plan = LiveConnectionRulesPlanner.plan(
        const [chromeYoutube, langServerGoogle, tgBareIp1, tgBareIp2],
        mode: LiveRuleTargetMode.auto,
      );

      expect(plan.domains, ['youtube.com', 'play.googleapis.com']);
      expect(plan.apps, hasLength(1));
      expect(plan.apps.single.displayName, 'Telegram.exe');
      expect(
        plan.apps.single.rulePath,
        r'C:\Users\Test\AppData\Roaming\Telegram Desktop\Telegram.exe',
      );
      expect(plan.skippedSharedBareIpProcesses, isEmpty);
    });

    test('Авто: голый IP браузера НЕ превращает весь chrome.exe в AppRule', () {
      final plan = LiveConnectionRulesPlanner.plan(
        const [chromeBareIp, chromeYoutube],
        mode: LiveRuleTargetMode.auto,
      );

      expect(plan.apps, isEmpty);
      expect(plan.domains, ['youtube.com']);
      expect(plan.skippedSharedBareIpProcesses, ['chrome.exe']);
    });

    test('Авто: отдельное приложение с >= 4 поддоменами сворачивается в AppRule', () {
      final shards = [
        for (var i = 1; i <= 4; i++)
          LiveConnectionEntry(
            id: 'sp$i',
            host: 'ap$i.spotify.com',
            destinationIp: '35.186.224.$i',
            destinationPort: 443,
            network: 'tcp',
            process: 'Spotify.exe',
            processPath: r'C:\Spotify\Spotify.exe',
            chains: const ['proxy'],
            rule: 'final',
            uploadBytes: 10,
            downloadBytes: 20,
            start: null,
            route: LiveRouteKind.vpn,
          ),
      ];

      final plan = LiveConnectionRulesPlanner.plan(
        shards,
        mode: LiveRuleTargetMode.auto,
      );

      expect(plan.domains, isEmpty);
      expect(plan.apps.single.displayName, 'Spotify.exe');
    });

    test('applyToSettings переключает SplitMode.all на exceptSelected и сохраняет сервер', () {
      final plan = LiveConnectionRulesPlanner.plan(
        const [chromeYoutube, tgBareIp1],
        mode: LiveRuleTargetMode.auto,
      );

      const initial = AppSettings(
        splitTunnel: SplitTunnelConfig(mode: SplitMode.all),
      );
      final res = LiveConnectionRulesPlanner.applyToSettings(
        initial,
        plan,
        action: AppAction.tunnel,
        serverKey: 'vless://nl@nl.example:443#NL',
      );

      expect(res.switchedModeFromAll, isTrue);
      expect(res.settings.splitTunnel.mode, SplitMode.exceptSelected);
      expect(res.addedSites, 1);
      expect(res.addedApps, 1);
      expect(res.settings.splitTunnel.sites.single.domain, 'youtube.com');
      expect(
        res.settings.splitTunnel.sites.single.serverKey,
        'vless://nl@nl.example:443#NL',
      );
      expect(res.settings.splitTunnel.apps.single.name, 'Telegram.exe');
      expect(res.settings.splitTunnel.apps.single.byName, isTrue);
      expect(
        res.settings.splitTunnel.apps.single.serverKey,
        'vless://nl@nl.example:443#NL',
      );
    });
  });

  group('LiveConnectionsClient Clash API (fetch processPath & closeConnections)', () {
    test('извлекает processPath и закрывает сокеты через DELETE /connections/{id}', () async {
      await HttpOverrides.runZoned(() async {
        final deletedIds = <String>[];
        String? lastAuth;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((req) async {
          lastAuth = req.headers.value(HttpHeaders.authorizationHeader);
          if (req.method == 'GET' && req.uri.path == '/connections') {
            req.response.statusCode = 200;
            req.response.write(jsonEncode({
              'connections': [
                {
                  'id': 'sock-42',
                  'chains': ['proxy'],
                  'metadata': {
                    'network': 'tcp',
                    'host': 'github.com',
                    'destinationIP': '140.82.121.4',
                    'destinationPort': 443,
                    'process': 'Telegram.exe',
                    'processPath': r'C:\Apps\Telegram\Telegram.exe',
                  },
                },
              ],
            }));
            await req.response.close();
            return;
          }
          if (req.method == 'DELETE' &&
              req.uri.pathSegments.length == 2 &&
              req.uri.pathSegments.first == 'connections') {
            deletedIds.add(req.uri.pathSegments[1]);
            req.response.statusCode = 204;
            await req.response.close();
            return;
          }
          req.response.statusCode = 404;
          await req.response.close();
        });

        const client = LiveConnectionsClient();
        final api = LiveCoreApi(port: server.port, secret: 'sec-token');

        final snap = await client.fetch(api);
        expect(snap, isNotNull);
        expect(snap!.vpn.single.process, 'Telegram.exe');
        expect(snap.vpn.single.processPath, r'C:\Apps\Telegram\Telegram.exe');
        expect(snap.vpn.single.hasExecutablePath, isTrue);

        final closed = await client.closeConnections(api, ['sock-42', 'sock-99']);
        expect(closed, 2);
        expect(deletedIds, containsAll(['sock-42', 'sock-99']));
        expect(lastAuth, 'Bearer sec-token');
      }, createHttpClient: (ctx) => _RealHttpOverrides().createHttpClient(ctx));
    });
  });

  group('LiveConnectionsSheet UI: пауза, протяжка ЛКМ, ПКМ и пакетные правила', () {
    late Directory tmp;
    late _FakeConnectedEngine engine;
    late AppState state;
    late ProbeController probe;
    late SettingsController settings;
    late _FakeLiveClient fakeClient;

    const nl = VpnServer(
      protocol: 'vless',
      remark: 'NL Нидерланды',
      address: 'nl.example',
      port: 443,
      id: '00000000-0000-0000-0000-000000000010',
      rawLink: 'vless://00000000-0000-0000-0000-000000000010@nl.example:443'
          '?type=tcp&security=none#NL',
    );

    const initialSnap = LiveConnectionsSnapshot(
      vpn: [
        LiveConnectionEntry(
          id: 'id-1',
          host: '',
          destinationIp: '149.154.167.41',
          destinationPort: 443,
          network: 'tcp',
          process: 'Telegram.exe',
          processPath: r'C:\Telegram\Telegram.exe',
          chains: ['proxy'],
          rule: 'final',
          uploadBytes: 234,
          downloadBytes: 374,
          start: null,
          route: LiveRouteKind.vpn,
        ),
        LiveConnectionEntry(
          id: 'id-2',
          host: 'play.googleapis.com',
          destinationIp: '172.217.117.4',
          destinationPort: 443,
          network: 'tcp',
          process: 'chrome.exe',
          processPath: r'C:\Chrome\chrome.exe',
          chains: ['proxy'],
          rule: 'final',
          uploadBytes: 1024,
          downloadBytes: 4096,
          start: null,
          route: LiveRouteKind.vpn,
        ),
        LiveConnectionEntry(
          id: 'id-3',
          host: 'youtube.com',
          destinationIp: '142.250.74.14',
          destinationPort: 443,
          network: 'tcp',
          process: 'chrome.exe',
          processPath: r'C:\Chrome\chrome.exe',
          chains: ['proxy'],
          rule: 'final',
          uploadBytes: 2048,
          downloadBytes: 8192,
          start: null,
          route: LiveRouteKind.vpn,
        ),
      ],
    );

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('sg_live_sheet_');
      AppPaths.overrideRoot(tmp);
      engine = _FakeConnectedEngine();
      state = AppState(engine: engine);
      engine.emit(const VpnStatus(VpnConnectionState.connected));
      await state.togglePin(nl);
      state.selectServer(0);
      probe = ProbeController();
      settings = SettingsController();
      settings.update(
        (s) => s.copyWith(
          captureMode: CaptureMode.tun,
          alwaysReloadVpnOnNewSite: true,
          splitTunnel: const SplitTunnelConfig(mode: SplitMode.exceptSelected),
        ),
      );
      fakeClient = _FakeLiveClient(initialSnap);
    });

    tearDown(() async {
      engine.emit(const VpnStatus.disconnected());
      state.dispose();
      await engine.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> openSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<ProbeController>.value(value: probe),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    key: const Key('openSheetBtn'),
                    onPressed: () => showLiveConnectionsSheet(
                      ctx,
                      client: fakeClient,
                      initial: initialSnap,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('openSheetBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('кнопка паузы замораживает обновление снимка', (tester) async {
      await openSheet(tester);
      expect(find.text('149.154.167.41:443'), findsOneWidget);

      // Ставим на паузу.
      await tester.tap(find.byKey(const Key('liveConnsPauseBtn')));
      await tester.pump();
      expect(find.text('На паузе · список заморожен'), findsOneWidget);

      // Меняем ответ клиента и ждём 2 секунды таймера — список обязан остаться прежним.
      fakeClient.current = LiveConnectionsSnapshot.empty;
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('149.154.167.41:443'), findsOneWidget);

      // Снимаем с паузы — новый снимок сразу подтягивается.
      await tester.tap(find.byKey(const Key('liveConnsPauseBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('149.154.167.41:443'), findsNothing);
    });

    testWidgets(
        'протяжка ЛКМ через 2+ строки включает режим выбора, ставит галочки и создаёт правила через сервер',
        (tester) async {
      await openSheet(tester);

      final row1 = tester.getCenter(find.text('149.154.167.41:443'));
      final row2 = tester.getCenter(find.text('play.googleapis.com:443'));

      // Зажимаем ЛКМ на 1-й строке: пока на ней, режим выбора ещё не включён.
      final gesture = await tester.startGesture(
        row1,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await tester.pump();
      expect(find.byKey(const Key('liveConnsBatchPanel')), findsNothing);

      // Протягиваем на 2-ю строку: сразу появляются галочки и панель действий!
      await gesture.moveTo(row2);
      await tester.pump();
      expect(find.byKey(const Key('liveConnsBatchPanel')), findsOneWidget);
      expect(find.text('Выбрано: 2'), findsOneWidget);

      await gesture.up();
      await tester.pump();

      // Умный предпросмотр Авто: 1 сайт (play.googleapis.com) и 1 программа (Telegram.exe).
      final preview =
          tester.widget<Text>(find.byKey(const Key('liveConnsPlanPreview')));
      expect(preview.data, contains('play.googleapis.com'));
      expect(preview.data, contains('Telegram.exe'));

      // Жмём «Через сервер...» и выбираем NL Нидерланды.
      await tester.tap(find.byKey(const Key('liveConnsBatchViaServer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final nlTile =
          find.byWidgetPredicate((w) => w is ServerTile && w.server.key == nl.key);
      await tester.tap(nlTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Проверяем созданные правила в SettingsController и сброс сокетов.
      final st = settings.settings.splitTunnel;
      expect(st.sites.single.domain, 'play.googleapis.com');
      expect(st.sites.single.serverKey, nl.key);
      expect(st.apps.single.name, 'Telegram.exe');
      expect(st.apps.single.serverKey, nl.key);
      expect(fakeClient.closedIds, containsAll(['id-1', 'id-2']));
    });

    testWidgets('ПКМ открывает контекстное меню с быстрым фильтром и разрывом соединения',
        (tester) async {
      await openSheet(tester);

      final row2 = tester.getCenter(find.text('play.googleapis.com:443'));
      await tester.tapAt(row2, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Разорвать соединение'), findsOneWidget);
      expect(find.textContaining('Фильтр по процессу «chrome.exe»'), findsOneWidget);

      await tester.tap(find.text('Разорвать соединение'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(fakeClient.closedIds, contains('id-2'));
      expect(find.text('play.googleapis.com:443'), findsNothing);
    });
  });
}

class _RealHttpOverrides extends HttpOverrides {}

class _FakeLiveClient extends LiveConnectionsClient {
  _FakeLiveClient(this.current);

  LiveConnectionsSnapshot? current;
  final List<String> closedIds = <String>[];

  @override
  Future<LiveConnectionsSnapshot?> fetch(
    LiveCoreApi api, {
    SplitTunnelConfig? split,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async =>
      current;

  @override
  Future<int> closeConnections(
    LiveCoreApi api,
    Iterable<String> ids, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final list = ids.toList();
    closedIds.addAll(list);
    current = current?.withoutIds(list.toSet());
    return list.length;
  }
}

class _FakeConnectedEngine extends VpnEngine {
  _FakeConnectedEngine();

  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = const VpnStatus(VpnConnectionState.connected);

  void emit(VpnStatus next) {
    _status = next;
    if (!_statusCtrl.isClosed) {
      _statusCtrl.add(next);
    }
  }

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
  LiveCoreApi? get connectionsCoreApi =>
      const LiveCoreApi(port: 19090, secret: 'test');

  @override
  Future<void> connect(
    VpnServer server, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {}

  @override
  Future<void> connectBalancer(
    List<VpnServer> servers, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
