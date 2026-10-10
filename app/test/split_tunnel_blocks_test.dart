import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/settings/split_tunnel_counts.dart';
import 'package:silentgate/core/settings/split_tunnel_text.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_en.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/ui/widgets/rule_counts_text.dart';
import 'package:silentgate/ui/widgets/rule_import_dialog.dart';

/// Сводка, порядок блоков и диалог импорта.
///
/// ⚠️ ЖАЛОБА, ИЗ КОТОРОЙ ВЫРОС ЭТОТ ФАЙЛ (01.10.2026). Поле «Добавить сайт»
/// стояло НАД всем экраном, а не над своим списком, экспорт был JSON-ом, и
/// импорт молча заменял все правила. У человека с сотнями доменов это значит:
/// до нужного элемента надо прокрутить весь список, а вставить чужой кусок
/// списка нельзя вовсе.
void main() {
  group('formatRuleCounts: сводка в заголовке', () {
    final ru = AppLocalizationsRu();
    final en = AppLocalizationsEn();

    test('пустой список называется пустым, а не «всего 0»', () {
      expect(formatRuleCounts(ru, RuleCounts.empty), ru.splitCountEmpty);
    });

    test('⚠️ нулевые графы не пишутся', () {
      final s = formatRuleCounts(
          ru,
          countSiteRules(const [
            SiteRule('a.com', action: AppAction.tunnel),
            SiteRule('b.com', action: AppAction.tunnel),
          ]));
      expect(s, contains('2'));
      expect(s, isNot(contains(ru.splitCountBlock(0))),
          reason: 'перечень того, чего нет, прячет то, что есть');
      expect(s, isNot(contains(ru.splitCountOff(0))));
    });

    test('вкл/выкл появляются парой и только когда есть выключенные', () {
      const on = AppRule('a.exe', byName: true, action: AppAction.tunnel);
      const off =
          AppRule('b.exe', byName: true, action: AppAction.direct, enabled: false);
      expect(formatRuleCounts(ru, countAppRules(const [on])),
          isNot(contains(ru.splitCountOn(1))));
      final mixed = formatRuleCounts(ru, countAppRules(const [on, off]));
      expect(mixed, contains(ru.splitCountOn(1)));
      expect(mixed, contains(ru.splitCountOff(1)));
    });

    test('все графы разом — «всего 4 · вкл 3 · выкл 1 · …»', () {
      final s = formatRuleCounts(
          ru,
          countAppRules(const [
            AppRule('a.exe', byName: true, action: AppAction.tunnel),
            AppRule('b.exe', byName: true, action: AppAction.direct),
            AppRule('c.exe', byName: true, action: AppAction.block),
            AppRule('d.exe',
                byName: true, action: AppAction.tunnel, enabled: false),
          ]));
      for (final part in [
        ru.splitCountTotal(4),
        ru.splitCountOn(3),
        ru.splitCountOff(1),
        ru.splitCountTunnel(1),
        ru.splitCountDirect(1),
        ru.splitCountBlock(1),
      ]) {
        expect(s, contains(part));
      }
    });

    test('переводится, а не прибит к русскому', () {
      final s = formatRuleCounts(
          en, countSiteRules(const [SiteRule('a.com', action: AppAction.block)]));
      expect(s, contains(en.splitCountBlock(1)));
      expect(s, isNot(contains('блок')));
    });
  });

  group('⚠️ Добавление стоит НАД своим списком, а не под ним', () {
    // Порядок виджетов — требование владельца, а не вкусовщина: под списком из
    // сотен строк поле добавления недостижимо. Проверяем по исходнику экрана:
    // поднять весь экран в тесте нельзя (он требует живого AppState), а молча
    // вернуть поле вниз при следующем рефакторинге — можно.
    final src = File('lib/ui/split_tunnel_screen.dart').readAsStringSync();

    int at(String needle) {
      final i = src.indexOf(needle);
      expect(i, greaterThan(0), reason: 'в экране не найдено: $needle');
      return i;
    }

    test('приложения: заголовок → кнопки добавления → список', () {
      expect(at('title: l.splitAppsHeader'), lessThan(at('_appTools(')));
      expect(at('_appTools('), lessThan(at('...g.rules.map(')));
    });

    test('сайты: заголовок → поле → экспорт/импорт → список', () {
      final header = at('title: l.splitSitesHeader');
      final field = at('_AddSiteField(controller: controller)');
      final tools = at('_siteTools(');
      final list = at('...siteTreeRows(');
      expect(header, lessThan(field));
      expect(field, lessThan(tools));
      expect(tools, lessThan(list));
    });

    test('⚠️ JSON-экспорта больше нет', () {
      expect(src, isNot(contains('SplitTunnelBackup')),
          reason: 'владелец просил простой список, одна строка — одно правило');
    });

    test('списки скрываются по сохранённому флагу', () {
      expect(src, contains('if (!controller.settings.splitAppsCollapsed)'));
      expect(src, contains('if (!controller.settings.splitSitesCollapsed)'));
    });
  });

  group('Диалог импорта', () {
    const current = [
      SiteRule('a.com', action: AppAction.tunnel),
      SiteRule('b.com', action: AppAction.direct),
    ];

    late RuleImportResult<SiteRule>? result;

    Future<void> pump(WidgetTester tester) async {
      result = null;
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result =
                      await showDialog<RuleImportResult<SiteRule>>(
                    context: context,
                    builder: (_) => RuleImportDialog<SiteRule>(
                      title: 'Импорт сайтов',
                      parse: (t) =>
                          parseSiteRules(t, defaultAction: AppAction.tunnel),
                      plan: (incoming) => planSiteMerge(current, incoming),
                      apply: (p, {required overwrite}) => applySiteMerge(
                          current, p,
                          overwriteConflicts: overwrite),
                      label: (s) => s.label,
                      describe: (s) => s.action.name,
                    ),
                  );
                },
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ пустой текст: обе кнопки заблокированы', (tester) async {
      await pump(tester);
      final add = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(add.onPressed, isNull,
          reason: 'импорт «ничего» выглядел бы как «импорт съел правила»');
      final replace = tester.widget<TextButton>(
          find.widgetWithText(TextButton, AppLocalizationsRu().splitImportReplaceAll));
      expect(replace.onPressed, isNull);
    });

    testWidgets('голый список доменов добавляется к существующим',
        (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'c.com\nd.com');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.replaced, isFalse);
      expect(result!.added, 2);
      expect(result!.rules.map((s) => s.domain),
          ['a.com', 'b.com', 'c.com', 'd.com']);
    });

    testWidgets('«Заменить всё» отдаёт только разобранное', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'only.com');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          TextButton, AppLocalizationsRu().splitImportReplaceAll));
      await tester.pumpAndSettle();

      expect(result!.replaced, isTrue);
      expect(result!.rules.map((s) => s.domain), ['only.com']);
    });

    testWidgets('⚠️ спор виден до нажатия и слушается переключателя',
        (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '[block]\nb.com');
      await tester.pumpAndSettle();

      final l = AppLocalizationsRu();
      expect(find.textContaining(l.splitImportStatConflict(1)), findsOneWidget,
          reason: 'молчаливая перезапись чужих правок — это и была жалоба');

      // По умолчанию перезаписываем; выключаем — старое правило цело.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final add = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(add.onPressed, isNull,
          reason: 'нечего применять: новых нет, спорные решено не трогать');
    });

    testWidgets('перезапись спорного меняет действие', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '[block]\nb.com');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(result!.overwritten, 1);
      expect(result!.rules.firstWhere((s) => s.domain == 'b.com').action,
          AppAction.block);
    });

    testWidgets('неразобранные строки показываются человеку', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'мой список\nc.com');
      await tester.pumpAndSettle();
      expect(find.text('мой список'), findsOneWidget);
      expect(find.textContaining(AppLocalizationsRu().splitImportStatBad(1)),
          findsOneWidget);
    });

    testWidgets('«Вставить из буфера» дописывает, а не затирает набранное',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'from-clipboard.com'};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pump(tester);
      await tester.enterText(find.byType(TextField), 'typed.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsRu().splitImportPasteClipboard));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result!.rules.map((s) => s.domain),
          containsAll(['typed.com', 'from-clipboard.com']));
    });
  });
}
