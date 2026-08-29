import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// УВЕДОМЛЕНИЕ О МЁРТВОМ ПУТИ ПРАВИЛА — ТАМ, ГДЕ ЧЕЛОВЕК ПРИ ПОДКЛЮЧЕНИИ.
///
/// ⚠️ ДО ЭТОЙ ПРАВКИ ФАКТ БЫЛ ВИДЕН ТОЛЬКО В ЖУРНАЛЕ И В СПИСКЕ ПРАВИЛ
/// (`DeadPathBadge`) — а на главном экране, где человек жмёт «Подключиться»,
/// не было ничего. Правило приложения «по полному пути» устаревает МОЛЧА,
/// когда программа обновляется и переезжает в папку с номером версии (случай
/// владельца — `claude.exe` в `…claude-code-2.1.238-win32-x64\…`).
///
/// ⚠️ Сопоставление ПО ИМЕНИ исправно (`CHANGELOG.md` #602) — тест это НЕ
/// перепроверяет, он стережёт условие показа заметки про путь.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sg_dead_rule_notice_'));
  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppState> stateWithServer() async {
    AppPaths.overrideRoot(tmp);
    final app = AppState(engine: _FakeEngine());
    await app.init();
    // Одиночная share-ссылка добавляется офлайн (см. `AppState.importSource`)
    // и делает сервер выбранным — без неё `toggleConnection` откажет ДО
    // проверки правил (`AppErrorCode.pickServerFirst`).
    await app.importSource('vless://11111111-2222-3333-4444-555555555555'
        '@127.0.0.1:443#test');
    expect(app.selectedServer, isNotNull);
    return app;
  }

  AppSettings settingsWithApp(AppRule rule) => AppSettings.defaults.copyWith(
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          apps: [rule],
        ),
      );

  test('есть мёртвый путь у включённого правила — заметка появляется',
      () async {
    final app = await stateWithServer();
    final deadExe = '${tmp.path}${Platform.pathSeparator}app-1.0-нет.exe';
    final settings = settingsWithApp(
        AppRule(deadExe, byName: false, action: AppAction.direct));

    await app.toggleConnection(settings);

    final notice = app.pendingNotice;
    expect(notice, isNotNull, reason: 'ЗДЕСЬ БЫЛА ТИШИНА: правило мёртвое, а '
        'на главном экране — ни слова');
    expect(notice!.kind, EngineNoticeKind.deadAppRule);
    expect(notice.detail, deadExe,
        reason: 'путь нужен целиком — по нему уводят «к этому правилу»');

    app.dispose();
  });

  test('файл живой — заметки нет', () async {
    final app = await stateWithServer();
    final alive = File('${tmp.path}${Platform.pathSeparator}живой.exe')
      ..writeAsStringSync('x');
    final settings = settingsWithApp(
        AppRule(alive.path, byName: false, action: AppAction.direct));

    await app.toggleConnection(settings);

    expect(app.pendingNotice, isNull,
        reason: 'живой файл — предупреждение было бы ложной тревогой');

    app.dispose();
  });

  test('правило выключено — заметки нет, хотя путь мёртв', () async {
    final app = await stateWithServer();
    final deadExe = '${tmp.path}${Platform.pathSeparator}выкл.exe';
    final settings = settingsWithApp(AppRule(deadExe,
        byName: false, action: AppAction.direct, enabled: false));

    await app.toggleConnection(settings);

    expect(app.pendingNotice, isNull,
        reason: 'выключенное правило и так не применяется — предупреждать не о чем');

    app.dispose();
  });

  test('⚠️ правило «по имени» с тем же мёртвым путём — заметки нет', () async {
    // Сопоставление по имени от пути не зависит (см. `AppRule.matches`) —
    // это и есть лечение, а не то, что нужно чинить снова.
    final app = await stateWithServer();
    final deadExe = '${tmp.path}${Platform.pathSeparator}по-имени.exe';
    final settings = settingsWithApp(
        AppRule(deadExe, byName: true, action: AppAction.direct));

    await app.toggleConnection(settings);

    expect(app.pendingNotice, isNull);

    app.dispose();
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
