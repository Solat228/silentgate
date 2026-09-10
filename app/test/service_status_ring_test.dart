import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';
import 'package:silentgate/ui/widgets/site_favicon.dart';

/// СОСТОЯНИЕ — ОБВОДКОЙ ЗНАЧКА, ПЕРЕХОД — СТРЕЛКОЙ.
///
/// Решение владельца 04.09.2026 по разбору десяти раскладок в масштабе:
/// «сделай вариант с обводкой, убрав цветную точку, но оставь стрелочку».
///
/// ⚠️ ЗАЧЕМ ЭТО ВАЖНО ЧИСЛОМ, А НЕ ТОЛЬКО НА ВИД. Кружок рядом со значком стоил
/// дороже всего именно на ЖИВОМ канале: там к нему добавлялась пара «до →
/// после» со стрелкой, и ячейка росла с 43 до 71 px. Раскладка, крупная в
/// покое, на подключённом VPN сжималась — то есть мельчала ровно тогда, когда
/// на неё и смотрят. Обводка живёт НА значке и ширины не занимает вовсе.
///
/// ⚠️ И ПОЧЕМУ СТРЕЛКА ОБЯЗАНА ОСТАТЬСЯ. Обводка показывает, как СТАЛО. Без
/// стрелки, окрашенной в цвет «до», сравнение исчезает — а ради него проверки
/// и делаются. Убрать её значит оставить половину смысла.
void main() {
  Widget host({
    required int httpPort,
    String locale = 'ru',
    ServiceCheckController? ctrl,
    List<ProbeService> services = const [
      ProbeService.youtube,
      ProbeService.telegram,
      ProbeService.chatgpt,
    ],
  }) =>
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ctrl ?? ServiceCheckController(),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 584,
                height: 260,
                child: ConnectCenterpiece(
                  serverName: 'Германия 2.4',
                  httpPort: httpPort,
                  button: const SizedBox(
                      key: Key('btn'), width: 148, height: 148),
                  services: services,
                  layout: ServiceChecksLayout.sides,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('⚠️ отдельных кружков состояния больше нет', (t) async {
    t.view.physicalSize = const Size(700, 400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(host(httpPort: 0));
    await t.pump();
    expect(t.takeException(), isNull);

    // ⚠️ ФИНДЕР СУЖЕН ДО ОБВОДОК ЗНАЧКОВ, А НЕ «ЛЮБАЯ РАМКА В ДЕРЕВЕ».
    //
    // Найдено ревью 05.09.2026: прежний вариант искал любой `DecoratedBox` с
    // рамкой во всём дереве и требовал «хотя бы одну». Такая рамка есть у
    // плашки имени сервера (`ActiveServerLabel`), причём она в дереве ВСЕГДА —
    // её держат `Visibility` с `maintainState`. Проверено прогоном: при
    // `services: const []`, где нет ни одного значка и ни одной обводки
    // состояния, тест находил одну рамку и оставался зелёным.
    //
    // То есть утверждение держалось на ЧУЖОЙ рамке: убери обводку из значка
    // (или верни прежний кружок) — состояние сервисов перестанет отображаться
    // вообще, а прогон останется зелёным.
    //
    // Теперь считаем рамки ВНУТРИ ячеек сервисов и требуем их столько, сколько
    // сервисов на экране.
    Finder ringsOf(Finder scope) => find.descendant(
          of: scope,
          matching: find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border != null),
        );

    final cells = find.byKey(const ValueKey('svc:telegram'));
    expect(cells, findsOneWidget, reason: 'ячейка сервиса не нарисовалась');
    expect(ringsOf(cells), findsWidgets,
        reason: 'у значка сервиса нет обводки состояния');

    // И контрольная проверка от вырожденности: без сервисов обводок быть не
    // должно ВООБЩЕ. Прежний финдер здесь находил рамку плашки и проходил.
    await t.pumpWidget(host(httpPort: 0, services: const []));
    await t.pump();
    expect(
      find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null &&
          ((w.decoration as BoxDecoration).border as Border?)?.top.width == 2),
      findsNothing,
      reason: 'обводка состояния нарисована там, где сервисов нет',
    );
  });

  testWidgets('⚠️ на живом канале появляется стрелка перехода', (t) async {
    t.view.physicalSize = const Size(700, 400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(host(httpPort: 10809));
    await t.pump();
    expect(t.takeException(), isNull);
    // Замеров «до» в свежем контроллере нет, поэтому стрелка не рисуется —
    // и это верно: рисовать переход, которого не было, значит врать.
    expect(find.text('→'), findsNothing,
        reason: 'стрелка нарисована без замера «до»');
  });

  test('⚠️ подпись не шире ячейки больше, чем на запас под слово', () {
    // Ширину блока задаёт самый широкий элемент. Пока подпись заметно шире
    // содержимого, увеличивать значки бесполезно: сторона упирается в неё.
    //
    // ⚠️ ПОТОЛОК ВЫРАЖЕН ЧЕРЕЗ САМУ ЯЧЕЙКУ, А НЕ ЧИСЛОМ. Числом он уже
    // протух один раз: ячейка выросла с 48 до 64 (в неё добавился второй
    // значок «через VPN»), и страж упал на правке, которую должен был
    // пропустить. Инвариант тут не «подпись ≤ 54», а «подпись не тянет блок
    // шире содержимого».
    expect(ServiceChecksSides.labelWidthFor(false),
        lessThanOrEqualTo(cellWidth + 6),
        reason: 'подпись снова стала диктовать ширину блока');
  });

  testWidgets('⚠️ в фарси пара НЕ переворачивается: «до» остаётся слева',
      (t) async {
    // Подпись под блоком переведена дословно — «چپ — بدون VPN» значит
    // «слева — без VPN». Если `Row` возьмёт направление у локали, значки
    // поменяются местами, а стрелка «→» не зеркалится (U+2192 не имеет пары
    // в BidiMirroring) и станет показывать от «после» к «до».
    //
    // Иранский пользователь — ядро аудитории VPN-клиента: он прочтёт
    // подпись, посмотрит на левый значок и увидит замер ЧЕРЕЗ VPN. Сервис,
    // который VPN починил, будет выглядеть им сломанным.
    t.view.physicalSize = const Size(900, 400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);

    Future<double> leftEdgeOfFirstIcon(String loc) async {
      await t.pumpWidget(host(httpPort: 0, locale: loc));
      await t.pump();
      final cell = find.byKey(const ValueKey('svc:telegram'));
      expect(cell, findsOneWidget);
      final row = find.descendant(of: cell, matching: find.byType(Row));
      return t.getTopLeft(row.first).dx;
    }

    // Само по себе положение ячейки в RTL зеркалится — это нормально.
    // Проверяем ВНУТРЕННЕЕ направление: оно обязано остаться слева направо.
    await leftEdgeOfFirstIcon('fa');
    final dir = Directionality.of(
        t.element(find.descendant(
            of: find.byKey(const ValueKey('svc:telegram')),
            matching: find.byType(Row)).first));
    expect(dir, TextDirection.ltr,
        reason: 'в RTL-локали пара «до → после» перевернулась, и подпись '
            '«слева — без VPN» стала ложью');
  });

  testWidgets('⚠️ на ЖИВОМ канале рисуется пара «до → после» со стрелкой',
      (t) async {
    // ⚠️ ДО РЕВЬЮ 05.09.2026 ЭТОГО НЕ ПРОВЕРЯЛ НИ ОДИН ТЕСТ. Ветка живой пары
    // включается, только когда есть замер «до», а во всех виджет-тестах
    // контроллер создавался пустым. Соседний тест назывался «на живом канале
    // появляется стрелка» и утверждал ровно обратное — `findsNothing`.
    //
    // То есть можно было удалить второй значок и стрелку целиком — сравнение
    // «без VPN → через VPN», ради которого весь блок и переделывали, исчезло
    // бы с экрана, а прогон остался бы зелёным. Включая файл, в шапке
    // которого написано, почему стрелка обязана остаться.
    t.view.physicalSize = const Size(900, 500);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);

    final saved = ServiceCheckController.prober;
    addTearDown(() => ServiceCheckController.prober = saved);
    ServiceCheckController.prober = (port, s) async =>
        const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 42);

    final ctrl = ServiceCheckController();
    // Замер «до» — то самое состояние, в которое тесты не заходили.
    await ctrl.checkBaseline(const [
      ProbeService.youtube,
      ProbeService.telegram,
      ProbeService.chatgpt,
    ]);

    await t.pumpWidget(host(httpPort: 10809, ctrl: ctrl));
    await t.pump();
    expect(t.takeException(), isNull);

    expect(find.text('→'), findsNWidgets(3),
        reason: 'стрелка перехода пропала — сравнение «до и после» исчезло');
    // Два значка на сервис: «без VPN» и «через VPN».
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('svc:telegram')),
        matching: find.byType(SiteFavicon),
      ),
      findsNWidgets(2),
      reason: 'на живом канале должно быть ДВА значка: до и после',
    );
  });

  /// ДВОЙНОЙ КОНТУР: КОЛЬЦО, ПРОСЛОЙКА ЦВЕТА ФОНА, ЗНАЧОК.
  ///
  /// ⚠️ Жалоба владельца (08.09.2026): «обводка сливается с брендом» у
  /// зелёного Spotify и красного YouTube. Механика найдена разведкой:
  /// прослойки не было ВООБЩЕ. `DecoratedBox` не отступает под рамку (в
  /// отличие от `Container`), и кольцо 2 px рисовалось ПОВЕРХ крайнего
  /// пикселя значка — зелёное на зелёном.
  ///
  /// Проверяется ГЕОМЕТРИЕЙ, а не «на глаз»: прямоугольник прослойки обязан
  /// быть прямоугольником кольца, сжатым ровно на его толщину.
  group('⚠️ двойной контур и глиф состояния', () {
    Finder ringsIn(Finder scope) => find.descendant(
          of: scope,
          matching: find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).border as Border?)?.top.width ==
                  2),
        );

    /// Прослойка — цветная коробка БЕЗ рамки внутри кольца.
    Finder gapsIn(Finder scope) => find.descendant(
          of: scope,
          matching: find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border == null &&
              (w.decoration as BoxDecoration).color != null),
        );

    Future<ServiceCheckController> ctrlWith(ServiceCheckState state) async {
      final saved = ServiceCheckController.prober;
      addTearDown(() => ServiceCheckController.prober = saved);
      ServiceCheckController.prober =
          (port, s) async => ServiceCheckOutcome(state, latencyMs: 42);
      final ctrl = ServiceCheckController();
      await ctrl.checkBaseline(const [
        ProbeService.youtube,
        ProbeService.telegram,
        ProbeService.chatgpt,
      ]);
      return ctrl;
    }

    for (final layout in const [
      ServiceChecksLayout.sides,
      ServiceChecksLayout.grid,
    ]) {
      testWidgets('прослойка = кольцо, сжатое на 2 px (${layout.name})',
          (t) async {
        t.view.physicalSize = const Size(900, 500);
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
                  height: 260,
                  child: ConnectCenterpiece(
                    serverName: 'Германия 2.4',
                    httpPort: 0,
                    button: const SizedBox(
                        key: Key('btn'), width: 148, height: 148),
                    services: const [ProbeService.telegram],
                    layout: layout,
                  ),
                ),
              ),
            ),
          ),
        ));
        await t.pump();
        expect(t.takeException(), isNull);

        final cell = find.byKey(const ValueKey('svc:telegram'));
        expect(ringsIn(cell), findsOneWidget, reason: 'кольца нет');
        expect(gapsIn(cell), findsOneWidget,
            reason: 'прослойки между кольцом и значком нет — кольцо снова '
                'рисуется поверх значка и сливается с брендом');
        final ring = t.getRect(ringsIn(cell));
        final gap = t.getRect(gapsIn(cell));
        final icon = t.getRect(
            find.descendant(of: cell, matching: find.byType(SiteFavicon)));
        // ⚠️ Прямоугольники — ЭКРАННЫЕ, а блок по бокам нарисован через
        // `FittedBox` с ростом (здесь ×1,6): толщина 2 логических px на
        // экране — это 2·k. Масштаб выводится из самого значка: 26 в паре,
        // 20 в сетке (`_pairIconSize` / `_buildDense`).
        final k = icon.width / (layout == ServiceChecksLayout.grid ? 20 : 26);
        expect(k, greaterThan(0.99), reason: 'значок сжат там, где место есть');
        void expectRect(Rect got, Rect want, String what) {
          for (final (a, b) in [
            (got.left, want.left),
            (got.top, want.top),
            (got.right, want.right),
            (got.bottom, want.bottom),
          ]) {
            expect(a, closeTo(b, 0.05), reason: what);
          }
        }

        expectRect(gap, ring.deflate(2 * k),
            'прослойка не отступает от кольца ровно на его толщину');
        // И значок отступает от прослойки ещё на 2 px — иначе прослойки
        // не видно.
        expectRect(icon, gap.deflate(2 * k),
            'значок не отступает от прослойки на её ширину');
        // Прослойка — цвета ФОНА окна, а не поверхности: контраст нужен с
        // тем, что нарисовано вокруг значка.
        final gapBox = t.widget<DecoratedBox>(gapsIn(cell));
        expect((gapBox.decoration as BoxDecoration).color,
            Theme.of(t.element(cell)).scaffoldBackgroundColor);
      });

      for (final (state, icon) in const [
        (ServiceCheckState.ok, Icons.check),
        (ServiceCheckState.geoBlocked, Icons.priority_high),
        (ServiceCheckState.fail, Icons.close),
      ]) {
        testWidgets('глиф ${state.name} → ${icon.codePoint} (${layout.name})',
            (t) async {
          t.view.physicalSize = const Size(900, 500);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.resetPhysicalSize);
          final ctrl = await ctrlWith(state);
          await t.pumpWidget(MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChangeNotifierProvider<ServiceCheckController>.value(
              value: ctrl,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 584,
                    height: 260,
                    child: ConnectCenterpiece(
                      serverName: 'Германия 2.4',
                      httpPort: 0,
                      button: const SizedBox(
                          key: Key('btn'), width: 148, height: 148),
                      services: const [ProbeService.telegram],
                      layout: layout,
                    ),
                  ),
                ),
              ),
            ),
          ));
          await t.pump();
          expect(t.takeException(), isNull);
          final cell = find.byKey(const ValueKey('svc:telegram'));
          expect(find.descendant(of: cell, matching: find.byIcon(icon)),
              findsOneWidget,
              reason: 'у состояния ${state.name} нет глифа в углу');
          // ⚠️ `Icons.block` запрещён: `service_chips_test` требует его
          // отсутствия, а глиф отказа с ним путался бы с бейджем «Блок».
          expect(find.byIcon(Icons.block), findsNothing);
          // Глиф — в ПРАВОМ НИЖНЕМ углу кольца (бейдж обхода живёт слева
          // сверху, и столкнуться они не должны).
          final ring = t.getRect(ringsIn(cell));
          final glyph = t.getRect(
              find.descendant(of: cell, matching: find.byIcon(icon)));
          expect(glyph.center.dx, greaterThan(ring.center.dx));
          expect(glyph.center.dy, greaterThan(ring.center.dy));
        });
      }
    }

    testWidgets('без замера глифа нет', (t) async {
      t.view.physicalSize = const Size(900, 500);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(host(httpPort: 0));
      await t.pump();
      for (final i in const [Icons.check, Icons.priority_high, Icons.close]) {
        expect(find.byIcon(i), findsNothing,
            reason: 'глиф нарисован у непроверенного сервиса');
      }
    });

    testWidgets('⚠️ на мелком масштабе глиф не рисуется', (t) async {
      // Кружок 12 px при масштабе 0,5 — это 6 px: пятно, а не знак. Ниже
      // порога читаемости глиф только пачкает кольцо.
      t.view.physicalSize = const Size(900, 500);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final ctrl = await ctrlWith(ServiceCheckState.ok);
      await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>.value(
          value: ctrl,
          child: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 584,
                // Четырнадцать сервисов в 150 px — масштаб около 0,45.
                height: 150,
                child: ServiceChecksSides(
                  services: ServiceChecks.catalog,
                  httpPort: 0,
                  button: SizedBox(width: 148, height: 148),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byIcon(Icons.check), findsNothing,
          reason: 'глиф рисуется на масштабе, где он нечитаем');
    });
  });
}
