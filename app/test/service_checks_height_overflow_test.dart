import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// БЛОК ПРОВЕРОК НЕ РИСУЕТ НИЖЕ ВЫДАННОЙ ЕМУ ВЫСОТЫ.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 03.09.2026 и СНИМОК ИЗ VM. Блок получил потолок, влез в
/// окно целиком — и подпись «Доступность сервисов проверена без VPN» легла
/// ПОВЕРХ кнопки Connect, а «Автонастройка» осталась срезанной.
///
/// ⚠️ ПРИЧИНА — ОЦЕНКА, ВЫДАННАЯ ЗА ИЗМЕРЕНИЕ. `_estimateScale` считает высоту
/// по числу строк, то есть приблизительно, и при четырнадцати сервисах
/// ошибается в меньшую сторону: измерено в госте — панель 447 px, потолок блока
/// 237, фактическая высота около 340. Ветка «влезаю» возвращала голый `Row`,
/// поэтому правильность зависела от ТОЧНОСТИ оценки. Ветка «не влезаю» этой
/// беды не знала: там `FittedBox`, а `RenderFittedBox` физически не рисует
/// ребёнка крупнее выделенного места.
///
/// ⚠️ ПОЧЕМУ ЭТОГО НЕ ЛОВИЛ НИ ОДИН ТЕСТ. Соседний страж
/// (`service_checks_sides_width_test`) даёт дереву высоту 900 px — при ней
/// оценка не ошибается, потому что места хватает с запасом. Дефект живёт
/// только в ТЕСНОМ по высоте окне, а такого случая среди стражей не было.
/// И в release-сборке полоски переполнения вырезаны: на готовом приложении
/// ошибка не сообщает о себе ничем, кроме наложившихся надписей.
void main() {
  const button = SizedBox(key: Key('btn'), width: 148, height: 148);

  Widget host({required double width, required double height}) => MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                // ⚠️ ИМЕННО `SizedBox` С ВЫСОТОЙ, А НЕ `Center` — потолок,
                // который блоку выдаёт панель. Без него дети `Column`
                // получают бесконечность, сжатие не включается, и тест
                // проверял бы случай, которого в тесном окне не бывает.
                height: height,
                child: ConnectCenterpiece(
                  serverName: '🇩🇪 🚀Германия 1.4',
                  httpPort: 10809,
                  button: button,
                  services: ServiceChecks.catalog,
                  layout: ServiceChecksLayout.sides,
                ),
              ),
            ),
          ),
        ),
      );

  // ⚠️ ПРОПУСК `BACKLOG #35` СНЯТ 09.09.2026 — вместе с причиной.
  //
  // Прежняя попытка (коммит 36229ab) провалилась, потому что при
  // ограниченной высоте оценка уводила раскладку в РЯДЫ, у которых сжатия
  // нет. Теперь бока при ограниченной высоте остаются на ЛЮБОМ масштабе
  // (в ряды уходим только когда упирается ШИРИНА), а высота блока считается
  // ПОСЛЕ масштаба, а не до него. Четырнадцать сервисов в 237 px — это
  // масштаб около 0,74, читаемо.
  group('⚠️ тесное по высоте окно: переполнения нет', () {
    // 237 — измеренный в госте потолок при окне 1024×781 и четырнадцати
    // сервисах; остальные значения обкладывают его с двух сторон, чтобы
    // правка не оказалась подгонкой под одно число.
    for (final h in const [180.0, 237.0, 300.0, 380.0]) {
      testWidgets('высота ${h.toInt()} px — блок не выходит за края',
          (t) async {
        t.view.physicalSize = Size(640, h + 40);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        await t.pumpWidget(host(width: 584, height: h));
        await t.pump();
        // В тестах переполнение — это исключение, а не полоска: сам факт
        // отсутствия ошибок и есть проверяемое утверждение.
        expect(t.takeException(), isNull,
            reason: 'блок нарисовался ниже выданных $h px');
        expect(find.byType(ServiceChecksRows), findsNothing,
            reason: 'под потолком высоты раскладка снова упала в ряды — '
                'это провал коммита 36229ab');
      });
    }

    // ⚠️ СЛУЧАЙ ШИРИНЫ. Высота не ограничена (телефон в прокрутке), а
    // ширина — впритык: здесь и только здесь бока уступают место рядам.
    testWidgets('упирается ШИРИНА, высота свободна — ряды под кнопкой',
        (t) async {
      t.view.physicalSize = const Size(700, 1200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 300,
                child: ServiceChecksSides(
                  services: ServiceChecks.catalog,
                  httpPort: 0,
                  button: button,
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byType(ServiceChecksRows), findsOneWidget,
          reason: 'при ширине 300 боков не построить читаемыми');
    });
  });

  testWidgets('⚠️ и с одним сервисом тоже — блок не обязан быть большим',
      (t) async {
    // Обратный край: правка ради четырнадцати сервисов не должна раздувать
    // или ломать самый частый случай.
    t.view.physicalSize = const Size(900, 400);
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
              height: 237,
              child: ConnectCenterpiece(
                serverName: 'Германия 1.4',
                httpPort: 10809,
                button: button,
                services: const [ProbeService.youtube],
                layout: ServiceChecksLayout.sides,
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('⚠️ ветка «места категорически мало» тоже не переполняется',
      (t) async {
    // Найдено ревью 05.09.2026 замером: при `scale < _minReadableScale`
    // возвращался голый `Column` — ни сжатия, ни прокрутки. Пока блоку давали
    // бесконечную высоту, ветка была недостижима; с появлением настоящего
    // потолка она включается и даёт «overflowed by 277 pixels».
    //
    // ⚠️ В release полосок переполнения НЕТ — подписи просто лягут поверх
    // кнопки. То есть на готовой сборке дефект выглядит не как ошибка, а как
    // кривая вёрстка, и жалоба приходит от человека, а не от прогона.
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);

    // Числа — из находки: ровно то место, где ветка включается.
    for (final box in const [Size(500, 171), Size(560, 90)]) {
      await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: ServiceChecksSides(
                  services: ServiceChecks.services,
                  httpPort: 0,
                  button: const SizedBox(width: 148, height: 148),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull,
          reason: 'вёрстка переполнилась на месте '
              '${box.width.toInt()}×${box.height.toInt()}');
    }
  });
}
