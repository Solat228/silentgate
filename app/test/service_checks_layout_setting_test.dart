import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// СТРАЖ НА ПЕРЕКЛЮЧАТЕЛЬ РАСКЛАДКИ ПРОВЕРОК СЕРВИСОВ (`ServiceChecksLayout`,
/// раздел «Оформление» в `settings_screen.dart`) — из BACKLOG.md, раздел
/// отложенных тестов вёрстки: ни у одного из пяти вариантов не было теста,
/// что выбор в выпадающем списке действительно доезжает до настройки.
///
/// ⚠️ Класс бага, который тут уже случался с другими полями («Связки
/// провайдеров и ленивость», «поле пишется, но не читается»): виджет
/// нарисован, выглядит рабочим, а нажатие ничего не делает — `onChanged`
/// не подключён или подключён не к тому полю. Компилятор такое не ловит.
void main() {
  final l = AppLocalizationsRu();

  late Directory tmp;
  late SettingsController settings;

  setUp(() {
    // ⚠️ Боевой `%APPDATA%` тестам недоступен (`AppPaths`) —
    // `tests-must-not-touch-real-appdata`.
    tmp = Directory.systemTemp.createTempSync('sg_service_checks_layout_');
    AppPaths.overrideRoot(tmp);
    settings = SettingsController();
  });

  tearDown(() {
    settings.dispose();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  void preset(AppSettings Function(AppSettings) mutate) {
    unawaited(settings.update(mutate));
  }

  /// Раздел «Оформление» настоящего [buildSettingsSections] — та же причина,
  /// что и в `settings_new_fields_ui_test.dart`: копия раскладки в тесте
  /// молчала бы про расхождение с тем, что видит пользователь.
  Widget host() => ChangeNotifierProvider<SettingsController>.value(
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
                sections: all
                    .where((s) => s.id == SettingsSectionIds.appearance)
                    .toList(),
                collapsed: const {},
                onToggleSection: (_) {},
              );
            }),
          ),
        ),
      );

  Future<void> pump(WidgetTester t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(880, 2400);
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    await t.pump();
  }

  /// Открыть выпадающий список и выбрать пункт с текстом [label].
  ///
  /// ⚠️ `.last`, А НЕ ОДИНОЧНЫЙ `find.text`. Текущее значение уже нарисовано
  /// закрытой кнопкой поля (например «Авто»); при открытии меню тот же текст
  /// появляется ВТОРОЙ раз внутри самого списка. Если выбираем пункт, который
  /// сейчас НЕ выбран, совпадение всё равно одно — но `.last` делает тест
  /// устойчивым и для случая, когда выбираемый пункт совпадает с текущим.
  Future<void> selectLayout(WidgetTester t, String label) async {
    await t.tap(find.byType(DropdownButtonFormField<ServiceChecksLayout>));
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  testWidgets('раздел есть, поле показывает текущее значение', (t) async {
    await pump(t);
    expect(settings.settings.serviceChecksLayout, ServiceChecksLayout.adaptive,
        reason: 'умолчание — adaptive (settings_roundtrip_test это стережёт)');
    expect(find.text(l.serviceChecksLayoutTitle), findsOneWidget);
    expect(find.text(l.serviceChecksLayoutAdaptive), findsOneWidget,
        reason: 'закрытое поле обязано показывать ТЕКУЩЕЕ значение');
  });

  testWidgets('выбор пункта доезжает до настройки', (t) async {
    await pump(t);
    await selectLayout(t, l.serviceChecksLayoutRows);
    expect(settings.settings.serviceChecksLayout, ServiceChecksLayout.rows,
        reason: 'нажатие на пункт списка не изменило настройку — та самая '
            'ловушка «выглядит рабочим, но onChanged не подключён»');
    expect(find.text(l.serviceChecksLayoutRows), findsOneWidget,
        reason: 'поле обязано перерисоваться с новым выбором');
  });

  testWidgets('каждый из пяти вариантов доезжает до настройки', (t) async {
    // Не один вариант, а ВСЕ: `onChanged` могло быть подключено к одному
    // конкретному значению вместо общего параметра `v`.
    const cases = [
      (ServiceChecksLayout.rows, 'serviceChecksLayoutRows'),
      (ServiceChecksLayout.sides, 'serviceChecksLayoutSides'),
      (ServiceChecksLayout.grid, 'serviceChecksLayoutGrid'),
      (ServiceChecksLayout.hidden, 'serviceChecksLayoutHidden'),
      (ServiceChecksLayout.adaptive, 'serviceChecksLayoutAdaptive'),
    ];
    final labels = {
      ServiceChecksLayout.rows: l.serviceChecksLayoutRows,
      ServiceChecksLayout.sides: l.serviceChecksLayoutSides,
      ServiceChecksLayout.grid: l.serviceChecksLayoutGrid,
      ServiceChecksLayout.hidden: l.serviceChecksLayoutHidden,
      ServiceChecksLayout.adaptive: l.serviceChecksLayoutAdaptive,
    };

    await pump(t);
    for (final (value, _) in cases) {
      await selectLayout(t, labels[value]!);
      expect(settings.settings.serviceChecksLayout, value,
          reason: 'вариант $value не доехал до настройки');
    }
  });

  testWidgets('значение переживает перезапись контроллера (нет опечатки в '
      'ключе copyWith)', (t) async {
    await pump(t);
    await selectLayout(t, l.serviceChecksLayoutGrid);
    expect(settings.settings.serviceChecksLayout, ServiceChecksLayout.grid);

    // Соседняя правка (тема) не должна откатывать раскладку проверок — если
    // бы `copyWith` в обработчике забыл про это поле, оно молча слетело бы к
    // умолчанию при следующем же сохранении настроек с диска.
    preset((s) => s.copyWith(themeMode: AppThemeMode.dark));
    await t.pump();
    expect(settings.settings.serviceChecksLayout, ServiceChecksLayout.grid,
        reason: 'несвязанная правка настроек стёрла выбранную раскладку');
  });
}
