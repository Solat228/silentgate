import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// СЕРЕДИНА ГЛАВНОГО ЭКРАНА НА НАСТОЯЩИХ РАЗРЕШЕНИЯХ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. 19.08.2026 проверки сервисов переехали из двух
/// колонок по бокам кнопки Connect в ряды по смысловым группам под ней. Ряды
/// были написаны и покрыты тестами ещё раньше — но на месте вызова подмену
/// забыли сделать, и группировка полгода жила в коде, не доходя до человека.
/// Владелец сказал прямо: «в интерфейсе я этого не заметил».
///
/// Раскладка середины экрана меняется редко и ломается тихо: при четырнадцати
/// сервисах рядов пять, и на узком телефоне это совсем другая высота. Поэтому
/// здесь она собирается НАСТОЯЩИМ виджетом ([ConnectCenterpiece], тем самым,
/// что стоит в `_ConnectPane`) на одиннадцати ходовых разрешениях.
///
/// ⚠️ Проверять копию раскладки бессмысленно — на этом уже обжигались: прошлый
/// страж плашки собирал `Row` с заглушками вместо колонок и оставался зелёным
/// всё время, пока плашка наезжала на настоящие колонки.
void main() {
  /// Настоящие разрешения (логические точки), самые ходовые.
  const screens = <String, Size>{
    'iPhone SE 1 (самый тесный)': Size(320, 568),
    'Android 360×640': Size(360, 640),
    'Android 360×800 (самый ходовой)': Size(360, 800),
    'iPhone SE 2/3, 8': Size(375, 667),
    'iPhone 14/15': Size(390, 844),
    'Pixel 7/8': Size(393, 873),
    'Samsung S23': Size(412, 915),
    'iPhone 11/XR': Size(414, 896),
    'iPhone Pro Max': Size(428, 926),
    'планшет, портрет': Size(800, 1280),
    // ⚠️ Окно Windows в минимальном размере: ширины больше, а высоты меньше,
    // чем у любого телефона, — рядам это самый тесный случай по вертикали.
    'Windows, минимальное окно': Size(880, 680),
  };

  /// Круг кнопки Connect — 148 px, как `_ConnectButton` на нормальной высоте.
  const button = SizedBox(key: Key('btn'), width: 148, height: 148);

  Widget host(Widget child) => MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider(
          create: (_) => ServiceCheckController(),
          // ⚠️ Скролл здесь НАМЕРЕННО: на узком экране `_ConnectPane` оборачивает
          // колонку в `SingleChildScrollView` (`_MaybeScroll`), и без него тест
          // краснел бы на нехватке высоты, которой в приложении нет.
          child: Scaffold(
            body: SingleChildScrollView(child: Center(child: child)),
          ),
        ),
      );

  group('⚠️ Полный набор из 14 сервисов на одиннадцати экранах', () {
    for (final e in screens.entries) {
      testWidgets('${e.key} — вёрстка цела, группы видны', (t) async {
        t.view.physicalSize = e.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        await t.pumpWidget(host(ConnectCenterpiece(
          serverName: '🇩🇪 🚀Германия 2.7 (edge)',
          httpPort: 10809,
          button: button,
          services: ServiceChecks.catalog,
        )));
        await t.pump();

        // ⚠️ ГЛАВНОЕ: переполнение Flutter сообщает исключением, и без этой
        // проверки тест зеленел бы на экране, где ряды уехали за край.
        expect(t.takeException(), isNull,
            reason: '${e.key}: вёрстка переполнилась');

        // Ряды обязаны умещаться по ширине: `Wrap` внутри переносит чипы сам,
        // и вылезти за край он может только если сломали ограничения.
        final rows = t.getSize(find.byType(ServiceChecksRows));
        expect(rows.width, lessThanOrEqualTo(e.value.width),
            reason: '${e.key}: ряды шире экрана');

        // И ради чего всё затевалось: группировка ВИДНА, а не просто существует.
        expect(find.byKey(const ValueKey('serviceGroup:messengers')),
            findsOneWidget,
            reason: '${e.key}: подписи групп не отрисовались');
        expect(find.byKey(const ValueKey('serviceGroup:other')), findsOneWidget);
      });
    }
  });

  group('Границы набора', () {
    testWidgets('⚠️ проверки выключены — середина не занимает лишнего',
        (t) async {
      // Владелец просил «галочку полного отключения». Пустые ряды, рисуемые
      // пустыми, съедали бы высоту у кнопки на телефоне.
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host(const ConnectCenterpiece(
        serverName: null,
        httpPort: 0,
        button: button,
        services: [],
      )));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(ServiceChecksRows)), Size.zero);
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('один сервис — один ряд, а не пять пустых', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host(const ConnectCenterpiece(
        serverName: null,
        httpPort: 0,
        button: button,
        services: [ProbeService.telegram],
      )));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('serviceGroup:messengers')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('serviceGroup:ai')), findsNothing,
          reason: 'пустая группа не имеет права занимать строку');
    });
  });
}
