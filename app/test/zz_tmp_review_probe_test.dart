// ВРЕМЕННЫЙ файл ревью — проверка нажатия по заголовку раздела настроек.
// Удаляется сразу после прогона.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/settings_screen.dart';

void main() {
  final sections = [
    SettingsSectionData(
      id: 'about',
      title: 'О программе',
      icon: Icons.info_outline,
      rows: [
        SettingsRow(
            search: 'Версия SilentGate',
            build: (_) => const ListTile(title: Text('Версия SilentGate'))),
      ],
    ),
  ];

  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('нажатие ПО ТЕКСТУ заголовка сворачивает раздел',
      (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(host(SettingsBody(
      sections: sections,
      collapsed: const {},
      onToggleSection: toggled.add,
    )));
    await tester.pump();
    await tester.tap(find.text('О программе'));
    await tester.pump();
    expect(toggled, ['about'], reason: 'тап по самому заголовку');
  });

  testWidgets('нажатие по стрелке сворачивает раздел', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(host(SettingsBody(
      sections: sections,
      collapsed: const {},
      onToggleSection: toggled.add,
    )));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pump();
    expect(toggled, ['about'], reason: 'тап по стрелке');
  });
}
