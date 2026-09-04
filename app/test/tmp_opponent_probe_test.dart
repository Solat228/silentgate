import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

void main() {
  Widget host(double w, double h) => MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: ServiceChecksSides(
                  services: ServiceChecks.catalog,
                  httpPort: 0,
                  button: const SizedBox(key: Key('btn'), width: 148, height: 148),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('замер по ширинам', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    for (final h in [237.0, 300.0]) {
      for (final w in [500.0, 519.0, 520.0, 551.0, 560.0, 600.0, 700.0, 900.0]) {
        await t.pumpWidget(host(w, h));
        await t.pump();
        final rows = find.byKey(const ValueKey('serviceChecksSidesRow'));
        final has = rows.evaluate().isNotEmpty;
        final f = find.byKey(const ValueKey('svc:telegram'));
        final r = f.evaluate().isEmpty ? Rect.zero : t.getRect(f.first);
        // ignore: avoid_print
        print('h=$h w=$w sides=$has cell=${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}');
      }
    }
  });
}
