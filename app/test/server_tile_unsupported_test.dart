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
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// СТРОКА НЕПОДДЕРЖИВАЕМОГО СЕРВЕРА — СЕРАЯ, С ПОЯСНЕНИЕМ, БЕЗ ПИНГА/АВТОНАСТРОЙКИ.
///
/// Решение владельца 25.09.2026: сервер с маской, которую клиент не умеет
/// собрать (`VpnServer.isUnsupported`), не выбрасывается из подписки — иначе
/// выглядит как «подписка потеряла сервер». Вместо этого строка гаснет
/// (`Opacity`) и получает «!» со своим текстом; пункты меню, которые требуют
/// живого подключения (пинг/скорость/автонастройка), скрыты.
void main() {
  late Directory tmp;
  late AppState state;
  late ProbeController probe;
  late SettingsController settings;
  late AutoConfigController autoCfg;

  const unsupported = VpnServer(
    protocol: 'hysteria2',
    remark: 'Unsupported Hy2',
    address: '203.0.113.20',
    port: 443,
    id: 'fake-auth',
    network: 'quic',
    security: 'tls',
    rawLink: 'hysteria2://fake-auth@203.0.113.20:443'
        '?unsupported=hy2_mask%3Agecko#Unsupported%20Hy2',
    unsupportedReason: 'hy2_mask:gecko',
  );

  const supported = VpnServer(
    protocol: 'vless',
    remark: 'Германия',
    address: 'de.example',
    port: 443,
    id: '00000000-0000-0000-0000-000000000000',
    rawLink: 'vless://00000000-0000-0000-0000-000000000000@de.example:443'
        '?type=tcp&security=none#Германия',
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_tile_unsupported_');
    AppPaths.overrideRoot(tmp);
    state = AppState(engine: _FakeEngine());
    probe = ProbeController();
    settings = SettingsController();
    autoCfg = AutoConfigController();
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpTile(WidgetTester tester, VpnServer server) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
            ServerTile(server: server, selected: false, onTap: () {}),
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  // Тесты бегут на десктопном хосте (`Platform.isAndroid/isIOS` == false),
  // поэтому `ServerTile._isTouchLayout` даёт `touch == false` и долгое
  // нажатие ничего не открывает — на десктопе меню только по ПКМ
  // (`onSecondaryTapDown`). Эмулируем именно её.
  //
  // ⚠️ Кликаем у ЛЕВОГО края строки, не по центру: `showMenu` строит попап
  // вправо от точки клика и ограничивает его ширину оставшимся местом до
  // края экрана. Плитка растянута на весь `ListView` (1000 px), и клик по
  // центру (500 px) оставляет меню лишь половину ширины — самый длинный
  // пункт («Умный подбор параметров») не помещается, и `RenderFlex`
  // переполняется ошибкой, роняющей тест ДО любого `expect`.
  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final topLeft = tester.getTopLeft(finder);
    final gesture = await tester.startGesture(
      topLeft + const Offset(20, 10),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
  }

  testWidgets('неподдерживаемый сервер — строка приглушена и есть «!»',
      (tester) async {
    await pumpTile(tester, unsupported);
    expect(find.byType(Opacity), findsWidgets);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('«!» называет причину человеческим текстом', (tester) async {
    await pumpTile(tester, unsupported);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Маскировка «gecko» пока не поддерживается клиентом'),
        findsOneWidget);
  });

  testWidgets('обычный сервер — без приглушения и без «!»', (tester) async {
    await pumpTile(tester, supported);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('меню неподдерживаемого сервера — без пинга/скорости/автонастройки',
      (tester) async {
    await pumpTile(tester, unsupported);
    await rightClick(tester, find.byType(ServerTile));
    await tester.pumpAndSettle();

    expect(find.text('Пинговать'), findsNothing);
    expect(find.text('Измерить скорость'), findsNothing);
    expect(find.text('Умный подбор параметров'), findsNothing);
    // Остальные пункты меню остаются — сервер можно закрепить/удалить/
    // посмотреть JSON, просто не подключиться и не проверить.
    expect(find.text('Информация о сервере'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('меню обычного сервера — пинг/скорость/автонастройка на месте',
      (tester) async {
    await pumpTile(tester, supported);
    await rightClick(tester, find.byType(ServerTile));
    await tester.pumpAndSettle();

    expect(find.text('Пинговать'), findsOneWidget);
    expect(find.text('Измерить скорость'), findsOneWidget);
    expect(find.text('Умный подбор параметров'), findsOneWidget);
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
