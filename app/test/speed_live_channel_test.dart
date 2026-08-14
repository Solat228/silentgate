import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/net/speed_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/proxy_probe.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/probe_controller.dart';

/// Замер скорости на Android — жалоба владельца 1.4.3: «на телефоне нет
/// измерения скорости».
///
/// ЧТО БЫЛО. Замер качает пробу через локальный http-порт харнесса, а на
/// Android харнесс порта наружу НЕ ДАЁТ: `LibXray.ping` поднимает ядро внутри
/// вызова, меряет сам и гасит его, а `proxyPortFor` там всегда 0. Прогон честно
/// стартовал, писал в журнал «харнесс не дал порт» и заканчивался «измерено 0
/// из 1» — то есть пункт меню был, а замера не было, и почему — не сказано.
///
/// ЧТО ДОЛЖНО БЫТЬ. Подключённый сервер меряется через ЖИВОЙ канал (инбаунд
/// проб уже поднят ради сервис-чипов) — на обеих платформах. Остальные серверы
/// на Android измерить нечем, и это видно снаружи ([canMeasureSpeed]), а не
/// выясняется после нажатия.
///
/// Ни одного байта наружу: закачка подменена, харнесс — фейк.
void main() {
  late Directory tmp;
  late String savedUser;
  late String savedPassword;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_speed_live_');
    AppPaths.overrideRoot(tmp);
    // Креды живого инбаунда — статики процесса; тест их подменяет и обязан
    // вернуть, иначе следующий тест получит чужой пароль.
    savedUser = ProxyProbe.user;
    savedPassword = ProxyProbe.password;
    ProxyProbe.user = 'sg';
    ProxyProbe.password = 'live-secret';
  });

  tearDown(() {
    ProxyProbe.user = savedUser;
    ProxyProbe.password = savedPassword;
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Android без подключения: мерить нечем, и это видно ─────────────────────

  test('Android: неподключённый сервер в замер не идёт и не молчит', () async {
    final probe = _controller(harness: _FakeHarness(givesPort: false));
    final calls = _recordDownloads(probe);
    final s = _server('far');
    probe.setResult(s, _passed);

    expect(probe.canMeasureSpeed(s), isFalse,
        reason: 'харнесс на Android порта не даёт, живого канала нет');
    expect(probe.speedTargets([s]), isEmpty,
        reason: 'кнопка «измерить все» обязана видеть это ДО прогона');

    await probe.measureSpeedAll([s], const AppSettings());
    expect(calls, isEmpty);

    // Пункт меню у строки сервера: раньше он запускал прогон, получал порт 0 и
    // заканчивался «измерено 0 из 1» без причины.
    await probe.measureSpeedOne(s, const AppSettings());
    expect(calls, isEmpty);
    expect(probe.speedFor(s), isNull);
    expect(probe.speedSummary, isNotNull,
        reason: 'нажатие обязано получить ответ, а не тишину');
    expect(probe.speedSummary, contains('живое подключение'));
    expect(probe.speedFinishedAt, isNotNull,
        reason: 'без отметки времени уведомление не покажется');
  });

  // ── Android с подключением: замер идёт через живой канал ───────────────────

  test('Android: подключённый сервер меряется через живой канал', () async {
    final s = _server('active');
    final probe = _controller(
      harness: _FakeHarness(givesPort: false),
      livePort: 10811,
      liveKey: s.key,
    );
    final calls = _recordDownloads(probe);
    probe.setResult(s, _passed);

    expect(probe.canMeasureSpeed(s), isTrue);
    await probe.measureSpeedOne(
        s, const AppSettings(speedTestSize: SpeedTestSize.light));

    expect(calls.length, 1, reason: 'ЗДЕСЬ БЫЛ ПРОПУСК ЗАМЕРА НА ТЕЛЕФОНЕ');
    expect(calls.single.port, 10811);
    expect(calls.single.size, SpeedTestSize.light);
    // ⚠️ Креды ЖИВОГО инбаунда, а не харнесса: инбаунд проб закрыт паролем
    // (1.3.0), и чужой пароль дал бы 407 и «замер не удался».
    expect(calls.single.user, 'sg');
    expect(calls.single.password, 'live-secret');
    expect(probe.speedFor(s)?.mbps, closeTo(24, 0.01));
    expect(probe.speedSummary, contains('1 из 1'));
  });

  test('живой канал берётся только для ПОДКЛЮЧЁННОГО сервера', () async {
    final active = _server('active');
    final other = _server('other');
    final probe = _controller(
      harness: _FakeHarness(givesPort: true), // как Windows
      livePort: 10809,
      liveKey: active.key,
    );
    final calls = _recordDownloads(probe);
    probe.setResult(active, _passed);
    probe.setResult(other, _passed);

    await probe.measureSpeedAll([active, other], const AppSettings());

    expect(calls.length, 2);
    // Подключённый — через живой порт и сессионные креды.
    expect(calls[0].port, 10809);
    expect(calls[0].password, 'live-secret');
    // ⚠️ А сосед — через харнесс. Померить его через ЧУЖОЙ живой туннель
    // значило бы положить в его строку скорость другого сервера.
    expect(calls[1].port, _fakePort);
    expect(calls[1].password, _fakeSecret);
  });

  test('«подключается» — не «подключено»: порт 0 живым каналом не считается',
      () async {
    final s = _server('rising');
    final probe = _controller(
      harness: _FakeHarness(givesPort: false),
      livePort: 0, // канал ещё поднимается
      liveKey: s.key,
    );
    final calls = _recordDownloads(probe);
    probe.setResult(s, _passed);

    expect(probe.canMeasureSpeed(s), isFalse);
    await probe.measureSpeedOne(s, const AppSettings());
    expect(calls, isEmpty,
        reason: 'порт уже слушает, но никуда не доставляет — замер провалился '
            'бы и записал ноль в строку живого сервера');
  });

  test('гейт «не прошёл проверку канала» живым каналом не обходится', () async {
    final s = _server('unverified');
    final probe = _controller(
      harness: _FakeHarness(givesPort: false),
      livePort: 10811,
      liveKey: s.key,
    );
    final calls = _recordDownloads(probe);
    // Пинг прошёл по TCP, проверки через сервер не было.
    probe.setResult(s, const PingResult(outcome: PingOutcome.ok, latencyMs: 30));

    await probe.measureSpeedOne(s, const AppSettings());
    expect(calls, isEmpty,
        reason: 'решение владельца: без пройденной проверки канала трафик '
            'подписки на замер не тратим');
    // И объяснение тут другое — его даёт интерфейс (`speedNotVerified`),
    // поэтому своего сообщения прогон не пишет.
    expect(probe.speedSummary, isNull);
  });

  test('провал закачки по живому каналу не записывается как замер', () async {
    final s = _server('slow');
    final probe = _controller(
      harness: _FakeHarness(givesPort: false),
      livePort: 10811,
      liveKey: s.key,
    );
    probe.speedDownload = ({
      required SpeedTestSize size,
      int? proxyPort,
      String proxyUser = '',
      String proxyPassword = '',
    }) async => const SpeedResult.failed('Таймаут');
    probe.setResult(s, _passed);

    await probe.measureSpeedOne(s, const AppSettings());
    expect(probe.speedFor(s), isNull, reason: 'ноль в строке — не результат');
    expect(probe.speedSummary, contains('0 из 1'));
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

const _fakePort = 24081;
const _fakeSecret = 'harness-secret';
const _passed = PingResult(
    outcome: PingOutcome.ok,
    latencyMs: 30,
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

ProbeController _controller({
  required _FakeHarness harness,
  int livePort = 0,
  String liveKey = '',
}) =>
    ProbeController(
      harnessFactory: () => harness,
      liveProxyPort: () => livePort,
      activeServerKey: () => liveKey,
    );

class _Download {
  _Download(this.size, this.port, this.user, this.password);
  final SpeedTestSize size;
  final int? port;
  final String user;
  final String password;
}

List<_Download> _recordDownloads(ProbeController probe) {
  final calls = <_Download>[];
  probe.speedDownload = ({
    required SpeedTestSize size,
    int? proxyPort,
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    calls.add(_Download(size, proxyPort, proxyUser, proxyPassword));
    return const SpeedResult(
        bitsPerSecond: 24000000, bytes: 5000000, elapsed: Duration(seconds: 2));
  };
  return calls;
}

/// [givesPort] `false` — харнесс как на Android: инбаунд поднимается, но порт
/// наружу не отдаётся, замерить через него произвольную закачку нельзя.
class _FakeHarness implements ProbeHarness {
  _FakeHarness({required this.givesPort});
  final bool givesPort;

  @override
  bool get supportsProxyRequests => givesPort;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async =>
      _FakeHandle(givesPort);
}

class _FakeHandle implements HarnessHandle {
  _FakeHandle(this.givesPort);
  final bool givesPort;

  @override
  String get proxyUser => harnessProxyUser;

  @override
  String get proxyPassword => _fakeSecret;

  @override
  int proxyPortFor(int index) => givesPort ? _fakePort : 0;

  @override
  Future<int?> delayMs(int index) async => givesPort ? null : 42;

  @override
  Future<void> stop() async {}
}
