import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/app.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/info_tooltip.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// ВРЕМЕННЫЙ: копия колонки `_ConnectPane` (не-compact) с настоящим
/// `ConnectCenterpiece` под тем же `ConstrainedBox`.
void main() {
  Widget pane({
    required double paneHeight,
    required List<ProbeService> services,
    double scale = 1.0,
  }) =>
      MaterialApp(
        locale: const Locale('ru'),
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ServiceCheckController(),
          child: Builder(builder: (context) {
            final l = AppLocalizations.of(context);
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 584,
                    height: paneHeight,
                    child: LayoutBuilder(builder: (context, paneBox) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(l.serviceChecksLegendBefore,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                            color:
                                                Theme.of(context).hintColor)),
                              ),
                              InfoTooltip(l.serviceChecksInfo),
                              const ServiceChecksMenuButton(),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight: checksHeightBudget(
                                    paneHeight: paneBox.maxHeight)),
                            child: ConnectCenterpiece(
                              key: const Key('cp'),
                              serverName: 'Test 1.4',
                              httpPort: 0,
                              services: services,
                              layout: ServiceChecksLayout.adaptive,
                              button: const SizedBox(
                                  key: Key('btn'), width: 148, height: 148),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('status',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          TextButton.icon(
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: Text(l.homeServerInfo),
                              onPressed: () {}),
                          const SizedBox(height: 20),
                          FilledButton.tonalIcon(
                              icon: const Icon(Icons.bolt),
                              label: Text(l.homeAutoBest),
                              onPressed: () {}),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                              icon: const Icon(Icons.auto_fix_high),
                              label: Text(l.homeAutoConfig),
                              onPressed: () {}),
                          const Spacer(),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.arrow_downward,
                                                  size: 16),
                                              const SizedBox(width: 4),
                                              Text('0',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall),
                                            ]),
                                        Text('0',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                      ]),
                                  Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.arrow_upward,
                                                  size: 16),
                                              const SizedBox(width: 4),
                                              Text('0',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall),
                                            ]),
                                        Text('0',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                      ]),
                                ]),
                            const SizedBox(height: 6),
                            Text(l.homeSessionTraffic('0', '0'),
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            );
          }),
        ),
      );

  for (final n in [3, 14]) {
    for (final h in [600.0, 750.0, 1000.0]) {
      testWidgets('pane $h services $n', (t) async {
        t.view.physicalSize = const Size(1200, 1400);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        final services = ServiceChecks.catalog.take(n).toList();
        await t.pumpWidget(pane(paneHeight: h, services: services));
        await t.pump();
        final cp = t.getSize(find.byKey(const Key('cp'))).height;
        final err = t.takeException();
        // ignore: avoid_print
        print('pane=$h services=$n '
            'budget=${checksHeightBudget(paneHeight: h)} centerpiece=$cp '
            'exception=${err == null ? "none" : err.toString().split("\n").first}');
      });
    }
  }
}
