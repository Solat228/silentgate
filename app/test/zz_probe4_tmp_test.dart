// ВРЕМЕННЫЙ: почему черновик находки даёт 8, а мой пробник — 1.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// ТОЧНАЯ копия класса из черновика находки.
class _Draft extends VpnEngineBase {
  int startCalls = 0;
  bool succeedOnStart = true;
  bool throwOnStart = false;
  Duration teardownDelay = Duration.zero;

  @override
  Future<void> startSession() async {
    startCalls++;
    final gen = newGeneration();
    if (throwOnStart) throw StateError('ядро не стартовало');
    if (!succeedOnStart) return;
    if (isStale(gen)) return;
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    if (teardownDelay > Duration.zero) await Future.delayed(teardownDelay);
  }

  @override
  Future<void> platformCleanup() async {}
}

/// Мой вариант: те же поля + счётчики.
class _Mine extends VpnEngineBase {
  int startCalls = 0;
  int teardownCalls = 0;
  bool succeedOnStart = false;
  Duration teardownDelay = Duration.zero;

  @override
  Future<void> startSession() async {
    startCalls++;
    final gen = newGeneration();
    if (!succeedOnStart) return;
    if (isStale(gen)) return;
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    teardownCalls++;
    if (teardownDelay > Duration.zero) await Future.delayed(teardownDelay);
  }

  @override
  Future<void> platformCleanup() async {}
}

VpnServer _server(String name) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: '$name.example.com',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@$name.example.com:443#$name',
    );

ConnectionOptions get _opts => ConnectionOptions(
    settings: AppSettings.defaults.copyWith(autoReconnect: true));

void main() {
  test('D-1. черновик, delay=20мс, 8 событий', () async {
    final e = _Draft()
      ..succeedOnStart = false
      ..teardownDelay = const Duration(milliseconds: 20);
    await e.connectWith('{}', _opts, [_server('a')]);
    final futures = [for (var i = 0; i < 8; i++) e.scheduleRetry('обрыв $i')];
    print('D-1 синхронно после цикла: attempt=${e.attemptsUsed}');
    final res = await Future.wait(futures);
    print('D-1 итог: attemptsUsed=${e.attemptsUsed}, true=${res.where((r) => r).length}/8');
    e.dropPendingRetry();
  });

  test('D-2. мой, delay=20мс, 8 событий', () async {
    final e = _Mine()..teardownDelay = const Duration(milliseconds: 20);
    await e.connectWith('{}', _opts, [_server('a')]);
    final futures = [for (var i = 0; i < 8; i++) e.scheduleRetry('обрыв $i')];
    print('D-2 синхронно после цикла: attempt=${e.attemptsUsed}');
    final res = await Future.wait(futures);
    print('D-2 итог: attemptsUsed=${e.attemptsUsed}, teardownCalls=${e.teardownCalls}, '
        'true=${res.where((r) => r).length}/8');
    e.dropPendingRetry();
  });

  test('D-3. черновик, delay=0, 8 событий', () async {
    final e = _Draft()..succeedOnStart = false;
    await e.connectWith('{}', _opts, [_server('a')]);
    final futures = [for (var i = 0; i < 8; i++) e.scheduleRetry('обрыв $i')];
    print('D-3 синхронно после цикла: attempt=${e.attemptsUsed}');
    await Future.wait(futures);
    print('D-3 итог: attemptsUsed=${e.attemptsUsed}');
    e.dropPendingRetry();
  });

  test('D-4. семантика: продолжение после await у sync-async функции', () async {
    var post = 0;
    Future<void> inner() async {}
    Future<void> outer() async {
      await inner();
      post++;
    }
    outer();
    print('D-4: post сразу после вызова = $post (0 → await суспендит)');
    await Future.delayed(Duration.zero);
    print('D-4: post после микрозадач = $post');
  });
}
