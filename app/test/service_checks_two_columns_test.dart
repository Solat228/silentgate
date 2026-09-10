import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// СЕТКА ПРОВЕРОК — РОВНО ДВЕ КОЛОНКИ, ДО ТРЁХ РЯДОВ НА СТОРОНУ.
///
/// ⚠️ Требование владельца (08.09.2026): «Колонки могут быть в ширину только
/// 2 колонки. В высоту строки могут быть до 3-ёх штук». До этого число блоков
/// в ряду зависело от ширины панели (`paneWidth >= 520 ? 3 : 2`), и ровно это
/// условие рождало жалобу «слева пустует место»: справа три блока в ряд,
/// слева два, а общий масштаб считался по широкой стороне — левая половина
/// жалась вслед за правой и оставляла пустоту у края окна.
///
/// ⚠️ Здесь меряется ФАКТ на экране — положение подписей групп, — а не
/// константа. Константу можно поменять, забыв про раскладку; блоки на экране
/// не соврут.
void main() {
  const button = SizedBox(key: Key('btn'), width: 148, height: 148);

  Widget host({
    required double width,
    required double height,
    List<ProbeService> services = ServiceChecks.catalog,
    ServiceCheckController? ctrl,
    int httpPort = 10809,
  }) =>
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ctrl ?? ServiceCheckController(),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: ConnectCenterpiece(
                  serverName: '🇩🇪 🚀Германия 1.4',
                  httpPort: httpPort,
                  button: button,
                  services: services,
                  layout: ServiceChecksLayout.sides,
                ),
              ),
            ),
          ),
        ),
      );

  /// Подписи групп на экране: по ним видно, сколько блоков стоит в одном
  /// ряду. Ключ у подписи один на обе раскладки — `serviceGroup:<имя>`.
  List<Rect> groupRects(WidgetTester t) => [
        for (final g in ServiceGroup.values)
          for (final e in find.byKey(ValueKey('serviceGroup:${g.name}')).evaluate())
            t.getRect(find.byWidget(e.widget)),
      ];

  group('⚠️ колонок ровно две при любой ширине', () {
    for (final w in const [520.0, 535.0, 595.0, 760.0, 1200.0, 2000.0]) {
      testWidgets('панель ${w.toInt()} px', (t) async {
        t.view.physicalSize = Size(w + 40, 800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(width: w, height: 600));
        await t.pump();
        expect(t.takeException(), isNull);

        final btn = t.getRect(find.byKey(const Key('btn')));
        final rects = groupRects(t);
        expect(rects, hasLength(5), reason: 'пять групп — пять подписей');

        // Блоки одного ряда стоят на одной высоте. Считаем, сколько их в
        // самом широком ряду КАЖДОЙ стороны.
        int widestRow(Iterable<Rect> side) {
          final byTop = <int, int>{};
          for (final r in side) {
            final key = r.top.round();
            byTop[key] = (byTop[key] ?? 0) + 1;
          }
          return byTop.values.fold(0, (a, b) => a > b ? a : b);
        }

        final left = rects.where((r) => r.center.dx < btn.center.dx);
        final right = rects.where((r) => r.center.dx > btn.center.dx);
        expect(widestRow(left), 2,
            reason: 'слева в ряду не два блока при ширине ${w.toInt()}');
        expect(widestRow(right), 2,
            reason: 'справа в ряду не два блока при ширине ${w.toInt()}');
        // Пять групп при двух в ряд — это 2 и 3, а не 1 и 4.
        expect(left.length, 2);
        expect(right.length, 3);
      });
    }
  });

  group('⚠️ тесное окно: переполнения нет', () {
    // Ширина панели в VM при окне 980×800 (535) и 1040×820 (595); высоты —
    // площадь блока при нынешнем низе экрана и при сжатом (BACKLOG, выбор
    // владельца ещё впереди). Четыре точки, а не одна, чтобы правка не
    // оказалась подгонкой под единственный снимок.
    for (final box in const [
      Size(535, 283),
      Size(595, 303),
      Size(535, 186),
      Size(595, 193),
    ]) {
      testWidgets('${box.width.toInt()}×${box.height.toInt()}', (t) async {
        t.view.physicalSize = Size(box.width + 40, box.height + 40);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(width: box.width, height: box.height));
        await t.pump();
        expect(t.takeException(), isNull,
            reason: 'блок переполнился на ${box.width.toInt()}×'
                '${box.height.toInt()}');
        // И это по-прежнему бока, а не ряды под кнопкой: при ограниченной
        // высоте сжатие есть у боков, у рядов его нет.
        expect(find.byType(ServiceChecksRows), findsNothing,
            reason: 'под потолком высоты раскладка упала в ряды');
      });
    }
  });

  test('константы сетки — 2 в ширину, 3 в высоту', () {
    expect(ServiceChecksSides.perRow, 2);
    expect(ServiceChecksSides.maxRows, 3);
    // Двенадцать блоков на две стороны — потолок сетки. Групп в приложении
    // пять; новая группа сверх двенадцати молча уводила бы раскладку в ряды.
    expect(ServiceGroup.values.length,
        lessThanOrEqualTo(ServiceChecksSides.perRow * ServiceChecksSides.maxRows * 2));
  });

  test('ширина стороны при пяти группах — два блока и просвет', () {
    final rows = ServiceChecks.grouped(ServiceChecks.catalog);
    final split = ServiceChecksSides.splitForTest(rows, dense: false);
    expect(ServiceChecksSides.sideWidthOf(split.right, dense: false),
        closeTo(2 * 82 + 10, 0.01),
        reason: 'сторона шире двух блоков — в ряд встало больше двух');
    expect(ServiceChecksSides.sideWidthOf(split.left, dense: false),
        closeTo(2 * 82 + 10, 0.01));
  });

  test('⚠️ формула высоты блока описывает то, что рисуется', () {
    // Подпись 22 + 2 + линия 1 = 25, зазор 4, на сервис — бокс 34 плюс
    // 8 отступов. Просвет 10 — ТОЛЬКО между рядами. Две копии этой формулы
    // (`sideHeightOf` и `_naturalSize`) уже расходились; теперь она одна.
    final one = ServiceChecks.grouped(const [ProbeService.youtube]);
    expect(ServiceChecksSides.sideHeightOf(one, dense: false),
        closeTo(25 + 4 + 1 * (34 + 8), 0.01));
    final rows = ServiceChecks.grouped(ServiceChecks.catalog);
    final split = ServiceChecksSides.splitForTest(rows, dense: false);
    // Справа три блока: ряд из двух (самый высокий — три сервиса) + ряд из
    // одного (три сервиса) + просвет между ними.
    expect(ServiceChecksSides.sideHeightOf(split.right, dense: false),
        closeTo((29 + 3 * 42) * 2 + 10, 0.01));
  });

  testWidgets('⚠️ живая пара со стрелкой не шире ячейки', (t) async {
    // Стрелка нарисована текстом; ширина ячейки — константа. Если стрелка
    // окажется шире отведённого ей места, второй значок вылезет за ячейку и
    // пара разъедется ровно на живом канале, где на неё и смотрят.
    t.view.physicalSize = const Size(900, 700);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final saved = ServiceCheckController.prober;
    addTearDown(() => ServiceCheckController.prober = saved);
    ServiceCheckController.prober = (port, s) async =>
        const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 42);
    final ctrl = ServiceCheckController();
    await ctrl.checkBaseline(const [ProbeService.telegram]);

    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<ServiceCheckController>.value(
        value: ctrl,
        child: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: ServiceChecksRows(
                  services: [ProbeService.telegram], httpPort: 10809),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(find.text('→'), findsOneWidget);
    final cell = find.byKey(const ValueKey('svc:telegram'));
    final pair = find.descendant(of: cell, matching: find.byType(Row)).first;
    // В рядах масштаб 1.0, поэтому ширина здесь — в тех же единицах, что
    // и константа.
    expect(t.getSize(pair).width, lessThanOrEqualTo(cellWidth + 0.5),
        reason: 'пара «до → после» шире ячейки');
  });
}
