import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/info_tooltip.dart';

/// Правка 10.09.2026: `serviceChecksInfo` переписан с одного абзаца на пять
/// блоков по пунктам (жалоба владельца — читать по пунктам, не блоком текста).
/// Текст заметно длиннее прежнего абзаца, а показывает его `InfoTooltip` в
/// `AlertDialog` — задание требовало явно проверить, не переполняет ли он
/// диалог на тесном окне.
///
/// ⚠️ ПРОВЕРЕНО ВРУЧНУЮ (не только этим файлом), и вот почему тест ниже
/// устроен именно так. `AlertDialog` без `scrollable: true` не бросает
/// `RenderFlex overflowed` на слишком высокий `content` — сам текст просто
/// МОЛЧА ОБРЕЗАЕТСЯ до доступной высоты (проверено синтетическим текстом
/// в 60 строк на разных размерах окна: `tester.takeException()` оставался
/// `null` вплоть до ~150 px высоты, где уже переполняются заголовок и кнопки,
/// а вовсе не наш текст). Значит для ЭТОГО текста при 964×500 ×1.3
/// `takeException()` в принципе не покажет «переполнение» даже без обёртки —
/// это не тест на пиксельный overflow, а тест на то, что содержимое ВООБЩЕ
/// ДОСТИЖИМО целиком, то есть на факт наличия `SingleChildScrollView`.
void main() {
  /// Прогоняем ВСЕ десять языков: длина текста разная (zh короче ru втрое,
  /// fr — длиннее из-за пробелов перед «:»), и самый рискованный язык
  /// заранее не угадать — уже ошибались с этим на других экранах.
  Future<void> openDialog(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(964, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Масштаб шрифта ×1.3 — «крупный текст» из системных настроек
      // доступности, тот же множитель, что владелец просил проверить.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Builder(builder: (context) {
        final l = AppLocalizations.of(context);
        return Scaffold(
          body: Center(
            child:
                InfoTooltip(l.serviceChecksInfo, title: l.serviceChecksTitle),
          ),
        );
      }),
    ));
    await tester.pump();

    await tester.tap(find.byType(InfoTooltip));
    await tester.pumpAndSettle();
  }

  for (final locale in AppLocalizations.supportedLocales) {
    final code = locale.languageCode;
    testWidgets(
        '$code: диалог пояснения открывается на 964×500 при масштабе ×1.3 '
        'без исключений слоя', (tester) async {
      await openDialog(tester, locale);

      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'диалог пояснения не открылся');
      expect(tester.takeException(), isNull,
          reason: 'открытие диалога пояснения "$code" бросило исключение '
              'при раскладке на тесном окне');
    });
  }

  // ⚠️ ГЛАВНЫЙ СТРАЖ ЭТОГО ФАЙЛА. Именно эта проверка мутируется: убери
  // `SingleChildScrollView` в `info_tooltip.dart` — и тест ниже покраснеет
  // первым, ещё ДО всякой пиксельной раскладки. Без него длинный (пять
  // блоков вместо абзаца) текст, обрезанный до размера окна, был бы
  // НЕДОЧИТЫВАЕМ ЦЕЛИКОМ и никак не сигналил бы об этом — ни ассертом,
  // ни визуально отличимой от «текст просто короткий» картиной.
  testWidgets(
      'содержимое диалога пояснения обёрнуто в SingleChildScrollView '
      '(текст достижим целиком, а не обрезан молча)', (tester) async {
    await openDialog(tester, const Locale('ru'));

    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView)),
        findsOneWidget,
        reason: 'AlertDialog.content должен быть прокручиваемым — иначе '
            'длинный текст пояснения молча обрежется на тесном окне '
            '(AlertDialog НЕ бросает overflow-исключение на это, проверено)');
  });
}
