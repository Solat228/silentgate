import 'dart:async';
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
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';
import 'package:silentgate/ui/widgets/site_favicon.dart';

/// ЗНАЧОК СЕРВИСА В РАЗРЕЗАННОЙ РАМКЕ.
///
/// Решение владельца 27–28.10.2026 по макету (вариант 4): левая половина рамки
/// — замер без VPN, правая — через VPN, кружок внизу справа — как сейчас.
/// Правила раздельного туннелирования видны значками по углам: развилка и
/// круглая рамка у «Прямо», красный запрет у «Блок», синий замок со стрелкой у
/// выхода через другой сервер.
///
/// ⚠️ ЗАЧЕМ СТРАЖИ ЧИСЛОМ И ЦВЕТОМ, А НЕ «ЯЧЕЙКА НАРИСОВАЛАСЬ». Сравнение «до и
/// после» — смысл всего блока. Перепутай половины или покрась обе одним
/// замером — ячейка по-прежнему рисуется, а сравнение исчезает молча.
void main() {
  Widget host({
    required int httpPort,
    String locale = 'ru',
    ServiceCheckController? ctrl,
    ServiceChecksLayout layout = ServiceChecksLayout.sides,
    List<ProbeService> services = const [
      ProbeService.youtube,
      ProbeService.telegram,
      ProbeService.chatgpt,
    ],
  }) =>
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>(
          create: (_) => ctrl ?? ServiceCheckController(),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 584,
                height: 260,
                child: ConnectCenterpiece(
                  serverName: 'Германия 2.4',
                  httpPort: httpPort,
                  button: const SizedBox(
                      key: Key('btn'), width: 148, height: 148),
                  services: services,
                  layout: layout,
                ),
              ),
            ),
          ),
        ),
      );

  void bigView(WidgetTester t) {
    t.view.physicalSize = const Size(900, 500);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
  }

  final cell = find.byKey(const ValueKey('svc:telegram'));
  Finder ringIn(Finder scope) => find.descendant(
      of: scope, matching: find.byKey(const ValueKey('serviceRing')));

  /// Поля художника рамки. Класс приватный, поля — публичные имена:
  /// `dynamic` читает их без расширения API ради теста.
  dynamic painterOf(WidgetTester t) =>
      t.widget<CustomPaint>(ringIn(cell)).painter;

  /// Контроллер, у которого замер «до» дал [before], а «через VPN» даст
  /// [after]. Порт 0 — проба напрямую (см. `ServiceCheckController.check`).
  Future<ServiceCheckController> ctrlWith(ServiceCheckState before,
      {ServiceCheckState? after}) async {
    final saved = ServiceCheckController.prober;
    addTearDown(() => ServiceCheckController.prober = saved);
    ServiceCheckController.prober = (port, s) async =>
        ServiceCheckOutcome(port > 0 ? (after ?? before) : before,
            latencyMs: 42);
    final ctrl = ServiceCheckController();
    await ctrl.checkBaseline(const [
      ProbeService.youtube,
      ProbeService.telegram,
      ProbeService.chatgpt,
    ]);
    return ctrl;
  }

  testWidgets('у каждой ячейки своя рамка, без сервисов рамок нет',
      (t) async {
    bigView(t);
    await t.pumpWidget(host(httpPort: 0));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(cell, findsOneWidget, reason: 'ячейка сервиса не нарисовалась');
    expect(ringIn(cell), findsOneWidget, reason: 'у значка нет рамки');
    expect(find.byKey(const ValueKey('serviceRing')), findsNWidgets(3));

    await t.pumpWidget(host(httpPort: 0, services: const []));
    await t.pump();
    expect(find.byKey(const ValueKey('serviceRing')), findsNothing);
  });

  testWidgets('⚠️ на живом канале ОДИН значок, а замеры — в половинах рамки',
      (t) async {
    // Прежняя пара «до → после» рисовала два значка и стрелку. Теперь значок
    // один, и сравнение обязано жить в рамке: левая половина — «до», правая —
    // «после». Здесь «до» провален, «после» открывается.
    bigView(t);
    final ctrl = await ctrlWith(ServiceCheckState.fail,
        after: ServiceCheckState.ok);
    await ctrl.check(ProbeService.telegram, 10809);
    await t.pumpWidget(host(httpPort: 10809, ctrl: ctrl));
    await t.pump();
    expect(t.takeException(), isNull);

    expect(find.descendant(of: cell, matching: find.byType(SiteFavicon)),
        findsOneWidget);
    expect(find.text('→'), findsNothing);
    final p = painterOf(t);
    expect(p.left, const Color(0xFFE35D5D),
        reason: 'левая половина не показывает замер без VPN');
    expect(p.right, Colors.green,
        reason: 'правая половина не показывает замер через VPN');
    expect(p.circle, isFalse);
    // Кружок «как сейчас» на живом канале — по замеру через VPN.
    expect(find.descendant(of: cell, matching: find.byIcon(Icons.check)),
        findsOneWidget);
    expect(find.descendant(of: cell, matching: find.byIcon(Icons.close)),
        findsNothing);
  });

  testWidgets('VPN выключен: правая половина серая, кружок по замеру «до»',
      (t) async {
    bigView(t);
    final ctrl = await ctrlWith(ServiceCheckState.geoBlocked);
    await t.pumpWidget(host(httpPort: 0, ctrl: ctrl));
    await t.pump();
    final p = painterOf(t);
    expect(p.left, Colors.orange);
    expect(p.right, Theme.of(t.element(cell)).disabledColor);
    expect(
        find.descendant(of: cell, matching: find.byIcon(Icons.priority_high)),
        findsOneWidget);
    expect(find.byTooltip('Через VPN: VPN выключен'), findsWidgets);
    expect(find.byTooltip('Без VPN: Открывается, но заблокирован в стране выхода'), findsWidgets);
  });

  test('⚠️ подпись не шире ячейки больше, чем на запас под слово', () {
    // Ширину блока задаёт самый широкий элемент. Пока подпись заметно шире
    // содержимого, увеличивать значки бесполезно: сторона упирается в неё.
    // Инвариант не «подпись ≤ N», а «подпись не тянет блок шире содержимого».
    expect(ServiceChecksSides.labelWidthFor(false),
        lessThanOrEqualTo(cellWidth + 6),
        reason: 'подпись снова стала диктовать ширину блока');
  });

  testWidgets('⚠️ в фарси половины рамки НЕ меняются местами', (t) async {
    // Подсказка «i» на фарси говорит «левая половина — без VPN». Если ячейка
    // возьмёт направление у локали, половины поменяются местами, и иранский
    // пользователь увидит слева замер ЧЕРЕЗ VPN.
    t.view.physicalSize = const Size(900, 400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(host(httpPort: 0, locale: 'fa'));
    await t.pump();
    final dir = Directionality.of(t.element(ringIn(cell)));
    expect(dir, TextDirection.ltr,
        reason: 'в RTL-локали рамка перевернулась, и подсказка '
            '«слева — без VPN» стала ложью');
  });

  for (final layout in const [
    ServiceChecksLayout.sides,
    ServiceChecksLayout.grid,
  ]) {
    testWidgets('значок не касается рамки (${layout.name})', (t) async {
      bigView(t);
      await t.pumpWidget(host(
          httpPort: 0,
          layout: layout,
          services: const [ProbeService.telegram]));
      await t.pump();
      expect(t.takeException(), isNull);
      final ring = t.getRect(ringIn(cell));
      final icon = t.getRect(
          find.descendant(of: cell, matching: find.byType(SiteFavicon)));
      // Значок 28 в рамке 42 (сетка: 20 в 30) — между ними толщина рамки и
      // просвет цвета фона. Масштаб выводится из самой рамки.
      final grid = layout == ServiceChecksLayout.grid;
      final k = ring.width / (grid ? 30 : 42);
      expect(k, greaterThan(0.99), reason: 'ячейка сжата там, где место есть');
      expect(icon.width, closeTo((grid ? 20 : 28) * k, 0.05));
      expect(icon.center.dx, closeTo(ring.center.dx, 0.05));
      expect(icon.center.dy, closeTo(ring.center.dy, 0.05));
      expect(ring.width, closeTo(ring.height, 0.01));
    });

    for (final (state, icon) in const [
      (ServiceCheckState.ok, Icons.check),
      (ServiceCheckState.geoBlocked, Icons.priority_high),
      (ServiceCheckState.fail, Icons.close),
    ]) {
      testWidgets('кружок ${state.name} → ${icon.codePoint} (${layout.name})',
          (t) async {
        bigView(t);
        final ctrl = await ctrlWith(state);
        await t.pumpWidget(host(
            httpPort: 0,
            ctrl: ctrl,
            layout: layout,
            services: const [ProbeService.telegram]));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.descendant(of: cell, matching: find.byIcon(icon)),
            findsOneWidget,
            reason: 'у состояния ${state.name} нет знака в кружке');
        // ⚠️ Запрет — значок правила «Блок»; знак отказа с ним не путается.
        expect(find.byIcon(Icons.block_rounded), findsNothing);
        // Кружок — в ПРАВОМ НИЖНЕМ углу рамки: верхние углы заняты замками.
        final ring = t.getRect(ringIn(cell));
        final glyph = t.getRect(
            find.descendant(of: cell, matching: find.byIcon(icon)));
        expect(glyph.center.dx, greaterThan(ring.center.dx));
        expect(glyph.center.dy, greaterThan(ring.center.dy));
      });
    }
  }

  testWidgets('без замера кружка нет', (t) async {
    bigView(t);
    await t.pumpWidget(host(httpPort: 0));
    await t.pump();
    for (final i in const [Icons.check, Icons.priority_high, Icons.close]) {
      expect(find.byIcon(i), findsNothing,
          reason: 'знак нарисован у непроверенного сервиса');
    }
    // Без замера левая половина — подсказка «не проверялось».
    expect(find.byTooltip('Без VPN не проверялось'), findsWidgets);
  });

  testWidgets('⚠️ на мелком масштабе кружок не рисуется', (t) async {
    // Кружок 14 px при масштабе 0,45 — это 6 px: пятно, а не знак.
    bigView(t);
    final ctrl = await ctrlWith(ServiceCheckState.ok);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<ServiceCheckController>.value(
        value: ctrl,
        child: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 584,
              // Четырнадцать сервисов в 150 px — масштаб меньше 0,5.
              height: 150,
              child: ServiceChecksSides(
                services: ServiceChecks.catalog,
                httpPort: 0,
                button: SizedBox(width: 148, height: 148),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byIcon(Icons.check), findsNothing,
        reason: 'знак рисуется на масштабе, где он нечитаем');
  });

  group('значки правил', () {
    late Directory tmp;
    late SettingsController settings;
    late AppState state;

    setUp(() async {
      // ⚠️ Боевой каталог под тестами не отдаётся — объявляем свой.
      tmp = Directory.systemTemp.createTempSync('sg_status_ring_');
      AppPaths.overrideRoot(tmp);
      settings = SettingsController();
      state = AppState(engine: _FakeEngine());
    });

    tearDown(() {
      settings.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget ruleHost() => MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<ServiceCheckController>(
                create: (_) => ServiceCheckController()),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 584,
                  height: 260,
                  child: ConnectCenterpiece(
                    serverName: null,
                    httpPort: 0,
                    button: SizedBox(width: 148, height: 148),
                    services: [ProbeService.telegram, ProbeService.github],
                    layout: ServiceChecksLayout.sides,
                  ),
                ),
              ),
            ),
          ),
        );

    Future<void> withRules(WidgetTester t, SplitTunnelConfig split) async {
      await t.runAsync(
          () => settings.update((c) => c.copyWith(splitTunnel: split)));
      await t.pumpWidget(ruleHost());
      await t.pump();
      expect(t.takeException(), isNull);
    }

    Finder lock(String which, Finder scope) => find.descendant(
        of: scope, matching: find.byKey(ValueKey(which)));
    final github = find.byKey(const ValueKey('svc:github'));

    testWidgets('без правил: открытый и закрытый замки, рамка из половин',
        (t) async {
      bigView(t);
      await withRules(t, const SplitTunnelConfig());
      expect(lock('lockOpen', cell), findsOneWidget);
      expect(lock('lockClosed', cell), findsOneWidget);
      expect(painterOf(t).circle, isFalse);
    });

    testWidgets('«Прямо»: круглая рамка, развилка, правого замка нет',
        (t) async {
      bigView(t);
      await withRules(
          t,
          const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            sites: [SiteRule('telegram.org', action: AppAction.direct)],
          ));
      expect(painterOf(t).circle, isTrue,
          reason: 'мимо VPN рамка обязана стать круглой');
      expect(find.descendant(of: cell, matching: find.byIcon(Icons.alt_route_rounded)),
          findsOneWidget);
      expect(lock('lockOpen', cell), findsNothing);
      expect(lock('lockClosed', cell), findsNothing);
      expect(find.byTooltip(
              'Мимо VPN: правило «telegram.org» в раздельном туннелировании '
              'отправляет этот домен напрямую — сервис пойдёт под вашим '
              'настоящим адресом.'),
          findsOneWidget);
      // У соседа без правила всё по-прежнему.
      expect(lock('lockClosed', github), findsOneWidget);
    });

    testWidgets('«Блок»: красный запрет вместо закрытого замка', (t) async {
      bigView(t);
      await withRules(
          t,
          const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            sites: [SiteRule('telegram.org', action: AppAction.block)],
          ));
      expect(find.descendant(of: cell, matching: find.byIcon(Icons.block_rounded)),
          findsOneWidget);
      expect(lock('lockClosed', cell), findsNothing);
      expect(lock('lockOpen', cell), findsOneWidget);
    });

    testWidgets('выход: синий замок со стрелкой и имя сервера в подсказке',
        (t) async {
      bigView(t);
      await t.runAsync(() => state.importSource(_exitLink));
      final key = ShareLinkParser.canonicalKey(_exitLink);
      // ⚠️ В режиме «Всё через VPN» выходы ДЕЙСТВУЮТ — значок обязан быть.
      await withRules(
          t,
          SplitTunnelConfig(
            sites: [SiteRule('telegram.org',
                  action: AppAction.tunnel, serverKey: key)],
          ));
      expect(
          find.descendant(
              of: cell, matching: find.byIcon(Icons.arrow_forward_rounded)),
          findsOneWidget);
      expect(
          find.byTooltip('Через другой сервер: правило «telegram.org» в '
              'раздельном туннелировании ведёт этот домен через «Германия».'),
          findsOneWidget);
    });

    testWidgets('⚠️ выход на пропавший сервер — обычный замок', (t) async {
      // Сервера в подписке нет: трафик правила идёт основным туннелем
      // (`ExitOutbounds.build`), и синий замок соврал бы.
      bigView(t);
      await withRules(
          t,
          const SplitTunnelConfig(
            sites: [
              SiteRule('telegram.org',
                  action: AppAction.tunnel,
                  serverKey: 'vless://00000000-0000-0000-0000-000000000000'
                      '@192.0.2.1:443#gone')
            ],
          ));
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(lock('lockClosed', cell), findsOneWidget);
    });
  });

  group('ServiceChecks.markRuleFor', () {
    const exit = SiteRule('telegram.org',
        action: AppAction.tunnel, serverKey: 'k');

    test('«Всё через VPN»: выход есть, «Прямо» и «Блок» нет', () {
      const split = SplitTunnelConfig(sites: [
        SiteRule('telegram.org', action: AppAction.direct),
      ]);
      expect(ServiceChecks.markRuleFor(split, ProbeService.telegram), isNull);
      const withExit = SplitTunnelConfig(sites: [exit]);
      expect(ServiceChecks.markRuleFor(withExit, ProbeService.telegram),
          same(exit));
    });

    test('более конкретное «Прямо» побеждает выход родителя', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('google.com', action: AppAction.tunnel, serverKey: 'k'),
          SiteRule('gemini.google.com', action: AppAction.direct),
        ],
      );
      expect(ServiceChecks.markRuleFor(split, ProbeService.gemini)?.action,
          AppAction.direct);
    });

    test('туннель без сервера — не выход', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('telegram.org', action: AppAction.tunnel)],
      );
      expect(ServiceChecks.markRuleFor(split, ProbeService.telegram), isNull);
    });
  });
}

/// Сервер выхода. Адрес из TEST-NET: в тесте сети нет и не нужно.
const _exitLink =
    'vless://11111111-2222-3333-4444-555555555555@192.0.2.10:443'
    '?security=none&type=tcp#Германия';

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
