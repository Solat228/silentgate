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
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Значок «сервер обновился» на карточке — источник: `AppState.updatedFieldsOf`
/// (сам диф считается в `SubscriptionSyncResult.diff`, здесь проверяется
/// только отрисовка). Метка ставится по `server.key` ПОСЛЕ обновления.
///
/// ⚠️ НЕ ПУТАТЬ СО СВОИМИ СОСЕДЯМИ. В строке уже есть «!» у панельного профиля
/// и у непригодного сервера — оба используют `Icons.info_outline`. Значок
/// «обновлён» обязан иметь СВОЮ иконку, иначе три разных смысла на одной
/// строке слипаются в одну неотличимую пиктограмму.
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
    tmp = Directory.systemTemp.createTempSync('sg_tile_updated_');
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

  Future<void> pumpTile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

  testWidgets('сервер без метки — значка «обновлён» нет', (tester) async {
    await pumpTile(tester);
    expect(find.byIcon(Icons.published_with_changes), findsNothing);
  });

  testWidgets('сервер с меткой — значок появился и подсказка называет поля',
      (tester) async {
    state.debugSetUpdatedFields({
      server.key: ['address', 'shortId'],
    });
    await pumpTile(tester);

    final icon = find.byIcon(Icons.published_with_changes);
    expect(icon, findsOneWidget);

    // Подсказка — человеческими словами, а не сырыми именами полей.
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'При обновлении подписки изменилось: Адрес, Short ID (Reality)'),
        findsOneWidget);
    expect(find.textContaining('shortId'), findsNothing,
        reason: 'сырое имя поля не должно попасть в текст для человека');
  });

  testWidgets('пустой список полей — обобщённая фраза, а не пустая подсказка',
      (tester) async {
    // Пустой список — законный случай: сменилась только запись ссылки
    // (например, gRPC `serviceName=` → `path=`), поля совпали.
    state.debugSetUpdatedFields({server.key: const []});
    await pumpTile(tester);

    final icon = find.byIcon(Icons.published_with_changes);
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('При обновлении подписки обновилась запись сервера'),
        findsOneWidget);
  });

  testWidgets('значок «обновлён» отличим от «!» панели/непригодности',
      (tester) async {
    state.debugSetUpdatedFields({
      server.key: ['sni'],
    });
    await pumpTile(tester);

    expect(find.byIcon(Icons.published_with_changes), findsOneWidget);
    // Соседние «!» в этом тесте не показаны (сервер не панельный и годный) —
    // значит на строке ровно одна иконка-пояснение, и это не info_outline.
    expect(find.byIcon(Icons.info_outline), findsNothing);
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
