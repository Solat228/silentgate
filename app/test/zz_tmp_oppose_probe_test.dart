import 'package:flutter/material.dart';
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
    required List<ProbeService> services,
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
                  serverName: 'srv',
                  httpPort: 10809,
                  button: button,
                  services: services,
                  layout: layout,
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> probe(WidgetTester tester,
      {required double w,
      required double h,
      required ServiceChecksLayout layout,
      required List<ProbeService> services,
      required String tag}) async {
    tester.view.physicalSize = Size(w + 200, h + 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        host(width: w, height: h, layout: layout, services: services));
    await tester.pump();

    final groups = ServiceChecks.grouped(services);
    final sides = ServiceChecksSides.splitForTest(groups,
        dense: layout == ServiceChecksLayout.grid,
        perRow: ServiceChecksSides.blocksPerRowFor(w));
    // ignore: avoid_print
    print('--- $tag  ${w}x$h  layout=$layout  services=${services.length}');
    // ignore: avoid_print
    print('    left groups=${sides.left.map((g) => g.group.name).toList()}');
    // ignore: avoid_print
    print('    right groups=${sides.right.map((g) => g.group.name).toList()}');

    double? sideAvg(List<GroupedRow> rows) {
      final ws = <double>[];
      for (final g in rows) {
        for (final s in g.services) {
          final f = find.byKey(ValueKey('svc:${s.name}'));
          if (f.evaluate().isEmpty) continue;
          ws.add(tester.getRect(f).width);
        }
      }
      if (ws.isEmpty) return null;
      return ws.reduce((a, b) => a + b) / ws.length;
    }

    final l = sideAvg(sides.left);
    final r = sideAvg(sides.right);
    // ignore: avoid_print
    print('    avg pair width  left=$l  right=$r');
    if (l != null && r != null && l > 0) {
      // ignore: avoid_print
      print('    ratio right/left = ${(r / l).toStringAsFixed(3)}');
    }
  }

  testWidgets('grid 14 @584x237', (t) async {
    await probe(t,
        w: 584,
        h: 237,
        layout: ServiceChecksLayout.grid,
        services: ServiceChecks.catalog,
        tag: 'GRID-14');
  });

  testWidgets('grid default set', (t) async {
    await probe(t,
        w: 584,
        h: 237,
        layout: ServiceChecksLayout.grid,
        services: ServiceChecks.services,
        tag: 'GRID-default');
  });

  testWidgets('sides 14 @584x237 (control)', (t) async {
    await probe(t,
        w: 584,
        h: 237,
        layout: ServiceChecksLayout.sides,
        services: ServiceChecks.catalog,
        tag: 'SIDES-14');
  });
}
