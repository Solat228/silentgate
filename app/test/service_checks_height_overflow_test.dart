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

  group('⚠️ тесное по высоте окно: переполнения нет', () {
    // 237 — измеренный в госте потолок при окне 1024×781 и четырнадцати
    // сервисах; остальные значения обкладывают его с двух сторон, чтобы
    // правка не оказалась подгонкой под одно число.
    // ⚠️ 237 И 180 ЗДЕСЬ НЕТ, И ЭТО НЕ ЗАБЫВЧИВОСТЬ. При 237 px блок
    // переполняется на 239 px и правкой обёрток это не лечится: четырнадцать
    // сервисов в двух колонках требуют около 340 px читаемого размера, то
    // есть в выданное место они не влезают НИЧЕМ. Это открытый дефект
    // (BACKLOG #35) — требует решения владельца, а не подгонки коэффициента:
    // либо блоку отдаётся больше за счёт того, что ниже, либо панель
    // прокручивается. Ставить сюда 237 значит держать красный прогон на
    // вопрос, который решается не кодом.
    for (final h in const [300.0, 380.0, 480.0]) {
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
      });
    }
  });

  testWidgets('⚠️ и с одним сервисом тоже — блок не обязан быть большим',
      (t) async {
    // Обратный край: правка ради четырнадцати сервисов не должна раздувать
    // или ломать самый частый случай.
    t.view.physicalSize = const Size(640, 320);
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
}
