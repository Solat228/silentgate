import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// Читаемость экрана настроек.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА, РАДИ КОТОРОЙ ЭТО СДЕЛАНО: «на винде нужно сделать
/// настройки более читаемыми, так как сейчас всё растягивается на всё
/// пространство и в итоге выглядит не очень; как искать версию — непонятно».
/// Ограничения ширины в экране не было вовсе: на широком окне подпись тянулась
/// через весь экран, а тумблер уезжал к правому краю.
void main() {
  SettingsSectionData section(String id, String title, List<SettingsRow> rows) =>
      SettingsSectionData(
          id: id, title: title, icon: Icons.settings, rows: rows);

  SettingsRow row(String search, String text) =>
      SettingsRow(search: search, build: (_) => ListTile(title: Text(text)));

  final sections = [
    section('about', 'О программе', [
      row('Версия SilentGate', 'Версия SilentGate'),
      row('HWID устройства', 'HWID устройства'),
    ]),
    section('network', 'Сеть', [
      row('Восстановить сеть', 'Восстановить сеть'),
    ]),
  ];

  // ⚠️ Делегаты локализации обязательны: экран берёт строки через
  // AppLocalizations.of(context) с nullable-getter:false, и без них падает на
  // проверке null ещё до первой отрисовки.
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  /// Задать ширину ОКНА, а не виджета.
  ///
  /// ⚠️ `SizedBox(width: 1400)` здесь не работает: поверхность теста по
  /// умолчанию 800×600, и родитель зажимает коробку до 800 — `LayoutBuilder`
  /// видит 800, порог бокового меню не срабатывает, а тест «на широком окне
  /// меню есть» падает, хотя код верен.
  void setWindow(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
  }

  group('Поиск — ответ на «как искать версию непонятно»', () {
    test('находит строку по подписи, а не только по заголовку раздела', () {
      final out = filterSettingsSections(sections, 'версия');
      expect(out, hasLength(1));
      expect(out.single.id, 'about');
      expect(out.single.rows, hasLength(1),
          reason: 'в разделе должна остаться только подходящая строка');
    });

    test('находит раздел по его названию', () {
      final out = filterSettingsSections(sections, 'сеть');
      expect(out.single.id, 'network');
      expect(out.single.rows, hasLength(1));
    });

    test('регистр и лишние пробелы не мешают', () {
      expect(filterSettingsSections(sections, '  ВЕРСИЯ '), hasLength(1));
    });

    test('пустой запрос отдаёт всё как есть', () {
      expect(filterSettingsSections(sections, '   '), same(sections));
    });

    test('ничего не найдено — пустой список, а не весь экран', () {
      expect(filterSettingsSections(sections, 'зюзюка'), isEmpty);
    });
  });

  group('Ширина содержимого ограничена', () {
    testWidgets('на широком окне строка не тянется во всю ширину',
        (tester) async {
      setWindow(tester, 1400);
      await tester.pumpWidget(host(SettingsBody(
        sections: sections,
        collapsed: const {},
        onToggleSection: (_) {},
      )));
      await tester.pump();

      final tile = tester.getSize(find.text('Версия SilentGate').first);
      expect(tile.width, lessThanOrEqualTo(kSettingsContentMaxWidth),
          reason: 'до правки подпись растягивалась на всё окно');
    });
  });

  group('Боковое меню разделов', () {
    testWidgets('на широком окне есть', (tester) async {
      setWindow(tester, 1400);
      await tester.pumpWidget(host(SettingsBody(
        sections: sections,
        collapsed: const {},
        onToggleSection: (_) {},
      )));
      await tester.pump();
      expect(find.byKey(const ValueKey('settings-rail')), findsOneWidget);
    });

    testWidgets('⚠️ на узком окне и на телефоне его НЕТ', (tester) async {
      // Иначе на 600 dp меню съело бы 240 и содержимому осталось бы меньше,
      // чем на телефоне в ландшафте.
      setWindow(tester, kSettingsSidebarMinWidth - 1);
      await tester.pumpWidget(host(SettingsBody(
        sections: sections,
        collapsed: const {},
        onToggleSection: (_) {},
      )));
      await tester.pump();
      expect(find.byKey(const ValueKey('settings-rail')), findsNothing);
    });
  });

  group('Сворачивание разделов', () {
    testWidgets('свёрнутый раздел не строит свои строки', (tester) async {
      setWindow(tester, 1400);
      await tester.pumpWidget(host(SettingsBody(
        sections: sections,
        collapsed: const {'about'},
        onToggleSection: (_) {},
      )));
      await tester.pump();
      expect(find.text('Версия SilentGate'), findsNothing);
      expect(find.text('Восстановить сеть'), findsOneWidget,
          reason: 'соседний раздел сворачиваться не должен');
    });

    test('по умолчанию всё развёрнуто — прямое решение владельца', () {
      expect(const AppSettings().collapsedSections, isEmpty);
    });

    test('свёрнутость переживает сохранение и чтение', () {
      const s = AppSettings(collapsedSections: ['about']);
      expect(AppSettings.fromJson(s.toJson()).collapsedSections, ['about'],
          reason: 'класс багов: поле пишется в toJson, но не читается обратно');
    });

    test('⚠️ раскладка интерфейса НЕ требует переподключения', () {
      // Попади она в причины — пользователь получал бы плашку
      // «переподключитесь» за то, что свернул раздел, а при живом канале это
      // ещё и предложение оборвать себе VPN.
      const a = AppSettings();
      expect(a.reconnectReasons(a.copyWith(collapsedSections: ['about'])),
          isEmpty);
    });
  });
}
