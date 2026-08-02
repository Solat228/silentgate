import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/ui/layout/adaptive.dart';

/// Страж вёрстки. Ловит класс багов, который не видят ни компилятор, ни
/// `flutter analyze`: разметка валидна, тесты логики зелёные, а на телефоне
/// диалог рвётся жёлто-чёрными полосами.
///
/// Проверяются два инварианта, на которых держатся все правки:
///  1. `adaptiveDialogBody` НИКОГДА не отдаёт больше, чем есть на экране;
///  2. на окне Windows (не меньше 980×800) он отдаёт РОВНО запрошенное — то
///     есть десктоп не меняется. Это не надежда, а арифметика, и она должна
///     оставаться верной после любой будущей правки.
void main() {
  /// Прогон при заданном размере экрана и высоте клавиатуры.
  Future<Size> measure(
    WidgetTester tester, {
    required Size screen,
    double keyboard = 0,
    required double reqWidth,
    required double reqHeight,
  }) async {
    late Size got;
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(
        size: screen,
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          final w = adaptiveDialogBody(context,
              width: reqWidth, height: reqHeight, child: const SizedBox());
          got = Size((w as SizedBox).width!, w.height!);
          return w;
        }),
      ),
    ));
    return got;
  }

  group('Тело диалога не выходит за экран', () {
    testWidgets('телефон 360×640 с клавиатурой: высота обрезается', (t) async {
      final got = await measure(t,
          screen: const Size(360, 640),
          keyboard: 300,
          reqWidth: 440,
          reqHeight: 480);
      // 640 − 300 (клавиатура) − 164 (инсеты+заголовок+кнопки) = 176.
      expect(got.height, lessThan(480),
          reason: 'запрошенные 480 в 176 не влезают — это и есть overflow');
      expect(got.height, greaterThan(0));
      expect(got.width, lessThanOrEqualTo(360 - 80),
          reason: 'диалог не может быть шире экрана минус его же отступы');
    });

    testWidgets('телефон без клавиатуры: высота всё равно ограничена',
        (t) async {
      final got = await measure(t,
          screen: const Size(360, 640), reqWidth: 440, reqHeight: 480);
      expect(got.height, lessThanOrEqualTo(640 - 164));
    });

    testWidgets('высота не схлопывается в ноль на крошечном экране', (t) async {
      final got = await measure(t,
          screen: const Size(360, 400),
          keyboard: 300,
          reqWidth: 440,
          reqHeight: 480);
      expect(got.height, greaterThanOrEqualTo(120),
          reason: 'иначе вместо обрезанного диалога получили бы пустую полоску');
    });
  });

  group('Десктоп не меняется — это арифметика, а не надежда', () {
    testWidgets('окно 980×800 отдаёт РОВНО запрошенное', (t) async {
      for (final req in const [
        Size(440, 480), // пикер приложений
        Size(600, 480), // редактор JSON
        Size(640, 420), // лог TUN
        Size(520, 420), // лицензии
      ]) {
        final got = await measure(t,
            screen: const Size(980, 800),
            reqWidth: req.width,
            reqHeight: req.height);
        expect(got, req,
            reason: 'на минимальном окне Windows размеры обязаны совпадать '
                'байт в байт со старым поведением');
      }
    });
  });

  group('Классы экрана', () {
    testWidgets('пороги ширины', (t) async {
      Future<SgWidth> at(double w) async {
        late SgWidth got;
        await t.pumpWidget(MediaQuery(
          data: MediaQueryData(size: Size(w, 800)),
          child: Builder(builder: (c) {
            got = c.sg.width;
            return const SizedBox();
          }),
        ));
        return got;
      }

      expect(await at(360), SgWidth.compact);
      expect(await at(599), SgWidth.compact);
      expect(await at(600), SgWidth.medium);
      expect(await at(839), SgWidth.medium);
      expect(await at(840), SgWidth.expanded);
      expect(await at(980), SgWidth.expanded,
          reason: 'минимальное окно Windows обязано быть expanded — на этом '
              'держится вся оценка риска для десктопа');
    });

    testWidgets('клавиатура переводит экран в short', (t) async {
      late SgHeight got;
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
        child: Builder(builder: (c) {
          got = c.sg.height;
          return const SizedBox();
        }),
      ));
      expect(got, SgHeight.short,
          reason: 'ради этого случая отдельная ось высоты и заводилась');
    });
  });
}
