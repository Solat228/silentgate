import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// У ЗАМЕТКИ «НАСТРОЙКА ИЗМЕНЕНА — ПЕРЕПОДКЛЮЧИТЕСЬ» ЕСТЬ СРОК.
///
/// ⚠️ Просьба владельца от 28.08.2026. Плашка висела на главном экране
/// БЕССРОЧНО: снять её было некому — событие одноразовое, «настройку вернули
/// назад» приложению никто не сообщает, а человек, решивший применить
/// изменение позже, весь день смотрел на упрёк.
///
/// ⚠️ ИМЕННО СРОК, А НЕ ФЛАГ. Флагом это не лечится по той же причине, по
/// которой не лечилась пометка о заблокированном сайте: снимать флаг пришлось
/// бы кому-то, а этого «кого-то» не существует.
void main() {
  late Directory tmp;
  final realTtl = AppState.pendingRestartTtl;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_pending_restart_');
    AppPaths.overrideRoot(tmp);
    // Настоящий срок — минута; ждать её в прогоне значило бы не написать этот
    // тест вовсе (см. комментарий у `AppState.pendingRestartTtl`).
    AppState.pendingRestartTtl = const Duration(milliseconds: 120);
  });

  tearDown(() {
    AppState.pendingRestartTtl = realTtl;
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppState> connectedState(_FakeEngine engine) async {
    final app = AppState(engine: engine);
    await app.init();
    engine.emit(const VpnStatus(VpnConnectionState.connected));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(app.status.isConnected, isTrue);
    return app;
  }

  test('⚠️ ГЛАВНОЕ: заметка гаснет сама и сообщает об этом экрану', () async {
    final engine = _FakeEngine();
    final app = await connectedState(engine);
    var notified = 0;
    app.addListener(() => notified++);

    app.notePendingRestart('Настройка изменена');
    expect(app.pendingRestart, 'Настройка изменена');
    final afterNote = notified;

    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(app.pendingRestart, isNull,
        reason: 'плашка обязана уйти сама — снимать её больше некому');
    // ⚠️ Одного срока мало: экран читает `pendingRestart` при перерисовке, а
    // перерисовывать его без уведомления никто не станет — плашка провисела бы
    // до следующего чужого события.
    expect(notified, greaterThan(afterNote),
        reason: 'угасание обязано разбудить перерисовку');

    app.dispose();
  });

  test('до срока заметка на месте — гасим не сразу', () async {
    final engine = _FakeEngine();
    final app = await connectedState(engine);
    app.notePendingRestart('Настройка изменена');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(app.pendingRestart, isNotNull);
    app.dispose();
  });

  test('новая правка продлевает срок, а не наследует старый', () async {
    final engine = _FakeEngine();
    final app = await connectedState(engine);
    app.notePendingRestart('Первая');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    app.notePendingRestart('Вторая');
    // Прошло уже больше первого срока — но отсчёт пошёл заново.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(app.pendingRestart, 'Вторая');
    app.dispose();
  });

  test('снятая вручную заметка не воскресает по таймеру', () async {
    final engine = _FakeEngine();
    final app = await connectedState(engine);
    app.notePendingRestart('Настройка изменена');
    app.clearPendingRestart();
    expect(app.pendingRestart, isNull);
    var notified = 0;
    app.addListener(() => notified++);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(app.pendingRestart, isNull);
    expect(notified, 0,
        reason: 'снятый таймер не имеет права дёргать перерисовку');
    app.dispose();
  });

  test('⚠️ dispose снимает таймер: иначе он ударит в мёртвый объект', () async {
    // `notifyListeners()` у выброшенного ChangeNotifier бросает исключение, а
    // ловить его было бы некому: таймер живёт сам по себе.
    final engine = _FakeEngine();
    final app = await connectedState(engine);
    app.notePendingRestart('Настройка изменена');
    app.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    // Дошли сюда без исключения — таймер снят.
  });
}

class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = const VpnStatus.disconnected();

  void emit(VpnStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

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
  VpnStatus get status => _status;

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
