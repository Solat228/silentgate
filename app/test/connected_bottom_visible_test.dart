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
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// НИЗ ГЛАВНОГО ЭКРАНА ВИДЕН В САМОМ ТЯЖЁЛОМ ИЗ РЕАЛЬНЫХ СОСТОЯНИЙ.
///
/// ⚠️ ЧЕГО НЕ ХВАТАЛО ДЕЙСТВУЮЩИМ СТРАЖАМ. Они проверяют вёрстку на наборе по
/// умолчанию (три сервиса) и в ОТКЛЮЧЁННОМ состоянии. А у владельца включены
/// все ЧЕТЫРНАДЦАТЬ, и в подключённом состоянии каждая ячейка становится ПАРОЙ
/// «до → после», то есть вдвое шире и с двумя кольцами вместо одного. Ровно это
/// сочетание — состав владельца плюс живой канал с готовыми вердиктами — и
/// показал живой прогон 10.09.2026; ни один из 2710 тестов его не собирал.
///
/// ⚠️ И ПРОВЕРЯЕТСЯ НЕ «НЕТ ИСКЛЮЧЕНИЯ ПЕРЕПОЛНЕНИЯ», А «НИЗ ВИДЕН».
/// Содержимое панели лежит внутри `_MaybeScroll`, и уехавший за нижнюю кромку
/// низ исключения НЕ вызывает — он просто не виден. Это и была исходная
/// жалоба: счётчики трафика на минимальном окне оказывались за краем, а тесты
/// оставались зелёными. Поэтому здесь сравниваются КООРДИНАТЫ: нижняя кромка
/// [TrafficRow] против нижней кромки панели.
void main() {
  late Directory tmp;
  late Future<ServiceCheckOutcome> Function(int, ProbeService) savedProber;
  late Future<bool> Function(int) savedReadiness;

  const links = [
    'vless://11111111-2222-3333-4444-555555555555'
        '@a.example.com:443?encryption=none#Germany',
    'vless://11111111-2222-3333-4444-555555555555'
        '@b.example.com:443?encryption=none#Netherlands',
  ];

  /// ⚠️ РАЗНЫЕ ВЕРДИКТЫ, А НЕ ЧЕТЫРНАДЦАТЬ ЗЕЛЁНЫХ. Красный и «геоблок»
  /// рисуют ещё и глиф в углу кольца, то есть занимают больше зелёного;
  /// набор из одних «ok» проверял бы САМЫЙ ЛЁГКИЙ случай и назывался бы при
  /// этом проверкой самого тяжёлого.
  ServiceCheckState stateFor(ProbeService s) {
    final i = ServiceChecks.catalog.indexOf(s);
    return switch (i % 3) {
      0 => ServiceCheckState.ok,
      1 => ServiceCheckState.fail,
      _ => ServiceCheckState.geoBlocked,
    };
  }

  setUp(() {
    savedProber = ServiceCheckController.prober;
    savedReadiness = ServiceCheckController.readinessProbe;
    // Сети в стражах вёрстки быть не должно: пробы сервисов — настоящие
    // сокеты, и тест на них висел бы, а падал бы «A Timer is still pending».
    ServiceCheckController.prober = (port, s) async =>
        ServiceCheckOutcome(stateFor(s), latencyMs: 120 + port % 7);
    ServiceCheckController.readinessProbe = (port) async => true;

    // ⚠️ Боевой `%APPDATA%` тестам недоступен (`AppPaths`) — тест уже
    // переписывал владельцу `subscriptions.json`.
    tmp = Directory.systemTemp.createTempSync('sg_bottom_visible_');
    AppPaths.overrideRoot(tmp);
    File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp.path}${Platform.pathSeparator}subscriptions.json')
        .writeAsStringSync(jsonEncode({
      'activeId': 'sub-test',
      'items': [
        {
          'id': 'sub-test',
          'url': 'https://panel.example/sub',
          'title': 'Test',
          'servers': links,
          'addedAt': '2026-09-01T00:00:00.000Z',
        },
      ],
    }));
  });

  tearDown(() async {
    ServiceCheckController.prober = savedProber;
    ServiceCheckController.readinessProbe = savedReadiness;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// ⚠️ ЧЕРЕЗ `runAsync`: `AppState.init()` читает файлы с диска, а в
  /// поддельном времени `testWidgets` настоящие файловые операции не
  /// завершаются НИКОГДА — тест не падает, а виснет.
  Future<AppState> boot(WidgetTester t) async {
    final state = AppState(engine: _FakeEngine());
    await t.runAsync(() => state.init());
    return state;
  }

  /// Контроллер проверок в том состоянии, в котором его видит владелец:
  /// замер «до» снят по всем четырнадцати, туннель поднят, вердикты «после»
  /// получены. Пары «до → после» рисуются только так.
  Future<ServiceCheckController> seededChecks(WidgetTester t) async {
    final ctrl = ServiceCheckController();
    await t.runAsync(() async {
      await ctrl.checkBaseline(ServiceChecks.catalog);
      ctrl.setTunnelUp(true);
      for (final s in ServiceChecks.catalog) {
        await ctrl.check(s, 10809);
      }
    });
    // Страховка от самообмана: пустой контроллер нарисовал бы одинокие серые
    // кружки, то есть САМЫЙ узкий случай, и тест ничего бы не проверял.
    for (final s in ServiceChecks.catalog) {
      expect(ctrl.baselineFor(s).state, isNot(ServiceCheckState.idle),
          reason: 'замер «до» не снят — пары «до → после» не нарисуются');
      expect(ctrl.resultFor(s).state, isNot(ServiceCheckState.idle),
          reason: 'вердикт «через VPN» не записан — вторая половина пары '
              'осталась пустой');
    }
    return ctrl;
  }

  Widget host(Widget child, AppState state, ServiceCheckController checks,
          {double textScale = 1.0}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ProbeController>.value(
              value: ProbeController()),
          ChangeNotifierProvider<SettingsController>.value(
              value: SettingsController()),
          ChangeNotifierProvider<AutoConfigController>.value(
              value: AutoConfigController()),
          ChangeNotifierProvider<ServiceCheckController>.value(value: checks),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Окна из снимков в VM: минимальное и рабочее.
  const windows = <Size>[Size(964, 761), Size(1024, 781)];

  /// Раскладки: `adaptive` — умолчание настройки, `sides` — то, что стоит у
  /// владельца. На панели этой ширины `adaptive` выбирает `sides` сама, и
  /// проверяются обе именно поэтому: подмену выбора (а он уже разъезжался
  /// однажды, см. `_sidesMinWidth`) видно только сравнением.
  ///
  /// ⚠️ `rows` ЗДЕСЬ С 10.09.2026, И ЭТО НЕ ФОРМАЛЬНОСТЬ. До правки раскладка
  /// рядами на широком окне с четырнадцатью сервисами переполняла панель на
  /// 97 px (1024×781) и 117 px (964×761) — причём и в ОТКЛЮЧЁННОМ состоянии, с
  /// пустым контроллером проверок: дефект был не в паре «до → после» и не в
  /// живом канале, а в самой раскладке — у рядов не было сжатия вовсе, а
  /// потолок высоты им всё равно выдавался. Теперь ряды сжимают СВОЁ
  /// содержимое (`ServiceChecksRows`), кнопка Connect остаётся своего диаметра,
  /// и случай проверяется наравне с прочими. Подробный разбор с размерами
  /// значков — `service_checks_rows_fit_test.dart`.
  const layouts = <ServiceChecksLayout>[
    ServiceChecksLayout.adaptive,
    ServiceChecksLayout.sides,
    ServiceChecksLayout.rows,
  ];

  for (final size in windows) {
    for (final layout in layouts) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()}, ${layout.name}: '
          '14 сервисов, подключено, вердикты на месте', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        final state = await boot(t);
        final checks = await seededChecks(t);
        await t.pumpWidget(host(
          HomeBody(
            status: const VpnStatus(VpnConnectionState.connected),
            settings: AppSettings(
              connectCheckServices: {...ServiceChecks.catalog},
              serviceChecksLayout: layout,
            ),
            onOpen: (_) {},
          ),
          state,
          checks,
        ));
        await t.pump();

        expect(t.takeException(), isNull,
            reason: 'панель переполнилась при полном наборе проверок и живом '
                'канале');

        // ⚠️ ГЛАВНОЕ УТВЕРЖДЕНИЕ: НИЗ ВИДЕН.
        final pane = t.getRect(find.byType(ConnectPane));
        final traffic = t.getRect(find.byType(TrafficRow));
        expect(traffic.bottom, lessThanOrEqualTo(pane.bottom + 0.5),
            reason: 'счётчики трафика уехали за нижнюю кромку панели на '
                '${(traffic.bottom - pane.bottom).toStringAsFixed(1)} px — '
                'исключения при этом нет, беда видна только глазами');
        expect(traffic.top, greaterThanOrEqualTo(pane.top - 0.5),
            reason: 'счётчики уехали вверх за кромку панели');

        // И проверки действительно нарисованы парами: иначе тест меряет не тот
        // случай, ради которого написан.
        expect(find.byKey(const ValueKey('svc:telegram')), findsWidgets,
            reason: 'ячеек проверок нет вовсе — набор до экрана не дошёл');
      });
    }
  }

  testWidgets('⚠️ 964×761, sides, шрифт ×1,3: низ всё ещё виден', (t) async {
    // Крупный системный шрифт растит ровно то, что лежит НИЖЕ потолка блока
    // проверок (статус, подписи кнопок, счётчики). Правка ради тесного окна,
    // ломающаяся на первом же человеке с плохим зрением, — не правка.
    t.view.physicalSize = const Size(964, 761);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final state = await boot(t);
    final checks = await seededChecks(t);
    await t.pumpWidget(host(
      HomeBody(
        status: const VpnStatus(VpnConnectionState.connected),
        settings: const AppSettings(
          connectCheckServices: {...ServiceChecks.catalog},
          serviceChecksLayout: ServiceChecksLayout.sides,
        ),
        onOpen: (_) {},
      ),
      state,
      checks,
      textScale: 1.3,
    ));
    await t.pump();

    expect(t.takeException(), isNull);
    final pane = t.getRect(find.byType(ConnectPane));
    final traffic = t.getRect(find.byType(TrafficRow));
    expect(traffic.bottom, lessThanOrEqualTo(pane.bottom + 0.5),
        reason: 'при шрифте ×1,3 низ панели ушёл за край на '
            '${(traffic.bottom - pane.bottom).toStringAsFixed(1)} px');
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
