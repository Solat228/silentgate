import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';

/// Уведомление с отменой («Подписка удалена — Восстановить»).
///
/// Просьба владельца 26.10.2026: кнопка на ПРОТИВОПОЛОЖНОЙ от крестика
/// стороне, и уведомление гаснет само ВСЕГДА через 10 с — обычный тост с
/// кнопкой висит до нажатия, и для отмены это не годится.
void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  setUp(AppToast.dismiss);

  Future<void> showUndo(WidgetTester tester, VoidCallback onAction) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => AppToast.undo(
          Overlay.maybeOf(context),
          'Подписка «Тест» удалена',
          actionLabel: 'Восстановить',
          onAction: onAction,
        ),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }

  testWidgets('гаснет само через 10 с, хотя у него есть кнопка',
      (tester) async {
    await showUndo(tester, () {});

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Подписка «Тест» удалена'), findsOneWidget,
        reason: 'через 9 с из 10 уведомление обязано висеть');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Подписка «Тест» удалена'), findsNothing,
        reason: 'отмена не висит до нажатия — через 10 с её нет');
  });

  testWidgets('кнопка слева, крестик справа', (tester) async {
    await showUndo(tester, () {});

    final action = tester.getCenter(find.text('Восстановить'));
    final close = tester.getCenter(find.byIcon(Icons.close));
    final message = tester.getCenter(find.text('Подписка «Тест» удалена'));
    expect(action.dx, lessThan(message.dx),
        reason: 'кнопка — в начале строки');
    expect(close.dx, greaterThan(message.dx),
        reason: 'крестик — в конце строки');
  });

  testWidgets('нажатие зовёт действие и снимает уведомление', (tester) async {
    var restored = 0;
    await showUndo(tester, () => restored++);

    await tester.tap(find.text('Восстановить'));
    await tester.pumpAndSettle();
    expect(restored, 1);
    expect(find.text('Подписка «Тест» удалена'), findsNothing);
  });

  testWidgets('без оверлея молчит, а не падает', (tester) async {
    AppToast.undo(null, 'x', actionLabel: 'y', onAction: () {});
  });
}
