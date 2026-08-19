import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/servers_screen.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';
import 'package:silentgate/ui/widgets/ping_gate.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// «Почему пинг сейчас нельзя» — один гейт на все точки входа (третий круг
/// ревью, 14.08.2026).
///
/// ⚠️ ЧТО ИМЕННО ЗДЕСЬ СТЕРЕЖЁТСЯ.
///
/// `ProbeController._pingBatch` выходит первой же строкой, если идёт замер
/// скорости: оба прогона делят один харнесс и одни локальные порты. Кнопка на
/// экране серверов и пункт «Пинг» в меню строки спрашивали только
/// `probe.running`: во время замера (десятки минут на сотне серверов) они
/// выглядели живыми, нажатие не делало ничего и ничего не объясняло.
///
/// ⚠️ ГЕЙТ ПРИМЕНЁН РОВНО В ЭТИХ ДВУХ ТОЧКАХ — их и проверяем в настоящих
/// виджетах. Кнопка на главном экране, пункт в меню переключателя подписок и
/// `POST /v1/ping` локального API спрашивают исполнителя своим кодом и на
/// гейт не переведены; обещать за них здесь нечего.
///
/// Плюс — главное — совпадение гейта с ИСПОЛНИТЕЛЕМ: разрешение и исполнение
/// обязаны спрашивать одно и то же (тот же урок, что и у `needsToken` в
/// `single_instance.dart`).
///
/// Ни один тест не ходит в сеть: харнесс подменён, порт он не отдаёт вовсе.
void main() {
  final l = AppLocalizationsRu();

  late Directory tmp;

  setUp(() {
    // Результаты пинга и логи пишутся на диск — свой каталог обязателен.
    tmp = Directory.systemTemp.createTempSync('sg_ping_gate_');
    AppPaths.overrideRoot(tmp);
    AppToast.dismiss();
  });

  tearDown(() async {
    // ⚠️ Дать досчитать фоновым цепочкам. `ProbeController.setResult` уходит в
    // запись БЕЗ await: сбросив подмену раньше, мы отправили бы её резолвить
    // каталог заново — то есть на предохранитель AppPaths (в худшем случае, до
    // его появления, — в боевой %APPDATA%).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Сам гейт ───────────────────────────────────────────────────────────────

  group('PingGate: можно ли пинговать и почему нет', () {
    test('свободно — можно, объяснять нечего', () {
      final g = PingGate.from(
          pinging: false, measuringSpeed: false, hasTargets: true);
      expect(g.allowed, isTrue);
      expect(g.blocker, isNull);
      expect(g.reason(l), isNull);
      expect(g.label(l, 'Пинговать все'), 'Пинговать все');
    });

    test('идёт замер скорости — нельзя, и причина названа вслух', () {
      final g = PingGate.from(
          pinging: false, measuringSpeed: true, hasTargets: true);
      expect(g.allowed, isFalse);
      expect(g.blocker, PingBlocker.measuringSpeed);
      expect(g.reason(l), l.subSwitcherPingBusySpeed);
      // Подпись действия подменяется причиной — иначе кнопка называлась бы
      // «Пинговать все» и молчала.
      expect(g.label(l, l.serversPingAll), l.subSwitcherPingBusySpeed);
    });

    test('идёт пинг — нельзя, причина своя', () {
      final g = PingGate.from(
          pinging: true, measuringSpeed: false, hasTargets: true);
      expect(g.blocker, PingBlocker.pinging);
      expect(g.reason(l), l.serversPinging);
    });

    test('пинговать нечего — по умолчанию про пустой список', () {
      final g = PingGate.from(
          pinging: false, measuringSpeed: false, hasTargets: false);
      expect(g.blocker, PingBlocker.noTargets);
      expect(g.reason(l), l.serversEmpty);
      // Экран вправе сказать точнее: при активном поиске серверы есть, просто
      // ни один не подошёл под запрос.
      expect(g.reason(l, noTargets: l.serversNothingFound),
          l.serversNothingFound);
    });

    test('порядок причин повторяет порядок проверок исполнителя', () {
      // `_pingBatch`: `if (_running || _speedRunning || servers.isEmpty)`.
      expect(
          PingGate.from(pinging: true, measuringSpeed: true, hasTargets: false)
              .blocker,
          PingBlocker.pinging);
      expect(
          PingGate.from(pinging: false, measuringSpeed: true, hasTargets: false)
              .blocker,
          PingBlocker.measuringSpeed);
    });
  });

  // ── Гейт против настоящего исполнителя ─────────────────────────────────────

  group('Гейт и ProbeController отвечают одинаково', () {
    late _GateHarness harness;
    late ProbeController probe;
    const settings = AppSettings();

    // hysteria2 — нарочно: у него нет TCP-фазы (QUIC), поэтому прогон уходит
    // сразу в харнесс и НИ ОДНОГО сокета наружу тест не открывает.
    final hy2a = _hy2('Альфа', 'a.example');
    final hy2b = _hy2('Браво', 'b.example');

    setUp(() {
      harness = _GateHarness();
      probe = ProbeController(harnessFactory: () => harness);
    });

    test('свободный контроллер: гейт открыт И прогон реально начинается',
        () async {
      expect(PingGate.of(probe).allowed, isTrue);

      // Не ждём: `_pingBatch` до первого await успевает поднять флаг и
      // пометить серверы «проверяю» — значит прогон действительно пошёл.
      final run = probe.pingAll([hy2a], settings);
      expect(probe.running, isTrue);
      expect(probe.resultFor(hy2a).outcome, PingOutcome.testing);

      harness.release();
      await run;
      expect(probe.running, isFalse);
    });

    test('идёт замер скорости: гейт закрыт И пинг не запускается', () async {
      // Скорость мерится только у прошедших проверку канала.
      probe.setResult(
          hy2a,
          const PingResult(
              outcome: PingOutcome.ok,
              latencyMs: 40,
              verification: PingVerification.passed));

      final measuring = probe.measureSpeedOne(hy2a, settings);
      expect(probe.speedRunning, isTrue);
      expect(PingGate.of(probe).blocker, PingBlocker.measuringSpeed,
          reason: 'гейт обязан назвать ровно ту причину, по которой '
              'исполнитель откажет');

      // Исполнитель отказывает молча — вот это и проверяем: сервер не помечен
      // «проверяю», второй харнесс не поднят.
      final refused = probe.pingAll([hy2b], settings);
      expect(probe.running, isFalse);
      expect(probe.resultFor(hy2b).outcome, PingOutcome.untested,
          reason: 'прогон бы сразу пометил сервер «проверяю»');
      expect(harness.starts, 1, reason: 'харнесс занят замером скорости');

      harness.release();
      await Future.wait([measuring, refused]);
    });

    test('идёт пинг: гейт закрыт И второй прогон не запускается', () async {
      final first = probe.pingAll([hy2a], settings);
      expect(PingGate.of(probe).blocker, PingBlocker.pinging);

      final second = probe.pingAll([hy2b], settings);
      expect(probe.resultFor(hy2b).outcome, PingOutcome.untested);
      expect(harness.starts, lessThanOrEqualTo(1));

      harness.release();
      await Future.wait([first, second]);
    });

    test('пинговать нечего: гейт закрыт И прогон не начинается', () async {
      expect(PingGate.of(probe, hasTargets: false).blocker,
          PingBlocker.noTargets);
      await probe.pingAll(const [], settings);
      expect(probe.running, isFalse);
      expect(harness.starts, 0);
    });
  });

  // ── Кнопка на экране серверов ──────────────────────────────────────────────

  group('Экран серверов: кнопка пинга', () {
    const urlA = 'https://panel.example/sub/aaaaaaaa';
    const s1 = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
        '?type=tcp&security=none#Alpha-1';
    const s2 = 'vless://11111111-1111-1111-1111-111111111111@a2.example:443'
        '?type=tcp&security=none#Alpha-2';

    late AppState state;
    late _SpyProbe probe;
    late SettingsController settings;

    /// Подписка с двумя серверами кладётся на диск ДО `init()` — тем же путём,
    /// каким она приезжает после перезапуска приложения.
    Future<void> boot() async {
      final sep = Platform.pathSeparator;
      File('${tmp.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp.path}${sep}subscriptions.json')
          .writeAsStringSync(jsonEncode({
        'activeId': SubscriptionProfile.idFor(urlA),
        'items': [
          {
            'id': SubscriptionProfile.idFor(urlA),
            'url': urlA,
            'servers': [s1, s2],
            // ⚠️ Дата добавления — явно. Профилю без неё `AppState.init`
            // проставляет её сам и уходит в ФОНОВУЮ запись
            // (`unawaited(_saveSubscriptions())`), которая может досчитать уже
            // после сброса подмены каталога в `tearDown`.
            'addedAt': '2026-08-01T00:00:00.000Z',
          },
        ],
      }));
      state = AppState(engine: _FakeEngine());
      await state.init();
      probe = _SpyProbe();
      settings = SettingsController();
      await settings.init();
    }

    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ServersScreen(),
        ),
      ));
      await tester.pump();
    }

    /// Кнопка пинга — та, что в шапке и не «Обновить».
    ///
    /// ⚠️ ИМЕННО В ШАПКЕ. `Scaffold` кладёт в дерево СНАЧАЛА тело, поэтому
    /// поиск по всему экрану первой находит кнопку-шеврон в строке сервера
    /// («Редактировать»), и тест проверял бы не ту кнопку.
    Finder pingFinder() => find.descendant(
        of: find.byType(AppBar), matching: find.byType(IconButton));

    IconButton pingButton(WidgetTester tester) => tester
        .widgetList<IconButton>(pingFinder())
        .firstWhere((b) => b.tooltip != l.serversRefresh);

    testWidgets('во время замера скорости погашена и называет причину',
        (tester) async {
      await tester.runAsync(boot);
      probe.speedBusy = true;
      await mount(tester);

      final btn = pingButton(tester);
      expect(btn.onPressed, isNull,
          reason: 'пинг во время замера скорости не запустится — кнопка '
              'обязана быть выключена, а не делать вид');
      expect(btn.tooltip, l.subSwitcherPingBusySpeed);
      // ⚠️ ПРОВЕРЯЕМ НЕ «ПОДСКАЗКА ЗАДАНА», А «ПОДСКАЗКА ПОКАЗЫВАЕТСЯ ПРИ
      // НАВЕДЕНИИ НА ВЫКЛЮЧЕННУЮ КНОПКУ». Это единственный способ узнать
      // причину, оставшийся у человека, и на словах верить тут нечему:
      // выключенная кнопка нажатий не принимает, а подсказку рисует `Tooltip`
      // поверх неё — потому она выключение и переживает.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(pingFinder().last));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l.subSwitcherPingBusySpeed), findsOneWidget,
          reason: 'причина обязана быть видима человеку, а не только коду');

      // Увести курсор, чтобы подсказка ушла и не оставила висящих таймеров.
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(pingFinder().last, warnIfMissed: false);
      await tester.pump();
      expect(probe.pingedAll, isNull, reason: 'нажатие не имеет права пинговать');
    });

    testWidgets('замер кончился — кнопка ожила и пингует найденное',
        (tester) async {
      await tester.runAsync(boot);
      probe.speedBusy = true;
      await mount(tester);

      probe.setSpeedBusy(false);
      await tester.pump();

      final btn = pingButton(tester);
      expect(btn.onPressed, isNotNull);
      expect(btn.tooltip, l.serversPingAll);

      btn.onPressed!();
      await tester.pump();
      expect(probe.pingedAll?.length, 2);
    });

    testWidgets('поиск ничего не нашёл — причина своя, не «список пуст»',
        (tester) async {
      await tester.runAsync(boot);
      await mount(tester);

      await tester.enterText(find.byType(TextField), 'такого-сервера-нет');
      await tester.pump();

      final btn = pingButton(tester);
      expect(btn.onPressed, isNull);
      expect(btn.tooltip, l.serversNothingFound,
          reason: 'серверы есть, просто под запрос не подошёл ни один — '
              '«импортируйте подписку» здесь было бы неправдой');
    });

    testWidgets('⚠️ СПИСОК ОПУСТЕЛ ПРИ НАБРАННОМ ЗАПРОСЕ — ОДИН ОТВЕТ, НЕ ДВА',
        (tester) async {
      // Развилка «пусто» или «не найдено» стояла у подсказки по НАЛИЧИЮ
      // ЗАПРОСА, а у тела экрана — по наличию серверов. Расходятся они ровно
      // здесь: строка поиска набрана, а серверов не осталось (обновление
      // подписки увело все, удаление последнего). Экран в этот момент говорит
      // «импортируйте подписку», а подсказка кнопки — «ничего не найдено».
      await tester.runAsync(boot);
      await mount(tester);

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump();
      expect(pingButton(tester).tooltip, l.serversPingFound,
          reason: 'предпосылка: запрос набран и что-то нашлось');

      await tester.runAsync(() async {
        for (final s in state.servers.toList()) {
          await state.removeServer(s);
        }
      });
      await tester.pump();

      expect(find.text(l.serversEmpty), findsOneWidget,
          reason: 'предпосылка: тело экрана говорит «список пуст»');
      expect(pingButton(tester).tooltip, l.serversEmpty,
          reason: 'подсказка кнопки и тело экрана обязаны отвечать одинаково: '
              'развилка идёт по наличию серверов, а не по набранному запросу');
    });
  });

  // ── Пункт «Пинг» в контекстном меню строки ─────────────────────────────────

  group('Строка сервера: пункт «Пинг» в меню', () {
    const server = VpnServer(
      protocol: 'vless',
      remark: 'Германия',
      address: 'de.example',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://00000000-0000-0000-0000-000000000000@de.example:443'
          '?type=tcp&security=none#Германия',
    );

    late _SpyProbe probe;

    /// Живёт ли строка в дереве. Нужен одному тесту: строку сносят, пока
    /// закрывается меню, — так `context.mounted` становится ложью в настоящем
    /// приложении (уход с экрана, обновление подписки), а не в теории.
    late ValueNotifier<bool> alive;

    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(
              value: AppState(engine: _FakeEngine())),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          ChangeNotifierProvider<SettingsController>.value(
              value: SettingsController()),
          ChangeNotifierProvider<AutoConfigController>.value(
              value: AutoConfigController()),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // ⚠️ ТЕКСТ УМЕНЬШЕН НАРОЧНО, И ЭТО НЕ ПРО ВЁРСТКУ ПРИЛОЖЕНИЯ.
          // В тестах рисует шрифт-заглушка, у которого КАЖДЫЙ знак шириной со
          // свой кегль: «Умный подбор параметров» занимает 322 px вместо
          // ~150 px настоящего Roboto. Ширина выпадающего меню при этом
          // прибита самим Material (280 dp), поэтому пункты переполняются —
          // в тесте, но не в приложении. Уменьшение возвращает пропорции;
          // проверяем мы здесь поведение пункта, а не его ширину (за ширину
          // отвечает `server_tile_layout_test`).
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(0.6)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<bool>(
                valueListenable: alive,
                builder: (_, show, __) => show
                    ? ServerTile(
                        server: server, selected: false, onTap: () {})
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    /// Правая кнопка мыши — единственный вход в это меню на десктопе.
    ///
    /// ⚠️ ЖДЁМ КОНЦА АНИМАЦИИ, А НЕ ПОЯВЛЕНИЯ ТЕКСТА. Пока маршрут меню
    /// разворачивается, он накрыт `IgnorePointer`: нажатие до пункта не
    /// доходит, хотя пункт уже нарисован и лежит на экране. Тест при этом
    /// падал не там, где сломано, — «не дождались вызова pingOne».
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byType(ServerTile),
          buttons: kSecondaryButton, warnIfMissed: false);
      await _pumpUntil(
          tester,
          () =>
              !tester.binding.hasScheduledFrame &&
              _visible(find.text(l.srvTilePing)),
          what: 'контекстное меню строки сервера');
    }

    setUp(() {
      probe = _SpyProbe();
      alive = ValueNotifier<bool>(true);
    });

    tearDown(() {
      AppToast.dismiss();
      alive.dispose();
    });

    testWidgets('во время замера скорости не пингует, а объясняет причину',
        (tester) async {
      probe.speedBusy = true;
      await mount(tester);
      await openMenu(tester);

      await tester.tap(find.text(l.srvTilePing));
      await _pumpUntil(
          tester, () => _visible(find.text(l.subSwitcherPingBusySpeed)),
          what: 'уведомление с причиной отказа');

      expect(probe.pingedOne, isNull,
          reason: 'пинг во время замера скорости всё равно бы не пошёл');
    });

    testWidgets('свободный контроллер — пункт пингует, ничего не объясняя',
        (tester) async {
      await mount(tester);
      await openMenu(tester);

      await tester.tap(find.text(l.srvTilePing));
      await _pumpUntil(tester, () => probe.pingedOne != null,
          what: 'вызов ProbeController.pingOne');

      expect(probe.pingedOne?.key, server.key);
      expect(find.text(l.subSwitcherPingBusySpeed), findsNothing);
      expect(find.text(l.serversPinging), findsNothing);
    });

    testWidgets('⚠️ СТРОКИ УЖЕ НЕТ, А ПУНКТ НАЖАЛИ, — ПИНГ ВСЁ РАВНО ИДЁТ',
        (tester) async {
      // Пункт исполняется ПОСЛЕ `await` закрытия меню, и к тому моменту строки
      // может уже не быть: ушли с экрана, обновилась подписка. Проверка
      // `context.mounted` вокруг ВСЕГО пункта означала бы «нет контекста — нет
      // и пинга», то есть ровно то молчание, которое правка изгоняла. Контекст
      // нужен только уведомлению; сам пинг живёт в контроллере.
      await mount(tester);
      await openMenu(tester);

      // ⚠️ СНОСИМ СТРОКУ, ПОКА МЕНЮ ОТКРЫТО, А НЕ ПОСЛЕ НАЖАТИЯ. Меню живёт
      // отдельным маршрутом в оверлее и строку не держит: пункт нажимается
      // прекрасно, а `context` пункта к этому моменту уже мёртв. Снос ПОСЛЕ
      // нажатия ничего бы не проверил — `showMenu` возвращает значение сразу
      // на `Navigator.pop`, ещё до нашего кадра (проверено запуском: с
      // заведомо сломанным кодом тест оставался зелёным).
      alive.value = false;
      await tester.pump();
      expect(find.byType(ServerTile), findsNothing,
          reason: 'предпосылка: контекст пункта мёртв к моменту исполнения');

      await tester.tap(find.text(l.srvTilePing));
      await _pumpUntil(tester, () => probe.pingedOne != null,
          what: 'вызов ProbeController.pingOne после сноса строки');
      expect(probe.pingedOne?.key, server.key);
    });
  });

  group('⚠️ Страж: КАЖДАЯ точка входа пинга идёт через гейт', () {
    // ⚠️ ЗАЧЕМ СТРАЖ ПО ИСХОДНИКУ, ЕСЛИ ЕСТЬ ТЕСТЫ НА САМ ГЕЙТ. Затем, что
    // гейт можно написать безупречно и не позвать. Ровно так и было: гейт
    // существовал, был покрыт тестами и закрывал две точки входа из четырёх, а
    // самая заметная кнопка приложения — «Пинг серверов» на главном — держала
    // собственное условие без проверки автопрогона сервисов. Нажатие не делало
    // ничего и ничего не объясняло, а тесты оставались зелёными.
    //
    // Страж ищет точки входа САМ, а не сверяется со списком: список пришлось бы
    // пополнять руками, то есть он снова отстал бы от кода.
    test('файл, который запускает прогон, обязан спрашивать PingGate', () {
      final offenders = <String>[];
      for (final f in Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        final startsPing =
            src.contains('.pingAll(') || src.contains('.pingOne(');
        if (startsPing && !src.contains('PingGate')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'эти экраны начинают пинг мимо гейта и будут молча '
              'отказывать: ${offenders.join(', ')}');
    });

    test('все четыре известные точки входа на месте', () {
      // Обратная проверка к предыдущей: та ловит НОВУЮ точку без гейта, эта —
      // исчезнувшую. Пропади вызов гейта вместе с кнопкой, первый тест
      // остался бы зелёным.
      for (final path in const [
        'lib/ui/servers_screen.dart',
        'lib/ui/home_screen.dart',
        'lib/ui/widgets/server_tile.dart',
        'lib/ui/widgets/subscription_switcher.dart',
      ]) {
        expect(File(path).readAsStringSync(), contains('PingGate.of('),
            reason: '$path перестал спрашивать гейт');
      }
    });
  });

}

// ── Вспомогательное ─────────────────────────────────────────────────────────

VpnServer _hy2(String name, String host) => VpnServer(
      protocol: 'hysteria2',
      remark: name,
      address: host,
      port: 443,
      id: 'pass',
      rawLink: 'hysteria2://pass@$host:443#$name',
    );

/// Виджет найден И его центр лежит на экране (меню разворачивается анимацией,
/// и в первых кадрах его содержимое висит в отрицательных координатах).
bool _visible(Finder f) {
  final found = f.evaluate();
  if (found.isEmpty) return false;
  final box = found.first.renderObject;
  if (box is! RenderBox || !box.hasSize) return false;
  final c = box.localToGlobal(box.size.center(Offset.zero));
  return c.dx >= 0 && c.dy >= 0;
}

/// Качать кадры, пока не наступит [ready], но не бесконечно. `pumpAndSettle`
/// здесь не годится: в уведомлении живёт убывающая полоска, «покоя» не будет.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String what,
  int maxFrames = 200,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (ready()) return;
    await tester.pump(step);
  }
  expect(ready(), isTrue, reason: 'не дождались: $what');
}

/// Харнесс, который ЗАВИСАЕТ на старте, пока его не отпустят. Так прогон живёт
/// ровно столько, сколько нужно тесту, и ни один сокет наружу не открывается.
class _GateHarness implements ProbeHarness {
  final _gate = Completer<void>();
  int starts = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    starts++;
    await _gate.future;
    return _GateHandle();
  }

  @override
  bool get supportsProxyRequests => true;
}

/// Порт не отдаём вовсе (-1 = «второе ядро не поднялось»): для потребителя это
/// штатный случай, а тест остаётся без сетевых обращений.
class _GateHandle implements HarnessHandle {
  @override
  String get proxyUser => harnessProxyUser;

  @override
  String get proxyPassword => 'secret';

  @override
  int proxyPortFor(int index) => -1;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}

/// Контроллер-шпион: состояние занятости задаётся снаружи, пинг никуда не идёт.
class _SpyProbe extends ProbeController {
  bool speedBusy = false;
  bool pingBusy = false;
  List<VpnServer>? pingedAll;
  VpnServer? pingedOne;

  @override
  bool get running => pingBusy;

  @override
  bool get speedRunning => speedBusy;

  void setSpeedBusy(bool value) {
    speedBusy = value;
    notifyListeners();
  }

  @override
  Future<void> pingAll(List<VpnServer> servers, AppSettings settings) async {
    pingedAll = servers;
  }

  @override
  Future<void> pingOne(VpnServer server, AppSettings settings) async {
    pingedOne = server;
  }
}

/// Движок-пустышка: VPN не поднимается ни при каких условиях.
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
