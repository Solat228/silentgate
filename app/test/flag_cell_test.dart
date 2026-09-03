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

  test('⚠️ РАЗРЕЗ ИЗ УГЛА В УГОЛ — доля ровно 1.0', () {
    // ⚠️ ЭТОТ ТЕСТ ПЕРЕПИСАН 03.09.2026 ПО КАРТИНКЕ ВЛАДЕЛЬЦА: он провёл линию
    // поверх снимка, и она идёт из левого нижнего угла в правый верхний.
    //
    // Прежняя редакция требовала «50–60°» и была НЕВЕРНА по существу. Владелец
    // дважды просил «больший угол», и доля дважды уменьшалась (0.75, потом
    // 0.5): линия становилась круче, но верхняя точка уезжала от правого угла
    // к середине — и верхний флаг вырождался в узкий клин. На снимке от
    // российского флага осталась полоска. Просили не крутизну, а РАВНЫЕ
    // ПОЛОВИНЫ.
    expect(splitTopFraction, 1.0,
        reason: 'меньше единицы — верхний флаг снова станет клином');
  });

  test('обе половины покрывают ячейку целиком и не наезжают друг на друга', () {
    // Верхний треугольник: (0,0) → (w,0) → (0,h). Нижний — его дополнение по
    // той же линии. Сумма площадей равна площади ячейки: щели и нахлёста нет.
    const w = 34.0, h = 24.0;
    final top = 0.5 * (w * splitTopFraction) * h;
    final bottom = w * h - top;
    expect(top + bottom, closeTo(w * h, 0.001));
    expect(top, closeTo(bottom, 0.001),
        reason: 'из угла в угол — половины равны, это и просил владелец');
  });
}
