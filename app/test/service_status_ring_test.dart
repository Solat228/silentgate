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
  Widget host({required int httpPort}) => MaterialApp(
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
                  httpPort: httpPort,
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
      );

  testWidgets('⚠️ отдельных кружков состояния больше нет', (t) async {
    t.view.physicalSize = const Size(700, 400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(host(httpPort: 0));
    await t.pump();
    expect(t.takeException(), isNull);

    // Обводка рисуется рамкой на самом значке. Кружок рядом — это то, от чего
    // ушли: если он вернётся, ячейка снова начнёт расти на живом канале.
    final borders = find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).border != null);
    expect(borders, findsWidgets,
        reason: 'обводки состояния не нарисовалось');
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
}
