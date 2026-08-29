import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// ЗАДАЧА ПЛАНИРОВЩИКА ЧИНИТСЯ САМА — А НЕ НАДОЕДАЕТ.
///
/// Владелец 29.08.2026: «Это разве не работа приложения фиксить это?» —
/// устаревшая задача `SilentGateTun` до этой правки только писала строку в
/// журнал и молча уходила в запасной путь (окно UAC на КАЖДОМ подключении).
/// Решение: показать заметку с кнопкой один раз за сессию, а не спрашивать
/// заново при каждом подключении, пока человек не перезапустит приложение.
///
/// Тест проверяет РЕШЕНИЕ движка (эмитит ли он `EngineNoticeKind
/// .staleScheduledTask` и сколько раз), а не реальный `schtasks`/UAC — тем же
/// приёмом, что и `windows_session_guards_test.dart`.
class _FakeStaleTunRouter implements TunRouter, StaleScheduledTaskReporter {
  /// Что вернёт [lastStartHitStaleScheduledTask] на СЛЕДУЮЩЕМ чтении —
  /// имитирует то, что реально решает `SingboxRouterWindows._startOnce`.
  bool stale = false;

  @override
  bool get lastStartHitStaleScheduledTask => stale;

  @override
  Future<void> start(SplitTunnelConfig split,
      {required int xraySocksPort,
      required TunOptions options,
      void Function(String message)? onProgress,
      bool Function()? abort,
      List<Map<String, dynamic>> exitOutbounds = const [],
      String xraySocksUser = '',
      String xraySocksPassword = '',
      List<String> apiExitServerKeys = const [],
      List<String> apiOnlyExitKeys = const [],
      String apiToken = ''}) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  late Directory tmp;
  late _FakeStaleTunRouter router;
  late WindowsEngine engine;

  final servers = [
    const VpnServer(
      protocol: 'vless',
      remark: 'a',
      address: '203.0.113.10',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@203.0.113.10:443#a',
    ),
  ];

  ConnectionOptions options() => ConnectionOptions(
        settings: AppSettings.defaults.copyWith(
          captureMode: CaptureMode.tun,
          tunWatchdogSeconds: 0,
          splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
        ),
      );

  Future<bool> raise({required int gen}) => engine.raiseTun(
        options: options(),
        servers: servers,
        apiKeys: const [],
        aborted: () => false,
        gen: gen,
      );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_stale_task_notice_');
    AppPaths.overrideRoot(tmp);
    router = _FakeStaleTunRouter();
    engine = WindowsEngine(tunRouter: router, recoverSystemProxy: false);
    engine.adapterDnsForTest = () => const ['192.168.1.1'];
    engine.dnsReachableForTest = (_) async => true;
  });

  tearDown(() async {
    await engine.dispose();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('задача исправна — заметки нет вовсе', () async {
    router.stale = false;
    final notices = <EngineNotice>[];
    final sub = engine.notices.listen(notices.add);

    expect(await raise(gen: 1), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(notices.where((n) => n.kind == EngineNoticeKind.staleScheduledTask),
        isEmpty,
        reason: 'исправная задача — предлагать нечего');
    await sub.cancel();
  });

  test('⚠️ ГЛАВНОЕ: задача устарела — заметка ровно ОДНА за сессию', () async {
    router.stale = true;
    final notices = <EngineNotice>[];
    final sub = engine.notices.listen(notices.add);

    // Три подключения подряд с одной и той же устаревшей задачей — ровно то,
    // что раньше давало окно UAC (и теперь давало бы заметку) на КАЖДОМ из них.
    expect(await raise(gen: 1), isTrue);
    expect(await raise(gen: 2), isTrue);
    expect(await raise(gen: 3), isTrue);
    await Future<void>.delayed(Duration.zero);

    final stale =
        notices.where((n) => n.kind == EngineNoticeKind.staleScheduledTask);
    expect(stale, hasLength(1),
        reason: 'три подключения подряд не должны спросить трижды — '
            'назойливость хуже исходной проблемы (решение владельца)');
    await sub.cancel();
  });
}
