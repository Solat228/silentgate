import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/info_tooltip.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// Жалоба владельца, поданная ДВАЖДЫ: «ты так и не исправил имя сервера,
/// который подключен» — плашка над кнопкой Connect лежала на верхней кромке
/// круга и на колонках проверок сервисов.
///
/// ⚠️ ПОЧЕМУ ЭТОТ СТРАЖ ПОДНИМАЕТ [ConnectCenterpiece], А НЕ СВОЮ СТРОКУ.
/// Прошлый страж собирал раскладку сам: `Row` с `Expanded`-заглушками вместо
/// колонок проверок. Он был зелёным всё время, пока плашка наезжала на
/// настоящие колонки, — потому что проверял копию, а не экран. Здесь поднимается
/// ровно тот виджет, который стоит в `ConnectPane`.
void main() {
  /// Круг кнопки Connect: 148 px — размер `_ConnectButton` на нормальной высоте
  /// (на низком экране он ужимается до 116, и плашке от этого только просторнее).
  const buttonSize = 148.0;
  const btnKey = Key('btn');

  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider(
          create: (_) => ServiceCheckController(),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  /// ⚠️ Размер задаётся ОКНУ, а не виджету: поверхность теста по умолчанию
  /// 800×600 зажала бы строку, и плашка «уместилась» бы по чужой причине.
  Future<void> pump(
    WidgetTester t, {
    required String? name,
    double width = 1040,
    int httpPort = 10809,
  }) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = Size(width, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(host(ConnectCenterpiece(
      serverName: name,
      httpPort: httpPort,
      button: const SizedBox(key: btnKey, width: buttonSize, height: buttonSize),
    )));
    await t.pump();
  }

  Rect labelRect(WidgetTester t) => t.getRect(find.byType(ActiveServerLabel));
  /// ⚠️ РЯДЫ, А НЕ КОЛОНКИ. Проверки переехали из двух столбцов по бокам
  /// кнопки в ряды по смысловым группам под ней (19.08.2026): при четырнадцати
  /// сервисах столбцы лезли за край экрана, а сама группировка, ради которой их
  /// и заводили, до интерфейса не доходила вовсе.
  Rect rowsRect(WidgetTester t) => t.getRect(find.byType(ServiceChecksRows));

  RenderParagraph paragraph(WidgetTester t) => t.renderObject<RenderParagraph>(
      find.descendant(
          of: find.byType(ActiveServerLabel), matching: find.byType(Text)));

  /// Имя владельца со скриншота: флаг, эмодзи, номер и метка в скобках.
  const ownerName = '🇩🇪 🚀Германия 2.7 (edge)';

  /// 60+ символов — такие имена у панелей встречаются регулярно.
  const longName = '🇳🇱 Нидерланды Амстердам премиум канал для просмотра '
      'видео и работы, узел двадцать семь';

  group('Плашка активного сервера не наезжает ни на кого', () {
    testWidgets('имя владельца: ни круга, ни колонок не касается', (t) async {
      await pump(t, name: ownerName);
      expect(t.takeException(), isNull);

      final label = labelRect(t);
      final btn = t.getRect(find.byKey(btnKey));
      expect(label.overlaps(btn), isFalse,
          reason: 'плашка лежала на верхней кромке круга — именно это владелец '
              'и показывал на скриншоте');
      expect(label.bottom, lessThanOrEqualTo(btn.top),
          reason: 'плашка обязана стоять НАД кнопкой, а не поверх неё');
      expect(label.overlaps(rowsRect(t)), isFalse,
          reason: 'плашка накрыла ряды проверок');
    });

    testWidgets('длинное имя: то же самое и на узком окне', (t) async {
      await pump(t, name: longName, width: 360);
      expect(t.takeException(), isNull,
          reason: 'переполнение вёрстки — это и есть «плашка обрезалась»');

      final label = labelRect(t);
      final btn = t.getRect(find.byKey(btnKey));
      expect(label.overlaps(btn), isFalse);
      expect(label.overlaps(rowsRect(t)), isFalse);
      expect(label.left, greaterThanOrEqualTo(0));
      expect(label.right, lessThanOrEqualTo(360),
          reason: 'плашка уехала за край экрана');
    });

    testWidgets('длинное имя на широком окне не растягивает плашку', (t) async {
      await pump(t, name: longName);
      expect(t.takeException(), isNull);
      expect(labelRect(t).width,
          lessThanOrEqualTo(ActiveServerLabel.maxWidth + 0.5),
          reason: 'без потолка пилюля растянулась бы через весь экран');
    });

    testWidgets('короткое имя ужимается по содержимому', (t) async {
      await pump(t, name: 'DE-1');
      expect(labelRect(t).width, lessThan(160),
          reason: 'иначе короткое имя болталось бы посреди пилюли во всю кнопку');
    });
  });

  group('Длинное имя показывается, а не съедается', () {
    testWidgets('имя владельца влезает целиком, без многоточия', (t) async {
      await pump(t, name: ownerName);
      expect(paragraph(t).didExceedMaxLines, isFalse,
          reason: 'ровно то имя, что у владельца на экране, — если уж и его '
              'режет, плашка бессмысленна');
      expect(find.text('🚀Германия 2.7 (edge)'), findsOneWidget,
          reason: 'флаг рисуется картинкой и вырезается из текста');
    });

    testWidgets('на длинное имя отдаётся вторая строка', (t) async {
      await pump(t, name: 'DE-1');
      final short = paragraph(t).size.height;
      await pump(t, name: longName);
      final long = paragraph(t).size.height;
      expect(long, greaterThan(short),
          reason: 'одна строка обрезала имя ровно там, где начинается отличие '
              'узлов друг от друга: номер и метка edge/premium');
    });

    testWidgets('полное имя всегда доступно подсказкой', (t) async {
      await pump(t, name: longName);
      expect(find.byTooltip(longName), findsOneWidget,
          reason: 'что не влезло в плашку, человек обязан суметь прочитать');
    });
  });

  group('Место под плашку занято всегда', () {
    testWidgets('кнопка и ряды не прыгают при подключении', (t) async {
      await pump(t, name: null, httpPort: 0);
      final btnOff = t.getRect(find.byKey(btnKey));
      final rowsOff = rowsRect(t);

      await pump(t, name: ownerName);
      expect(t.getRect(find.byKey(btnKey)), btnOff,
          reason: 'плашка появляется при подключении — если она забирает место '
              'только тогда, вся середина экрана дёргается на каждом Connect');
      expect(rowsRect(t), rowsOff);
    });

    testWidgets('без подключения имени не видно', (t) async {
      await pump(t, name: null, httpPort: 0);
      expect(find.text('DE-1'), findsNothing);
      final vis = t.widget<Visibility>(find
          .ancestor(
              of: find.byType(ActiveServerLabel),
              matching: find.byType(Visibility))
          .first);
      expect(vis.visible, isFalse,
          reason: 'место держим, а пустую пилюлю не рисуем');
    });
  });

  /// КНОПКИ «i» И ПОДМЕНЮ ЖИВУТ В ПОЛОСЕ ПЛАШКИ, А НЕ СВОЕЙ СТРОКОЙ.
  ///
  /// ⚠️ Решение владельца (08.09.2026): легенду «Слева — без VPN…» убрать
  /// совсем, оставить только «i». Её строка стоила 42 px — ровно те, из-за
  /// которых низ экрана обрезался на минимальном окне. Кнопки переезжают в
  /// правый край полосы плашки: та держит высоту всегда
  /// (`Visibility(maintainSize)`), значит собственного ряда они не стоят.
  ///
  /// ⚠️ ЦЕНТРОВКА — СИММЕТРИЧНОЙ РАСПОРКОЙ. Без неё плашка уезжает от оси
  /// кнопки на половину ширины кнопок — и это видно глазом.
  group('Хвост полосы плашки', () {
    const trailingKey = Key('trailing');
    Widget trailing() => const Row(
          key: trailingKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 28, height: 28),
            SizedBox(width: 2),
            SizedBox(width: 28, height: 28),
          ],
        );

    Future<void> pumpWithTrailing(WidgetTester t,
        {required String? name, Widget? tail}) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1040, 900);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(SizedBox(
        width: 584,
        child: ConnectCenterpiece(
          serverName: name,
          httpPort: 10809,
          button: const SizedBox(
              key: btnKey, width: buttonSize, height: buttonSize),
          bannerTrailing: tail,
        ),
      )));
      await t.pump();
    }

    testWidgets('⚠️ плашка остаётся на оси кнопки', (t) async {
      await pumpWithTrailing(t, name: ownerName, tail: trailing());
      expect(t.takeException(), isNull);
      final label = labelRect(t);
      final btn = t.getRect(find.byKey(btnKey));
      expect(label.center.dx, closeTo(btn.center.dx, 1.0),
          reason: 'хвост сдвинул плашку с оси кнопки на '
              '${(label.center.dx - btn.center.dx).toStringAsFixed(1)} px');
    });

    testWidgets('хвост стоит в полосе плашки, у правого края', (t) async {
      await pumpWithTrailing(t, name: ownerName, tail: trailing());
      final banner = t.getRect(find.byType(ActiveServerBanner));
      final tail = t.getRect(find.byKey(trailingKey));
      final label = labelRect(t);
      expect(tail.top, greaterThanOrEqualTo(banner.top - 0.5));
      expect(tail.bottom, lessThanOrEqualTo(banner.bottom + 0.5),
          reason: 'хвост вылез из полосы плашки');
      expect(tail.left, greaterThanOrEqualTo(label.right),
          reason: 'хвост наехал на плашку');
      expect(tail.right, closeTo(banner.right, 0.5),
          reason: 'хвост не прижат к правому краю полосы');
    });

    testWidgets('⚠️ хвост не стоит собственного ряда', (t) async {
      // Полоса — это плашка плюс просвет до кнопки. Хвост ниже плашки по
      // высоте, значит полоса с ним обязана быть той же высоты, что и без.
      await pumpWithTrailing(t, name: ownerName);
      final plain = t.getSize(find.byType(ActiveServerBanner)).height;
      await pumpWithTrailing(t, name: ownerName, tail: trailing());
      final withTail = t.getSize(find.byType(ActiveServerBanner)).height;
      final label = labelRect(t).height;
      // Хвост 28 px: если плашка ниже него, полоса растёт ровно до 28 —
      // и ни на пиксель больше.
      final expected = (label > 28 ? label : 28) + ActiveServerBanner.gap;
      expect(withTail, closeTo(expected, 0.5),
          reason: 'хвост занял собственную строку');
      expect(withTail, greaterThanOrEqualTo(plain - 0.5),
          reason: 'полоса с хвостом стала ниже, чем без него');
    });

    testWidgets('⚠️ НАСТОЯЩИЕ кнопки хвоста тоже не растят полосу', (t) async {
      // Заглушки выше — 28 px по построению. Настоящие `IconButton` без
      // зажима тянутся до 40 px областью нажатия Material — и полоса
      // поднялась бы на 12 px, съев треть выигрыша от убранной легенды.
      // Проверяем ровно те виджеты, что кладёт в хвост главный экран.
      await pumpWithTrailing(t, name: ownerName);
      final plain = t.getSize(find.byType(ActiveServerBanner)).height;
      await pumpWithTrailing(
        t,
        name: ownerName,
        tail: const Row(
          key: trailingKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoTooltip('подсказка', compact: true),
            SizedBox(width: 2),
            ServiceChecksMenuButton(),
          ],
        ),
      );
      expect(t.takeException(), isNull);
      final withTail = t.getSize(find.byType(ActiveServerBanner)).height;
      final label = labelRect(t).height;
      final expected = (label > 28 ? label : 28) + ActiveServerBanner.gap;
      expect(withTail, closeTo(expected, 0.5),
          reason: 'настоящие кнопки подняли полосу: было $plain, стало '
              '$withTail');
      final tail = t.getRect(find.byKey(trailingKey));
      expect(tail.height, lessThanOrEqualTo(28.5),
          reason: 'кнопки хвоста выше 28 px');
      expect(tail.width, lessThanOrEqualTo(ActiveServerBanner.trailingWidth),
          reason: 'хвост шире отведённой распорки — центровка уедет');
      // И обе кнопки нажимаются: «i» открывает диалог.
      await t.tap(find.byType(InfoTooltip));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('без имени хвост виден всё равно', (t) async {
      // Кнопкой подменю проверки и включают обратно — прятать её вместе с
      // плашкой значило бы оставить человека без пути назад.
      await pumpWithTrailing(t, name: null, tail: trailing());
      expect(find.byKey(trailingKey), findsOneWidget);
      final tail = t.getRect(find.byKey(trailingKey));
      expect(tail.width, greaterThan(0));
    });

    test('⚠️ страж по исходнику: экран кладёт кнопки в хвост, легенды нет',
        () {
      // Виджет с параметром по умолчанию `null` компилятор не проверит:
      // забытый `bannerTrailing:` молча оставил бы главный экран без «i» и
      // без подменю — а подменю единственный путь включить проверки обратно.
      final home = File('lib/ui/home_screen.dart')
          .readAsLinesSync()
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join(String.fromCharCode(10));
      final at = home.indexOf('ConnectCenterpiece(');
      expect(at, greaterThan(0));
      final call = home.substring(at, at + 1200);
      expect(call, contains('bannerTrailing:'),
          reason: 'кнопки «i» и подменю не переданы в полосу плашки');
      expect(call, contains('ServiceChecksMenuButton('),
          reason: 'подменю проверок пропало с главного экрана');
      expect(call, contains('serviceChecksInfo'),
          reason: 'подсказка «i» пропала с главного экрана');
      expect(home, isNot(contains('serviceChecksLegend')),
          reason: 'легенда должна быть убрана целиком — решение владельца');
    });
  });

  group('Имя — того сервера, ЧЕРЕЗ КОТОРЫЙ идёт трафик', () {
    // Ключ сервера — это его share-ссылка целиком (`VpnServer.key`).
    VpnServer srv(String remark) => VpnServer(
          protocol: 'vless',
          address: '$remark.example.com',
          port: 443,
          id: '11111111-2222-3333-4444-555555555555',
          remark: remark,
          rawLink: 'vless://11111111-2222-3333-4444-555555555555'
              '@$remark.example.com:443?encryption=none#$remark',
        );

    final servers = [srv('Germany'), srv('Netherlands')];

    test('выбор ДРУГОГО сервера подпись не меняет', () {
      // Поднят ВТОРОЙ сервер, а в списке выбран первый: `AppState.selectServer`
      // живой туннель не трогает, он лишь просит переподключиться. Плашка
      // обязана называть тот узел, через который идёт трафик.
      final name = activeServerName(
        connected: true,
        connectedKey: servers[1].key,
        servers: servers,
        autoLabel: 'Авто',
      );
      expect(name, servers[1].displayName);
      expect(name, isNot(servers.first.displayName),
          reason: 'подпись назвала выбранный в списке сервер вместо поднятого');
    });

    test('без подключения подписи нет вовсе', () {
      expect(
          activeServerName(
            connected: false,
            connectedKey: servers.first.key,
            servers: servers,
            autoLabel: 'Авто',
          ),
          isNull);
    });

    test('режим «Авто»: сессию держит балансировщик, а не узел', () {
      expect(
          activeServerName(
            connected: true,
            connectedKey: null,
            servers: servers,
            autoLabel: 'Авто',
          ),
          'Авто');
    });

    test('исчезнувший из подписки сервер не выдаёт свой ключ', () {
      final name = activeServerName(
        connected: true,
        connectedKey: srv('Gone').key,
        servers: servers,
        autoLabel: 'Авто',
      );
      // Ключ — это share-ссылка с логином сервера внутри; показывать её нельзя
      // ни при каких обстоятельствах.
      expect(name, 'Авто');
      expect(name, isNot(contains('vless://')));
    });
  });
}
