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
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/ping_chip.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Вёрстка строки сервера: плашки пинга и скорости (жалоба владельца 13.08.2026
/// — «с пингом и скоростью всё плохо, из-за скорости всё поплыло»).
///
/// ⚠️ ЧТО ИМЕННО БЫЛО СЛОМАНО, и почему это не видно глазами в коде.
/// `ListTile` с `dense: true` + `VisualDensity(vertical: -2)` отводит под
/// `trailing` РОВНО 40 dp и строку под него НЕ растягивает. Плашка была 25 dp
/// высотой, столбик «пинг + просвет + скорость» — 52 dp: он вылезал за пределы
/// своей строки на 11 px и рисовался поверх соседней. Замеряно на этом же
/// стенде до правки:
///   ping = 6.5…31.5, speed = 33.5…57.5, а сама строка — всего 53 px.
/// Плюс `RenderFlex overflowed by 11 pixels` в отладочной сборке.
///
/// Здесь проверяется НАСТОЯЩИЙ `ServerTile`, а не его копия: плотность строки
/// (`dense`/`visualDensity`) задаётся в нём, и копия молча разошлась бы с
/// оригиналом ровно по тому параметру, из-за которого всё и сломалось.
///
/// Сети и VPN тест не касается: движок фиктивный, результаты пинга и скорости
/// кладутся в контроллер руками.
void main() {
  late Directory tmp;
  late AppState state;
  late ProbeController probe;
  late SettingsController settings;

  const server = VpnServer(
    protocol: 'vless',
    remark: 'Германия',
    address: 'de.example',
    port: 443,
    id: '00000000-0000-0000-0000-000000000000',
    rawLink: 'vless://00000000-0000-0000-0000-000000000000@de.example:443'
        '?type=tcp&security=none#Германия',
  );

  setUp(() {
    // Результаты пинга/скорости сохраняются на диск — уводим корень данных в
    // темп, чтобы не трогать боевой %APPDATA%\SilentGate.
    tmp = Directory.systemTemp.createTempSync('sg_tile_layout_');
    AppPaths.overrideRoot(tmp);
    state = AppState(engine: _FakeEngine());
    probe = ProbeController();
    settings = SettingsController();
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Рисует строку сервера с заданным пингом и (необязательно) скоростью.
  ///
  /// ⚠️ Размер поверхности задаётся через `tester.view.physicalSize`, а НЕ
  /// обёрткой `SizedBox`: стандартные 800×600 теста зажимают строку и врут о
  /// доступной ширине.
  Future<void> pumpTile(
    WidgetTester tester, {
    required PingResult ping,
    ServerSpeed? speed,
    double width = 1000,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    probe.setResult(server, ping);
    if (speed != null) probe.adoptSpeeds({server.key: speed});

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<ProbeController>.value(value: probe),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [
            ServerTile(server: server, selected: false, onTap: () {}),
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  const passed = PingResult(
      outcome: PingOutcome.ok,
      latencyMs: 256,
      verification: PingVerification.passed);
  const speed = ServerSpeed(mbps: 49.6);

  Rect tileRect(WidgetTester tester) =>
      tester.getRect(find.byType(ListTile).first);

  // ── Главное: столбик обязан помещаться в строку ────────────────────────────

  testWidgets('столбик со скоростью не вылезает за пределы строки',
      (tester) async {
    await pumpTile(tester, ping: passed, speed: speed);

    expect(find.text('256 мс'), findsOneWidget);
    expect(find.text('49.6 Мбит/с'), findsOneWidget);

    final tile = tileRect(tester);
    final column = tester.getRect(find.byType(PingSpeedColumn));
    final speedRect = tester.getRect(find.byType(SpeedChip));

    // ⚠️ ЗДЕСЬ БЫЛ ДЕФЕКТ: низ плашки скорости был на 4.5 px НИЖЕ низа строки
    // (57.5 против 53) — плашка рисовалась поверх соседнего сервера.
    expect(speedRect.bottom, lessThanOrEqualTo(tile.bottom),
        reason: 'скорость рисовалась поверх соседней строки');
    expect(column.top, greaterThanOrEqualTo(tile.top));
    expect(column.bottom, lessThanOrEqualTo(tile.bottom));

    // И сам `RenderFlex` больше не переполняется.
    expect(tester.takeException(), isNull,
        reason: 'столбик переполнял отведённые ему 40 dp');
  });

  testWidgets('появление скорости не меняет высоту строки', (tester) async {
    await pumpTile(tester, ping: passed);
    final without = tileRect(tester).height;

    await pumpTile(tester, ping: passed, speed: speed);
    final with_ = tileRect(tester).height;

    // «Список дышит» — жалоба владельца. Высота строки обязана определяться
    // текстом, а не тем, успел ли пользователь замерить скорость.
    expect((with_ - without).abs(), lessThanOrEqualTo(2),
        reason: 'строка со скоростью и без обязана быть одной высоты');
  });

  // ── Порядок по вертикали ───────────────────────────────────────────────────

  testWidgets('пинг прижат к верху столбика, скорость — к низу',
      (tester) async {
    await pumpTile(tester, ping: passed, speed: speed);

    final column = tester.getRect(find.byType(PingSpeedColumn));
    final pingRect = tester.getRect(find.byType(PingChip));
    final speedRect = tester.getRect(find.byType(SpeedChip));

    expect(pingRect.top, lessThan(speedRect.top),
        reason: 'пинг обязан быть ВЫШЕ скорости');
    // Прижаты именно к краям, а не «где-то в столбике».
    expect(pingRect.top, closeTo(column.top, 0.5));
    expect(speedRect.bottom, closeTo(column.bottom, 0.5));
    // Между ними пусто — просьба владельца дословно.
    expect(speedRect.top - pingRect.bottom, greaterThanOrEqualTo(4));
  });

  // ── Компактность ───────────────────────────────────────────────────────────

  test('высота столбика влезает в 40 dp, которые ListTile даёт trailing', () {
    // Эти 40 dp — не наша величина: (48 dense) + (-2 × 4 плотности) = 40.
    // Столбик обязан влезать в них ЦЕЛИКОМ, иначе он рисуется поверх соседей.
    expect(PingChip.columnHeight, lessThanOrEqualTo(40));
    expect(PingChip.columnHeight,
        PingChip.chipHeight * 2 + PingChip.chipGap);
  });

  testWidgets('плашки компактные и одинаковые', (tester) async {
    await pumpTile(tester, ping: passed, speed: speed);

    final pingSize = tester.getSize(find.byType(PingChip));
    final speedSize = tester.getSize(find.byType(SpeedChip));
    // До правки было 25 и 24 — «обводка почти во всю высоту строки».
    expect(pingSize.height, PingChip.chipHeight);
    expect(speedSize.height, PingChip.chipHeight);
    expect(PingChip.chipHeight, lessThanOrEqualTo(18),
        reason: 'владелец просил обводку ПОМЕНЬШЕ');

    // Радиус и шрифт — тоже мельче, и у обеих плашек ОДИНАКОВЫЕ: они читаются
    // как пара, а не как значение и приписка к нему.
    final pingPill = _pill(tester, find.byType(PingChip));
    final speedPill = _pill(tester, find.byType(SpeedChip));
    expect(_radius(pingPill), lessThanOrEqualTo(8));
    expect(_radius(pingPill), _radius(speedPill));

    final pingFont = tester.widget<Text>(find.text('256 мс')).style?.fontSize;
    final speedFont =
        tester.widget<Text>(find.text('49.6 Мбит/с')).style?.fontSize;
    expect(pingFont, lessThanOrEqualTo(11));
    expect(pingFont, speedFont);
  });

  // ── Состояния ──────────────────────────────────────────────────────────────

  testWidgets('состояния пинга не ломают высоту и не переполняют столбик',
      (tester) async {
    // Каждое состояние — своя ветка `PingChip.build`; любая из них выше
    // [PingChip.chipHeight] снова распёрла бы столбик.
    //
    // ⚠️ Замер скорости здесь ОБЯЗАТЕЛЕН: компактной плашка бывает только в
    // столбике. Без замера пинг рисуется крупным — это отдельный вид, и стерёг
    // его отдельный файл (`test/ping_chip_layout_test.dart`).
    final cases = <String, PingResult>{
      'n/a': const PingResult(outcome: PingOutcome.failed),
      'таймаут': const PingResult(outcome: PingOutcome.timeout),
      'проверяю': const PingResult(
          outcome: PingOutcome.ok, verification: PingVerification.pending),
    };
    for (final entry in cases.entries) {
      await pumpTile(tester, ping: entry.value, speed: speed);
      expect(find.text(entry.key), findsOneWidget,
          reason: 'состояние «${entry.key}» пропало из плашки');
      expect(tester.getSize(find.byType(PingChip)).height, PingChip.chipHeight);
      expect(tester.getRect(find.byType(PingChip)).bottom,
          lessThanOrEqualTo(tileRect(tester).bottom));
    }

    // «Ещё не проверяли» — кружок, а не текст: он тоже обязан быть ростом с
    // плашку, иначе строка дёргается, когда результат появится.
    await pumpTile(tester, ping: PingResult.untested, speed: speed);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(PingChip)).height, PingChip.chipHeight);

    // «Проверяю прямо сейчас» — кружок прогресса того же роста.
    await pumpTile(tester, ping: PingResult.testing, speed: speed);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(PingChip)).height, PingChip.chipHeight);
  });

  testWidgets('у непрошедшего проверку плашки скорости нет вовсе',
      (tester) async {
    await pumpTile(tester,
        ping: const PingResult(outcome: PingOutcome.timeout));

    // ⚠️ ЗДЕСЬ ЖДАЛИ ПРОЧЕРК «—» — прежнее решение владельца, ОТМЕНЁННОЕ им
    // 18.08.2026: «убери значок проверки скорости, если он не проводился».
    // Прочерков в списке было большинство, и из-за них плашка пинга ужималась
    // у всех строк подряд. Не возвращать.
    expect(find.text('—'), findsNothing);
    expect(find.byType(SpeedChip), findsNothing);
    final tile = tileRect(tester);
    expect(tester.getRect(find.byType(PingChip)).bottom,
        lessThanOrEqualTo(tile.bottom));
    expect(tester.takeException(), isNull);
  });

  // ── Телефон ────────────────────────────────────────────────────────────────

  testWidgets('на узком экране столбик не ломает вёрстку', (tester) async {
    // 360 dp — ширина обычного телефона.
    await pumpTile(tester, ping: passed, speed: speed, width: 360);

    final tile = tileRect(tester);
    expect(tile.width, 360, reason: 'строка не должна вылезать по горизонтали');
    final column = tester.getRect(find.byType(PingSpeedColumn));
    expect(column.right, lessThanOrEqualTo(tile.right + 0.5));
    expect(column.left, greaterThanOrEqualTo(tile.left));
    expect(column.height, PingChip.columnHeight);
    // Имя сервера на месте (у заголовка многоточие, а не переполнение).
    expect(find.text('Германия'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'на телефоне строка не должна переполняться');
  });
}

/// Контейнер-плашка внутри виджета (у неё и радиус, и фон).
Container _pill(WidgetTester tester, Finder chip) => tester.widget<Container>(
    find.descendant(of: chip, matching: find.byType(Container)).first);

double _radius(Container pill) {
  final d = pill.decoration as BoxDecoration;
  return (d.borderRadius as BorderRadius).topLeft.x;
}

/// Движок-пустышка: ни одного реального действия, VPN не поднимается.
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
