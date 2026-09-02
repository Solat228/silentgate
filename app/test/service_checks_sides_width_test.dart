import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 02.09.2026: «при стандартном разрешении по бокам НИХУЯ
/// не разлетелось, хотя место точно есть».
///
/// Причина — одна константа на два разных вопроса. `_twoPaneMinWidth` = 760
/// заведена под вопрос «когда список серверов уезжает на отдельный экран», и
/// меряет она ШИРИНУ ОКНА. А выбор раскладки проверок спрашивает её же про
/// ШИРИНУ ЛЕВОЙ ПАНЕЛИ — то есть про другое. В двухпанельном режиме панель это
/// окно минус список (380 px), поэтому бока включались бы только при окне
/// шире 1140. У владельца окно 964 — панель около 584, и он видел ряды при
/// свободном месте по бокам.
///
/// Здесь мерится ФАКТ: при какой ширине панели раскладка «по бокам» реально
/// раскладывается без переполнения. Порог в коде обязан идти от этого числа, а
/// не от чужой константы.
/// Провайдер нужен: `ServiceChecksRows` читает контроллер, и без него дерево
/// падает раньше, чем дойдёт до вёрстки, — то есть тест мерил бы не то.
Widget _wrap(Widget child) => ChangeNotifierProvider<ServiceCheckController>(
      create: (_) => ServiceCheckController(),
      child: child,
    );

void main() {
  const button = SizedBox(key: Key('btn'), width: 148, height: 148);

  Widget host(double width) => MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _wrap(Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const ConnectCenterpiece(
                serverName: '🇩🇪 🚀Германия 1.4',
                httpPort: 10809,
                button: button,
                services: ServiceChecks.catalog,
                layout: ServiceChecksLayout.sides,
              ),
            ),
          ),
        )),
      );

  group('⚠️ Раскладка «по бокам» помещается там, где для неё есть место', () {
    // Ширина ЛЕВОЙ ПАНЕЛИ при ходовых размерах окна: окно минус список серверов
    // (380 px) и отступы. 584 — случай владельца (окно 964).
    for (final w in const [520.0, 584.0, 640.0, 760.0, 900.0]) {
      testWidgets('панель ${w.toInt()} px — без переполнения', (t) async {
        t.view.physicalSize = Size(w + 40, 900);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        await t.pumpWidget(host(w));
        await t.pump();

        expect(t.takeException(), isNull,
            reason: 'при ${w.toInt()} px «по бокам» переполняется — значит '
                'порог обязан быть выше этого числа');
      });
    }
  });

  testWidgets('⚠️ ГЛАВНОЕ: у владельца (панель 584 px) выбираются БОКА',
      (t) async {
    // Тот же путь, что на экране: раскладка `adaptive`, решение принимает
    // `ConnectCenterpiece`. Проверяем не константу, а результат.
    t.view.physicalSize = const Size(624, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _wrap(const Scaffold(
        body: Center(
          child: SizedBox(
            width: 584,
            child: ConnectCenterpiece(
              serverName: '🇩🇪 🚀Германия 1.4',
              httpPort: 10809,
              button: button,
              services: ServiceChecks.catalog,
              layout: ServiceChecksLayout.adaptive,
            ),
          ),
        ),
      )),
    ));
    await t.pump();

    expect(find.byType(ServiceChecksSides), findsOneWidget,
        reason: 'место есть — колонки обязаны быть по бокам, а не рядами');
    expect(t.takeException(), isNull);
  });

  testWidgets('на телефоне (панель 360 px) по-прежнему ряды', (t) async {
    // Контроль: порог опускаем не до нуля. На узком экране бока не помещаются,
    // и ряды там правильный ответ.
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _wrap(const Scaffold(
        body: SingleChildScrollView(
          child: ConnectCenterpiece(
            serverName: null,
            httpPort: 10809,
            button: button,
            services: ServiceChecks.catalog,
            layout: ServiceChecksLayout.adaptive,
          ),
        ),
      )),
    ));
    await t.pump();

    expect(find.byType(ServiceChecksSides), findsNothing,
        reason: 'на 360 px колонки по бокам не помещаются');
  });
}
