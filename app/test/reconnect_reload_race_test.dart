import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/live_connections.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/live_connections_sheet.dart';

const _serverLink =
    'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
    '?encryption=none&security=tls&sni=example.com#ReloadTest';

/// Имитирует реальное поведение `VpnEngineBase`:
/// `disconnectKeepingCapture()` / `disconnect()` сначала шлют `disconnecting`,
/// ждут остановку дочернего процесса (за этот await событие `disconnecting`
/// успевает дойти до `AppState._statusSub`), а прямо перед `return` шлют
/// `disconnected` в асинхронный `StreamController.broadcast()`.
class _RealisticDisconnectEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = const VpnStatus.disconnected();

  int connectCalls = 0;
  int balancerCalls = 0;
  int disconnectCalls = 0;
  int softDisconnectCalls = 0;
  int forceDisconnectCalls = 0;
  Duration stepDelay = const Duration(milliseconds: 2);
  LiveCoreApi? mockCoreApi = const LiveCoreApi(port: 19090, secret: 't');

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
      _status.isConnected ? mockCoreApi : null;

  @override
  bool canKeepCaptureFor(AppSettings next) => next.captureMode == CaptureMode.tun;

  void _emit(VpnStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  @override
  Future<void> connect(
    VpnServer server, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {
    connectCalls++;
    _emit(const VpnStatus(VpnConnectionState.connecting));
    if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
    _emit(const VpnStatus(VpnConnectionState.connected));
  }

  @override
  Future<void> connectBalancer(
    List<VpnServer> servers, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {
    balancerCalls++;
    _emit(const VpnStatus(VpnConnectionState.connecting));
    if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
    _emit(const VpnStatus(VpnConnectionState.connected));
  }

  @override
  Future<void> disconnectKeepingCapture() async {
    softDisconnectCalls++;
    _emit(const VpnStatus(VpnConnectionState.disconnecting));
    // Во время остановки Xray событие `disconnecting` доставляется в AppState.
    if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
    // Событие `disconnected` кладётся в broadcast-поток синхронно перед возвратом
    // и дойдёт до слушателей только в следующем микротаске!
    _emit(const VpnStatus.disconnected());
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _emit(const VpnStatus(VpnConnectionState.disconnecting));
    if (stepDelay > Duration.zero) await Future<void>.delayed(stepDelay);
    _emit(const VpnStatus.disconnected());
  }

  @override
  Future<void> forceDisconnect() async {
    forceDisconnectCalls++;
    _emit(const VpnStatus.disconnected());
  }

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}

class _StubLiveConnectionsClient extends LiveConnectionsClient {
  const _StubLiveConnectionsClient(this.snapshot);
  final LiveConnectionsSnapshot snapshot;

  @override
  Future<LiveConnectionsSnapshot?> fetch(
    LiveCoreApi api, {
    SplitTunnelConfig? split,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async =>
      snapshot;
}

void main() {
  group('Перезапуск VPN («Перезагрузить VPN») и отпечаток правил туннеля', () {
    late Directory tempDir;
    late _RealisticDisconnectEngine engine;
    late AppState state;
    late SettingsController settingsCtrl;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('sg_reconnect_race_');
      AppPaths.overrideRoot(tempDir);
      engine = _RealisticDisconnectEngine();
      state = AppState(engine: engine);
      await state.init();
      settingsCtrl = SettingsController();
      await settingsCtrl.init();

      await state.importSource(_serverLink);
      final key = ShareLinkParser.canonicalKey(_serverLink);
      state.selectServer(state.servers.indexWhere((s) => s.key == key));
    });

    tearDown(() {
      state.dispose();
      settingsCtrl.dispose();
      AppPaths.resetForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('reconnect при keepCaptureOnSwitch=true поднимает новую сессию, а не зовёт forceDisconnect', () async {
      const cfg = AppSettings(
        captureMode: CaptureMode.tun,
        seamlessServerSwitch: true,
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          sites: [SiteRule('fbsbx.com', action: AppAction.tunnel)],
        ),
      );

      await state.toggleConnection(cfg);
      await pumpEventQueue();
      expect(state.status.isConnected, isTrue);
      expect(engine.connectCalls, 1);
      expect(
        state.connectedSplitSignature,
        splitRoutingSignature(cfg.splitTunnel, noRealIp: cfg.noRealIp),
      );

      final updatedCfg = cfg.copyWith(
        splitTunnel: const SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          sites: [
            SiteRule('fbsbx.com', action: AppAction.tunnel),
            SiteRule('anthropic.com', action: AppAction.tunnel),
          ],
        ),
      );

      await state.reconnect(updatedCfg);
      await pumpEventQueue();

      expect(engine.softDisconnectCalls, 1);
      expect(
        engine.forceDisconnectCalls,
        0,
        reason: 'асинхронный статус disconnecting не должен попадать в toggleConnection -> forceDisconnect',
      );
      expect(engine.connectCalls, 2);
      expect(state.status.isConnected, isTrue);
      expect(
        state.connectedSplitSignature,
        splitRoutingSignature(updatedCfg.splitTunnel, noRealIp: updatedCfg.noRealIp),
      );
    });

    test('reconnectAuto также не срывается в forceDisconnect при асинхронном disconnecting', () async {
      const cfg = AppSettings(
        captureMode: CaptureMode.tun,
        seamlessServerSwitch: false,
      );

      await state.connectAuto(cfg);
      await pumpEventQueue();
      expect(state.status.isConnected, isTrue);
      expect(engine.balancerCalls, 1);

      await state.reconnectAuto(cfg);
      await pumpEventQueue();

      expect(engine.disconnectCalls, 1);
      expect(engine.forceDisconnectCalls, 0);
      expect(engine.balancerCalls, 2);
      expect(state.status.isConnected, isTrue);
    });
  });

  testWidgets('LiveConnectionsBadge не показывает «Маршруты обновились», если правила не менялись после Connect, но показывает после добавления сайта', (tester) async {
    late Directory tempDir;
    late _RealisticDisconnectEngine engine;
    late AppState state;
    late SettingsController settingsCtrl;

    await tester.runAsync(() async {
      tempDir = Directory.systemTemp.createTempSync('sg_reconnect_widget_');
      AppPaths.overrideRoot(tempDir);
      engine = _RealisticDisconnectEngine()..stepDelay = Duration.zero;
      state = AppState(engine: engine);
      await state.init();
      settingsCtrl = SettingsController();
      await settingsCtrl.init();

      await state.importSource(_serverLink);
      final key = ShareLinkParser.canonicalKey(_serverLink);
      state.selectServer(state.servers.indexWhere((s) => s.key == key));

      await settingsCtrl.update(
        (s) => s.copyWith(
          captureMode: CaptureMode.tun,
          splitTunnel: const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            sites: [SiteRule('fbsbx.com', action: AppAction.tunnel)],
          ),
        ),
      );
      await state.toggleConnection(settingsCtrl.settings);
      await Future<void>.delayed(Duration.zero);
    });
    addTearDown(() async {
      state.dispose();
      settingsCtrl.dispose();
      AppPaths.resetForTests();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    await tester.pump();
    expect(state.status.isConnected, isTrue);

    // Даже если в снимке оказалось старое прямое соединение до fbsbx.com,
    // туннель уже поднят с ЭТИМ ЖЕ списком правил — диалога быть не должно.
    const staleDirectSnap = LiveConnectionsSnapshot(
      direct: [
        LiveConnectionEntry(
          id: 'c2',
          host: 'newsite.example',
          destinationIp: '93.184.216.34',
          destinationPort: 443,
          network: 'tcp',
          process: 'chrome.exe',
          chains: ['direct'],
          rule: 'final',
          uploadBytes: 100,
          downloadBytes: 200,
          start: null,
          route: LiveRouteKind.direct,
        ),
        LiveConnectionEntry(
          id: 'c1',
          host: 'fbsbx.com',
          destinationIp: '157.240.241.35',
          destinationPort: 443,
          network: 'tcp',
          process: 'chrome.exe',
          chains: ['direct'],
          rule: 'final',
          uploadBytes: 100,
          downloadBytes: 200,
          start: null,
          route: LiveRouteKind.direct,
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LiveConnectionsBadge(
              client: _StubLiveConnectionsClient(staleDirectSnap),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Маршруты обновились'), findsNothing);

    // Теперь пользователь добавляет `newsite.example` ПРИ ЖИВОМ туннеле:
    // отпечаток правил изменился -> диалог обязан появиться.
    await tester.runAsync(() async {
      await settingsCtrl.update(
        (s) => s.copyWith(
          splitTunnel: const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            sites: [
              SiteRule('fbsbx.com', action: AppAction.tunnel),
              SiteRule('newsite.example', action: AppAction.tunnel),
            ],
          ),
        ),
      );
    });
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Маршруты обновились'), findsOneWidget);
    expect(find.textContaining('newsite.example'), findsOneWidget);

    // Закрываем диалог и размонтируем виджет (гасит 1-секундный таймер опроса).
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await state.disconnect();
    });
    await tester.pump();
  });
}
