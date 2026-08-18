// Живая проверка на реальной подписке: импорт → профили панели → ПИНГ через
// собственный balancer/burstObservatory профиля. VPN НЕ включается (движок-заглушка,
// системный прокси не трогается) — поднимается только проброс-харнесс Xray.
//
//   $env:APPDATA="<temp>\isolated"; flutter test --run-skipped test/diag_live_test.dart
@Tags(['diag'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';

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
  Future<void> disconnectKeepingCapture() async {}

  @override
  bool canKeepCaptureFor(AppSettings next) => false;
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

// Реальную ссылку подписки передаём через окружение (секрет не коммитим):
//   flutter test --run-skipped --dart-define=SUB_URL=https://<панель>/sub/<токен>
const _subUrl = String.fromEnvironment('SUB_URL',
    defaultValue: 'https://sub.example.com/sub/REPLACE_ME');

void main() {
  test('импорт реальной подписки, профили панели и пинг автовыбора', () async {
    final dir = (await AppPaths.supportDir()).path;
    expect(dir.toLowerCase().contains('scratchpad'), isTrue,
        reason: 'APPDATA не изолирован — отказываюсь писать в $dir');

    final app = AppState(engine: _FakeEngine());
    await app.init();
    await app.importSource(_subUrl);
    expect(app.error, isNull, reason: 'импорт не должен падать');

    final profiles = app.servers.where((s) => s.isPanelProfile).toList();
    final plain = app.servers.where((s) => !s.isPanelProfile).toList();
    // ignore: avoid_print
    print('серверов: ${app.servers.length} '
        '(профилей «Авто»: ${profiles.length}, обычных: ${plain.length})');
    // ignore: avoid_print
    print('сводка обновления: ${app.lastSync?.summary}');
    expect(profiles, isNotEmpty, reason: 'профили «Авто» не распознаны');

    // Профиль сохранён целиком: outbound'ов много, есть балансировщик.
    final p = profiles.first;
    final cfg = jsonDecode(p.rawPanelConfig!) as Map;
    // ignore: avoid_print
    print('${p.displayName}: outbound=${(cfg['outbounds'] as List).length}, '
        'balancers=${((cfg['routing'] as Map)['balancers'] as List).length}, '
        'burst=${cfg.containsKey('burstObservatory')}');
    expect((cfg['outbounds'] as List).length, greaterThan(2));

    // Перезапуск: полный конфиг должен пережить (на диске только ссылки).
    final again = AppState(engine: _FakeEngine());
    await again.init();
    final afterRestart = again.servers.where((s) => s.isPanelProfile).length;
    // ignore: avoid_print
    print('после перезапуска профилей: $afterRestart');
    expect(afterRestart, profiles.length);

    // ПИНГ профиля через его собственный balancer + burstObservatory.
    // Это и есть то, что раньше не работало из-за «левого» конфига.
    final probe = ProbeController();
    const settings = AppSettings(pingTimeoutMs: 8000);
    final target = again.servers.firstWhere((s) => s.isPanelProfile);
    await probe.pingOne(target, settings);
    final r = probe.resultFor(target);
    // ignore: avoid_print
    print('ПИНГ «${target.displayName}»: outcome=${r.outcome.name} '
        'latency=${r.latencyMs} proxyRtt=${r.proxyRttMs} '
        'reachable=${r.reachableViaProxy}');

    // ignore: avoid_print
    print('\n--- лог приложения ---\n${await AppLog.dump()}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
