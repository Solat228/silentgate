import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/ui/widgets/subscription_bar.dart';

/// Компактная карточка подписки на низком окне.
///
/// ⚠️ ОТКУДА. Разбор вёрстки 10.09.2026: на минимальном окне 980×800 (клиент
/// 964×761) карточка с объявлением от панели съедала до 200 px, и при длинном
/// тексте низ главного экрана снова прятался. Решение владельца — на низком
/// окне карточка сворачивается: объявление и ссылки уезжают под «⋮», а у
/// кнопки появляется метка, что внутри непрочитанное.
///
/// Здесь стережётся ФАКТ, а не намерение: карточка меряется в пикселях на том
/// самом размере, объявление достаётся из меню, высокое окно не изменилось,
/// крупный шрифт не переполняет.
void main() {
  final l = AppLocalizationsRu();

  Directory? tmp;
  AppState? state;

  /// Состояние с ОДНОЙ подпиской; [announce] — объявление от панели (null =
  /// панель ничего не прислала).
  Future<AppState> init({String? announce = _announce}) async {
    tmp = Directory.systemTemp.createTempSync('sg_sub_compact_');
    AppPaths.overrideRoot(tmp!);
    final sep = Platform.pathSeparator;
    // Автообновление выключено: тест не должен ходить в сеть.
    File('${tmp!.path}${sep}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp!.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
      'activeId': _id,
      'items': [
        {
          'id': _id,
          'url': _url,
          'servers': [_link],
          'info': {
            'title': 'SilentGate VPN',
            'uploadBytes': 1 << 30,
            'downloadBytes': 5 << 30,
            'totalBytes': 100 << 30,
            'expiresAt': '2099-01-01T00:00:00.000Z',
            'announce': announce,
          },
        },
      ],
    }));
    SubscriptionBar.resetReadAnnouncesForTests();
    final s = AppState(engine: _FakeEngine());
    await s.init();
    state = s;
    return s;
  }

  tearDown(() async {
    state?.dispose();
    state = null;
    // Фоновые цепочки состояния успевают дописать файлы уже после dispose —
    // сперва даём им кадр, и только потом снимаем подмену каталога.
    await Future<void>.delayed(Duration.zero);
    AppPaths.resetForTests();
    try {
      tmp?.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpBar(WidgetTester tester,
      {required Size size,
      bool? compact,
      double textScale = 1.0,
      AppState? withState}) async {
    // ⚠️ `runAsync`, А НЕ ПРОСТО `await`: тело `testWidgets` идёт под
    // FakeAsync, где таймеры `AppState.init()` не тикают, — прямой `await`
    // висел бы вечно, и таймаут теста этого не ловил.
    final state = withState ?? (await tester.runAsync(init))!;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Карточка живёт в левой панели главного экрана шириной ~584 px на
        // минимальном окне (964 − 380 список) — ширину даём ту же, иначе
        // объявление переносится не так и замер врёт.
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
                size: size, textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 584,
                // В `Column`, как на главном экране: там карточка получает
                // высоту по содержимому, а в свободном слоте `Column` внутри
                // неё растянулся бы на всё окно, и замер мерил бы окно.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [SubscriptionBar(compact: compact)],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  double cardHeight(WidgetTester tester) =>
      tester.getSize(find.byType(Card)).height;

  group('низкое окно 964×761', () {
    testWidgets(
        '⚠️ ЗАМЕР: компактная карточка ниже полной не меньше чем на 60 px',
        (tester) async {
      // Полная карточка — принудительно, чтобы замерить «до» на том же окне.
      await pumpBar(tester, size: _lowWindow, compact: false);
      final full = cardHeight(tester);
      // Объявление в три строки действительно ВИДНО в полной — иначе замер
      // «до» был бы замером карточки без объявления.
      expect(find.text(_announce), findsOneWidget);

      await pumpBar(tester, size: _lowWindow, withState: state);
      final compact = cardHeight(tester);
      // Печатаем числа: отчёт требует замера «до/после», а не «стало меньше».
      // ignore: avoid_print
      print('SubscriptionBar 964×761: полная ${full.round()} px, '
          'компактная ${compact.round()} px, выигрыш ${(full - compact).round()} px');
      expect(full - compact, greaterThanOrEqualTo(60),
          reason: 'цель правки — выиграть не меньше 60 px на низком окне');
      // Компактная карточка не показывает ни объявления, ни кнопок-ссылок.
      expect(find.text(_announce), findsNothing);
      expect(find.text(l.subBarSupport), findsNothing);
      expect(find.text(l.subBarOpenSite), findsNothing);
      // Но остаётся всё, ради чего карточка нужна: имя, шкала, «N из M», срок.
      expect(find.text('SilentGate VPN'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining(l.subBarGbUnit), findsOneWidget);
      expect(find.text(l.subBarValidUntil), findsOneWidget);
    });

    testWidgets('автоматика: ниже порога карточка сворачивается сама',
        (tester) async {
      await pumpBar(tester, size: _lowWindow);
      expect(SubscriptionBar.isCompactFor(tester.element(find.byType(Card))),
          isTrue);
      expect(find.text(_announce), findsNothing);
    });

    testWidgets('⚠️ объявление не теряется: метка на «⋮», пункт в меню, диалог',
        (tester) async {
      await pumpBar(tester, size: _lowWindow);
      // Метка «внутри непрочитанное» видна, пока объявление не открыто.
      expect(find.byKey(SubscriptionBar.unreadBadgeKey), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // В меню — и объявление, и «Поддержка», и «Сайт» (они ушли из карточки).
      expect(find.text(SubscriptionBar.announceLabel(l)), findsOneWidget);
      expect(find.text(l.subBarSupport), findsOneWidget);
      expect(find.text(l.subBarOpenSite), findsOneWidget);

      await tester.tap(find.text(SubscriptionBar.announceLabel(l)));
      await tester.pumpAndSettle();
      // Диалог показывает полный текст объявления.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_announce), findsOneWidget);

      await tester.tap(find.text(l.commonClose));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      // Прочитано — метка снята. ⚠️ Именно СНЯТА, а не «висит вечно»: метка,
      // которая горит всегда, перестаёт что-либо значить.
      expect(find.byKey(SubscriptionBar.unreadBadgeKey), findsNothing);
    });

    testWidgets('без объявления метки на «⋮» нет и пункта в меню нет',
        (tester) async {
      await pumpBar(tester,
          size: _lowWindow,
          withState: await tester.runAsync(() => init(announce: null)));
      expect(find.byKey(SubscriptionBar.unreadBadgeKey), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(SubscriptionBar.announceLabel(l)), findsNothing);
      expect(find.text(l.subBarSupport), findsOneWidget);
    });

    testWidgets('крупный шрифт ×1,3 — без переполнения', (tester) async {
      await pumpBar(tester, size: _lowWindow, textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('высокое окно 1200×960 — регресс', () {
    testWidgets('вид не изменился: объявление и кнопки в карточке, метки нет',
        (tester) async {
      await pumpBar(tester, size: _tallWindow);
      expect(SubscriptionBar.isCompactFor(tester.element(find.byType(Card))),
          isFalse);
      expect(find.text(_announce), findsOneWidget);
      expect(find.text(l.subBarSupport), findsOneWidget);
      expect(find.text(l.subBarOpenSite), findsOneWidget);
      expect(find.byKey(SubscriptionBar.unreadBadgeKey), findsNothing);
      // Меню прежнее: пункта «Объявление» в нём нет — объявление и так на виду.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(SubscriptionBar.announceLabel(l)), findsNothing);
      expect(find.text(l.subBarCopyLink), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('крупный шрифт ×1,3 — без переполнения', (tester) async {
      await pumpBar(tester, size: _tallWindow, textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  test('порог сворачивания: минимальное окно — ниже, 960 — выше', () {
    // ⚠️ Порог — граница между «низом, который прячется» и «местом, которого
    // хватает»: минимальное окно Windows (клиент 761) обязано быть под ним,
    // иначе правка не решает ту жалобу, ради которой сделана.
    expect(SubscriptionBar.compactBelowHeight, greaterThan(761));
    expect(SubscriptionBar.compactBelowHeight, lessThanOrEqualTo(900));
  });
}

const Size _lowWindow = Size(964, 761);
/// Высокое окно берём с запасом над порогом, а не впритык: тест про «вид не
/// изменился», а не про граничное значение (его стережёт отдельный тест).
const Size _tallWindow = Size(1200, 960);

/// Объявление «в три строки» на ширине панели ~584 px при bodySmall.
const _announce =
    'Уважаемые пользователи! В ночь с 12 на 13 сентября проводятся '
    'плановые работы на узлах в Германии и Нидерландах. Возможны кратковременные '
    'обрывы соединения, переподключитесь на другой сервер. Спасибо за понимание.';

const _url = 'https://panel.example/sub/aaaaaaaa';
final _id = SubscriptionProfile.idFor(_url);
const _link = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
    '?type=tcp&security=none#Alpha-1';

/// Движок-пустышка: `AppState` подписывается на его потоки в конструкторе,
/// самому тесту движок не нужен — ни одного подключения здесь нет.
class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();

  @override
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
