import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/backup/settings_bundle.dart';
import 'package:silentgate/data/settings_backup.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/settings_backup_actions.dart';

/// Окна экспорта и импорта настроек (P11).
///
/// Главное, что стережётся: человек видит, что в файл уходят ключи доступа
/// к VPN, ДО того, как файл создан, и при импорте понимает, заменятся ли его
/// подписки. Ответ окна — это и есть решение, которое уйдёт в
/// `SettingsBackup`, поэтому проверяется возвращаемое значение.
void main() {
  Future<Future<T?>> open<T>(WidgetTester tester, Widget dialog) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    final result = showDialog<T>(context: ctx, builder: (_) => dialog);
    await tester.pumpAndSettle();
    return result;
  }

  AppLocalizations l10n(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(AlertDialog)));

  group('Экспорт', () {
    testWidgets('по умолчанию с подписками и с предупреждением о ключах',
        (tester) async {
      final result = await open<bool>(tester, const ExportSettingsDialog());
      final l = l10n(tester);
      expect(find.text(l.backupExportSubsWarning), findsOneWidget);
      expect(find.text(l.backupExportDeviceNote), findsOneWidget);
      await tester.tap(find.text(l.backupExportAction));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('сняли галочку — предупреждение уходит, ответ false',
        (tester) async {
      final result = await open<bool>(tester, const ExportSettingsDialog());
      final l = l10n(tester);
      await tester.tap(find.byKey(const ValueKey('backup-export-subs')));
      await tester.pumpAndSettle();
      expect(find.text(l.backupExportSubsWarning), findsNothing);
      expect(find.text(l.backupExportNoSubsNote), findsOneWidget);
      await tester.tap(find.text(l.backupExportAction));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('«Отмена» не экспортирует ничего', (tester) async {
      final result = await open<bool>(tester, const ExportSettingsDialog());
      await tester.tap(find.text(l10n(tester).commonCancel));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('Импорт', () {
    BundleContents bundle({required String platform, bool subs = true}) =>
        BundleContents(
          platform: platform,
          appVersion: '1.17.0',
          createdAt: DateTime.utc(2026, 10, 20, 7, 30),
          files: {
            SettingsBundle.settingsFile: {'themeMode': 'dark'},
            if (subs)
              SettingsBundle.subscriptionsFile: {
                'activeId': 'a',
                'items': [
                  {'id': 'a'},
                  {'id': 'b'},
                ],
              },
          },
        );

    testWidgets('показывает число подписок и по умолчанию их заменяет',
        (tester) async {
      final result = await open<bool>(tester,
          ImportSettingsDialog(bundle: bundle(platform: SettingsBackup.platform)));
      final l = l10n(tester);
      expect(find.text(l.backupImportSubsCount(2)), findsOneWidget);
      expect(find.text(l.backupImportOtherPlatform), findsNothing);
      await tester.tap(find.text(l.backupImportAction));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('можно оставить свои подписки', (tester) async {
      final result = await open<bool>(tester,
          ImportSettingsDialog(bundle: bundle(platform: SettingsBackup.platform)));
      final l = l10n(tester);
      await tester.tap(find.byKey(const ValueKey('backup-import-subs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.backupImportAction));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('файл другой платформы — сказано, что останется прежним',
        (tester) async {
      final other =
          SettingsBackup.platform == 'windows' ? 'android' : 'windows';
      await open<bool>(tester, ImportSettingsDialog(bundle: bundle(platform: other)));
      expect(find.text(l10n(tester).backupImportOtherPlatform), findsOneWidget);
    });

    testWidgets('без подписок в файле — галочки нет, ответ false',
        (tester) async {
      final result = await open<bool>(
          tester,
          ImportSettingsDialog(
              bundle: bundle(platform: SettingsBackup.platform, subs: false)));
      final l = l10n(tester);
      expect(find.byKey(const ValueKey('backup-import-subs')), findsNothing);
      await tester.tap(find.text(l.backupImportAction));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });

  // Пока открыто системное окно выбора файла, экран настроек пересобирается,
  // и элемент строки создаётся заново. Импорт, державшийся за контекст
  // строки, молча обрывался после выбора файла (найдено живьём в эмуляторе).
  testWidgets('контекст действия переживает пересоздание строки',
      (tester) async {
    late BuildContext row;
    Widget screen(Key rowKey) => MaterialApp(
          home: Scaffold(
            body: Builder(
              key: rowKey,
              builder: (c) {
                row = c;
                return const SizedBox();
              },
            ),
          ),
        );
    await tester.pumpWidget(screen(const ValueKey('a')));
    final firstRow = row;
    final host = backupActionHost(firstRow);
    await tester.pumpWidget(screen(const ValueKey('b')));
    expect(firstRow.mounted, isFalse);
    expect(host.mounted, isTrue);
  });

  test('имя файла экспорта — с датой и своим расширением', () {
    expect(SettingsBackup.exportFileName(DateTime(2026, 10, 20, 9, 5)),
        'SilentGate-settings-20261020-0905.sgsettings');
  });
}
