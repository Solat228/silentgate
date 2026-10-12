import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';
import 'package:silentgate/ui/widgets/error_banner.dart';

/// Системное «убрать анимации» не должно сжимать таймеры уведомлений.
///
/// Flutter при `disableAnimations` умножает длительность обычного
/// `AnimationController` на 0,05. Полоска-таймер тоста — тоже контроллер,
/// и 6-секундное уведомление жило 0,3 с: на эмуляторе с нулевым масштабом
/// анимаций ошибка «QR не найден» приходила, а на экране не было ничего
/// (живой прогон 10.10.2026). Так же жил бы тост у человека, включившего
/// «Убрать анимацию» в спецвозможностях Android.
void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  setUp(() {
    AppToast.dismiss();
    AppToast.dismissProgress('reduced-motion');
  });

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  testWidgets('тост живёт свои 6 секунд и при «убрать анимации»',
      (tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(host(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => AppToast.show(context, 'QR не найден',
            kind: ToastKind.error),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('QR не найден'), findsOneWidget,
        reason: 'через 3 с из 6 уведомление обязано висеть');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('QR не найден'), findsNothing,
        reason: 'по истечении срока уведомление уходит');
  });

  testWidgets('итог карточки прогресса держится полный срок', (tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(host(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => AppToast.progress(context,
            id: 'reduced-motion', message: 'Пинг: готово', finished: true),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Пинг: готово'), findsOneWidget,
        reason: 'итог показывается 10 с, а не 0,5 с');

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Пинг: готово'), findsNothing);
  });

  testWidgets('баннер ошибки не закрывается раньше срока', (tester) async {
    reduceMotion(tester);
    var closed = false;
    await tester.pumpWidget(host(ErrorBanner('Ошибка', onClose: () {
      closed = true;
    })));
    await tester.pump(const Duration(seconds: 3));
    expect(closed, isFalse, reason: 'через 3 с из 6 баннер ещё открыт');
    await tester.pump(const Duration(seconds: 4));
    expect(closed, isTrue);
  });
}
