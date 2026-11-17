import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/speed_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/clash_delay.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/provider_wiring.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';

class _FakeClashDelayProbe extends ClashDelayProbe {
  int calls = 0;
  final int delayMs;

  _FakeClashDelayProbe({this.delayMs = 42})
      : super(port: 19999, secret: 's', tag: 'proxy');

  @override
  Future<ClashDelayResult> measure({
    required String testUrl,
    required Duration timeout,
  }) async {
    calls++;
    return ClashDelayResult(PingOutcome.ok, delayMs: delayMs);
  }
}

class _InstantVpnEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = const VpnStatus.disconnected();

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
  int get httpProxyPort => _status.isConnected ? 10811 : 0;

  void emit(VpnStatus st) {
    _status = st;
    _statusCtrl.add(st);
  }

  @override
  Future<void> connect(
    VpnServer server, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {
    emit(const VpnStatus(VpnConnectionState.connected));
  }

  @override
  Future<void> connectBalancer(
    List<VpnServer> servers, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {}

  @override
  Future<void> disconnect() async {
    emit(const VpnStatus.disconnected());
  }

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}

void main() {
  late Directory scratchDir;

  setUp(() async {
    scratchDir = await Directory.systemTemp.createTemp('sg_scratchpad_auto_probe_');
    AppPaths.overrideRoot(scratchDir);
    ServiceCheckActivity.resetForTests();
  });

  tearDown(() async {
    ServiceCheckActivity.resetForTests();
    AppPaths.resetForTests();
    try {
      if (await scratchDir.exists()) {
        await scratchDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  final testServer = ShareLinkParser.tryParse(
    'vless://11111111-2222-4333-8444-555555555555@198.51.100.10:443?encryption=none&security=none&type=tcp#TestNode',
  )!;

  test('connectAutoSpeedTest включён по умолчанию и сохраняется в JSON', () {
    expect(AppSettings.defaults.connectAutoSpeedTest, isTrue);
    final off = AppSettings.defaults.copyWith(connectAutoSpeedTest: false);
    final restored = AppSettings.fromJson(off.toJson());
    expect(restored.connectAutoSpeedTest, isFalse);
  });

  test('autoProbeConnectedServer: пингует и меряет скорость даже во время проверки сервисов, но соблюдает кулдаун 1 мин',
      () async {
    final coreProbe = _FakeClashDelayProbe(delayMs: 37);
    var speedCalls = 0;
    SpeedTestSize? lastSize;

    final probe = ProbeController(
      liveProxyPort: () => 10811,
      activeServerKey: () => testServer.key,
      liveCoreDelay: () => coreProbe,
    );
    addTearDown(probe.dispose);
    probe.speedDownload = ({
      required SpeedTestSize size,
      int? proxyPort,
      String proxyUser = '',
      String proxyPassword = '',
    }) async {
      speedCalls++;
      lastSize = size;
      return const SpeedResult(
        bytes: 5000000,
        elapsed: Duration(seconds: 1),
        bitsPerSecond: 40000000,
      );
    };

    // Имитируем идущую проверку сервисов: авто-пинг активного узла НЕ должен блокироваться!
    ServiceCheckActivity.begin();
    const settings = AppSettings(
      speedTestSize: SpeedTestSize.full,
      connectAutoSpeedTest: true,
    );

    final t0 = DateTime(2026, 11, 17, 15, 0, 0);
    await probe.autoProbeConnectedServer(testServer, settings, now: t0);

    expect(coreProbe.calls, 1);
    expect(probe.resultFor(testServer).isWorking, isTrue);
    expect(probe.resultFor(testServer).latencyMs, 37);
    expect(speedCalls, 1);
    expect(lastSize, SpeedTestSize.full);
    expect(probe.speedFor(testServer)?.mbps, closeTo(40.0, 0.01));

    // Повтор через 30 секунд (< 1 мин) — ни пинг, ни спидтест повторно НЕ дергаются!
    await probe.autoProbeConnectedServer(
      testServer,
      settings,
      now: DateTime.now().add(const Duration(seconds: 30)),
    );
    expect(coreProbe.calls, 1);
    expect(speedCalls, 1);

    // Повтор через 65 секунд (> 1 мин), но с выключенной галочкой connectAutoSpeedTest —
    // пинг обновляется, а спидтест пропускается.
    await probe.autoProbeConnectedServer(
      testServer,
      settings.copyWith(connectAutoSpeedTest: false),
      now: DateTime.now().add(const Duration(seconds: 65)),
    );
    expect(coreProbe.calls, 2);
    expect(speedCalls, 1);
  });

  testWidgets('раздел «Захват трафика» стоит самым первым в Настройках и содержит переключатель авто-спидтеста',
      (tester) async {
    final settingsCtrl = SettingsController();
    addTearDown(settingsCtrl.dispose);

    late List<SettingsSectionData> sections;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                sections = buildSettingsSections(
                  ctx,
                  settingsCtrl.settings,
                  settingsCtrl,
                );
                final subset = sections
                    .where((s) =>
                        s.id == SettingsSectionIds.capture ||
                        s.id == SettingsSectionIds.ping)
                    .toList();
                return SettingsBody(
                  sections: subset,
                  collapsed: const {},
                  onToggleSection: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(sections.first.id, SettingsSectionIds.capture,
        reason: 'вкладка «Захват трафика» обязана быть в самом верху');
    expect(find.byKey(const Key('connectAutoSpeedTestSwitch'), skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('ConnectAutoProbeLink запускает авто-проверку при ручном подключении, не задерживая connect()',
      (tester) async {
    final engine = _InstantVpnEngine();
    final state = AppState(engine: engine);
    final settingsCtrl = SettingsController();
    await tester.runAsync(() async {
      await state.init();
      await state.importSource(testServer.rawLink);
      await settingsCtrl.init();
    });

    final coreProbe = _FakeClashDelayProbe(delayMs: 28);
    final speedDone = Completer<void>();
    var speedDownloaded = 0;
    final probe = ProbeController(liveCoreDelay: () => coreProbe);
    probe.speedDownload = ({
      required SpeedTestSize size,
      int? proxyPort,
      String proxyUser = '',
      String proxyPassword = '',
    }) async {
      // Медленная закачка не должна задерживать завершение toggleConnection!
      await Future<void>.delayed(const Duration(milliseconds: 50));
      speedDownloaded++;
      if (!speedDone.isCompleted) speedDone.complete();
      return const SpeedResult(
        bytes: 5000000,
        elapsed: Duration(seconds: 1),
        bitsPerSecond: 80000000,
      );
    };

    addTearDown(() async {
      probe.dispose();
      settingsCtrl.dispose();
      state.dispose();
      await engine.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          connectAutoProbeLinkProvider(),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    // Ручное подключение завершается мгновенно, не дожидаясь 50 мс закачки
    await tester.runAsync(() async {
      await state.toggleConnection(settingsCtrl.settings);
    });
    expect(state.status.isConnected, isTrue);
    expect(speedDownloaded, 0,
        reason: 'toggleConnection обязан завершиться до конца спидтеста');

    await tester.pump();
    for (var i = 0; i < 40 && !speedDone.isCompleted; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();

    expect(coreProbe.calls, 1);
    expect(speedDownloaded, 1);
    expect(probe.speedFor(testServer)?.mbps, closeTo(80.0, 0.01));

    await tester.runAsync(() => state.disconnect());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
