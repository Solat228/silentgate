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
import 'package:silentgate/ui/widgets/site_favicon.dart';

/// РАСКЛАДКА «РЯДЫ» ВЛЕЗАЕТ В ПАНЕЛЬ ПРИ ПОЛНОМ НАБОРЕ ПРОВЕРОК.
///
/// ⚠️ ЗАМЕР, С КОТОРОГО ВСЁ НАЧАЛОСЬ (10.09.2026): четырнадцать сервисов в
/// раскладке `rows` на широком окне переполняли панель на **97 px при
/// 1024×781** и **117 px при 964×761** — причём и в ОТКЛЮЧЁННОМ состоянии, с
/// пустым контроллером проверок. То есть дефект не в паре «до → после» и не в
/// живом канале, а в самой раскладке: у `ServiceChecksSides` содержимое
/// сжимается общим коэффициентом, а у рядов сжатия не было вовсе — при этом
/// потолок высоты (`checksHeightBudget`) им всё равно выдавался.
///
/// ⚠️ СЛУЧАЙ ДОСТИЖИМЫЙ, А НЕ ТЕОРЕТИЧЕСКИЙ. Раскладку выбирает человек в
/// подменю проверок; умолчание `adaptive` на такой ширине уходит в `sides` и
/// потому цело, но выбрать «ряды» руками можно — и тогда низ экрана уезжает.
///
/// ⚠️ ПРОВЕРЯЕТСЯ НЕ «НЕТ ИСКЛЮЧЕНИЯ ПЕРЕПОЛНЕНИЯ», А «НИЗ ВИДЕН» — см. шапку
/// `connected_bottom_visible_test.dart`: содержимое панели уезжает за нижнюю
/// кромку молча, без единого исключения.
///
/// ⚠️ И ОТДЕЛЬНО — ЧИТАЕМОСТЬ. Сжать можно до чего угодно, поэтому здесь же
/// проверяется РАЗМЕР значка на экране: сжатие, превращающее бренд-иконки в
/// пыль, решением не является — в этом случае правильный ответ был бы иным
/// (прокрутка), и тест обязан заставить об этом узнать.
void main() {
  late Directory tmp;
  late Future<ServiceCheckOutcome> Function(int, ProbeService) savedProber;
  late Future<bool> Function(int) savedReadiness;

  const links = [
    'vless://11111111-2222-3333-4444-555555555555'
        '@a.example.com:443?encryption=none#Germany',
  ];

  /// Разные вердикты, а не четырнадцать зелёных: красный и «геоблок» рисуют
  /// ещё и глиф в углу кольца — набор из одних «ok» проверял бы самый лёгкий
  /// случай, называясь при этом проверкой тяжёлого.
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
    ServiceCheckController.prober = (port, s) async =>
        ServiceCheckOutcome(stateFor(s), latencyMs: 120 + port % 7);
    ServiceCheckController.readinessProbe = (port) async => true;

    // ⚠️ Боевой `%APPDATA%` тестам недоступен (`AppPaths`) — тест уже
    // переписывал владельцу `subscriptions.json`.
    tmp = Directory.systemTemp.createTempSync('sg_rows_fit_');
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

  /// Контроллер в состоянии владельца: замер «до» снят по всем четырнадцати,
  /// туннель поднят, вердикты «после» получены. Пары «до → после» — самый
  /// широкий и самый высокий случай ячейки.
  Future<ServiceCheckController> seededChecks(WidgetTester t) async {
    final ctrl = ServiceCheckController();
    await t.runAsync(() async {
      await ctrl.checkBaseline(ServiceChecks.catalog);
      ctrl.setTunnelUp(true);
      for (final s in ServiceChecks.catalog) {
        await ctrl.check(s, 10809);
      }
    });
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

  /// Нижняя граница читаемости значка НА ЭКРАНЕ.
  ///
  /// ⚠️ Меряется не свойство виджета, а его ФАКТИЧЕСКИЙ прямоугольник
  /// (`getRect` проводит точки через матрицу преобразования, `getSize` — нет):
  /// сжатие живёт в `FittedBox`, то есть в трансформации, и «размер» виджета
  /// после него остаётся прежним.
  ///
  /// ⚠️ ПОРОГ РАЗНЫЙ ПО МАСШТАБУ ШРИФТА, И ЭТО ЧЕСТНОЕ ЧИСЛО, А НЕ ПОБЛАЖКА.
  /// Замеры после правки (10.09.2026, полный набор из четырнадцати):
  ///   ×1,0: 16,8 px (964×761) и 18,4 px (1024×781) — с запасом;
  ///   ×1,3: 11,2 px (964×761) и 12,7 px (1024×781) — НА САМОМ КРАЮ.
  /// Крупный системный шрифт бьёт дважды: резерв под низом панели растёт на
  /// треть (`checksHeightBudget`), а подписи групп внутри рядов растут вместе
  /// с ним — потолок опускается и содержимое пухнет одновременно. 11 px на
  /// минимальном окне — граница, ниже которой сжатие перестаёт быть ответом:
  /// дальше правильный ход — не мельчить, а прокручивать ряды. Просядет это
  /// число — не опускайте порог, меняйте раскладку.
  double minReadableIconFor(double textScale) => textScale > 1 ? 11.0 : 12.0;

  for (final size in windows) {
    for (final connected in const [false, true]) {
      for (final textScale in const [1.0, 1.3]) {
        testWidgets(
            '${size.width.toInt()}×${size.height.toInt()}, rows, '
            '${connected ? 'подключено' : 'отключено'}, шрифт ×$textScale: '
            '14 сервисов помещаются', (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);

          final state = await boot(t);
          // Отключённое состояние — с ПУСТЫМ контроллером: именно так дефект
          // и был замерен, и именно так видно, что дело не в парах.
          final checks = connected
              ? await seededChecks(t)
              : ServiceCheckController();
          await t.pumpWidget(host(
            HomeBody(
              status: VpnStatus(connected
                  ? VpnConnectionState.connected
                  : VpnConnectionState.disconnected),
              settings: const AppSettings(
                connectCheckServices: {...ServiceChecks.catalog},
                serviceChecksLayout: ServiceChecksLayout.rows,
              ),
              onOpen: (_) {},
            ),
            state,
            checks,
            textScale: textScale,
          ));
          await t.pump();

          expect(t.takeException(), isNull,
              reason: 'панель переполнилась на раскладке «ряды»');

          final pane = t.getRect(find.byType(ConnectPane));
          final traffic = t.getRect(find.byType(TrafficRow));
          expect(traffic.bottom, lessThanOrEqualTo(pane.bottom + 0.5),
              reason: 'счётчики трафика уехали за нижнюю кромку панели на '
                  '${(traffic.bottom - pane.bottom).toStringAsFixed(1)} px — '
                  'исключения при этом нет, беда видна только глазами');
          expect(traffic.top, greaterThanOrEqualTo(pane.top - 0.5),
              reason: 'счётчики уехали вверх за кромку панели');

          // Ряды действительно нарисованы, а не выродились в пустоту: иначе
          // «влезло» означало бы «показывать нечего».
          expect(
              find.descendant(
                  of: find.byType(ServiceChecksRows),
                  matching: find.byKey(const ValueKey('svc:telegram'))),
              findsOneWidget,
              reason: 'ряды проверок до экрана не дошли');

          // ⚠️ ЗНАЧКИ ОСТАЛИСЬ ЧИТАЕМЫМИ. Сжать блок можно до пыли, и тест
          // «низ виден» этого бы не заметил.
          final icon = t.getRect(find
              .descendant(
                  of: find.byType(ServiceChecksRows),
                  matching: find.byType(SiteFavicon))
              .first);
          expect(icon.width, greaterThanOrEqualTo(minReadableIconFor(textScale)),
              reason: 'значок сервиса сжат до '
                  '${icon.width.toStringAsFixed(1)} px — это уже не иконка, '
                  'а пятно: сжатие перестало быть правильным ответом');
        });
      }
    }
  }
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
