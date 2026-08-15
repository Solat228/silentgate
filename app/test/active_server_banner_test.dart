import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// Жалоба владельца, поданная ДВАЖДЫ: «ты так и не исправил имя сервера,
/// который подключен» — плашка над кнопкой Connect лежала на верхней кромке
/// круга и на колонках проверок сервисов.
///
/// ⚠️ ПОЧЕМУ ЭТОТ СТРАЖ ПОДНИМАЕТ [ConnectCenterpiece], А НЕ СВОЮ СТРОКУ.
/// Прошлый страж собирал раскладку сам: `Row` с `Expanded`-заглушками вместо
/// колонок проверок. Он был зелёным всё время, пока плашка наезжала на
/// настоящие колонки, — потому что проверял копию, а не экран. Здесь поднимается
/// ровно тот виджет, который стоит в `_ConnectPane`.
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
  Rect columnRect(WidgetTester t, int i) =>
      t.getRect(find.byType(ServiceChecksColumn).at(i));

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
      for (var i = 0; i < 2; i++) {
        expect(label.overlaps(columnRect(t, i)), isFalse,
            reason: 'плашка накрыла колонку проверок №${i + 1}');
      }
    });

    testWidgets('длинное имя: то же самое и на узком окне', (t) async {
      await pump(t, name: longName, width: 360);
      expect(t.takeException(), isNull,
          reason: 'переполнение вёрстки — это и есть «плашка обрезалась»');

      final label = labelRect(t);
      final btn = t.getRect(find.byKey(btnKey));
      expect(label.overlaps(btn), isFalse);
      for (var i = 0; i < 2; i++) {
        expect(label.overlaps(columnRect(t, i)), isFalse);
      }
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
    testWidgets('кнопка и колонки не прыгают при подключении', (t) async {
      await pump(t, name: null, httpPort: 0);
      final btnOff = t.getRect(find.byKey(btnKey));
      final leftOff = columnRect(t, 0);

      await pump(t, name: ownerName);
      expect(t.getRect(find.byKey(btnKey)), btnOff,
          reason: 'плашка появляется при подключении — если она забирает место '
              'только тогда, вся середина экрана дёргается на каждом Connect');
      expect(columnRect(t, 0), leftOff);
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
