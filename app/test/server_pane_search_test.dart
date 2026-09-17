import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/import_screen.dart';
import 'package:silentgate/ui/widgets/server_search_field.dart';

/// СТРАЖ НА `ServerPane` (`app/lib/ui/home_screen.dart`): не было ни одного
/// теста ни на пустой список (плашка импорта вместо панели), ни на поиск как
/// его видит сам виджет — из BACKLOG.md, раздел отложенных тестов вёрстки.
///
/// ⚠️ ГЛАВНОЕ, ЧТО СТЕРЕЖЁТСЯ. `ServerSearch.matchIndices` уже проверен как
/// чистая функция (`probe_test.dart`), но `ServerPane` могла бы вызвать её
/// правильно и всё равно передать `state.selectServer` не тот индекс — строка
/// `onTap: () => state.selectServer(idx)` использует `idx = shown[i]`
/// (ИСХОДНЫЙ индекс), а не позицию `i` в отфильтрованном списке. Мутация
/// «выбирать по позиции в списке, а не по исходному индексу» уже стоила
/// проекту переезда выбора на соседний сервер (см. комментарии в
/// `home_screen.dart` и `server_search.dart`) — здесь она проверяется на
/// СОБРАННОМ виджете, а не на изолированной функции.
void main() {
  late Directory tmp;

  const linkA = 'vless://11111111-2222-3333-4444-555555555555'
      '@a.example.com:443?encryption=none#Alpha';
  const linkB = 'vless://11111111-2222-3333-4444-555555555555'
      '@b.example.com:443?encryption=none#Bravo';
  const linkC = 'vless://11111111-2222-3333-4444-555555555555'
      '@c.example.com:443?encryption=none#Charlie';

  late Future<ServiceCheckOutcome> Function(int, ProbeService) savedProber;

  setUp(() {
    savedProber = ServiceCheckController.prober;
    ServiceCheckController.prober = (port, s) async =>
        const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 42);
    // ⚠️ Боевой `%APPDATA%` тестам недоступен (`AppPaths`) — свой временный
    // каталог единственный законный путь (`tests-must-not-touch-real-appdata`).
    tmp = Directory.systemTemp.createTempSync('sg_server_pane_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() async {
    ServiceCheckController.prober = savedProber;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  void writeSubscriptions(List<String> servers) {
    File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    if (servers.isEmpty) {
      // Без файла подписок вовсе — ровно то состояние, в котором приложение
      // оказывается до первого импорта.
      return;
    }
    File('${tmp.path}${Platform.pathSeparator}subscriptions.json')
        .writeAsStringSync(jsonEncode({
      'activeId': 'sub-test',
      'items': [
        {
          'id': 'sub-test',
          'url': 'https://panel.example/sub',
          'title': 'Test',
          'servers': servers,
          'addedAt': '2026-09-01T00:00:00.000Z',
        },
      ],
    }));
  }

  /// ⚠️ Через `runAsync` — иначе `AppState.init()` (реальный диск) висит под
  /// фальшивым временем `testWidgets` (см. `auto_pick_placement_test.dart`).
  Future<AppState> boot(WidgetTester t) async {
    final state = AppState(engine: _FakeEngine());
    await t.runAsync(() => state.init());
    return state;
  }

  Widget host(Widget child, AppState state) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ProbeController>.value(
              value: ProbeController()),
          ChangeNotifierProvider<SettingsController>.value(
              value: SettingsController()),
          ChangeNotifierProvider<AutoConfigController>.value(
              value: AutoConfigController()),
          ChangeNotifierProvider<ServiceCheckController>.value(
              value: ServiceCheckController()),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox(width: 380, height: 700, child: child)),
        ),
      );

  Future<AppState> pumpPane(
    WidgetTester t, {
    required List<String> servers,
    void Function(Widget screen)? onOpen,
  }) async {
    t.view.physicalSize = const Size(800, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    writeSubscriptions(servers);
    final state = await boot(t);
    await t.pumpWidget(host(ServerPane(onOpen: onOpen ?? (_) {}), state));
    await t.pump();
    return state;
  }

  group('⚠️ пустой список серверов — экран импорта, а не список', () {
    testWidgets('без серверов показана плашка импорта', (t) async {
      final l = AppLocalizationsRu();
      await pumpPane(t, servers: const []);
      expect(t.takeException(), isNull);

      expect(find.text(l.homeOnboardingTitle), findsOneWidget,
          reason: 'пустой список обязан давать экран приглашения к импорту');
      expect(find.text(l.homeImportSubscription), findsOneWidget);
      // Поиска и кнопки подбора при пустом списке нет: пингвать/подбирать
      // не из чего.
      expect(find.byType(ServerSearchField), findsNothing);
    });

    testWidgets('кнопка приглашения открывает ИМЕННО экран импорта',
        (t) async {
      Widget? opened;
      await pumpPane(t, servers: const [], onOpen: (w) => opened = w);
      await t.tap(find.byType(FilledButton));
      await t.pump();
      expect(opened, isA<ImportScreen>(),
          reason: 'кнопка на плашке обязана вести в импорт подписки, а не '
              'никуда');
    });

    testWidgets('появление серверов убирает плашку импорта', (t) async {
      final l = AppLocalizationsRu();
      await pumpPane(t, servers: const [linkA]);
      expect(find.text(l.homeOnboardingTitle), findsNothing,
          reason: 'сервер есть — приглашение импортировать больше не нужно');
      expect(find.byType(ServerSearchField), findsOneWidget);
    });
  });

  group('⚠️ поиск возвращает ИСХОДНЫЙ сервер, а не позицию в отфильтрованном '
      'списке', () {
    testWidgets('нашли ОДИН сервер не с начала списка — клик выбирает ЕГО',
        (t) async {
      // Порядок: Alpha(0), Bravo(1), Charlie(2). Ищем «charlie» — под запрос
      // подходит только Charlie, но он ТРЕТИЙ в исходном списке и ПЕРВЫЙ (и
      // единственный) в отфильтрованном. Мутация «выбирать по позиции в
      // видимом списке» дала бы здесь тот же результат, что и правильный код
      // (оба укажут на Charlie) — поэтому ниже отдельный тест с ДВУМЯ
      // совпадениями, где позиция и исходный индекс расходятся по-настоящему.
      final state = await pumpPane(t, servers: const [linkA, linkB, linkC]);
      final l = AppLocalizationsRu();

      await t.enterText(
          find.descendant(
              of: find.byType(ServerSearchField), matching: find.byType(TextField)),
          'charlie');
      await t.pump();
      expect(find.text(l.homeFoundCount(1, 3)), findsOneWidget);

      await t.tap(find.text('Charlie'));
      await t.pump();
      expect(state.selectedServer?.displayName, 'Charlie');
      expect(state.selectedIndex, 2,
          reason: 'Charlie лежит третьим в ИСХОДНОМ списке AppState.servers');
    });

    testWidgets(
        '⚠️ ДВА совпадения, позиция и исходный индекс расходятся — мутация '
        'здесь красит', (t) async {
      // Список: Alpha(0), Bravo(1, содержит "brA"), BravoTwo(2, тоже "brA").
      // Ищем «bra» — попадают Bravo(1) и BravoTwo(2), Alpha(0) исключена.
      // Кликаем ВТОРУЮ строку отфильтрованного списка (позиция 1). Верный
      // код передаёт `state.selectServer(shown[1])` = `selectServer(2)`
      // (BravoTwo). Мутация «передавать позицию `i` в списке вместо
      // `shown[i]`» передала бы `selectServer(1)` (Bravo) — те же ДВЕ
      // строки на экране, но НЕ ТОТ сервер получает выбор.
      const linkBravoTwo = 'vless://11111111-2222-3333-4444-555555555555'
          '@d.example.com:443?encryption=none#BravoTwo';
      final state =
          await pumpPane(t, servers: const [linkA, linkB, linkBravoTwo]);

      await t.enterText(
          find.descendant(
              of: find.byType(ServerSearchField), matching: find.byType(TextField)),
          'bra');
      await t.pump();

      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('BravoTwo'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing,
          reason: 'Alpha не подходит под запрос «bra» и не должна остаться '
              'на экране');

      await t.tap(find.text('BravoTwo'));
      await t.pump();
      expect(state.selectedServer?.displayName, 'BravoTwo',
          reason: 'клик по BravoTwo обязан выбрать именно его — это и есть '
              'регресс «выбор уезжает на соседа», который уже ловили');
      expect(state.selectedIndex, 2,
          reason: 'BravoTwo лежит третьим (индекс 2) в AppState.servers, а '
              'не вторым (позиция в отфильтрованном списке)');
    });

    testWidgets('запрос без совпадений — список пуст, поле поиска цело',
        (t) async {
      final l = AppLocalizationsRu();
      await pumpPane(t, servers: const [linkA, linkB, linkC]);
      await t.enterText(
          find.descendant(
              of: find.byType(ServerSearchField), matching: find.byType(TextField)),
          'зимбабве');
      await t.pump();
      expect(find.text(l.homeNothingFound), findsOneWidget);
      expect(find.byType(ServerSearchField), findsOneWidget,
          reason: 'поиск не должен исчезать вместе с результатами');
    });

    testWidgets('очистка запроса возвращает весь список', (t) async {
      final l = AppLocalizationsRu();
      await pumpPane(t, servers: const [linkA, linkB, linkC]);
      final field = find.descendant(
          of: find.byType(ServerSearchField), matching: find.byType(TextField));
      await t.enterText(field, 'charlie');
      await t.pump();
      expect(find.text(l.homeFoundCount(1, 3)), findsOneWidget);

      await t.enterText(field, '');
      await t.pump();
      expect(find.text(l.homeServersCount(3)), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });
  });
}

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
