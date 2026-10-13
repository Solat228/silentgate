import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/network_loss_watch.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// ОБРЫВ СЕТИ НА ПК — ЗА ~15 СЕКУНД, А НЕ ЗА 45–55.
///
/// Владелец 13.10.2026 выбрал «около 15 секунд». Сквозная проба канала идёт
/// раз в 45 секунд, и частить ею дорого (соединение с сервером на каждую).
/// Поэтому прямой интернет проверяется раз в 5 секунд, и его пропажа будит
/// проверку канала сразу.

const _server = VpnServer(
  protocol: 'vless',
  remark: 'a',
  address: '203.0.113.10',
  port: 443,
  id: '00000000-0000-0000-0000-000000000000',
  rawLink: 'vless://x@203.0.113.10:443#a',
);

Future<void> _settle([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Проба канала: обычный такт — раз в час (в тесте не наступает), проба вне
/// очереди отвечает тем, что лежит в движке.
class _Probe extends TunnelHealth {
  _Probe(this.engine)
      : super(proxyPort: 1, interval: const Duration(hours: 1));
  final _Engine engine;

  @override
  Future<bool> probeOnce() async => engine.tunnelAlive;

  @override
  Future<bool> probeNow() async {
    engine.urgentProbes++;
    return engine.tunnelAlive;
  }
}

class _Engine extends VpnEngineBase {
  _Engine({this.withWatch = true}) {
    _sub = notices.listen((n) => seen.add(n.kind));
  }

  final bool withWatch;
  bool tunnelAlive = true;
  bool directUp = true;
  int urgentProbes = 0;
  int teardowns = 0;
  NetworkLossWatch? watch;
  final seen = <EngineNoticeKind>[];
  late final StreamSubscription<EngineNotice> _sub;

  @override
  Future<bool?> directInternetAvailable() async => directUp;

  @override
  NetworkLossWatch? createNetworkLossWatch() {
    if (!withWatch) return null;
    return watch = NetworkLossWatch(
      check: () async => directUp,
      every: const Duration(milliseconds: 5),
    );
  }

  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) =>
      _Probe(this);

  @override
  Future<void> startSession() async {
    final gen = newGeneration();
    if (isStale(gen)) return;
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async => teardowns++;

  @override
  Future<void> platformCleanup() async {}

  Future<void> close() async {
    stopHealthWatch();
    await disconnect();
    await _sub.cancel();
  }
}

Future<_Engine> _connected({bool withWatch = true}) async {
  final e = _Engine(withWatch: withWatch);
  await e.connectWith(
      '{}',
      ConnectionOptions(
          settings: AppSettings.defaults.copyWith(
        captureMode: CaptureMode.tun,
        autoReconnect: true,
        splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
        tunWatchdogSeconds: 0,
      )),
      [_server]);
  e.startHealthWatch(() => false);
  return e;
}

void main() {
  group('NetworkLossWatch', () {
    NetworkLossWatch make(List<bool> answers, {int misses = 2}) {
      var i = 0;
      return NetworkLossWatch(
        check: () async => answers[i < answers.length ? i++ : answers.length - 1],
        every: const Duration(milliseconds: 2),
        missesToAct: misses,
      );
    }

    test('интернет пропал после успеха: один сигнал на эпизод', () async {
      final w = make([true, false, false, false, false, false]);
      var losses = 0;
      w.start(onLoss: () => losses++);
      await _settle(60);
      w.stop();
      expect(losses, 1, reason: 'один эпизод — один сигнал, без повторов');
    });

    test('⚠️ прямой путь закрыт с самого начала — сигнала нет', () async {
      // Провайдер закрыл 1.1.1.1 или режим белых списков: проверка не
      // проходит никогда, и будить сторожа каждые 10 секунд незачем.
      final w = make([false]);
      var losses = 0;
      w.start(onLoss: () => losses++);
      await _settle(40);
      w.stop();
      expect(losses, 0);
      expect(w.seenUp, isFalse);
    });

    test('одиночный промах — не сигнал', () async {
      final w = make([true, false, true, false, true, true]);
      var losses = 0;
      w.start(onLoss: () => losses++);
      await _settle(40);
      w.stop();
      expect(losses, 0);
    });

    test('сеть вернулась и пропала снова — второй сигнал', () async {
      final w = make([true, false, false, true, false, false, false]);
      var losses = 0;
      w.start(onLoss: () => losses++);
      await _settle(60);
      w.stop();
      expect(losses, 2);
    });

    test('stop останавливает проверки', () async {
      var checks = 0;
      final w = NetworkLossWatch(
          check: () async {
            checks++;
            return true;
          },
          every: const Duration(milliseconds: 2));
      w.start(onLoss: () {});
      await _settle(20);
      w.stop();
      final after = checks;
      await _settle(20);
      expect(checks, after);
      expect(w.isRunning, isFalse);
    });

    test('по умолчанию — раз в 5 секунд, сигнал после двух промахов', () {
      final w = NetworkLossWatch();
      expect(w.every, const Duration(seconds: 5));
      expect(w.missesToAct, 2);
    });
  });

  group('Движок: пропажа прямого интернета будит проверку канала', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_loss_');
      AppPaths.overrideRoot(tmp);
    });
    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('⚠️ сети нет вовсе — «Нет интернета» сразу, без переподключения',
        () async {
      final e = await _connected();
      await _settle(30);
      e.tunnelAlive = false;
      e.directUp = false;
      await _settle(80);
      expect(e.urgentProbes, greaterThanOrEqualTo(1),
          reason: 'канал не проверили вне очереди');
      expect(e.waitingForNetwork, isTrue,
          reason: 'сторож ждал бы своей пробы до 45 секунд');
      expect(e.status.state, VpnConnectionState.connected);
      expect(e.teardowns, 0, reason: 'без сети переподключение бесполезно');
      expect(e.seen, contains(EngineNoticeKind.noInternet));
      await e.close();
    });

    test('прямой путь закрыт, а канал отвечает — соединение не трогаем',
        () async {
      final e = await _connected();
      await _settle(30);
      e.directUp = false;
      await _settle(80);
      expect(e.urgentProbes, greaterThanOrEqualTo(1));
      expect(e.waitingForNetwork, isFalse);
      expect(e.teardowns, 0);
      expect(e.seen, isNot(contains(EngineNoticeKind.noInternet)));
      await e.close();
    });

    test('платформа без частой проверки (Android) — прежнее поведение',
        () async {
      final e = await _connected(withWatch: false);
      await _settle(30);
      e.tunnelAlive = false;
      e.directUp = false;
      await _settle(80);
      expect(e.urgentProbes, 0);
      expect(e.waitingForNetwork, isFalse);
      await e.close();
    });

    test('остановка сторожа останавливает и частую проверку', () async {
      final e = await _connected();
      await _settle(20);
      final w = e.watch!;
      expect(w.isRunning, isTrue);
      e.stopHealthWatch();
      expect(w.isRunning, isFalse);
      await e.close();
    });

    test('отключение пользователем — сигнал не трогает сессию', () async {
      final e = await _connected();
      await _settle(30);
      await e.disconnect();
      e.tunnelAlive = false;
      e.directUp = false;
      await _settle(60);
      expect(e.urgentProbes, 0);
      expect(e.waitingForNetwork, isFalse);
      await e.close();
    });
  });
}
