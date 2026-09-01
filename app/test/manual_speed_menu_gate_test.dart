import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Пункт «Измерить скорость» в меню строки сервера — ВТОРОЙ запрет,
/// отдельный от запрета внутри контроллера.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ТЕСТ. Исполнитель научили ставить ручной замер в очередь,
/// но интерфейс об этом не знал и продолжал ломаться первой же строкой
/// (`if (probe.running || probe.speedRunning) break;`) — молча, без объяснения.
/// Это ровно тот почерк, из-за которого в проекте уже заводили `PingGate`:
/// разрешение и исполнение расходятся, и кнопка выглядит живой, ничего не
/// делая. Комментарий в коде доказательством не считается — нужен нажатый
/// пункт меню.
void main() {
  final l = AppLocalizationsRu();

  late Directory tmp;
  late _SpyProbe probe;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_menu_gate_');
    AppPaths.overrideRoot(tmp);
    probe = _SpyProbe();
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

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
        // Шрифт-заглушка шире настоящего, а ширина меню прибита Material —
        // уменьшаем текст, иначе пункты переполняются в тесте, но не в
        // приложении. Проверяем здесь поведение пункта, а не его ширину.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ServerTile(server: _server, selected: false, onTap: () {}),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Правая кнопка мыши — единственный вход в это меню на десктопе.
  ///
  /// ⚠️ Ждём КОНЦА анимации, а не появления текста: пока маршрут меню
  /// разворачивается, он накрыт `IgnorePointer`, и нажатие до пункта не дойдёт.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(ServerTile),
        buttons: kSecondaryButton, warnIfMissed: false);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame &&
          _visible(find.text(l.srvTileMeasureSpeed))) {
        return;
      }
    }
    fail('контекстное меню строки сервера не открылось');
  }

  testWidgets('идёт массовый замер — пункт меню всё равно работает',
      (tester) async {
    // Сервер проверку канала прошёл: гейт «не проверен» тут ни при чём.
    probe.setResult(_server, _passed);
    probe.speedBusy = true;

    await mount(tester);
    await openMenu(tester);
    await tester.tap(find.text(l.srvTileMeasureSpeed));
    await tester.pumpAndSettle();

    expect(probe.measuredOne?.key, _server.key,
        reason: 'массовый прогон больше не запрет: исполнитель поставит '
            'ручной замер в голову очереди — интерфейс обязан до него дойти');
  });

  testWidgets('идёт прогон пинга — пункт меню тоже работает', (tester) async {
    probe.setResult(_server, _passed);
    probe.pingBusy = true;

    await mount(tester);
    await openMenu(tester);
    await tester.tap(find.text(l.srvTileMeasureSpeed));
    await tester.pumpAndSettle();

    expect(probe.measuredOne?.key, _server.key,
        reason: 'пинг тоже не запрет: замер дождётся его конца и состоится');
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

const _passed = PingResult(
    outcome: PingOutcome.ok,
    latencyMs: 40,
    verification: PingVerification.passed);

const _server = VpnServer(
  protocol: 'vless',
  remark: 'Германия',
  address: 'de.example',
  port: 443,
  id: '00000000-0000-0000-0000-000000000000',
  rawLink: 'vless://00000000-0000-0000-0000-000000000000@de.example:443'
      '?type=tcp&security=none#Германия',
);

bool _visible(Finder f) {
  final found = f.evaluate();
  if (found.isEmpty) return false;
  final box = found.first.renderObject;
  if (box is! RenderBox || !box.hasSize) return false;
  final origin = box.localToGlobal(Offset.zero);
  return origin.dy >= 0 && origin.dx >= 0;
}

class _SpyProbe extends ProbeController {
  bool speedBusy = false;
  bool pingBusy = false;
  VpnServer? measuredOne;

  @override
  bool get running => pingBusy;

  @override
  bool get speedRunning => speedBusy;

  @override
  Future<void> measureSpeedOne(VpnServer server, AppSettings settings) async {
    measuredOne = server;
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
