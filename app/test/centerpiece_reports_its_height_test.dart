import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';
import 'package:silentgate/ui/widgets/site_favicon.dart';

/// БЛОК ОБЯЗАН ЗАНИМАТЬ РОВНО СТОЛЬКО, СКОЛЬКО РИСУЕТ.
///
/// ⚠️ ЖИВОЙ СНИМОК ИЗ VM 04.09.2026: подпись «Доступность сервисов проверена
/// без VPN» и значок настроек легли ПОВЕРХ последнего ряда правых значков.
/// Всё, что идёт под блоком, ставится сразу за его границей — значит блок
/// сообщает о себе высоту МЕНЬШЕ, чем занимает на самом деле, и следующая
/// строка садится ему на голову.
///
/// ⚠️ ПОЧЕМУ ЭТОГО НЕ ЛОВИЛ НИ ОДИН СТРАЖ. Все прежние проверки вёрстки ищут
/// `RenderFlex overflowed` — исключение, которое Flutter бросает, когда
/// содержимое НЕ ПОМЕСТИЛОСЬ в отведённое место. Здесь оно не бросается вовсе:
/// места блоку никто не ограничивал, он честно нарисовал что хотел и честно
/// соврал о своём размере. Наложение и переполнение — разные беды, и вторая
/// проверка первую не заменяет.
void main() {
  Widget host({required double width, required List<ProbeService> services}) =>
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConnectCenterpiece(
                      serverName: 'Германия 2.4',
                      httpPort: 0,
                      button: const SizedBox(
                          key: Key('btn'), width: 148, height: 148),
                      services: services,
                      layout: ServiceChecksLayout.sides,
                    ),
                    // То, что в приложении идёт СРАЗУ под блоком: именно на
                    // него и наехали значки.
                    const Text('подпись под блоком', key: Key('below')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  /// Самая нижняя точка, до которой блок реально дорисовал значок сервиса.
  double lowestIcon(WidgetTester t) {
    var low = double.negativeInfinity;
    for (final e in find.byType(SiteFavicon).evaluate()) {
      final r = t.getRect(find.byWidget(e.widget));
      if (r.bottom > low) low = r.bottom;
    }
    return low;
  }

  testWidgets('⚠️ ПОД ПОТОЛКОМ ВЫСОТЫ блок жмётся, а не рисует поверх', (t) async {
    // Панель отдаёт блоку 237 px (замерено на живом окне), а сетке из пяти
    // групп нужно около 266. Под потолком блок обязан СЖАТЬСЯ — он это
    // умеет, — а не нарисовать лишнее поверх того, что идёт ниже.
    t.view.physicalSize = const Size(700, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<ServiceCheckController>(
        create: (_) => ServiceCheckController(),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 584,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 237),
                    child: ConnectCenterpiece(
                      serverName: 'Германия 2.4',
                      httpPort: 0,
                      button: const SizedBox(
                          key: Key('btn'), width: 148, height: 148),
                      services: ServiceChecks.catalog,
                      layout: ServiceChecksLayout.sides,
                    ),
                  ),
                  const Text('подпись под блоком', key: Key('below')),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);

    final below = t.getRect(find.byKey(const Key('below')));
    final low = lowestIcon(t);
    expect(low, lessThanOrEqualTo(below.top + 0.5),
        reason: 'под потолком 237 px блок нарисовал значки до '
            '${low.toStringAsFixed(0)}, а строка ниже начинается на '
            '${below.top.toStringAsFixed(0)}');
  });

  for (final n in const [14, 9, 5, 1]) {
    testWidgets('⚠️ $n сервисов: строка под блоком не садится на значки',
        (t) async {
      t.view.physicalSize = const Size(700, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
          host(width: 584, services: ServiceChecks.catalog.take(n).toList()));
      await t.pump();
      expect(t.takeException(), isNull);

      final below = t.getRect(find.byKey(const Key('below')));
      final low = lowestIcon(t);
      expect(low, isNot(double.negativeInfinity),
          reason: 'ни одного значка не нашлось — тест выродился');
      expect(low, lessThanOrEqualTo(below.top + 0.5),
          reason: 'значок дорисован до ${low.toStringAsFixed(0)}, а строка под '
              'блоком начинается на ${below.top.toStringAsFixed(0)} — наложение '
              'на ${(low - below.top).toStringAsFixed(0)} px');
    });
  }

  testWidgets('⚠️ блок берёт СВОЮ высоту, а не весь выданный потолок',
      (t) async {
    // Найдено ревью 05.09.2026. Потолок приходит `ConstrainedBox`-ом и
    // доводится цепочкой `Flexible` с нежёсткой посадкой; блок заполнял его
    // целиком, потому что корнем стоял `SizedBox(height: потолок)`.
    //
    // Замер тогда дал: потолок 486 px, содержимое 186 — и 190 px пустоты
    // между последним значком и строкой под блоком, из-за которых низ панели
    // уезжал за край. Потолок это «больше нельзя», а не «займи столько», и
    // разница видна ровно в самом частом случае — когда сервисов немного.
    t.view.physicalSize = const Size(1200, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);

    Future<double> heightUnder(double ceiling) async {
      await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 584, maxHeight: ceiling),
                child: ConnectCenterpiece(
                  serverName: 'Германия 2.4',
                  httpPort: 0,
                  button: const SizedBox(
                      key: Key('btn'), width: 148, height: 148),
                  services: const [
                    ProbeService.youtube,
                    ProbeService.telegram,
                    ProbeService.chatgpt,
                  ],
                  layout: ServiceChecksLayout.sides,
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      return t.getSize(find.byType(ConnectCenterpiece)).height;
    }

    final tight = await heightUnder(300);
    final loose = await heightUnder(700);
    expect(loose, closeTo(tight, 1.0),
        reason: 'при вдвое большем потолке блок стал выше на '
            '${(loose - tight).toStringAsFixed(0)} px — значит он съедает '
            'потолок целиком, а не занимает своё');
    expect(loose, lessThan(700),
        reason: 'блок занял весь выданный потолок');
  });

  testWidgets('⚠️ рост до потолка 1,6 больше не зажимается высотой блока',
      (t) async {
    // Найдено разведкой 08.09.2026: `boxHeight` считался по НЕМАСШТАБИРОВАННОЙ
    // высоте стороны ДО вычисления `k`, и `SizedBox(h·k)` внутри зажимался
    // строкой этой высоты. Фактический потолок роста был
    // `max(148, tallest) / tallest` — то есть ровно 1,0 при любой стороне
    // выше кнопки, а это все раскладки с пятью группами. `_maxGrow = 1.6`
    // существовал в коде и не работал НИ РАЗУ.
    //
    // Здесь места с избытком по обеим осям: панель 1200 (по 512 на сторону
    // при 174 нужных) и высота 700 (при 320 нужных). Значок обязан вырасти
    // до 26 × 1,6.
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<ServiceCheckController>(
        create: (_) => ServiceCheckController(),
        child: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 1200,
              height: 700,
              child: ServiceChecksSides(
                services: ServiceChecks.catalog,
                httpPort: 0,
                button: SizedBox(
                    key: Key('btn'), width: 148, height: 148),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    final icon = t.getRect(find
        .descendant(
            of: find.byKey(const ValueKey('svc:telegram')),
            matching: find.byType(SiteFavicon))
        .first);
    expect(icon.width, closeTo(26 * 1.6, 0.5),
        reason: 'значок ${icon.width.toStringAsFixed(1)} px при свободном '
            'месте — рост снова зажат');
    // И кнопка при этом не растёт: её размер задаёт панель.
    expect(t.getSize(find.byKey(const Key('btn'))), const Size(148, 148));
  });
}
