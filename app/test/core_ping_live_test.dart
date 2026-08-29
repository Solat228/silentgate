import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/clash_delay.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/proxy_probe.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/probe_controller.dart';

/// Пинг при ПОДНЯТОМ туннеле: откуда берётся показываемая цифра.
///
/// ⚠️ ЧТО ЧИНИМ. При активном TUN `Socket.connect` фазы 1 затягивается в
/// туннель, и рукопожатие завершает локальный стек sing-box за 1–3 мс — у ВСЕХ
/// серверов, включая мёртвые (проверено живыми замерами в VM; ни
/// `route_exclude_address`, ни привязка к адаптеру не помогли). Честный замер
/// текущего сервера делает САМО ядро через Clash API
/// (`GET /proxies/{tag}/delay`), а TCP-цифры остальных помечаются как снятые
/// сквозь туннель — и интерфейс их прячет.
///
/// Сети здесь нет: Clash API подменён транспортом-функцией, «живое ядро» и
/// харнесс — фальшивые прокси на 127.0.0.1, мишени TCP — локальные слушатели.
void main() {
  late Directory tmp;

  setUp(() {
    // Пинг сохраняет результаты на диск — уводим корень данных в темп,
    // чтобы тест не тронул боевой %APPDATA%.
    tmp = Directory.systemTemp.createTempSync('sg_core_ping_');
    AppPaths.overrideRoot(tmp);
    ProxyProbe.user = '';
    ProxyProbe.password = '';
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  ClashDelayProbe coreAnswering(int status, String body,
          {List<Uri>? calls}) =>
      ClashDelayProbe(
        port: 39999,
        secret: 's',
        httpGet: (url, {required String bearer, required Duration timeout}) //
            async {
          calls?.add(url);
          return ClashHttpResponse(status, body);
        },
      );

  test('туннель поднят: цифра текущего сервера — от ядра, с подписью coreUrl',
      () async {
    final tcp = await _tcpTarget();
    final server = _server('active', tcp.port);
    final harness = _RecordingHarness(port: 0);
    final calls = <Uri>[];

    final ctrl = ProbeController(
      harnessFactory: () => harness,
      liveProxyPort: () => 1, // живой канал есть; ходить в него не должны
      activeServerKey: () => server.key,
      captureActive: () => true,
      liveCoreDelay: () => coreAnswering(200, '{"delay": 217}', calls: calls),
    );
    await ctrl.pingAll([server], _settings);

    final r = ctrl.resultFor(server);
    // ГЛАВНОЕ: вместо ложной TCP-цифры в 1–3 мс — замер, выполненный ядром.
    expect(r.latencyMs, 217);
    expect(r.latencyMethod, PingMethod.coreUrl,
        reason: 'величина другая (запрос через туннель) — подпись обязана '
            'отличать её от TCP');
    expect(r.verification, PingVerification.passed,
        reason: 'запрос через сервер реально прошёл');
    expect(r.latencyThroughTunnel, isFalse,
        reason: 'эта цифра как раз честная — прятать её нельзя');
    expect(calls, hasLength(1), reason: 'один замер — один запрос к Clash API');
    expect(harness.starts, isEmpty,
        reason: 'текущий сервер в харнесс не уходит');
    await tcp.close();
  });

  test('туннель поднят БЕЗ двухфазности: ядро всё равно меряет текущий',
      () async {
    // Раньше без фазы 2 текущий сервер оставался с ложной TCP-цифрой:
    // живой замер жил только внутри верификации. Теперь честный замер не
    // зависит от режима проверки.
    final tcp = await _tcpTarget();
    final server = _server('active', tcp.port);

    final ctrl = ProbeController(
      harnessFactory: _RecordingHarness.new0,
      liveProxyPort: () => 1,
      activeServerKey: () => server.key,
      captureActive: () => true,
      liveCoreDelay: () => coreAnswering(200, '{"delay": 88}'),
    );
    await ctrl.pingAll(
        [server], _settings.copyWith(pingTwoPhase: false));

    final r = ctrl.resultFor(server);
    expect(r.latencyMs, 88);
    expect(r.latencyMethod, PingMethod.coreUrl);
    await tcp.close();
  });

  test('соседи при поднятом туннеле помечаются «сквозь туннель»', () async {
    final viaHarness = await _FakeProxy.start();
    final tcpA = await _tcpTarget();
    final tcpB = await _tcpTarget();
    final active = _server('active', tcpA.port);
    final other = _server('other', tcpB.port);
    final harness = _RecordingHarness(port: viaHarness.port);

    final ctrl = ProbeController(
      harnessFactory: () => harness,
      liveProxyPort: () => 1,
      activeServerKey: () => active.key,
      captureActive: () => true,
      liveCoreDelay: () => coreAnswering(200, '{"delay": 120}'),
    );
    await ctrl.pingAll([active, other], _settings);

    final r = ctrl.resultFor(other);
    expect(r.latencyThroughTunnel, isTrue,
        reason: 'рукопожатие завершил локальный туннель — цифра не про сервер');
    expect(r.latencyMethod, PingMethod.tcp);
    expect(r.verification, PingVerification.passed,
        reason: 'верификация харнессом настоящая — прячется только цифра');
    expect(ctrl.resultFor(active).latencyThroughTunnel, isFalse);
    await viaHarness.stop();
    await tcpA.close();
    await tcpB.close();
  });

  test('туннеля нет: прежний путь, цифра TCP без пометок', () async {
    final viaHarness = await _FakeProxy.start();
    final tcp = await _tcpTarget();
    final server = _server('plain', tcp.port);

    final ctrl = ProbeController(
      harnessFactory: () => _RecordingHarness(port: viaHarness.port),
      liveProxyPort: () => 0,
      activeServerKey: () => null,
      captureActive: () => false,
      liveCoreDelay: () => null,
    );
    await ctrl.pingAll([server], _settings);

    final r = ctrl.resultFor(server);
    expect(r.latencyMethod, PingMethod.tcp);
    expect(r.latencyThroughTunnel, isFalse);
    expect(r.latencyMs, isNotNull);
    await viaHarness.stop();
    await tcp.close();
  });

  test('Clash API молчит — откат на живой прокси-порт, а не выдуманный провал',
      () async {
    final live = await _FakeProxy.start();
    final tcp = await _tcpTarget();
    final server = _server('active', tcp.port);

    final ctrl = ProbeController(
      harnessFactory: () => _RecordingHarness(port: 0),
      liveProxyPort: () => live.port,
      activeServerKey: () => server.key,
      captureActive: () => true,
      liveCoreDelay: () => ClashDelayProbe(
        port: 1,
        httpGet: (_, {required String bearer, required Duration timeout}) =>
            throw const SocketException('refused'),
      ),
    );
    await ctrl.pingAll([server], _settings);

    expect(live.requests, hasLength(1),
        reason: 'замер обязан уйти в живой прокси-порт — он тоже честный');
    final r = ctrl.resultFor(server);
    expect(r.verification, PingVerification.passed);
    // TCP-цифра при этом снята сквозь туннель — пометка обязана уцелеть.
    expect(r.latencyThroughTunnel, isTrue);
    await live.stop();
    await tcp.close();
  });

  test('провал теста ядром — честный красный, а не зелёный TCP', () async {
    final tcp = await _tcpTarget();
    final server = _server('active', tcp.port);

    final ctrl = ProbeController(
      harnessFactory: () => _RecordingHarness(port: 0),
      liveProxyPort: () => 1,
      activeServerKey: () => server.key,
      captureActive: () => true,
      liveCoreDelay: () => coreAnswering(504, '{"message": "Timeout"}'),
    );
    await ctrl.pingAll([server], _settings);

    final r = ctrl.resultFor(server);
    expect(r.outcome, PingOutcome.timeout);
    expect(r.verification, PingVerification.failed);
    expect(r.latencyMethod, PingMethod.coreUrl);
    expect(r.latencyMs, isNull,
        reason: 'ложную TCP-цифру оставлять на экране нельзя');
    await tcp.close();
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

/// Двухфазный пинг с мишенью, которой нет в природе: запрос обязан уйти в
/// прокси-порт (живой или харнесса), а не в интернет.
const _settings = AppSettings(
  pingTwoPhase: true,
  testUrl: 'http://probe.invalid/generate_204',
  pingTimeoutMs: 3000,
);

VpnServer _server(String name, int port) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: '127.0.0.1',
      port: port,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink:
          'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:$port#$name',
    );

/// Слушатель, на который отвечает фаза 1 (TCP). Соединения не читаем: TcpPing
/// меряет только установку связи.
Future<ServerSocket> _tcpTarget() =>
    ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

/// Фальшивый http-прокси: принимает запрос, запоминает строку запроса и
/// отвечает 204. Изображает и живое ядро, и харнесс.
class _FakeProxy {
  _FakeProxy._(this._sock);
  final ServerSocket _sock;
  final List<String> requests = [];

  int get port => _sock.port;

  static Future<_FakeProxy> start() async {
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _FakeProxy._(sock);
    sock.listen((client) {
      final buf = <int>[];
      client.listen((data) async {
        buf.addAll(data);
        final text = String.fromCharCodes(buf);
        if (!text.contains('\r\n\r\n')) return;
        proxy.requests.add(text.split('\r\n').first);
        client.write('HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n');
        try {
          await client.flush();
          await client.close();
        } catch (_) {}
      }, onError: (_) {}, cancelOnError: true);
    });
    return proxy;
  }

  Future<void> stop() => _sock.close();
}

/// Харнесс-пустышка: запоминает, кого в него отдали, и отдаёт заранее
/// известный порт (порт фальшивого прокси либо 0 — «поднять не удалось»).
class _RecordingHarness implements ProbeHarness {
  _RecordingHarness({required this.port});
  static ProbeHarness new0() => _RecordingHarness(port: 0);
  final int port;
  final List<List<HarnessEntry>> starts = [];

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    starts.add(entries);
    return _RecordingHandle(port);
  }

  @override
  bool get supportsProxyRequests => true;
}

class _RecordingHandle implements HarnessHandle {
  _RecordingHandle(this.port);
  final int port;

  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  @override
  int proxyPortFor(int index) => port <= 0 ? -1 : port;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}
