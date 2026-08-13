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
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/selection_outline.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Обводка выбранного блока и прокрутка списка к запомненному серверу.
///
/// ⚠️ ЧЕГО ХОТЕЛ ВЛАДЕЛЕЦ (дословно, два захода):
///  1. «под обводкой я имел в виду, чтобы обводился ЭТОТ БЛОК, а не слева, но
///     оставь его» — рамка обязана идти по ВСЕМУ периметру, а полоса в боковом
///     меню настроек остаётся;
///  2. «сделай такую же обводку для выбранного сервера»;
///  3. «при запуске приложения если не видно мотай до него в списке серверов
///     чтобы показать юзеру какой сервер был запомнен».
///
/// Здесь проверяется каждое из трёх, причём геометрия рамки — по РЕАЛЬНОМУ
/// пути, который рисует painter: на скриншоте «рамка» и «толстая линия слева»
/// различаются плохо, а в тесте — однозначно.
void main() {
  // ⚠️ Делегаты локализации обязательны: строка сервера берёт тексты через
  // AppLocalizations.of(context) с nullable-getter:false и без них падает.
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  /// Задать размер ОКНА, а не виджета: поверхность теста по умолчанию 800×600,
  /// и `SizedBox` зажимается родителем — список получил бы не ту высоту.
  void setWindow(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  group('Рамка идёт по всему периметру блока', () {
    const size = Size(240, 60);

    /// Общая коробка всех кусков линии.
    Rect boundsOf(List<Path> segments) => segments
        .map((p) => p.getBounds())
        .reduce((a, b) => a.expandToInclude(b));

    test('при полном прогрессе накрыты все четыре грани', () {
      final painter = SelectionOutlinePainter(
          progress: 1, from: const Color(0xFF112233), to: const Color(0xFF445566));
      final segments = painter.outlineSegments(size);
      expect(segments, hasLength(2), reason: 'два конца из левого верхнего угла');

      final b = boundsOf(segments);
      // ⚠️ Ровно это и ловит возврат к «полосе слева»: у неё правая граница
      // осталась бы у нуля, а нижняя — у высоты одной линии.
      expect(b.left, closeTo(0, 0.6));
      expect(b.top, closeTo(0, 0.6));
      expect(b.right, closeTo(size.width, 0.6));
      expect(b.bottom, closeTo(size.height, 0.6));
    });

    test('оба конца растут ИЗ левого верхнего угла, а не откуда попало', () {
      final painter = SelectionOutlinePainter(
          progress: 0.5, from: const Color(0xFF112233), to: const Color(0xFF445566));
      final segments = painter.outlineSegments(size);
      expect(segments, hasLength(2));

      // ⚠️ Один кусок ИЗ угла и вперёд, второй — хвост пути, он в этот же угол
      // ПРИХОДИТ. Поэтому проверяем, что у каждого один из концов лежит в левом
      // верхнем углу (со скидкой на скругление 10).
      for (final p in segments) {
        final m = p.computeMetrics().first;
        final ends = [
          m.getTangentForOffset(0)!.position,
          m.getTangentForOffset(m.length)!.position,
        ];
        expect(ends.any((o) => o.dx < 12 && o.dy < 12), isTrue,
            reason: 'кусок линии не касается левого верхнего угла: $ends');
      }

      // И расходятся они в РАЗНЫЕ стороны: первый вправо по верхней грани,
      // второй вниз по левой и дальше по нижней.
      final top = segments.first.getBounds();
      expect(top.top, closeTo(0, 0.6));
      expect(top.right, greaterThan(size.width / 2),
          reason: 'верхняя грань обязана быть прочерчена — это не полоса слева');
      expect(top.bottom, lessThan(size.height / 2),
          reason: 'первый конец не должен уходить вниз');

      final down = segments.last.getBounds();
      expect(down.left, closeTo(0, 0.6));
      expect(down.bottom, closeTo(size.height, 0.6),
          reason: 'второй конец обязан дойти до нижней грани');
    });

    test('длина линии растёт вместе с прогрессом', () {
      double drawn(double progress) => SelectionOutlinePainter(
              progress: progress,
              from: const Color(0xFF112233),
              to: const Color(0xFF445566))
          .outlineSegments(size)
          .fold<double>(
              0,
              (sum, p) =>
                  sum + p.computeMetrics().fold<double>(0, (a, m) => a + m.length));

      expect(SelectionOutlinePainter(
              progress: 0,
              from: const Color(0xFF112233),
              to: const Color(0xFF445566))
          .outlineSegments(size), isEmpty);
      expect(drawn(0.5), closeTo(drawn(1) / 2, 1.0));
    });

    test('отступ внутрь не даёт рамке лечь на границу блока', () {
      final b = boundsOf(SelectionOutlinePainter(
              progress: 1,
              from: const Color(0xFF112233),
              to: const Color(0xFF445566),
              inset: 3)
          .outlineSegments(size));
      expect(b.left, closeTo(3, 0.6));
      expect(b.right, closeTo(size.width - 3, 0.6));
    });
  });

  group('SelectionOutline: рисуется у выбранного и только у него', () {
    /// Прогресс рамки у каждого блока в порядке появления на экране.
    List<double> progresses(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<SelectionOutlinePainter>()
        .map((p) => p.progress)
        .toList();

    testWidgets('выбранный обведён, соседи — нет', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        SelectionOutline(selected: false, child: SizedBox(height: 40, width: 200)),
        SelectionOutline(selected: true, child: SizedBox(height: 40, width: 200)),
        SelectionOutline(selected: false, child: SizedBox(height: 40, width: 200)),
      ])));
      await tester.pumpAndSettle();

      expect(progresses(tester), [0, 1, 0]);
    });

    testWidgets('снятие выбора стирает рамку', (tester) async {
      Widget build(bool selected) => host(SelectionOutline(
          selected: selected, child: const SizedBox(height: 40, width: 200)));

      await tester.pumpWidget(build(true));
      await tester.pumpAndSettle();
      expect(progresses(tester).single, 1);

      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(progresses(tester).single, 0);
    });

    testWidgets('⚠️ анимация не течёт: снятие виджета на ходу не роняет тикер',
        (tester) async {
      // Без `_c.dispose()` Flutter роняет «disposed with an active Ticker» —
      // именно поэтому тест снимает виджет ПОСЕРЕДИНЕ анимации, а не после неё.
      await tester.pumpWidget(host(const SelectionOutline(
          selected: false, child: SizedBox(height: 40, width: 200))));
      await tester.pumpWidget(host(const SelectionOutline(
          selected: true, child: SizedBox(height: 40, width: 200))));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(host(const SizedBox.shrink()));
      expect(tester.takeException(), isNull);
    });
  });

  group('Строка сервера: обводка достаётся выбранному', () {
    testWidgets('у выбранного сервера рамка есть, у остальных нет',
        (tester) async {
      final env = await _TileEnv.create();
      addTearDown(env.dispose);
      setWindow(tester, const Size(900, 600));

      await tester.pumpWidget(host(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: env.state),
          ChangeNotifierProvider<ProbeController>.value(value: env.probe),
        ],
        child: Column(children: [
          for (var i = 0; i < 3; i++)
            ServerTile(
              server: env.server('Сервер $i', 20001 + i),
              selected: i == 1,
              onTap: () {},
            ),
        ]),
      )));
      await tester.pumpAndSettle();

      final drawn = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<SelectionOutlinePainter>()
          .map((p) => p.progress)
          .toList();
      expect(drawn, [0, 1, 0],
          reason: 'обведена ровно выбранная строка, и она вторая');
    });
  });

  group('Прокрутка к запомненному серверу', () {
    test('первый показ списка — повод промотать', () {
      expect(
        serverScrollTrigger(
            hasServers: true,
            connected: false,
            wasConnected: false,
            startupDone: false),
        ServerScrollTrigger.startup,
      );
    });

    test('пока серверов нет — мотать нечего', () {
      expect(
        serverScrollTrigger(
            hasServers: false,
            connected: false,
            wasConnected: false,
            startupDone: false),
        ServerScrollTrigger.none,
      );
    });

    test('стартовая прокрутка делается ровно один раз', () {
      expect(
        serverScrollTrigger(
            hasServers: true,
            connected: false,
            wasConnected: false,
            startupDone: true),
        ServerScrollTrigger.none,
      );
    });

    test('подключение мотает только на переходе, а не каждый такт', () {
      expect(
        serverScrollTrigger(
            hasServers: true,
            connected: true,
            wasConnected: false,
            startupDone: true),
        ServerScrollTrigger.connected,
      );
      expect(
        serverScrollTrigger(
            hasServers: true,
            connected: true,
            wasConnected: true,
            startupDone: true),
        ServerScrollTrigger.none,
        reason: 'статус тикает раз в секунду — список ездил бы постоянно',
      );
    });

    test('строка видна целиком — смещение не нужно', () {
      // Область просмотра 600, строка 73: при смещении 100 строка №2
      // (146…219) видна полностью.
      expect(
        serverRowScrollTarget(
            pos: 2,
            rowExtent: 73,
            pixels: 100,
            viewport: 600,
            maxScrollExtent: 5000),
        isNull,
      );
    });

    test('строка ниже экрана — мотаем к ней', () {
      expect(
        serverRowScrollTarget(
            pos: 50,
            rowExtent: 73,
            pixels: 0,
            viewport: 600,
            maxScrollExtent: 5000),
        50 * 73.0,
      );
    });

    test('строки нет в списке (поиск отфильтровал) — не мотаем', () {
      expect(
        serverRowScrollTarget(
            pos: -1,
            rowExtent: 73,
            pixels: 0,
            viewport: 600,
            maxScrollExtent: 5000),
        isNull,
      );
    });

    test('конец списка не даёт промотать дальше, чем можно', () {
      expect(
        serverRowScrollTarget(
            pos: 99,
            rowExtent: 73,
            pixels: 0,
            viewport: 600,
            maxScrollExtent: 800),
        800,
      );
    });

    testWidgets('на живом списке: до дальней строки мотает, до видимой — нет',
        (tester) async {
      setWindow(tester, const Size(500, 600));
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(host(ListView.builder(
        controller: ctrl,
        itemCount: 100,
        itemExtent: kServerRowExtent,
        itemBuilder: (_, i) => Text('Сервер $i'),
      )));
      await tester.pump();

      expect(find.text('Сервер 60'), findsNothing);
      expect(scrollListToRow(ctrl, pos: 60), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Сервер 60'), findsOneWidget,
          reason: 'запомненный сервер обязан оказаться на экране');

      // Уже видимая строка список не двигает: иначе «прокрутка к выбранному»
      // дёргала бы список, который и так стоит там, где надо.
      final at = ctrl.offset;
      expect(scrollListToRow(ctrl, pos: 61), isFalse);
      await tester.pumpAndSettle();
      expect(ctrl.offset, at);
    });

    testWidgets('высота строки берётся ИЗМЕРЕННАЯ, а не константа',
        (tester) async {
      // ⚠️ Зачем это нужно: строки в списке не все одинаковые (строка-уведомление
      // истёкшей подписки ниже обычной), и промах в высоте копится с номером
      // строки — на 80-й он уже больше экрана, и «прокрутка к серверу» никуда не
      // доезжает. Здесь строка вдвое выше константы: код, считающий по
      // `kServerRowExtent`, не довезёт до 60-й.
      setWindow(tester, const Size(500, 600));
      const tall = kServerRowExtent * 2;
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(host(ListView.builder(
        controller: ctrl,
        itemCount: 100,
        itemExtent: tall,
        itemBuilder: (_, i) => Text('Сервер $i'),
      )));
      await tester.pump();

      expect(scrollListToRow(ctrl, pos: 60, rowExtent: tall), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Сервер 60'), findsOneWidget);
    });

    testWidgets('⚠️ не лезет в список, который пользователь увёл сам',
        (tester) async {
      setWindow(tester, const Size(500, 600));
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(host(ListView.builder(
        controller: ctrl,
        itemCount: 100,
        itemExtent: kServerRowExtent,
        itemBuilder: (_, i) => Text('Сервер $i'),
      )));
      await tester.pump();

      ctrl.jumpTo(900);
      await tester.pump();
      expect(scrollListToRow(ctrl, pos: 0, onlyIfUntouched: true), isFalse);
      await tester.pumpAndSettle();
      expect(ctrl.offset, 900, reason: 'список остался там, где его оставили');
    });
  });
}

/// Движок-пустышка: `AppState` подписывается на его потоки в конструкторе, а
/// самому тесту движок не нужен — ни одного подключения здесь не происходит.
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

/// Окружение для строки сервера: изолированный корень данных (тот же приём, что
/// в `test/api_handlers_test.dart`) + настоящий `AppState` с фейковым движком.
/// Строка читает состояние через `context.watch<AppState>()`, подменить его
/// нечем — интерфейса у состояния нет.
class _TileEnv {
  _TileEnv._(this.dir, this.state, this.probe);

  final Directory dir;
  final AppState state;
  final ProbeController probe;

  static Future<_TileEnv> create() async {
    final dir = Directory.systemTemp.createTempSync('sg_selection_outline_');
    AppPaths.overrideRoot(dir);
    return _TileEnv._(dir, AppState(engine: _FakeEngine()), ProbeController());
  }

  /// Сервер без флага в имени: `FlagCell` тогда рисует значок, а не картинку
  /// страны, и тесту не нужны ассеты.
  VpnServer server(String name, int port) =>
      ShareLinkParser.tryParse('vless://11111111-2222-3333-4444-555555555555'
          '@127.0.0.1:$port#$name')!;

  void dispose() {
    state.dispose();
    probe.dispose();
    AppPaths.resetForTests();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
