import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/app_info.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/whats_new_badge.dart';

void main() {
  late Directory tmp;
  late SettingsController settings;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sg_whats_new_test_');
    AppPaths.overrideRoot(tmp);
    HeaderVersionBadge.enableAutoPopupInTests = false;
    HeaderVersionBadge.resetAutoPopupStateForTest();
    settings = SettingsController();
    await settings.init();
  });

  tearDown(() async {
    HeaderVersionBadge.enableAutoPopupInTests = false;
    HeaderVersionBadge.resetAutoPopupStateForTest();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(title: child),
        ),
      ),
    );
  }

  testWidgets(
      'показывает колокольчик для новой версии, по клику открывает «Что нового» и гасит колокольчик',
      (tester) async {
    expect(settings.settings.lastSeenWhatsNewVersion, isNull);

    await tester.pumpWidget(wrap(const HeaderVersionBadge()));
    await tester.pump();

    expect(find.byKey(const Key('headerVersionBadgeButton')), findsOneWidget);
    expect(find.byKey(const Key('headerVersionBellIcon')), findsOneWidget);
    expect(find.text('v${AppInfo.fullVersion}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('headerVersionBadgeButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aboutVersionPatchesDialog')), findsOneWidget);
    expect(
      settings.settings.lastSeenWhatsNewVersion,
      AppInfo.fullVersion,
    );

    // Галочка «Больше не показывать автоматически после обновления»
    await tester.tap(find.byKey(const Key('whatsNewAutoShowCheckbox')));
    await tester.pumpAndSettle();
    expect(settings.settings.showWhatsNewOnUpdate, isFalse);

    await tester.tap(find.byKey(const Key('whatsNewCloseButton')));
    await tester.pumpAndSettle();

    // После прочтения колокольчик погас
    expect(find.byKey(const Key('headerVersionBellIcon')), findsNothing);
  });

  testWidgets(
      'автоматически открывает окно «Что нового» при первом запуске новой версии, если включено',
      (tester) async {
    HeaderVersionBadge.enableAutoPopupInTests = true;
    HeaderVersionBadge.resetAutoPopupStateForTest();

    await tester.pumpWidget(wrap(const HeaderVersionBadge()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('aboutVersionPatchesDialog')), findsOneWidget);
    expect(
      settings.settings.lastSeenWhatsNewVersion,
      AppInfo.fullVersion,
    );
  });
}
