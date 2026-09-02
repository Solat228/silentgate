import 'dart:math' as math;
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/flag_cell.dart';

/// Дефект: в имени сервера бывает ДВА флага подряд (мост — вход/выход), а
/// FlagCell держал одну переменную `iso` и рисовал ровно один CountryFlag.
/// Проверяем настоящий FlagCell (не собранную копию вёрстки — на копиях в
/// этом проекте уже дважды обжигались).
///
/// ⚠️ Overflow и прочие ошибки рендера flutter_test ловит сам: необработанный
/// FlutterError, брошенный во время pumpWidget/pump, проваливает тест без
/// дополнительных проверок с нашей стороны.
void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('один флаг в имени — рисуется один CountryFlag', (t) async {
    await t.pumpWidget(host(const FlagCell('🇳🇱 Amsterdam')));
    await t.pump();
    expect(find.byType(CountryFlag), findsOneWidget);
  });

  testWidgets('два флага подряд в имени — рисуются два CountryFlag', (t) async {
    // Мост: вход NL, выход CZ — имя, а не реальный адрес сервера.
    await t.pumpWidget(host(const FlagCell('🇳🇱🇨🇿 Bridge')));
    await t.pump();
    expect(find.byType(CountryFlag), findsNWidgets(2));
  });

  testWidgets('без флагов — ни одного CountryFlag', (t) async {
    await t.pumpWidget(host(const FlagCell('Plain server name')));
    await t.pump();
    expect(find.byType(CountryFlag), findsNothing);
  });

  testWidgets('два флага — виджет укладывается в заданный размер без overflow',
      (t) async {
    await t.pumpWidget(host(
      const FlagCell('🇳🇱🇨🇿 Bridge', width: 34, height: 24),
    ));
    await t.pump();
    // takeException() возвращает пойманное исключение (overflow и т.п.) и
    // одновременно гасит его — без вызова тест провалился бы сам.
    expect(t.takeException(), isNull);
  });
  test('⚠️ УГОЛ РАЗРЕЗА СЧИТАЕТСЯ В ГРАДУСАХ, а не сверяется с константой',
      () {
    // ⚠️ ЗАЧЕМ ИМЕННО ГРАДУСЫ. Владелец дважды просил «флаги с большим
    // углом». Первая правка поставила долю 0.75, а комментарий рядом обещал
    // 50–60° — по факту выходило 43°, и разницы с прежними 35° человек не
    // увидел. Тест на равенство константы это пропустил бы: он проверял бы
    // ЧИСЛО, а обещание было про УГОЛ.
    //
    // Ячейка списка 34×24 — тот размер, на котором это и смотрят.
    const w = 34.0, h = 24.0;
    final deg = math.atan(h / (w * splitTopFraction)) * 180 / math.pi;
    expect(deg, greaterThanOrEqualTo(50),
        reason: 'разрез положе, чем просил владелец: ${deg.round()}°');
    expect(deg, lessThanOrEqualTo(60),
        reason: 'разрез круче запрошенного — верхний флаг снова теряет половину: ${deg.round()}°');
  });

  test('половины разреза опираются на ОДНУ долю — без щели и нахлёста', () {
    // Обе фигуры строятся от splitTopFraction. Разойдись они — между
    // половинами появилась бы полоска фона либо один флаг залез бы на другой.
    expect(splitTopFraction, greaterThan(0));
    expect(splitTopFraction, lessThan(1));
  });
}
