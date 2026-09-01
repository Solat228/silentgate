import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/net/speed_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/probe_controller.dart';

/// Ручной замер скорости не отменяется массовым прогоном.
///
/// **Требование владельца 02.09.2026, дословно:** «в любом случае просто
/// запускаем пинг данного сервера раньше и вытесняем из общей очереди. Условно
/// клиент запустил массовый скан и проверил вручную другой сервер — его дальше
/// не проверяем».
///
/// Разворачивается в три проверяемых утверждения:
///   1. сервер, выбранный руками, меряется РАНЬШЕ остатка массового прогона;
///   2. из остатка он вычёркивается — второй раз за него трафик не платим;
///   3. массовый прогон после этого продолжается, а не отменяется.
///
/// ⚠️ Допущение, принятое явно: ручной замер не рвёт сервер, который прямо
/// сейчас качает мегабайты, — он встаёт СЛЕДУЮЩИМ. Трафик за начатый сервер
/// уже потрачен, и обрывать его значило бы выбросить эти мегабайты.
///
/// Ни одна проба наружу не уходит: харнесс и закачка подменены фейками.
void main() {
  late Directory tmp;

  setUp(() {
    // Замеры пишутся на диск — уводим корень данных в темп, чтобы тест не
    // трогал боевой %APPDATA%\SilentGate.
    tmp = Directory.systemTemp.createTempSync('sg_manual_speed_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() {
    _Downloads.current = null;
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('ручной замер во время массового прогона идёт следующим и только раз',
      () async {
    final probe = _controller();
    final a = _server('a');
    final b = _server('b');
    final c = _server('c');
    for (final s in [a, b, c]) {
      probe.setResult(s, _passed);
    }
    final rec = _Downloads(probe)..hold('a');

    // Массовый прогон: a, b, c. Первый сервер зависает на закачке — это и есть
    // окно, в котором человек лезет в меню и жмёт «Измерить скорость» у «c».
    final all = probe.measureSpeedAll([a, b, c], const AppSettings());
    await rec.startedFor('a');

    // ⚠️ Не ждём здесь: если ручной замер честно дождётся своей очереди, то
    // до отпускания «a» он и не закончится — ожидание вешало бы тест.
    final one = probe.measureSpeedOne(c, const AppSettings());
    rec.release('a');
    await all;
    await one;

    expect(rec.order, ['a', 'c', 'b'],
        reason: 'ручной «c» обязан идти сразу после текущего «a», '
            'а не в конце очереди');
    expect(rec.order.where((n) => n == 'c').length, 1,
        reason: 'вычеркнут из остатка: за один сервер платим один раз');
    expect(probe.speedFor(b), isNotNull,
        reason: 'массовый прогон продолжается, а не отменяется ручным замером');
  });

  test('ручной замер во время прогона ПИНГА не пропадает — идёт после него',
      () async {
    // ⚠️ Второй запрет, отдельный от первого. Пинг держит ТОТ ЖЕ харнесс и те
    // же локальные порты, поэтому параллельно замер не запустить. Но
    // требование владельца — «в любом случае измерить», значит отказ здесь
    // недопустим: замер обязан дождаться конца пинга и состояться сам.
    final harness = _HoldOnceHarness();
    final probe = ProbeController(harnessFactory: () => harness);
    final downloads = _countDownloads(probe);

    // hysteria2 нарочно: у него нет TCP-фазы (QUIC), прогон уходит сразу в
    // харнесс и ни одного сокета наружу тест не открывает.
    final pinged = _hy2('Браво', 'b.example');
    final measured = _hy2('Альфа', 'a.example');
    // Меряем ДРУГОЙ сервер, не тот, что пингуется: иначе прогон перепишет ему
    // вердикт проверки канала, и замер отсеется гейтом «не проверен».
    probe.setResult(measured, _passed);

    final ping = probe.pingAll([pinged], const AppSettings());
    expect(probe.running, isTrue, reason: 'прогон пинга действительно идёт');

    final one = probe.measureSpeedOne(measured, const AppSettings());
    harness.release();
    await ping;
    await one;
    await pumpEventQueue();

    expect(downloads.count, 1,
        reason: 'замер обязан состояться после пинга, а не пропасть молча');
    expect(probe.speedFor(measured), isNotNull);
  });

  test('пока замер ждёт конца пинга, интерфейсу есть что показать', () async {
    // ⚠️ Требование владельца прямое: «решить и назвать это в интерфейсе, а не
    // молчать». Отложенный замер без признака ожидания — то же молчание, что
    // и раньше: человек нажал пункт меню и по экрану не может понять, принято
    // ли нажатие вообще.
    final harness = _HoldOnceHarness();
    final probe = ProbeController(harnessFactory: () => harness);
    _countDownloads(probe);
    final pinged = _hy2('Браво', 'b.example');
    final measured = _hy2('Альфа', 'a.example');
    probe.setResult(measured, _passed);

    expect(probe.speedWaitsForPing, isFalse, reason: 'контроль: ждать нечего');

    final ping = probe.pingAll([pinged], const AppSettings());
    final one = probe.measureSpeedOne(measured, const AppSettings());
    expect(probe.speedWaitsForPing, isTrue,
        reason: 'нажатие принято и стоит в очереди — это и надо показать');

    harness.release();
    await ping;
    await one;
    await pumpEventQueue();

    expect(probe.speedWaitsForPing, isFalse,
        reason: 'дождался и состоялся — признак обязан сняться, иначе карточка '
            'ожидания повиснет навсегда');
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

const _passed = PingResult(
    outcome: PingOutcome.ok,
    latencyMs: 40,
    verification: PingVerification.passed);

VpnServer _server(String name) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: '127.0.0.1',
      port: 443,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink:
          'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:443#$name',
    );

ProbeController _controller() =>
    ProbeController(harnessFactory: () => _FakeHarness());

/// Подменённая закачка: записывает порядок и умеет ЗАДЕРЖАТЬ выбранные
/// серверы.
///
/// Управляемая задержка нужна именно здесь: мгновенная подмена не оставила бы
/// окна, в котором массовый прогон уже идёт, — а всё требование как раз про
/// это окно.
class _Downloads {
  _Downloads(ProbeController probe) {
    current = this;
    probe.speedDownload = ({
      required SpeedTestSize size,
      int? proxyPort,
      String proxyUser = '',
      String proxyPassword = '',
    }) async {
      // Имя сервера в закачку не передаётся, поэтому берём его у харнесса:
      // он поднимается прямо перед ней и знает кандидата поимённо.
      final name = _startedByHarness.removeAt(0);
      order.add(name);
      _waiting.remove(name)?.complete();
      final gate = _held[name];
      if (gate != null) await gate.future;
      return const SpeedResult(
          bitsPerSecond: 24000000,
          bytes: 5000000,
          elapsed: Duration(seconds: 2));
    };
  }

  /// Экземпляр, у которого харнесс отмечает поднятого кандидата.
  static _Downloads? current;

  /// Имена в том порядке, в каком закачка их получила.
  final List<String> order = [];

  final List<String> _startedByHarness = [];
  final Map<String, Completer<void>> _held = {};
  final Map<String, Completer<void>> _waiting = {};

  void noteHarnessStart(String name) => _startedByHarness.add(name);

  /// Держать закачку этого сервера, пока не позовут [release].
  void hold(String name) => _held[name] = Completer<void>();

  void release(String name) {
    final gate = _held.remove(name);
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// Ждём, пока закачка ДОЙДЁТ до сервера с этим именем.
  Future<void> startedFor(String name) {
    if (order.contains(name)) return Future.value();
    return (_waiting[name] ??= Completer<void>()).future;
  }
}

VpnServer _hy2(String name, String host) => VpnServer(
      protocol: 'hysteria2',
      remark: name,
      address: host,
      port: 443,
      id: 'pass',
      rawLink: 'hysteria2://pass@$host:443#$name',
    );

class _Counter {
  int count = 0;
}

/// Закачка без задержек: считаем только, сколько раз её позвали.
_Counter _countDownloads(ProbeController probe) {
  final c = _Counter();
  probe.speedDownload = ({
    required SpeedTestSize size,
    int? proxyPort,
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    c.count++;
    return const SpeedResult(
        bitsPerSecond: 24000000, bytes: 5000000, elapsed: Duration(seconds: 2));
  };
  return c;
}

/// Харнесс, который ПЕРВЫЙ раз висит до [release], а дальше отвечает сразу.
///
/// Первый — тот, что держит прогон пинга; последующие нужны замеру скорости.
class _HoldOnceHarness implements ProbeHarness {
  final _gate = Completer<void>();
  var _held = false;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    if (!_held) {
      _held = true;
      await _gate.future;
    }
    return _FakeHandle();
  }

  @override
  bool get supportsProxyRequests => true;
}

/// Харнесс, который сообщает тесту, за какого кандидата сейчас возьмётся
/// закачка.
class _FakeHarness implements ProbeHarness {
  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    for (final e in entries) {
      _Downloads.current?.noteHarnessStart(e.server.remark);
    }
    return _FakeHandle();
  }

  @override
  bool get supportsProxyRequests => true;
}

class _FakeHandle implements HarnessHandle {
  @override
  String get proxyUser => harnessProxyUser;

  @override
  String get proxyPassword => 'secret42';

  @override
  int proxyPortFor(int index) => 24081;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}
