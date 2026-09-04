import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

void main() {
  const button = SizedBox(key: Key('btn'), width: 148, height: 148);

  Widget host({
    required double width,
    required double height,
    required ServiceChecksLayout layout,
    String? name = 'Germany 1.4',
  }) =>
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
                height: height,
                child: ConnectCenterpiece(
                  serverName: name,
                  httpPort: 10809,
                  button: button,
                  services: ServiceChecks.catalog,
                  layout: layout,
                ),
              ),
            ),
          ),
        ),
      );

  for (final layout in [ServiceChecksLayout.sides, ServiceChecksLayout.grid]) {
    for (final w in const [460.0, 500.0, 519.0, 520.0, 560.0, 700.0]) {
      for (final h in const [171.0, 180.0, 200.0, 237.0, 300.0]) {
        testWidgets('$layout w=$w h=$h', (t) async {
          t.view.physicalSize = Size(w + 60, h + 120);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.resetPhysicalSize);
          await t.pumpWidget(host(width: w, height: h, layout: layout));
          await t.pump();
          final sides = find.byType(ServiceChecksSides);
          String cons = 'нет ServiceChecksSides';
          if (sides.evaluate().isNotEmpty) {
            final rb = t.renderObject<RenderBox>(sides);
            cons = '${rb.constraints} size=${rb.size}';
          }
          final fallbackRows = find.byType(ServiceChecksRows).evaluate().isNotEmpty;
          final ex = t.takeException();
          // ignore: avoid_print
          print('RES $layout w=$w h=$h | $cons | rowsFallback=$fallbackRows | ex=${ex == null ? "нет" : ex.toString().split("\n").first}');
        });
      }
    }
  }
}
