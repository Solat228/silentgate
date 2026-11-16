import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/app_store.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// Заявка MS3 (27.10.2026): EXE для Microsoft Store без драйвера wintun.
///
/// В поставке нет `wintun.dll` и `sing-box.exe` (правило Store 10.2.4.2), и
/// всё, что без них не работает, обязано исчезнуть из интерфейса, а не
/// остаться видимым и молча ломаться: режим TUN не поднимется, hysteria2 не
/// подключится. Настройки, пришедшие из резервной копии обычной сборки,
/// сводятся к системному прокси.
void main() {
  group('Режим захвата без драйвера', () {
    AppSettings norm(AppSettings s, {bool tun = false}) =>
        SettingsController.normalizeFor(s, android: false, tunAvailable: tun);

    test('TUN и «Только прокси» из копии настроек — системный прокси', () {
      for (final mode in [CaptureMode.tun, CaptureMode.proxyOnly]) {
        final s = norm(const AppSettings().copyWith(captureMode: mode));
        expect(s.captureMode, CaptureMode.systemProxy, reason: '$mode');
      }
    });

    test('смешанный режим (TUN + системный прокси) тоже снимается', () {
      final s = norm(const AppSettings().copyWith(
          captureMode: CaptureMode.systemProxy, alsoSetSystemProxy: true));
      expect(s.captureMode, CaptureMode.systemProxy);
      expect(s.alsoSetSystemProxy, isFalse);
    });

    test('обычная сборка режим не трогает', () {
      for (final mode in CaptureMode.values) {
        final s = norm(const AppSettings().copyWith(captureMode: mode),
            tun: true);
        expect(s.captureMode, mode);
      }
    });

    test('Android по-прежнему всегда TUN', () {
      final s = SettingsController.normalizeFor(
          const AppSettings().copyWith(captureMode: CaptureMode.systemProxy),
          android: true,
          tunAvailable: false);
      expect(s.captureMode, CaptureMode.tun);
    });
  });

  group('Серверы hysteria2 без sing-box', () {
    final hy2 = ShareLinkParser.tryParse(
        'hysteria2://pass@hy.example.com:8443?sni=hy.example.com#HY')!;
    final vless = ShareLinkParser.tryParse(
        'vless://id@a.example.com:443?type=tcp&security=tls#V')!;

    test('сборка без драйвера их не показывает', () {
      expect(hy2.core, ProxyCore.singbox);
      final shown =
          AppState.visibleServers([vless, hy2], singboxAvailable: false);
      expect(shown, [vless]);
    });

    test('обычная сборка показывает всё', () {
      expect(AppState.visibleServers([vless, hy2], singboxAvailable: true),
          [vless, hy2]);
    });
  });

  group('Интерфейс настроек без драйвера', () {
    final l = AppLocalizationsRu();
    late Directory tmp;
    late SettingsController settings;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_store_no_tun_');
      AppPaths.overrideRoot(tmp);
      settings = SettingsController();
    });

    tearDown(() {
      AppStoreInfo.tunAvailableOverride = null;
      settings.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget host(Set<String> ids) =>
        ChangeNotifierProvider<SettingsController>.value(
          value: settings,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(builder: (context) {
                final c = context.watch<SettingsController>();
                final all = buildSettingsSections(context, c.settings, c);
                return SettingsBody(
                  sections: all.where((s) => ids.contains(s.id)).toList(),
                  collapsed: const {},
                  onToggleSection: (_) {},
                );
              }),
            ),
          ),
        );

    Future<void> pump(WidgetTester t, Set<String> ids) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(880, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(ids));
      await t.pump();
    }

    testWidgets('выбора режима захвата нет — только системный прокси',
        (t) async {
      AppStoreInfo.tunAvailableOverride = false;
      await pump(t, {SettingsSectionIds.capture});
      expect(find.text(l.captureTun), findsNothing);
      expect(find.text(l.captureProxyOnly), findsNothing);
      expect(find.text(l.captureTunHint), findsNothing);
    });

    testWidgets('обычная сборка выбор режима показывает', (t) async {
      AppStoreInfo.tunAvailableOverride = true;
      await pump(t, {SettingsSectionIds.capture});
      expect(find.text(l.captureTun), findsWidgets);
    });

    testWidgets('«Держать TUN при смене сервера» скрыт', (t) async {
      AppStoreInfo.tunAvailableOverride = false;
      await pump(t, {SettingsSectionIds.seamless});
      expect(find.byKey(const Key('seamlessKeepTun')), findsNothing);
      expect(find.byKey(const Key('seamlessServerSwitch')), findsOneWidget);
    });

    testWidgets('kill switch без предложения перейти на TUN', (t) async {
      AppStoreInfo.tunAvailableOverride = false;
      unawaited(settings.update((s) => s.copyWith(
          killSwitch: true, autoReconnect: true,
          captureMode: CaptureMode.systemProxy)));
      await pump(t, {SettingsSectionIds.reliability});
      expect(find.byKey(const Key('killSwitchOfferTun')), findsNothing);
    });
  });
}
