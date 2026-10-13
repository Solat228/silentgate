import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// «НЕТ ИНТЕРНЕТА» — НЕ ОБРЫВ VPN.
///
/// Владелец 13.10.2026: выдернул кабель из роутера — трей остался
/// фиолетовым, а приложение молча крутило переподключения. Решение владельца:
/// после первого промаха проба каждые 5 с; нет ни VPN, ни прямого интернета —
/// «Нет интернета», красный трей, без бесполезных переподключений; вернулся —
/// «Связь восстановлена». И «без сильного спама уведомлениями».
///
/// Проба канала и проба прямого интернета подменены: настоящие ходят в сеть,
/// а сеть здесь — то, что тест выключает и включает.

const _server = VpnServer(
  protocol: 'vless',
  remark: 'a',
  address: '203.0.113.10',
  port: 443,
  id: '00000000-0000-0000-0000-000000000000',
  rawLink: 'vless://x@203.0.113.10:443#a',
);

AppSettings _settings({bool autoReconnect = true}) =>
    AppSettings.defaults.copyWith(
      captureMode: CaptureMode.tun,
      autoReconnect: autoReconnect,
      seamlessNetworkChange: true,
      splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
      tunWatchdogSeconds: 0,
      tunnelDnsForAll: false,
    );

/// Проба канала: отвечает то, что сейчас лежит в движке.
class _Probe extends TunnelHealth {
  _Probe(this.engine)
      : super(
          proxyPort: 1,
          interval: const Duration(milliseconds: 5),
          failuresToDeclareDown: 1,
        );
  final _Engine engine;

  @override
  Future<bool> probeOnce() async {
    engine.tunnelProbes++;
    return engine.tunnelAlive;
  }
}

class _Engine extends VpnEngineBase {
  bool tunnelAlive = true;
  bool? direct = true;
  int tunnelProbes = 0;
  int directChecks = 0;
  int starts = 0;
  int teardowns = 0;
  final seen = <EngineNoticeKind>[];
  late final StreamSubscription<EngineNotice> _sub;

  _Engine() {
    _sub = notices.listen((n) => seen.add(n.kind));
  }

  @override
  Future<bool?> directInternetAvailable() async {
    directChecks++;
    return direct;
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
    starts++;
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

/// Пустить события потоков и таймеры сторожа (интервал 5 мс).
Future<void> _settle([int ms = 60]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<_Engine> _connected({bool autoReconnect = true}) async {
  final e = _Engine();
  await e.connectWith('{}',
      ConnectionOptions(settings: _settings(autoReconnect: autoReconnect)),
      [_server]);
  e.debugSetConnectedAt(
      DateTime.now().subtract(VpnEngineBase.networkGrace * 2));
  return e;
}

/// Довести движок до «ждём сеть»: канал и прямой интернет молчат.
Future<void> _goOffline(_Engine e) async {
  e.tunnelAlive = false;
  e.direct = false;
  e.startHealthWatch(() => false);
  await _settle();
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_offline_');
    AppPaths.overrideRoot(tmp);
  });
  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('TunnelHealth', () {
    test('firstSuccess: первый ответивший, не дожидаясь медленных', () async {
      final slow = Completer<bool>();
      final sw = Stopwatch()..start();
      final got = await TunnelHealth.firstSuccess(
        ['slow', 'dead', 'ok'],
        (u) => switch (u) {
          'slow' => slow.future,
          'dead' => Future.value(false),
          _ => Future.delayed(const Duration(milliseconds: 10), () => true),
        },
      );
      expect(got, 'ok');
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'ждали медленную мишень, хотя ответ уже был');
      slow.complete(false);
    });

    test('firstSuccess: не ответил никто — null', () async {
      expect(
          await TunnelHealth.firstSuccess(
              ['a', 'b'], (_) => Future.value(false)),
          isNull);
      expect(await TunnelHealth.firstSuccess([], (_) async => true), isNull);
    });

    test('после промаха проба идёт чаще: приговор за доли обычного интервала',
        () async {
      var probes = 0;
      final h = _CountingProbe(() {
        probes++;
        return false;
      },
          interval: const Duration(milliseconds: 300),
          suspectInterval: const Duration(milliseconds: 10));
      final down = Completer<void>();
      final sw = Stopwatch()..start();
      h.start(onDown: () async => down.complete());
      await down.future.timeout(const Duration(seconds: 3));
      expect(probes, 3);
      // Без частых проб приговор пришёл бы через 3 × 300 мс.
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 650)));
    });

    test('пауза «под подозрением» не длиннее обычной', () {
      final h = TunnelHealth(
          proxyPort: 1,
          interval: const Duration(seconds: 2),
          suspectInterval: const Duration(seconds: 30));
      expect(h.suspectInterval, const Duration(seconds: 2));
    });

    test('markSuspect ставит один промах и не сбрасывает накопленные', () {
      final h = TunnelHealth(proxyPort: 1);
      expect(h.consecutiveFailures, 0);
      h.markSuspect();
      expect(h.consecutiveFailures, 1);
    });
  });

  group('уведомления', () {
    test('нет интернета — проблема, возврат — системное, но не проблема', () {
      const lost = EngineNotice(EngineNoticeKind.noInternet, 'x');
      const back = EngineNotice(EngineNoticeKind.internetRestored, 'x');
      const recovered = EngineNotice(EngineNoticeKind.recovered, 'x');
      expect(lost.isProblem, isTrue);
      expect(lost.needsSystemNotice, isTrue);
      expect(back.isProblem, isFalse);
      expect(back.needsSystemNotice, isTrue);
      expect(recovered.needsSystemNotice, isFalse,
          reason: 'прежнее поведение заметок трогать не нужно');
    });

    test('VpnStatus: признак «нет сети» по умолчанию снят', () {
      expect(const VpnStatus(VpnConnectionState.connected).offline, isFalse);
      expect(const VpnStatus.disconnected().offline, isFalse);
    });
  });

  group('движок', () {
    test('канал и прямой интернет молчат — ждём сеть, не переподключаемся',
        () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);

      expect(e.waitingForNetwork, isTrue);
      expect(e.status.state, VpnConnectionState.connected);
      expect(e.status.offline, isTrue);
      expect(e.status.text, isA<StatusNoInternet>());
      expect(e.teardowns, 0, reason: 'ядро без сети гасить незачем');
      expect(e.starts, 1, reason: 'переподключение без сети бесполезно');
      expect(e.seen, [EngineNoticeKind.noInternet]);
    });

    test('статус от платформы во время ожидания не снимает признак', () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);
      e.setStatus(VpnConnectionState.connected);
      expect(e.status.offline, isTrue,
          reason: 'трей перекрасился бы обратно при живом ожидании');
    });

    test('сеть вернулась и канал ожил — без переподключения, «восстановлена»',
        () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);

      e.tunnelAlive = true;
      await e.checkNetworkWhileOffline();
      await _settle(0);

      expect(e.waitingForNetwork, isFalse);
      expect(e.status.offline, isFalse);
      expect(e.teardowns, 0);
      expect(e.starts, 1);
      expect(e.healthWatch, isNotNull, reason: 'сторож обязан вернуться');
      expect(e.seen,
          [EngineNoticeKind.noInternet, EngineNoticeKind.internetRestored]);
    });

    test('сеть есть, канал молчит — переподключение без «Связь оборвалась»',
        () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);

      e.direct = true;
      await e.checkNetworkWhileOffline();
      expect(e.waitingForNetwork, isFalse);
      expect(e.teardowns, isPositive);
      expect(e.status.state, VpnConnectionState.connecting);

      // Повтор поднимает туннель.
      e.tunnelAlive = true;
      await _settle(1200);
      expect(e.starts, 2);
      expect(e.seen,
          [EngineNoticeKind.noInternet, EngineNoticeKind.internetRestored],
          reason: 'о пропаже сказали «Нет интернета» — и ответ должен быть '
              'про сеть, без лишних «оборвалась» и «соединение восстановлено»');
    });

    test('сеть ещё не вернулась — шаг ожидания ничего не трогает', () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);
      await e.checkNetworkWhileOffline();
      await e.checkNetworkWhileOffline();
      expect(e.waitingForNetwork, isTrue);
      expect(e.teardowns, 0);
      expect(e.seen, [EngineNoticeKind.noInternet],
          reason: 'одно уведомление на эпизод, а не на каждый шаг');
    });

    test('второй эпизод за пять минут проходит без уведомлений', () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);
      e.tunnelAlive = true;
      await e.checkNetworkWhileOffline();

      // Wi-Fi моргнул ещё раз.
      e.tunnelAlive = false;
      e.startHealthWatch(() => false);
      await _settle();
      expect(e.waitingForNetwork, isTrue);
      expect(e.status.offline, isTrue, reason: 'трей краснеет всё равно');
      e.tunnelAlive = true;
      await e.checkNetworkWhileOffline();
      await _settle(0);

      expect(e.seen,
          [EngineNoticeKind.noInternet, EngineNoticeKind.internetRestored],
          reason: 'моргающий Wi-Fi не должен сыпать уведомлениями');
    });

    test('прямой интернет узнать нельзя — прежнее поведение', () async {
      final e = await _connected();
      addTearDown(e.close);
      e.tunnelAlive = false;
      e.direct = null;
      e.startHealthWatch(() => false);
      await _settle();

      expect(e.waitingForNetwork, isFalse);
      expect(e.teardowns, isPositive);
      expect(e.seen, [EngineNoticeKind.reconnecting]);
    });

    test('прямой интернет есть — умер сервер, переподключаемся', () async {
      final e = await _connected();
      addTearDown(e.close);
      e.tunnelAlive = false;
      e.direct = true;
      e.startHealthWatch(() => false);
      await _settle();

      expect(e.waitingForNetwork, isFalse);
      expect(e.teardowns, isPositive);
      expect(e.seen, [EngineNoticeKind.reconnecting]);
    });

    test('смена сети без интернета — ждём сеть, а не переподключаемся',
        () async {
      final e = await _connected();
      addTearDown(e.close);
      e.tunnelAlive = false;
      e.direct = false;
      await e.onNetworkChanged();
      await _settle(0);

      expect(e.waitingForNetwork, isTrue);
      expect(e.teardowns, 0);
      expect(e.seen, [EngineNoticeKind.noInternet]);
    });

    test('смена сети во время ожидания — сразу проверка сети', () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);
      e.tunnelAlive = true;
      await e.onNetworkChanged();
      expect(e.waitingForNetwork, isFalse,
          reason: 'вставленный кабель не должен ждать шага таймера');
    });

    test('отключение кончает ожидание', () async {
      final e = await _connected();
      addTearDown(e.close);
      await _goOffline(e);
      await e.disconnect();
      expect(e.waitingForNetwork, isFalse);
      expect(e.status.offline, isFalse);
      final probes = e.tunnelProbes;
      await e.checkNetworkWhileOffline();
      expect(e.tunnelProbes, probes, reason: 'после отключения сеть не ждём');
    });
  });
}

class _CountingProbe extends TunnelHealth {
  _CountingProbe(this.answer,
      {required super.interval, required super.suspectInterval})
      : super(proxyPort: 1);
  final bool Function() answer;

  @override
  Future<bool> probeOnce() async => answer();
}
