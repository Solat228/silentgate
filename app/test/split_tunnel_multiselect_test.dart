import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/split_tunnel_screen.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

void main() {
  late Directory tmp;
  late AppState state;
  late ProbeController probe;
  late SettingsController settings;

  const de = VpnServer(
    protocol: 'vless',
    remark: 'DE Германия',
    address: 'de.example',
    port: 443,
    id: '00000000-0000-0000-0000-000000000021',
    rawLink: 'vless://00000000-0000-0000-0000-000000000021@de.example:443'
        '?type=tcp&security=none#DE',
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sg_split_multi_');
    AppPaths.overrideRoot(tmp);
    registerPlatformServices(
      PlatformServices(
        appCatalog: _FakeAppCatalog(),
        appIcons: _FakeAppIcons(),
        coreVersions: _FakeCoreVersions(),
        tunLog: _FakeTunLog(),
        privileges: _FakePrivileges(),
        support: _FakeSupport(),
      ),
    );
    state = AppState(engine: _FakeEngine());
    await state.togglePin(de);
    state.selectServer(0);
    probe = ProbeController();
    settings = SettingsController();
    settings.update(
      (s) => s.copyWith(
        captureMode: CaptureMode.tun,
        splitAppsCollapsed: false,
        splitSitesCollapsed: false,
        splitTunnel: const SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          apps: [
            AppRule(r'C:\Telegram\Telegram.exe', byName: true, action: AppAction.tunnel),
            AppRule(r'C:\Discord\Discord.exe', byName: true, action: AppAction.tunnel),
          ],
          sites: [
            SiteRule('youtube.com', action: AppAction.tunnel),
            SiteRule('openai.com', action: AppAction.tunnel),
            SiteRule('ads.example', action: AppAction.direct),
          ],
        ),
      ),
    );
  });

  tearDown(() async {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpSplit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SplitTunnelScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'одиночный ЛКМ вне режима выбора по-прежнему открывает диалог настройки правила',
      (tester) async {
    await pumpSplit(tester);

    final siteRow = find.byKey(const Key('site:youtube.com|'));
    await tester.ensureVisible(siteRow);
    await tester.pumpAndSettle();
    await tester.tap(siteRow);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('splitBatchActionBar')), findsNothing);
    expect(find.text('Готово'), findsOneWidget);
  });

  testWidgets(
      'протяжка ЛКМ по 2+ сайтам включает режим выбора и меняет сервер выбранным',
      (tester) async {
    await pumpSplit(tester);

    final site1 = find.byKey(const Key('site:youtube.com|'));
    final site2 = find.byKey(const Key('site:openai.com|'));
    await tester.ensureVisible(site1);
    await tester.pumpAndSettle();

    final p1 = tester.getCenter(site1);
    final p2 = tester.getCenter(site2);

    final gesture = await tester.startGesture(
      p1,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump();
    expect(find.byKey(const Key('splitBatchActionBar')), findsNothing);

    await gesture.moveTo(p2);
    await tester.pump();
    expect(find.byKey(const Key('splitBatchActionBar')), findsOneWidget);
    expect(find.text('Выбрано правил: 2'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    // Назначаем обоим сайтам сервер DE Германия одним действием.
    await tester.tap(find.byKey(const Key('splitBatchViaServer')));
    await tester.pumpAndSettle();

    final deTile =
        find.byWidgetPredicate((w) => w is ServerTile && w.server.key == de.key);
    await tester.tap(deTile);
    await tester.pumpAndSettle();

    final sites = settings.settings.splitTunnel.sites;
    expect(
      sites.firstWhere((s) => s.domain == 'youtube.com').serverKey,
      de.key,
    );
    expect(
      sites.firstWhere((s) => s.domain == 'openai.com').serverKey,
      de.key,
    );
    // Невыбранный сайт остался нетронутым.
    expect(
      sites.firstWhere((s) => s.domain == 'ads.example').action,
      AppAction.direct,
    );
  });

  testWidgets(
      'ПКМ -> Выбрать на приложении включает выбор, а пакетный Блок переводит оба приложения',
      (tester) async {
    await pumpSplit(tester);

    final app1 = find.byKey(const Key(r'app:C:\Telegram\Telegram.exe'));
    final app2 = find.byKey(const Key(r'app:C:\Discord\Discord.exe'));

    await tester.tapAt(tester.getCenter(app1), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать').last);
    await tester.pumpAndSettle();

    expect(find.text('Выбрано правил: 1'), findsOneWidget);

    // В режиме выбора одиночный ЛКМ по второму приложению добавляет его в выбор.
    await tester.tap(app2);
    await tester.pumpAndSettle();
    expect(find.text('Выбрано правил: 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('splitBatchBlock')));
    await tester.pumpAndSettle();

    final apps = settings.settings.splitTunnel.apps;
    expect(apps.every((a) => a.action == AppAction.block), isTrue);
    expect(find.byKey(const Key('splitBatchActionBar')), findsNothing);
  });
}

class _FakeAppCatalog implements AppCatalog {
  @override
  Future<List<CatalogApp>> list() async => const [];
  @override
  bool get supportsManualPick => true;
  @override
  String? cachedLabel(String key) => null;
  @override
  Future<String?> labelFor(String key) async => null;
}

class _FakeAppIcons implements AppIconLoader {
  @override
  Uint8List? cached(String key) => null;
  @override
  bool isCached(String key) => true;
  @override
  Future<Uint8List?> load(String key) async => null;
}

class _FakeCoreVersions implements CoreVersionInfo {
  @override
  Future<String> xray() async => 'test';
}

class _FakeTunLog implements TunLogReader {
  @override
  Future<String> tail({int lines = 400}) async => '';
  @override
  Future<String> filePath() async => '';
}

class _FakePrivileges implements PrivilegeSetup {
  @override
  bool get isApplicable => false;
  @override
  Future<bool> isConfigured() async => true;
  @override
  Future<PrivilegeSetupResult> configure() async => PrivilegeSetupResult.done;
  @override
  Future<bool> remove() async => true;
}

class _FakeSupport implements SupportReporter {
  @override
  Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  }) async =>
      '';
  @override
  Future<void> reveal(String path) async {}
}

class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

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
  VpnStatus get status => const VpnStatus.disconnected();

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
