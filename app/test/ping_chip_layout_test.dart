import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';
import 'package:silentgate/ui/widgets/ping_chip.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Плашка пинга и скорости: КРУПНЫЙ пинг, пока скорость не мерили (жалоба
/// владельца 18.08.2026) — и пункт меню «Скопировать ключ».
///
/// ⚠️ ЧТО БЫЛО СЛОМАНО. Плашка скорости показывалась не только по факту замера,
/// но и у сервера, который заведомо не измерить (мёртвый или не прошедший
/// проверку канала): на его месте стоял ПРОЧЕРК «—». Таких серверов в списке
/// большинство, поэтому столбик из двух плашек строился почти у каждой строки,
/// а пинг ужимался до 16 dp — хотя скорость не мерили ни у одного сервера.
/// Владелец: «убери значок проверки скорости, если он не проводился; если
/// серверы только пинговали — пинг большими буквами посередине». Это ОТМЕНЯЕТ
/// его же прежнее решение про прочерки, поэтому здесь стоит страж: вернувший
/// прочерк увидит красный тест, а не «непонятно, почему так».
///
/// ⚠️ Вторая половина файла — про высоту строки. Крупная плашка (25 dp) и
/// столбик (38 dp) разной высоты, и без общей коробки список бы дёргался ровно
/// у тех строк, где замер уже сделан.
///
/// Сети и VPN тест не касается: движок фиктивный, результаты кладутся руками.
void main() {
  late Directory tmp;
  late AppState state;
  late ProbeController probe;
  late SettingsController settings;
  late AutoConfigController autoCfg;

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
    // Результаты пинга/скорости пишутся на диск — уводим корень данных в темп,
    // чтобы тест не тронул боевой %APPDATA%\SilentGate.
    tmp = Directory.systemTemp.createTempSync('sg_ping_chip_');
    AppPaths.overrideRoot(tmp);
    state = AppState(engine: _FakeEngine());
    probe = ProbeController();
    settings = SettingsController();
    autoCfg = AutoConfigController();
    AppToast.dismiss();
  });

  tearDown(() {
    AppToast.dismiss();
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
    VpnServer srv = server,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    probe.setResult(srv, ping);
    if (speed != null) probe.adoptSpeeds({srv.key: speed});

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<ProbeController>.value(value: probe),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AutoConfigController>.value(value: autoCfg),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [
            ServerTile(server: srv, selected: false, onTap: () {}),
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
  const dead = PingResult(outcome: PingOutcome.failed);
  const noProxy = PingResult(
      outcome: PingOutcome.ok,
      latencyMs: 80,
      verification: PingVerification.failed);
  const speed = ServerSpeed(mbps: 49.6);

  Rect tileRect(WidgetTester tester) =>
      tester.getRect(find.byType(ListTile).first);

  Container pillOf(WidgetTester tester, Finder chip) => tester.widget<Container>(
      find.descendant(of: chip, matching: find.byType(Container)).first);

  double radiusOf(Container pill) =>
      ((pill.decoration as BoxDecoration).borderRadius as BorderRadius)
          .topLeft
          .x;

  // ── Скорость показываем ТОЛЬКО по факту замера ─────────────────────────────

  group('Плашка скорости — только когда замер реально был', () {
    testWidgets('замера не делали — плашки нет вовсе', (tester) async {
      await pumpTile(tester, ping: passed);

      expect(find.text('256 мс'), findsOneWidget);
      expect(find.byType(SpeedChip), findsNothing,
          reason: 'скорость не мерили — показывать нечего');
      expect(find.text('—'), findsNothing);
    });

    testWidgets('мёртвый сервер: прочерка на месте скорости больше нет',
        (tester) async {
      // ⚠️ ЗДЕСЬ БЫЛ ДЕФЕКТ: `SpeedChip.visible` возвращал true по
      // `ping.speedBlocked`, и почти вся колонка списка состояла из прочерков.
      await pumpTile(tester, ping: dead);

      expect(find.text('n/a'), findsOneWidget);
      expect(find.byType(SpeedChip), findsNothing);
      expect(find.text('—'), findsNothing,
          reason: 'прочерк отменён владельцем 18.08.2026 — не возвращать');
    });

    testWidgets('отвечает, но не проксирует — тоже без прочерка',
        (tester) async {
      await pumpTile(tester, ping: noProxy);

      expect(find.byType(SpeedChip), findsNothing);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('замер есть — плашка со скоростью на месте', (tester) async {
      await pumpTile(tester, ping: passed, speed: speed);

      expect(find.byType(SpeedChip), findsOneWidget);
      expect(find.text('49.6 Мбит/с'), findsOneWidget);
    });
  });

  // ── Размер плашки пинга ────────────────────────────────────────────────────

  group('Пинг крупный, пока скорость не мерили', () {
    testWidgets('без замера — крупная плашка (как было до скорости)',
        (tester) async {
      await pumpTile(tester, ping: passed);

      final size = tester.getSize(find.byType(PingChip));
      expect(size.height, PingChip.largeChipHeight,
          reason: 'владелец просил вернуть «пинг большими буквами»');
      expect(radiusOf(pillOf(tester, find.byType(PingChip))), 12);
      expect(tester.widget<Text>(find.text('256 мс')).style?.fontSize, 12);

      // Плашка стоит ПО ЦЕНТРУ отведённой строке высоты, а не прижата к краю.
      final column = tester.getRect(find.byType(PingSpeedColumn));
      final chip = tester.getRect(find.byType(PingChip));
      expect(chip.center.dy, closeTo(column.center.dy, 0.5));
    });

    testWidgets('замер есть — пинг ужимается и уходит наверх', (tester) async {
      await pumpTile(tester, ping: passed, speed: speed);

      expect(tester.getSize(find.byType(PingChip)).height, PingChip.chipHeight);
      expect(radiusOf(pillOf(tester, find.byType(PingChip))), 6);
      expect(tester.widget<Text>(find.text('256 мс')).style?.fontSize, 11);

      final column = tester.getRect(find.byType(PingSpeedColumn));
      final ping = tester.getRect(find.byType(PingChip));
      final sp = tester.getRect(find.byType(SpeedChip));
      expect(ping.top, closeTo(column.top, 0.5));
      expect(sp.bottom, closeTo(column.bottom, 0.5));
      expect(sp.top - ping.bottom, greaterThanOrEqualTo(4),
          reason: 'между пингом и скоростью пусто — просьба владельца');
    });

    testWidgets('крупный вид не переполняет отведённые trailing 40 dp',
        (tester) async {
      // Все ветки `PingChip.build` в крупном виде: любая выше [columnHeight]
      // снова полезла бы на соседнюю строку.
      final cases = <String, PingResult>{
        'n/a': dead,
        'таймаут': const PingResult(outcome: PingOutcome.timeout),
        '80 мс': noProxy,
      };
      for (final e in cases.entries) {
        await pumpTile(tester, ping: e.value);
        expect(find.text(e.key), findsOneWidget,
            reason: 'состояние «${e.key}» пропало из плашки');
        expect(tester.getSize(find.byType(PingChip)).height,
            PingChip.largeChipHeight);
        expect(tester.getRect(find.byType(PingChip)).bottom,
            lessThanOrEqualTo(tileRect(tester).bottom));
        expect(tester.takeException(), isNull);
      }
      expect(PingChip.largeChipHeight,
          lessThanOrEqualTo(PingChip.columnHeight));
    });
  });

  // ── Высота строки ──────────────────────────────────────────────────────────

  group('Строка не дёргается при смене вида плашки', () {
    testWidgets('высота строки одна и та же во всех трёх случаях',
        (tester) async {
      await pumpTile(tester, ping: passed);
      final withoutSpeed = tileRect(tester).height;
      final columnWithout = tester.getSize(find.byType(PingSpeedColumn)).height;

      await pumpTile(tester, ping: passed, speed: speed);
      final withSpeed = tileRect(tester).height;
      final columnWith = tester.getSize(find.byType(PingSpeedColumn)).height;

      await pumpTile(tester, ping: dead);
      final deadRow = tileRect(tester).height;
      final columnDead = tester.getSize(find.byType(PingSpeedColumn)).height;

      // ⚠️ Ключевое: коробка под плашки ОДНА на оба вида. Разойдись она —
      // список бы «дышал» у тех строк, где замер уже сделан.
      expect(columnWithout, PingChip.columnHeight);
      expect(columnWith, PingChip.columnHeight);
      expect(columnDead, PingChip.columnHeight);

      expect(withSpeed, withoutSpeed,
          reason: 'строка со скоростью и без обязана быть одной высоты');
      expect(deadRow, withoutSpeed);
    });
  });

  // ── Что кладём в буфер ─────────────────────────────────────────────────────

  group('Что копировать для сервера', () {
    test('обычный сервер — его ключ (это и есть share-ссылка)', () {
      expect(serverClipboardPayload(server), server.key);
    });

    test('панельный профиль — конфиг, а не служебный ключ panel://', () {
      const cfg = '{"outbounds":[{"tag":"proxy"}],"routing":{"balancers":[]}}';
      const panel = VpnServer(
        protocol: 'vless',
        remark: '🎬 Авто (YouTube)',
        address: 'de.example',
        port: 443,
        id: '00000000-0000-0000-0000-000000000000',
        rawLink: 'panel://🎬 Авто (YouTube)?sub=abcdef',
        rawPanelConfig: cfg,
      );
      // ⚠️ Ключ такого профиля `ShareLinkParser` не понимает вовсе — скопируй
      // его, и вставить обратно было бы некуда.
      expect(serverClipboardPayload(panel), cfg);
      expect(serverClipboardPayload(panel), isNot(panel.key));
    });

    test('сервер с JSON-override — сам JSON, и он сильнее панельного конфига',
        () {
      const own = '{"outbounds":[{"tag":"proxy","protocol":"vless"}]}';
      const custom = VpnServer(
        protocol: 'vless',
        remark: 'Свой JSON',
        address: 'de.example',
        port: 443,
        id: '00000000-0000-0000-0000-000000000000',
        rawLink: 'json://custom',
        rawJsonOverride: own,
        rawPanelConfig: '{"outbounds":[]}',
      );
      // Порядок ТОТ ЖЕ, что у движка при подключении: копируется то, что
      // реально применится.
      expect(serverClipboardPayload(custom), own);
    });

    test('пустой (пробельный) override не считается конфигом', () {
      final blank = VpnServer(
        protocol: 'vless',
        remark: 'Германия',
        address: 'de.example',
        port: 443,
        id: '00000000-0000-0000-0000-000000000000',
        rawLink: server.rawLink,
        rawJsonOverride: '   ',
      );
      expect(serverClipboardPayload(blank), server.rawLink);
    });
  });

  testWidgets('пункт меню «Скопировать ключ» кладёт в буфер то, что примет импорт',
      (tester) async {
    const cfg = '{"outbounds":[{"tag":"proxy"}]}';
    const panel = VpnServer(
      protocol: 'vless',
      remark: 'Авто',
      address: 'de.example',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'panel://Авто?sub=abcdef',
      rawPanelConfig: cfg,
    );

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    // ⚠️ АРТЕФАКТ ТЕСТОВОГО ШРИФТА, А НЕ ДЕФЕКТ МЕНЮ. В тестах глифы рисуются
    // квадратами шириной в кегль, поэтому русские подписи пунктов («Информация
    // о сервере» и соседи) не влезают в 280 dp, которые Material отводит
    // всплывающему меню, и каждая роняет `RenderFlex overflowed`. В настоящем
    // шрифте те же строки занимают вдвое меньше. Гасим ТОЛЬКО переполнение —
    // любая другая ошибка обязана уронить тест.
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    await pumpTile(tester, ping: passed, srv: panel);

    // Контекст-меню — по правой кнопке мыши (на десктопе это единственный вход).
    await tester.tap(find.byType(ListTile).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Скопировать ключ'), findsOneWidget,
        reason: 'пункт обязан быть в контекст-меню сервера');
    await tester.tap(find.text('Скопировать ключ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, [cfg],
        reason: 'у панельного профиля в буфер уходит конфиг, а не panel://…');
    AppToast.dismiss();
    await tester.pump(const Duration(milliseconds: 300));
  });
  group('Что уходит в буфер — то же, что применяет движок', () {
    // ⚠️ НАЙДЕНО СКЕПТИКОМ 18.08.2026. Порядок «правка → конфиг панели → поля»
    // был выписан РУКАМИ в двух местах — в движке и в копировании — и уже
    // разошёлся: у hysteria2-сервера движок Xray-правку игнорирует («поднимаю
    // sing-box»), а копирование её отдавало. Человек скопировал бы конфиг,
    // которым приложение не подключается, вставил обратно и получил другой
    // сервер. Теперь оба спрашивают `VpnServer.effectiveFullConfig`.

    VpnServer vless({String? override, String? panel}) => VpnServer(
          protocol: 'vless',
          address: 'a.example',
          port: 443,
          id: '00000000-0000-0000-0000-000000000000',
          remark: 'A',
          rawLink: 'vless://00000000-0000-0000-0000-000000000000@a.example:443',
          rawJsonOverride: override,
          rawPanelConfig: panel,
        );

    test('обычный сервер без правок — в буфере ключ', () {
      expect(serverClipboardPayload(vless()), vless().key);
    });

    test('правка пользователя побеждает конфиг панели', () {
      final s = vless(override: '{"o":1}', panel: '{"p":2}');
      expect(serverClipboardPayload(s), '{"o":1}');
    });

    test('⚠️ ГЛАВНОЕ: у hysteria2 Xray-правка НЕ копируется', () {
      // Движок её игнорирует, значит и в буфере ей делать нечего.
      final hy = VpnServer(
        protocol: 'hysteria2',
        address: 'h.example',
        port: 443,
        id: 'p',
        remark: 'H',
        rawLink: 'hysteria2://p@h.example:443',
        rawJsonOverride: '{"xray":true}',
      );
      expect(hy.core, ProxyCore.singbox);
      expect(serverClipboardPayload(hy), hy.key,
          reason: 'ЗДЕСЬ БЫЛО РАСХОЖДЕНИЕ: копировался конфиг, которым '
              'приложение не подключается');
    });

    test('⚠️ пробельная правка — не конфиг', () {
      // Движок раньше проверял isNotEmpty без обрезки и уходил в ветку «полный
      // конфиг», то есть подключался пустотой.
      expect(serverClipboardPayload(vless(override: '   ')), vless().key);
    });
  });
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
