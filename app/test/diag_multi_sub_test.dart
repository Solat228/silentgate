// Диагностика мульти-подписок: импорт двух ссылок, переключение, перезапуск.
// VPN не поднимается. Запуск с изолированным APPDATA:
//   $env:APPDATA="<temp>\isolated"; flutter test --run-skipped test/diag_multi_sub_test.dart
@Tags(['diag'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

class _FakeEngine implements VpnEngine {
  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}
  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

  @override
  Future<void> adoptRunningTunnel() async {}

  /// Диагностический движок сессий не ведёт — восстанавливать нечего.
  @override
  Future<void> armAdoptedSession(
      List<VpnServer> servers, ConnectionOptions options) async {}

  /// Диагностический движок в шторку не пишет.
  @override
  set subscriptionTitle(String title) {}

  @override
  set subscriptionLogoPath(String path) {}
  @override
  set compactNotification(bool compact) {}

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();
  @override
  VpnStatus get status => const VpnStatus.disconnected();
  @override
  int get httpProxyPort => 10809;
  @override
  Future<void> connect(VpnServer server,
          {ConnectionOptions options = const ConnectionOptions()}) async =>
      throw StateError('VPN в диагностике не поднимается');
  @override
  Future<void> connectBalancer(List<VpnServer> servers,
          {ConnectionOptions options = const ConnectionOptions()}) async =>
      throw StateError('VPN в диагностике не поднимается');
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> onNetworkChanged() async {}
  @override
  set fallbackServers(List<VpnServer> servers) {}

  @override
  set bypassCandidates(List<VpnServer> servers) {}

  @override
  set knownServerDomains(List<String> domains) {}
  @override
  Future<void> dispose() async {}
}

/// Две РАЗНЫЕ ссылки: рабочая и старая (истёкшая) — состав у них различается.
/// Секреты не коммитим — передаём через окружение:
///   flutter test --run-skipped --dart-define=SUB_A=… --dart-define=SUB_B=…
const _subA = String.fromEnvironment('SUB_A',
    defaultValue: 'https://sub.example.com/sub/REPLACE_ME_A');
const _subB = String.fromEnvironment('SUB_B',
    defaultValue: 'https://sub.example.com/sub/REPLACE_ME_B');

void main() {
  test('две подписки: импорт, переключение, перезапуск', () async {
    final dir = (await AppPaths.supportDir()).path;
    expect(dir.toLowerCase().contains('scratchpad'), isTrue,
        reason: 'APPDATA не изолирован — отказываюсь писать в $dir');

    final app = AppState(engine: _FakeEngine());
    await app.init();

    await app.importSource(_subA);
    expect(app.error, isNull);
    final countA = app.servers.length;
    final idA = app.activeSubscriptionId;

    await app.importSource(_subB);
    expect(app.error, isNull);
    final countB = app.servers.length;
    final idB = app.activeSubscriptionId;

    // ignore: avoid_print
    print('подписок: ${app.subscriptions.length}; A=$countA серверов, B=$countB');
    expect(app.subscriptions.length, 2,
        reason: 'вторая подписка должна добавиться, а не затереть первую');
    expect(idA, isNot(idB));

    // Переключение обратно на первую.
    await app.switchSubscription(idA!);
    // ignore: avoid_print
    print('после переключения на A: ${app.servers.length} серверов, '
        'активная=${app.activeSubscriptionId}');
    expect(app.activeSubscriptionId, idA);

    // Перезапуск: обе подписки и активная должны сохраниться.
    final again = AppState(engine: _FakeEngine());
    await again.init();
    // ignore: avoid_print
    print('после перезапуска: подписок=${again.subscriptions.length}, '
        'активная=${again.activeSubscriptionId}, серверов=${again.servers.length}');
    expect(again.subscriptions.length, 2);
    expect(again.activeSubscriptionId, idA);
    expect(again.servers, isNotEmpty);

    // Удаление активной — переключаемся на оставшуюся, а не в пустоту.
    await again.deleteSubscription();
    // ignore: avoid_print
    print('после удаления активной: подписок=${again.subscriptions.length}, '
        'активная=${again.activeSubscriptionId}');
    expect(again.subscriptions.length, 1);
    expect(again.activeSubscriptionId, idB);
    expect(again.subscriptionUrl, _subB);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
