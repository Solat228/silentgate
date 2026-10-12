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

  testWidgets('пара флагов шире одного в 1.15 раза, одиночный — прежний',
      (t) async {
    await t.pumpWidget(host(const Column(mainAxisSize: MainAxisSize.min, children: [
      FlagCell('🇺🇸🇩🇪 Bridge', key: ValueKey('pair'), width: 28, height: 20),
      FlagCell('🇺🇸 USA', key: ValueKey('one'), width: 28, height: 20),
    ])));
    await t.pump();
    expect(t.getSize(find.byKey(const ValueKey('pair'))).width,
        closeTo(28 * 1.15, 0.01));
    expect(t.getSize(find.byKey(const ValueKey('one'))).width, 28);
  });

  test('⚠️ решение владельца 25.09: ширина 1.15, наклон как у 25 %', () {
    // Не «улучшать»: владелец прямо запретил и делать разрез круче, и
    // вставлять зазор между флагами.
    expect(kFlagPairWidthFactor, 1.15);
    expect(kFlagPairCutOffset, 0.25);
    const fw = 28.0;
    final g = FlagPairGeometry.of(fw);
    expect(g.cutTop - g.cutBottom, closeTo(0.5 * fw, 0.001),
        reason: 'наклон как у прежних 25 %: (1 − 2·0.25)·ширина');
  });

  test('каждый флаг показан с начала и без зазора между ними', () {
    const fw = 28.0;
    final g = FlagPairGeometry.of(fw);
    // Первый флаг дотягивается до верхней точки разреза — иначе справа от
    // него была бы пустота.
    expect(g.cutTop, lessThanOrEqualTo(fw));
    // Второй начинается ровно в нижней точке разреза: левее — прятал бы
    // своё начало, правее — зазор.
    expect(g.secondLeft, g.cutBottom);
    // И дотягивается до правой грани ячейки.
    expect(g.secondLeft + fw, greaterThanOrEqualTo(g.cellWidth));
  });
}
