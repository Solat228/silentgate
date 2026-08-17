import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/probe/cancel_token.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/tcp_ping.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';
import 'package:silentgate/data/results_store.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/auto_config_screen.dart';

/// Экран автонастройки: четыре жалобы владельца от 12.08.2026.
///
/// У всех четырёх один почерк — экран выглядит рабочим, а данные под ним живут
/// своей жизнью:
///  * кнопок было ДВЕ, и верхняя молча стирала то, на чём держалась нижняя
///    (`start()` первым делом делал `_found.clear()`);
///  * список серверов пропадал с экрана на время прогона, а галочки выбора
///    умирали вместе с `State` виджета;
///  * времени и остатка не показывалось вовсе — у контроллера не было даже
///    отметки старта;
///  * фаза замера скорости о себе не отчитывалась, и прогресс десятки секунд
///    показывал давно проверенного кандидата.
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

/// Харнесс, который НИКОГДА не поднимается: `start` возвращает вечный Future.
/// Прогон замирает ровно на первом кандидате — состояние «идёт поиск»
/// становится наблюдаемым, а сети и ядер тест не касается.
class _HangingHarness implements ProbeHarness {
  @override
  bool get supportsProxyRequests => true;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) =>
      Completer<HarnessHandle>().future;
}

/// Харнесс с живым номером порта. Проб через него не будет: набор сервисов в
/// настройках пуст, поэтому кандидат считается прошедшим сразу
/// (`requiredServices == 0`) — нам нужна только фаза замера скорости.
class _PortHarness implements ProbeHarness {
  @override
  bool get supportsProxyRequests => true;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async => _PortHandle();
}

class _PortHandle implements HarnessHandle {
  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  @override
  int proxyPortFor(int index) => 21000;
  @override
  Future<int?> delayMs(int index) async => null;
  @override
  Future<void> stop() async {}
}

/// Харнесс без порта: кандидат считается непрошедшим, прогон кончается сразу.
class _NoPortHarness implements ProbeHarness {
  @override
  bool get supportsProxyRequests => true;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async =>
      _NoPortHandle();
}

class _NoPortHandle implements HarnessHandle {
  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  @override
  int proxyPortFor(int index) => -1;
  @override
  Future<int?> delayMs(int index) async => null;
  @override
  Future<void> stop() async {}
}

void main() {
  final l = AppLocalizationsRu();

  // ⚠️ Фаза 1 подбора отсеивает серверы, не ответившие по TCP, — а `a.example`
  // не отвечает и отвечать не может. Без подмены прогон заканчивался бы, не
  // дойдя до харнесса, и экранные тесты хода проверяли бы пустоту.
  setUp(() {
    AutoConfigEngine.tcpProbe = (host, port, timeout) async => const PingResult(
          outcome: PingOutcome.ok,
          latencyMs: 42,
          latencyMethod: PingMethod.tcp,
        );
  });
  tearDown(() {
    AutoConfigEngine.tcpProbe = (host, port, timeout) =>
        TcpPing.measure(host, port, timeout: timeout);
  });

  const linkA = 'vless://00000000-0000-0000-0000-000000000000@a.example:443'
      '?type=tcp&security=none#Alpha';
  const linkB = 'vless://11111111-1111-1111-1111-111111111111@b.example:443'
      '?type=tcp&security=none#Bravo';

  Directory? tmp;
  late AppState state;
  late SettingsController settings;
  late ProbeController probe;
  late AutoConfigController auto;

  /// Изолированный корень данных + один уже найденный результат в хранилище.
  Future<void> seedFound(String link) async {
    tmp = Directory.systemTemp.createTempSync('sg_autocfg_');
    AppPaths.overrideRoot(tmp!);
    final srv = ShareLinkParser.tryParse(link)!;
    await ResultsStore.autoConfig.save([
      AutoConfigResult(
        server: srv,
        variant: OutboundVariant.none,
        detail: CandidateResult(
          server: srv,
          variant: OutboundVariant.none,
          passed: const {ProbeService.youtube: true},
          avgLatencyMs: 42,
        ),
        measuredAt: DateTime.now(),
      ).toJson(),
    ]);
  }

  /// Готовое окружение экрана: два сервера в списке и один найденный результат.
  ///
  /// Найденный нужен не для красоты: ИМЕННО ПРИ НЕПУСТОМ списке найденных
  /// старый экран показывал ДВЕ заливные кнопки — «Подобрать для выбранных»
  /// посреди прокручиваемого списка и «Готово — обновить пинг найденных» внизу.
  Future<void> boot({AutoConfigEngine? acEngine}) async {
    await seedFound(linkA);
    state = AppState(engine: _FakeEngine());
    await state.init();
    await state.importSource(linkA);
    await state.importSource(linkB);
    settings = SettingsController();
    await settings.init();
    probe = ProbeController();
    auto = AutoConfigController(engine: acEngine);
    await auto.init();
  }

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          ChangeNotifierProvider<AutoConfigController>.value(value: auto),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AutoConfigScreen(),
        ),
      );

  /// Большой холст: `ListView` строит только то, что попадает в область
  /// видимости, и на стандартных 800×600 список серверов остался бы
  /// непостроенным — проверка «список на месте» краснела бы по ложной причине.
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  tearDown(() {
    try {
      tmp?.deleteSync(recursive: true);
    } catch (_) {}
    tmp = null;
  });

  group('Одна кнопка вместо двух', () {
    testWidgets('прогон не идёт — единственная кнопка «Подобрать (N)»',
        (tester) async {
      await tester.runAsync(boot);
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // ⚠️ ГЛАВНАЯ ПРОВЕРКА. При непустом списке найденных старый экран рисовал
      // ДВЕ заливные кнопки; запуск верхней делал `_found.clear()`, то есть
      // уничтожал данные, ради которых существовала нижняя.
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget,
          reason: 'заливная кнопка на экране обязана быть ровно одна');
      expect(find.byKey(const Key('autoAction')), findsOneWidget);
      expect(find.text('${l.autoTuneSelected} (2)'), findsOneWidget,
          reason: 'подпись обязана называть число выбранных серверов');
      expect(find.text(l.autoDoneRefreshPing), findsNothing,
          reason: 'вторая кнопка убрана по прямому требованию владельца');
    });

    testWidgets('пустой выбор — кнопка заблокирована', (tester) async {
      await tester.runAsync(boot);
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      auto.clearSelection();
      await tester.pumpAndSettle();

      final button =
          tester.widget<FilledButton>(find.byKey(const Key('autoAction')));
      expect(button.onPressed, isNull,
          reason: 'подбирать «для выбранных», когда не выбрано ничего, нечего');
      expect(find.text('${l.autoTuneSelected} (0)'), findsOneWidget);
    });

    testWidgets('во время прогона — «Остановить поиск», и список на месте',
        (tester) async {
      await tester.runAsync(() => boot(
          acEngine: AutoConfigEngine(harnessFactory: () => _HangingHarness())));
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('autoAction')));
      await tester.pump();

      expect(auto.running, isTrue);
      expect(find.text(l.autoStopSearch), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing,
          reason: 'во время прогона доступно ровно одно действие — остановка');

      // ⚠️ Владелец: «если выйти и зайти заново — не показывает список
      // серверов». Гейт `if (!ctrl.running)` снимал список с экрана целиком.
      final tileA = find.byKey(Key('autoSrv-${keyOf(linkA)}'));
      final tileB = find.byKey(Key('autoSrv-${keyOf(linkB)}'));
      expect(tileA, findsOneWidget);
      expect(tileB, findsOneWidget);

      // Состав менять нельзя: список кандидатов у движка уже построен.
      expect(tester.widget<CheckboxListTile>(tileA).onChanged, isNull);

      // ⚠️ ПОДСВЕЧИВАЮТСЯ ВСЕ, КТО ПРОВЕРЯЕТСЯ СЕЙЧАС, А НЕ ОДИН «ТЕКУЩИЙ».
      // Раньше кандидат был ровно один, и тест справедливо ждал в
      // `progress.candidateKey` последнюю импортированную ссылку (одиночный
      // импорт кладёт сервер в начало закреплённых). С
      // `autoConfigConcurrency > 1` их несколько сразу, и «последний начатый»
      // ничем не главнее остальных — проверяем множество активных.
      expect(auto.activeKeys, contains(keyOf(linkB)));
      expect(tester.widget<CheckboxListTile>(tileB).tileColor, isNotNull,
          reason: 'без подсветки непонятно, где сейчас идёт проверка');

      // Снимаем дерево, иначе секундный тикер таймера останется висеть.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Выбор серверов переживает уход с экрана', () {
    testWidgets('снятая галочка остаётся снятой после пересоздания экрана',
        (tester) async {
      await tester.runAsync(boot);
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final tileA = find.byKey(Key('autoSrv-${keyOf(linkA)}'));
      expect(tester.widget<CheckboxListTile>(tileA).value, isTrue);
      await tester.tap(tileA);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(tileA).value, isFalse);
      expect(find.text('${l.autoTuneSelected} (1)'), findsOneWidget);

      // Уход с экрана и возврат: раньше галочки лежали в `_BatchTuneState._sel`
      // и при новом `State` заполнялись «всеми» заново — снятый выбор
      // воскресал, и подбор уходил на серверы, которые человек исключил.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(tester.widget<CheckboxListTile>(tileA).value, isFalse,
          reason: 'выбор живёт в контроллере, а не в State экрана');
      expect(find.text('${l.autoTuneSelected} (1)'), findsOneWidget);
    });
  });

  group('Оценка остатка — по стоимости, а не по числу', () {
    test('одно и то же число пройденных даёт разный остаток', () {
      final fast = AutoConfigController.estimateRemaining(
          elapsed: const Duration(seconds: 10), done: 2, total: 10);
      final slow = AutoConfigController.estimateRemaining(
          elapsed: const Duration(seconds: 40), done: 2, total: 10);

      // ⚠️ Оценка «сколько осталось × константа» дала бы здесь ОДНО И ТО ЖЕ
      // число. Стоимость кандидата отличается в разы: у отвечающего сервера
      // добавляется замер задержки, у молчащего КАЖДАЯ проба ждёт полный
      // таймаут. Поэтому средняя берётся из уже прожитого времени прогона.
      expect(fast, const Duration(seconds: 40));
      expect(slow, const Duration(seconds: 160));
      expect(slow! > fast!, isTrue);
    });

    test('пока не закончился ни один кандидат — оценки нет', () {
      expect(
          AutoConfigController.estimateRemaining(
              elapsed: const Duration(seconds: 5), done: 0, total: 10),
          isNull,
          reason: 'выдуманная оценка хуже честного отсутствия');
    });

    test('всё пройдено — остаток ноль, а не отрицательный', () {
      expect(
          AutoConfigController.estimateRemaining(
              elapsed: const Duration(seconds: 5), done: 10, total: 10),
          Duration.zero);
      expect(
          AutoConfigController.estimateRemaining(
              elapsed: const Duration(seconds: 5), done: 12, total: 10),
          Duration.zero);
    });

    testWidgets('во время прогона на экране есть строка времени',
        (tester) async {
      await tester.runAsync(() => boot(
          acEngine: AutoConfigEngine(harnessFactory: () => _HangingHarness())));
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.textContaining('Прошло'), findsNothing,
          reason: 'до запуска считать нечего');

      await tester.tap(find.byKey(const Key('autoAction')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.textContaining('Прошло'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Фаза замера скорости отчитывается о себе', () {
    test('движок зовёт отчёт о каждом шаге замера', () async {
      // hysteria2 намеренно: у такого сервера движок не делает TCP-замер, то
      // есть тест не трогает сеть вовсе. Скачивание тоже никуда не уходит —
      // flutter_test подменяет HttpClient заглушкой.
      final srv = ShareLinkParser.tryParse(
          'hysteria2://pass@h1.example:443?sni=h1.example#Hydra')!;
      final engine = AutoConfigEngine(harnessFactory: () => _PortHarness());
      // Пустой набор сервисов ⇒ `requiredServices == 0` ⇒ кандидат считается
      // прошедшим без единой пробы. Нам нужна только фаза скорости.
      const s = AppSettings(
        autoConfigServices: <ProbeService>{},
        speedInAutoSelect: true,
        pingTimeoutMs: 100,
      );

      final steps = <String>[];
      await engine.run(
        servers: [srv],
        settings: s,
        cancel: CancelToken(),
        onSpeedCandidate: (i, total, server, variant) =>
            steps.add('$i/$total:${server?.remark ?? "own"}'),
      );

      // ⚠️ ДО ЭТОГО ФАЗА МОЛЧАЛА. `_rankBySpeed` не звал ни одного колбэка, и
      // прогресс десятки секунд показывал последнего кандидата ПЕРЕБОРА —
      // «тестирую X», хотя перебор давно кончился.
      expect(steps.first, '0/2:own',
          reason: 'свой канал — такой же шаг: он стоит столько же времени');
      expect(steps, contains('1/2:Hydra'));
    });

    testWidgets('на экране это отдельный текст, а не «Тестируется N/M»',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AutoConfigProgressView(
            progress: AutoConfigProgress(
              index: 1,
              total: 3,
              candidateName: 'Bravo',
              variant: OutboundVariant.none,
              services: const {},
              phase: AutoConfigPhase.speed,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l.autoSpeedRanking('Bravo')), findsOneWidget);
      expect(find.textContaining('Тестируется'), findsNothing,
          reason: 'замер скорости — не перебор кандидатов, и врать об этом '
              'нельзя: именно на этой фазе прогресс замирал');
    });
  });

  group('Плашка о настройках маршрутизации', () {
    /// Настройки, при которых плашке появляться не с чего.
    Future<void> quiet() => settings.update((st) => st.copyWith(
          noRealIp: false,
          myRulesOverridePanel: false,
          splitTunnel: st.splitTunnel.copyWith(mode: SplitMode.exceptSelected),
        ));

    testWidgets('молчит, когда все три настройки выключены', (tester) async {
      await tester.runAsync(() async {
        await boot();
        await quiet();
      });
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('autoWarn-noRealIp')), findsNothing);
      expect(find.byKey(const Key('autoWarn-allVpn')), findsNothing);
      expect(find.byKey(const Key('autoWarn-panelOverride')), findsNothing);
      expect(find.text(l.autoWarnProbesDirect), findsNothing);
    });

    testWidgets('«Не выходить под реальным IP» — плашка и снятие галочки',
        (tester) async {
      await tester.runAsync(() async {
        await boot();
        await quiet();
        await settings.update((st) => st.copyWith(noRealIp: true));
      });
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('autoWarn-noRealIp')), findsOneWidget);
      expect(find.text(l.autoWarnNoRealIp), findsOneWidget);
      // ⚠️ Текст обязан говорить правду про TUN: пробы идут мимо VPN-выхода,
      // но через процесс ядра — зависшее ядро делает результаты
      // ложно-отрицательными.
      expect(find.text(l.autoWarnProbesDirect), findsOneWidget);

      await tester.tap(find.byKey(const Key('autoWarnOff-noRealIp')));
      await tester.pumpAndSettle();

      expect(settings.settings.noRealIp, isFalse);
      expect(find.byKey(const Key('autoWarn-noRealIp')), findsNothing);
    });

    testWidgets('«Все — через VPN» — плашка и выход из режима', (tester) async {
      await tester.runAsync(() async {
        await boot();
        await quiet();
        await settings.update((st) => st.copyWith(
            splitTunnel: st.splitTunnel.copyWith(mode: SplitMode.all)));
      });
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('autoWarn-allVpn')), findsOneWidget);
      expect(find.text(l.autoWarnAllVpn), findsOneWidget);

      await tester.tap(find.byKey(const Key('autoWarnOff-allVpn')));
      await tester.pumpAndSettle();

      // ⚠️ Уходим в `exceptSelected`: трафик по умолчанию остаётся в туннеле,
      // но пользовательские правила начинают действовать. `onlySelected`
      // выкинул бы наружу всё неотмеченное — это не «снять галочку», а другой
      // способ пользоваться VPN.
      expect(settings.settings.splitTunnel.mode, SplitMode.exceptSelected);
      expect(find.byKey(const Key('autoWarn-allVpn')), findsNothing);
    });

    testWidgets('«Мои правила важнее правил панели» — плашка и снятие',
        (tester) async {
      await tester.runAsync(() async {
        await boot();
        await quiet();
        await settings.update((st) => st.copyWith(myRulesOverridePanel: true));
      });
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('autoWarn-panelOverride')), findsOneWidget);
      expect(find.text(l.autoWarnPanelOverride), findsOneWidget);

      await tester.tap(find.byKey(const Key('autoWarnOff-panelOverride')));
      await tester.pumpAndSettle();

      expect(settings.settings.myRulesOverridePanel, isFalse);
      expect(find.byKey(const Key('autoWarn-panelOverride')), findsNothing);
    });

    testWidgets('порядок по важности: реальный IP выше режима захвата',
        (tester) async {
      await tester.runAsync(() async {
        await boot();
        await settings.update((st) => st.copyWith(
              noRealIp: true,
              myRulesOverridePanel: true,
              splitTunnel: st.splitTunnel.copyWith(mode: SplitMode.all),
            ));
      });
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final y = <String, double>{
        for (final id in ['noRealIp', 'allVpn', 'panelOverride'])
          id: tester.getTopLeft(find.byKey(Key('autoWarn-$id'))).dy,
      };
      expect(y['noRealIp']! < y['allVpn']!, isTrue);
      expect(y['allVpn']! < y['panelOverride']!, isTrue);
    });
  });

  group('Прогон не стирает чужие результаты', () {
    test('подбор по одному серверу не трогает найденное по остальным',
        () async {
      await seedFound(linkA);
      final ctrl = AutoConfigController(
          engine: AutoConfigEngine(harnessFactory: () => _NoPortHarness()));
      await ctrl.init();
      expect(ctrl.found.length, 1);

      // ⚠️ Раньше `start()` первым делом делал `_found.clear()`, и подбор
      // ОДНОГО сервера из контекстного меню стирал итоги по всей подписке.
      final other = ShareLinkParser.tryParse(linkB)!;
      await ctrl.start([other],
          const AppSettings(autoConfigServices: {ProbeService.google}));

      expect(ctrl.found.length, 1);
      expect(ctrl.found.single.server.key, keyOf(linkA));
    });
  });
  group('Замер скорости стоит трафика подписки — и об этом спрашивают', () {
    // ⚠️ РАДИ ЧЕГО. Галочку замера включают ОДИН раз в настройках, а прогон
    // запускают потом — днями позже. Платит при этом подписка: по 5 МБ на
    // каждый из десяти серверов плюс столько же на свой канал, то есть 55 МБ
    // за нажатие. Узнавать об этом по счётчику остатка — худший способ.
    testWidgets('⚠️ при включённом замере спрашивают ДО прогона и называют объём',
        (tester) async {
      await tester.runAsync(boot);
      await tester.runAsync(() =>
          settings.update((c) => c.copyWith(speedInAutoSelect: true)));
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('autoAction')));
      await tester.pumpAndSettle();

      expect(find.text(l.autoSpeedTrafficTitle), findsOneWidget,
          reason: 'иначе трафик подписки тратится без спроса');
      // Число обязано прийти из одного места — settings.speedTestTrafficMb.
      final mb = settings.settings.speedTestTrafficMb;
      expect(find.textContaining('$mb'), findsWidgets,
          reason: 'предупреждение без цифры бесполезно: «замер потратит '
              'трафик» не говорит, сколько именно');
      expect(auto.running, isFalse, reason: 'до согласия прогон не начинается');

      // Отказ — прогон не стартует.
      await tester.tap(find.text(l.commonCancel));
      await tester.pumpAndSettle();
      expect(auto.running, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('замер выключен — лишнего вопроса нет', (tester) async {
      // Спрашивать не о чем: трафик подписки не тратится. Лишний вопрос на
      // каждом запуске приучает жать «да» не глядя, и тогда он не сработает
      // тогда, когда действительно нужен.
      await tester.runAsync(boot);
      bigSurface(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('autoAction')));
      await tester.pump();
      expect(find.text(l.autoSpeedTrafficTitle), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

}

/// Ключ сервера, каким его видит приложение.
///
/// ⚠️ НЕ РАВЕН исходной строке: с 1.4.2 ссылка приводится к каноническому виду,
/// потому что одни и те же данные приходят в разных написаниях (у gRPC имя
/// сервиса бывает `serviceName=`, бывает `path=`). Тест, сравнивающий с
/// исходником, проходил лишь по совпадению.
String keyOf(String link) => ShareLinkParser.canonicalKey(link);
