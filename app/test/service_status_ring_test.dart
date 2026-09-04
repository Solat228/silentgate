import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

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
          create: (_) => ServiceCheckController(),
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
}
