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
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/subscription_bar.dart';

/// Карточка подписки: компактный вид на низком окне и объявление от сервиса.
///
/// ⚠️ ОТКУДА. Разбор вёрстки 10.09.2026: на минимальном окне 980×800 (клиент
/// 964×761) карточка с объявлением от панели съедала до 200 px — карточку
/// научили сворачиваться, и объявление уехало под «⋮». 17.09.2026 владелец
/// открыл телефон: «ты съел объявление от панели». На телефоне высота окна
/// почти всегда ниже порога, то есть компактный вид там — не исключение, а
/// правило, и объявление человек не видел ВООБЩЕ. Решение владельца:
/// объявление видно по умолчанию на любой высоте, спрятать его можно
/// настройкой, заголовок — «Объявления от сервиса <имя>».
///
/// Здесь стережётся ФАКТ, а не намерение: объявление ищется в дереве на том
/// самом низком окне и на телефоне 360 px, настройка убирает его отовсюду,
/// заголовок несёт имя сервиса, высокое окно не изменилось, крупный шрифт не
/// переполняет.
void main() {
  final l = AppLocalizationsRu();

  Directory? tmp;
  AppState? state;
  SettingsController? settingsCtrl;

  /// Состояние с ОДНОЙ подпиской; [announce] — объявление от панели (null =
  /// панель ничего не прислала), [title] — имя сервиса из подписки,
  /// [hideAnnounce] — настройка «скрыть объявления».
  Future<AppState> init(
      {String? announce = _announce,
      String? title = _service,
      bool hideAnnounce = false}) async {
    tmp = Directory.systemTemp.createTempSync('sg_sub_compact_');
    AppPaths.overrideRoot(tmp!);
    final sep = Platform.pathSeparator;
    // Автообновление выключено: тест не должен ходить в сеть.
    File('${tmp!.path}${sep}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({
      'autoUpdateEnabled': false,
      'hidePanelAnnounce': hideAnnounce,
    }));
    File('${tmp!.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
      'activeId': _id,
      'items': [
        {
          'id': _id,
          'url': _url,
          'servers': [_link],
          'info': {
            'title': title,
            'uploadBytes': 1 << 30,
            'downloadBytes': 5 << 30,
            'totalBytes': 100 << 30,
            'expiresAt': '2099-01-01T00:00:00.000Z',
            'announce': announce,
          },
        },
      ],
    }));
    // Настройки читаются с того же диска, что и подписка: карточка спрашивает
    // «скрыть объявления» у настоящего контроллера, а не у подмены.
    final sc = SettingsController();
    await sc.init();
    settingsCtrl = sc;
    final s = AppState(engine: _FakeEngine());
    await s.init();
    state = s;
    return s;
  }

  tearDown(() async {
    state?.dispose();
    state = null;
    settingsCtrl?.dispose();
    settingsCtrl = null;
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
      double paneWidth = 584,
      AppState? withState}) async {
    // ⚠️ `runAsync`, А НЕ ПРОСТО `await`: тело `testWidgets` идёт под
    // FakeAsync, где таймеры `AppState.init()` не тикают, — прямой `await`
    // висел бы вечно, и таймаут теста этого не ловил.
    final state = withState ?? (await tester.runAsync(init))!;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl!),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Карточка живёт в левой панели главного экрана шириной ~584 px на
        // минимальном окне (964 − 380 список) — ширину даём ту же, иначе
        // объявление переносится не так и замер врёт. На телефоне панель —
        // во всю ширину экрана ([paneWidth] = 360).
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
                size: size, textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: paneWidth,
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

  final titled = SubscriptionBar.announceTitle(l, _service);
  final untitled = SubscriptionBar.announceTitle(l, null);

  group('низкое окно 964×761', () {
    testWidgets('⚠️ ЗАМЕР: компактная карточка всё ещё ниже полной',
        (tester) async {
      // Полная карточка — принудительно, чтобы замерить «до» на том же окне.
      await pumpBar(tester, size: _lowWindow, compact: false);
      final full = cardHeight(tester);
      expect(find.text(_announce), findsOneWidget);

      await pumpBar(tester, size: _lowWindow, withState: state);
      final compact = cardHeight(tester);
      // Печатаем числа: отчёт требует замера «до/после», а не «стало меньше».
      // ignore: avoid_print
      print('SubscriptionBar 964×761: полная ${full.round()} px, '
          'компактная ${compact.round()} px, выигрыш ${(full - compact).round()} px');
      // ⚠️ Порог 40, а не прежние 60: объявление теперь остаётся в карточке
      // на любой высоте (решение владельца 17.09.2026), компактность выигрывает
      // только на строке трафика и ряде кнопок-ссылок. Ниже 40 — значит
      // компактный вид перестал делать и это.
      expect(full - compact, greaterThanOrEqualTo(40),
          reason: 'компактный вид обязан выигрывать хотя бы кнопки и строку');
      // Кнопки-ссылки ушли под «⋮» …
      expect(find.text(l.subBarSupport), findsNothing);
      expect(find.text(l.subBarOpenSite), findsNothing);
      // … а всё, ради чего карточка нужна, на месте: имя, шкала, «N из M»,
      // срок — И ОБЪЯВЛЕНИЕ.
      expect(find.text(_service), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining(l.subBarGbUnit), findsOneWidget);
      expect(find.text(l.subBarValidUntil), findsOneWidget);
      expect(find.text(_announce), findsOneWidget);
    });

    testWidgets(
        '⚠️ объявление ВИДНО в компактном виде, заголовок несёт имя сервиса',
        (tester) async {
      await pumpBar(tester, size: _lowWindow);
      expect(SubscriptionBar.isCompactFor(tester.element(find.byType(Card))),
          isTrue);
      expect(find.text(_announce), findsOneWidget);
      expect(find.text(titled), findsOneWidget);
      // Имя сервиса — в заголовке блока, а не общее «от панели».
      expect(titled, contains(_service));
      expect(find.text(l.subBarAnnounce), findsNothing);
    });

    testWidgets('в меню «⋮» объявления больше нет — оно и так на виду',
        (tester) async {
      await pumpBar(tester, size: _lowWindow);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      // Ссылки — в меню (они ушли из карточки), объявления — нет.
      expect(find.text(l.subBarSupport), findsOneWidget);
      expect(find.text(l.subBarOpenSite), findsOneWidget);
      expect(find.text(titled), findsOneWidget,
          reason: 'единственный экземпляр — заголовок блока в карточке');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('⚠️ настройка «скрыть»: ни в карточке, ни в меню',
        (tester) async {
      await pumpBar(tester,
          size: _lowWindow,
          withState: await tester.runAsync(() => init(hideAnnounce: true)));
      expect(find.text(_announce), findsNothing);
      expect(find.text(titled), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(_announce), findsNothing);
      expect(find.text(titled), findsNothing);
      expect(find.text(l.subBarAnnounce), findsNothing);
      // Остальное меню цело.
      expect(find.text(l.subBarSupport), findsOneWidget);
    });

    testWidgets('пустое имя сервиса — заголовок без хвоста', (tester) async {
      await pumpBar(tester,
          size: _lowWindow,
          withState: await tester.runAsync(() => init(title: null)));
      expect(find.text(_announce), findsOneWidget);
      expect(find.text(untitled), findsOneWidget);
      expect(untitled, isNot(contains('null')));
      expect(untitled.trim(), untitled,
          reason: 'без имени не должно оставаться висячего пробела');
    });

    testWidgets('имя из одних пробелов = пустое', (tester) async {
      await pumpBar(tester,
          size: _lowWindow,
          withState: await tester.runAsync(() => init(title: '   ')));
      expect(find.text(untitled), findsOneWidget);
    });

    testWidgets('без объявления блока нет', (tester) async {
      await pumpBar(tester,
          size: _lowWindow,
          withState: await tester.runAsync(() => init(announce: null)));
      expect(find.text(titled), findsNothing);
      expect(find.text(untitled), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

  group('телефон 360×640', () {
    testWidgets('объявление видно, вёрстка не переполняется', (tester) async {
      await tester.binding.setSurfaceSize(_phone);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpBar(tester, size: _phone, paneWidth: 360);
      expect(SubscriptionBar.isCompactFor(tester.element(find.byType(Card))),
          isTrue);
      expect(find.text(_announce), findsOneWidget);
      expect(find.text(titled), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Блок ограничен по высоте: длинный текст крутится внутри, а не
      // растягивает карточку на весь экран телефона.
      expect(cardHeight(tester), lessThan(_phone.height / 2));
    });

    testWidgets('крупный шрифт ×1,3 — без переполнения', (tester) async {
      await tester.binding.setSurfaceSize(_phone);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpBar(tester, size: _phone, paneWidth: 360, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text(_announce), findsOneWidget);
    });
  });

  group('высокое окно 1200×960 — регресс', () {
    testWidgets('объявление с заголовком и кнопки в карточке', (tester) async {
      await pumpBar(tester, size: _tallWindow);
      expect(SubscriptionBar.isCompactFor(tester.element(find.byType(Card))),
          isFalse);
      expect(find.text(_announce), findsOneWidget);
      expect(find.text(titled), findsOneWidget);
      expect(find.text(l.subBarSupport), findsOneWidget);
      expect(find.text(l.subBarOpenSite), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(l.subBarCopyLink), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('настройка «скрыть» действует и на высоком окне',
        (tester) async {
      await pumpBar(tester,
          size: _tallWindow,
          withState: await tester.runAsync(() => init(hideAnnounce: true)));
      expect(find.text(_announce), findsNothing);
      expect(find.text(titled), findsNothing);
      expect(find.text(l.subBarSupport), findsOneWidget);
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

/// Телефон: самая частая узкая ширина (360 dp) — там и родилась жалоба.
const Size _phone = Size(360, 640);

const _service = 'SilentGate VPN';

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
