import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/app.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/info_tooltip.dart';

/// ВРЕМЕННЫЙ ЗАМЕР: сколько занимает всё, что стоит ВЫШЕ и НИЖЕ блока
/// проверок в `_ConnectPane`. Копия структуры из home_screen.dart.
void main() {
  Widget host(Widget child, {double scale = 1.0}) => MaterialApp(
        locale: const Locale('ru'),
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 584,
                  child: Column(
                      key: const Key('probe'),
                      mainAxisSize: MainAxisSize.min,
                      children: [child]),
                ),
              ),
            ),
          );
        }),
      );

  Widget above(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(
          child: Text(l.serviceChecksLegendBefore,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).hintColor)),
        ),
        InfoTooltip(l.serviceChecksInfo),
        // Кнопка подменю — тот же IconButton, что и в приложении.
        IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () {},
            icon: const Icon(Icons.tune)),
      ]),
      const SizedBox(height: 4),
    ]);
  }

  Widget below(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 16),
      Text('Отключено', style: Theme.of(context).textTheme.titleMedium),
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
      // _TrafficRow
      Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_downward, size: 16),
              const SizedBox(width: 4),
              Text('0 Б/с', style: Theme.of(context).textTheme.titleSmall),
            ]),
            Text('0 Б', style: Theme.of(context).textTheme.bodySmall),
          ]),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_upward, size: 16),
              const SizedBox(width: 4),
              Text('0 Б/с', style: Theme.of(context).textTheme.titleSmall),
            ]),
            Text('0 Б', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
        const SizedBox(height: 6),
        Text(l.homeSessionTraffic('0 Б', '0 Б'),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    ]);
  }

  for (final s in [1.0, 1.15, 1.3]) {
    testWidgets('замер при масштабе $s', (t) async {
      t.view.physicalSize = const Size(1000, 2000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
          host(Builder(builder: (c) => above(c)), scale: s));
      await t.pump();
      final hAbove = t.getSize(find.byKey(const Key('probe'))).height;
      await t.pumpWidget(
          host(Builder(builder: (c) => below(c)), scale: s));
      await t.pump();
      final hBelow = t.getSize(find.byKey(const Key('probe'))).height;
      // ignore: avoid_print
      print('scale=$s  above=$hAbove  below=$hBelow  sum=${hAbove + hBelow}');
    });
  }
}
