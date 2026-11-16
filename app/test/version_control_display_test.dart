import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/app_info.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/update_manifest.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/app_update_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';
import 'package:silentgate/ui/update_screen.dart';

import 'helpers/update_ui_harness.dart';

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

void main() {
  group('Контроль версий (+N, суффиксы, имена файлов)', () {
    test('isNewer сравнивает номер сборки +N и 4-е число, не зацикливаясь на коротком теге', () {
      expect(AppUpdate.isNewer('1.18.0+92', '1.18.0+91'), isTrue);
      expect(AppUpdate.isNewer('1.18.0+91', '1.18.0+91'), isFalse);
      expect(AppUpdate.isNewer('1.18.0+90', '1.18.0+91'), isFalse);
      expect(AppUpdate.isNewer('1.18.0.92', '1.18.0+91'), isTrue);
      // Короткий тег без +N не считается «новее» уже установленной сборки того же релиза.
      expect(AppUpdate.isNewer('1.18.0', '1.18.0+91'), isFalse);
      // Пре-релиз + номер сборки: +N не смешивается с номером беты.
      expect(AppUpdate.isNewer('1.18.0-beta.2+91', '1.18.0-beta.1+95'), isTrue);
      expect(AppUpdate.isNewer('1.18.0-beta.1+92', '1.18.0-beta.1+91'), isTrue);
      expect(AppUpdate.isNewer('1.18.0+91', '1.18.0-beta.3+99'), isTrue);
    });

    test('sameRelease учитывает +N, когда он указан у обеих сторон', () {
      expect(sameRelease('1.18.0', '1.18.0+91'), isTrue);
      expect(sameRelease('1.18.0+91', '1.18.0+91'), isTrue);
      expect(sameRelease('1.18.0.91', '1.18.0+91'), isTrue);
      expect(sameRelease('1.18.0+92', '1.18.0+91'), isFalse);
      expect(sameRelease('1.18.0-beta.1+91', '1.18.0-beta.1+91'), isTrue);
      expect(sameRelease('1.18.0-beta.1+92', '1.18.0-beta.1+91'), isFalse);
    });

    test('подбор актива находит переименованные файлы с +N / .N / -bN и не путает msstore/.bak', () async {
      for (final fileName in [
        'SilentGateSetup-1.18.0.exe',
        'SilentGateSetup-1.18.0+91.exe',
        'SilentGateSetup-1.18.0.91.exe',
        'SilentGateSetup-1.18.0-b91.exe',
      ]) {
        final r = await AppUpdate.check(
          assetHint: 'Setup.exe',
          fetcher: (_) async => UpdateHttpResponse(
            200,
            jsonEncode({
              'tag_name': 'v1.18.0',
              'assets': [
                {
                  'name': 'SilentGateSetup-1.18.0+91-msstore.exe',
                  'browser_download_url': 'https://example.com/msstore.exe',
                  'size': 100,
                },
                {
                  'name': '$fileName.bak',
                  'browser_download_url': 'https://example.com/bad.bak',
                  'size': 100,
                },
                {
                  'name': fileName,
                  'browser_download_url': 'https://example.com/$fileName',
                  'size': 100,
                },
              ],
            }),
          ),
        );
        expect(r.release?.assetName, fileName, reason: fileName);
      }
    });

    testWidgets('экран «Обновления» показывает текущую версию с номером сборки +N', (tester) async {
      final h = UpdateUiHarness.create(current: AppInfo.fullVersion);
      addTearDown(h.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: h.settings),
            ChangeNotifierProvider<AppUpdateController>.value(
              value: h.controller,
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: UpdateScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining(AppInfo.fullVersion), findsOneWidget);
    });

    testWidgets('«О программе» показывает vX.Y.Z+N и открывает диалог со списком патчей', (tester) async {
      final h = UpdateUiHarness.create(current: AppInfo.fullVersion);
      final appState = AppState(engine: _FakeEngine());
      final probeCtrl = ProbeController();
      addTearDown(() {
        probeCtrl.dispose();
        appState.dispose();
        h.dispose();
      });

      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: h.settings),
            ChangeNotifierProvider<AppUpdateController>.value(
              value: h.controller,
            ),
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<ProbeController>.value(value: probeCtrl),
          ],
          child: const MaterialApp(
            locale: Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final searchField = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField, '+${AppInfo.buildNumber}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final versionTile = find.byKey(const Key('aboutVersionTile'));
      expect(versionTile, findsOneWidget);
      expect(find.textContaining('v${AppInfo.fullVersion}'), findsOneWidget);

      await tester.ensureVisible(versionTile);
      await tester.pump();
      await tester.tap(versionTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('aboutVersionPatchesDialog')), findsOneWidget);
      expect(find.textContaining('+${AppInfo.buildNumber}'), findsWidgets);
      for (final p in AppInfo.builtInPatchesRu) {
        expect(find.textContaining(p), findsOneWidget);
      }
    });
  });
}
