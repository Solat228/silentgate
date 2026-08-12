import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/proxy_probe.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_harness_config_builder.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/state/probe_controller.dart';

/// ПРОВЕРКА ДОЛЖНА БЫТЬ НАСТОЯЩЕЙ.
///
/// Требование владельца дословно: «настоящий пинг — как если бы юзер включил
/// VPN, зашёл на сайт или в приложение, и у него загрузилось или нет».
///
/// Как было: ВСЁ проверялось отдельным процессом-харнессом с голым конфигом —
/// без правил раздельного туннелирования, без DNS пользователя, без блокировок.
/// Проба проходила там, где боевое подключение не работает: плашка пинга горела
/// зелёным, а сервис-чипы у кнопки Connect (они всегда ходили через ЖИВОЕ ядро)
/// в тот же момент были красными.
///
/// Ни один тест здесь не поднимает VPN: «живое ядро» и «харнесс» — это два
/// фальшивых http-прокси на 127.0.0.1, наружу не ходим.
void main() {
  late Directory tmp;

  setUp(() {
    // Пинг сохраняет результаты на диск — уводим корень данных в темп.
    tmp = Directory.systemTemp.createTempSync('sg_real_check_');
    AppPaths.overrideRoot(tmp);
    // Статики кредов общие на изолят: чужой пароль дал бы лишний заголовок.
    ProxyProbe.user = '';
    ProxyProbe.password = '';
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Кто через что проверяется ─────────────────────────────────────────────

  test('подключённый сервер проверяется через ЖИВОЕ ядро, а не через харнесс',
      () async {
    final live = await _FakeProxy.start();
    final tcp = await _tcpTarget();
    final server = _server('active', tcp.port);
    final harness = _RecordingHarness(port: 0);

    final ctrl = ProbeController(
      harnessFactory: () => harness,
      liveProxyPort: () => live.port,
      activeServerKey: () => server.key,
    );
    await ctrl.pingAll([server], _settings);

    // ЗДЕСЬ БЫЛ ГЛАВНЫЙ ДЕФЕКТ: на Windows подключённый сервер всё равно уходил
    // в харнесс — то есть проверялся конфигом, которым пользователь не
    // пользуется, и «зелёный» ничего не говорил о живом канале.
    expect(live.requests, hasLength(1),
        reason: 'проба обязана идти в порт живого ядра');
    expect(live.requests.single, contains('probe.invalid'));
    expect(harness.starts, isEmpty,
        reason: 'ради подключённого сервера второе ядро поднимать незачем');
    expect(ctrl.resultFor(server).verification, PingVerification.passed);

    await live.stop();
    await tcp.close();
  });

  test('неактивный сервер идёт через харнесс, активный — через живое ядро',
      () async {
    final live = await _FakeProxy.start();
    final viaHarness = await _FakeProxy.start();
    final tcpA = await _tcpTarget();
    final tcpB = await _tcpTarget();
    final active = _server('active', tcpA.port);
    final other = _server('other', tcpB.port);
    final harness = _RecordingHarness(port: viaHarness.port);

    final ctrl = ProbeController(
      harnessFactory: () => harness,
      liveProxyPort: () => live.port,
      activeServerKey: () => active.key,
    );
    await ctrl.pingAll([active, other], _settings);

    expect(live.requests, hasLength(1), reason: 'живое ядро — только активный');
    expect(viaHarness.requests, hasLength(1), reason: 'остальные — харнессом');
    expect(harness.starts.single.map((e) => e.key), [other.key],
        reason: 'активного в харнессе быть не должно: он уже проверен живьём');

    await live.stop();
    await viaHarness.stop();
    await tcpA.close();
    await tcpB.close();
  });

  test('при выключенном VPN активный сервер проверяется харнессом', () async {
    // Порт живого канала = 0 («не подключено» либо «подключается»): ходить
    // туда нельзя — порт уже слушает, но никуда не доставляет.
    final live = await _FakeProxy.start();
    final viaHarness = await _FakeProxy.start();
    final tcp = await _tcpTarget();
    final server = _server('active', tcp.port);
    final harness = _RecordingHarness(port: viaHarness.port);

    final ctrl = ProbeController(
      harnessFactory: () => harness,
      liveProxyPort: () => 0,
      activeServerKey: () => server.key,
    );
    await ctrl.pingAll([server], _settings);

    expect(live.requests, isEmpty);
    expect(viaHarness.requests, hasLength(1));
    expect(harness.starts.single.map((e) => e.key), [server.key]);

    await live.stop();
    await viaHarness.stop();
    await tcp.close();
  });

  // ── Прокси задаётся явно ──────────────────────────────────────────────────

  test('без прокси-порта запрос идёт DIRECT явно, а не по умолчанию SDK',
      () async {
    // ЗДЕСЬ БЫЛ ДЕФЕКТ: при proxyPort == 0 `findProxy` не трогали вовсе, и
    // маршрут решал Dart — на машине с http_proxy в окружении «замер без VPN»
    // тихо уходил через чужой прокси.
    final target = await _FakeProxy.start();
    // ⚠️ Настоящий клиент создаётся ДО входа в зону: внутри `createHttpClient`
    // вызов `HttpClient()` снова попал бы в тот же обработчик — рекурсия.
    final direct = _SpyHttpClient(HttpClient());
    await HttpOverrides.runZoned(
      () => ProxyProbe.check(0, 'http://127.0.0.1:${target.port}/direct'),
      createHttpClient: (_) => direct,
    );
    expect(direct.proxyDecision, 'DIRECT');

    final viaProxy = _SpyHttpClient(HttpClient());
    await HttpOverrides.runZoned(
      () => ProxyProbe.check(target.port, 'http://probe.invalid/via'),
      createHttpClient: (_) => viaProxy,
    );
    expect(viaProxy.proxyDecision, 'PROXY 127.0.0.1:${target.port}');
    await target.stop();
  });

  // ── Конфиг харнесса ближе к боевому ───────────────────────────────────────

  test('Xray-харнесс несёт правила по сайтам ВЫШЕ правил кандидатов', () {
    const builder = HarnessConfigBuilder();
    final realism = HarnessRealism.fromRules(const SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      sites: [
        SiteRule('blocked.example', action: AppAction.block),
        SiteRule('direct.example', action: AppAction.direct, port: 8443),
      ],
    ));
    final map = builder.buildMap([
      HarnessEntry(key: 'a', server: _server('a', 443), realism: realism),
    ]);
    final rules = (map['routing'] as Map)['rules'] as List;

    // Правило кандидата ловит из своего входа ВСЁ, поэтому сайты обязаны быть
    // выше него — иначе они не сработали бы ни разу.
    expect(rules.first['domain'], ['domain:blocked.example']);
    expect(rules.first['outboundTag'], 'block');
    expect(rules[1]['domain'], ['domain:direct.example']);
    expect(rules[1]['outboundTag'], 'direct');
    expect(rules[1]['port'], '8443', reason: 'правило с портом — только на него');
    expect(rules.last['inboundTag'], ['in-0'], reason: 'кандидат — последним');
  });

  test('Xray-харнесс переносит свой DNS и ограничивающую стратегию', () {
    const builder = HarnessConfigBuilder();
    final map = builder.buildMap([
      HarnessEntry(
        key: 'a',
        server: _server('a', 443),
        realism: HarnessRealism.fromRules(const SplitTunnelConfig(),
            dnsServer: '9.9.9.9', queryStrategy: 'UseIPv4'),
      ),
    ]);
    expect((map['dns'] as Map)['servers'], ['9.9.9.9']);
    expect((map['dns'] as Map)['queryStrategy'], 'UseIPv4');

    // При умолчаниях конфиг обязан остаться в точности прежним: правка не
    // должна задевать тех, у кого никаких настроек нет.
    final plain = builder.buildMap([HarnessEntry(key: 'a', server: _server('a', 443))]);
    expect(plain.containsKey('dns'), isFalse);
    expect(((plain['routing'] as Map)['rules'] as List).single['inboundTag'],
        ['in-0']);
  });

  test('режим «Всё через VPN» правил в харнесс не отдаёт', () {
    // Зеркало боевого гейта: в этом режиме пользовательские правила не входят
    // в конфиг вовсе. Харнесс, блокирующий то, что боевой конфиг пропускает,
    // врал бы в другую сторону.
    final realism = HarnessRealism.fromRules(const SplitTunnelConfig(
      mode: SplitMode.all,
      sites: [SiteRule('blocked.example', action: AppAction.block)],
    ));
    expect(realism.blocked, isEmpty);
    expect(realism.isEmpty, isTrue);
  });

  test('sing-box-харнесс несёт те же правила по сайтам', () {
    const builder = SingboxHarnessConfigBuilder();
    final realism = HarnessRealism.fromRules(const SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      sites: [
        SiteRule('blocked.example', action: AppAction.block),
        SiteRule('direct.example', action: AppAction.direct),
      ],
    ));
    final map = builder.buildMap([
      HarnessEntry(
          key: 'h',
          server: _server('h', 443, protocol: 'hysteria2'),
          realism: realism),
    ]);
    final rules = (map['route'] as Map)['rules'] as List;
    expect(rules.first['domain_suffix'], ['blocked.example']);
    expect(rules.first['action'], 'reject');
    expect(rules[1]['outbound'], 'direct');
    expect(rules.last['inbound'], ['in-0']);
  });

  test('прогон пинга доносит боевые правила и DNS до харнесса', () async {
    // Без этого правила лежали бы в настройках, а харнесс строился бы голым —
    // ровно то, из-за чего проверка проходила там, где подключение не работает.
    final tcp = await _tcpTarget();
    final server = _server('other', tcp.port);
    final harness = _RecordingHarness(port: 0);
    final ctrl = ProbeController(harnessFactory: () => harness);
    await ctrl.pingAll(
        [server],
        _settings.copyWith(
          splitTunnel: const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            sites: [SiteRule('blocked.example', action: AppAction.block)],
          ),
          dnsMode: DnsMode.custom,
          dnsCustomServer: '9.9.9.9',
          dnsStrategy: DnsStrategy.ipv4Only,
        ));

    final realism = harness.starts.single.single.realism;
    expect(realism.blocked.single.domain, 'blocked.example');
    expect(realism.dnsServer, '9.9.9.9');
    expect(realism.queryStrategy, 'UseIPv4');
    await tcp.close();
  });

  test('битый адрес своего DNS в конфиг не уезжает', () async {
    // Конфиг, который ядро отвергло, — это ноль проверенных серверов, поэтому
    // берём только то, что действительно является адресом.
    final tcp = await _tcpTarget();
    final server = _server('other', tcp.port);
    final harness = _RecordingHarness(port: 0);
    final ctrl = ProbeController(harnessFactory: () => harness);
    await ctrl.pingAll(
        [server],
        _settings.copyWith(
            dnsMode: DnsMode.custom, dnsCustomServer: 'https://dns.example/q'));
    expect(harness.starts.single.single.realism.dnsServer, isEmpty);
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

VpnServer _server(String name, int port, {String protocol = 'vless'}) =>
    VpnServer(
      protocol: protocol,
      remark: name,
      address: '127.0.0.1',
      port: port,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink:
          '$protocol://11111111-2222-3333-4444-555555555555@127.0.0.1:$port#$name',
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

/// Харнесс-пустышка: запоминает, кого в него отдали, и отдаёт заранее известный
/// порт (порт другого фальшивого прокси либо 0 — «поднять не удалось»).
class _RecordingHarness implements ProbeHarness {
  _RecordingHarness({required this.port});
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
  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  _RecordingHandle(this.port);
  final int port;

  @override
  int proxyPortFor(int index) => port <= 0 ? -1 : port;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}

/// Клиент-соглядатай: запоминает, какое решение о прокси ему задали. Нужен
/// потому, что «прокси не задан» и «задан DIRECT» снаружи выглядят одинаково,
/// а ведут себя по-разному на машине с прокси в переменных окружения.
class _SpyHttpClient implements HttpClient {
  _SpyHttpClient(this._inner);
  final HttpClient _inner;
  String? proxyDecision;

  @override
  set findProxy(String Function(Uri url)? f) {
    proxyDecision = f?.call(Uri.parse('http://probe.invalid/'));
    _inner.findProxy = f;
  }

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _inner.openUrl(method, url);

  @override
  void addProxyCredentials(
          String host, int port, String realm, HttpClientCredentials creds) =>
      _inner.addProxyCredentials(host, port, realm, creds);

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
