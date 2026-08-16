import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/probe/cancel_token.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/tcp_ping.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';

/// ФАЗЫ АВТОНАСТРОЙКИ: СНАЧАЛА ДЕШЁВОЕ, ПОТОМ ДОРОГОЕ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. До 17.08.2026 подбор шёл сразу к делу: на КАЖДОГО
/// кандидата (сервер × вариация) поднималось отдельное ядро — и только потом
/// выяснялось, что сервер вообще мёртв. При сотне серверов и четырёх вариациях
/// это сотни запусков ядра подряд ради того, что TCP-коннект отсеивает за
/// миллисекунды.
///
/// Порядок теперь тот же, что у обычного пинга: TCP до всех → проверка сервисов
/// у выживших → вариации у непрошедших → скорость лучших.
class _LoggingHarness implements ProbeHarness {
  _LoggingHarness(this.log);
  final List<String> log;

  /// Порт всегда -1: ядро «не поднялось», значит проб через прокси не будет и
  /// кандидат считается непрошедшим. Нам важен не итог проверки, а ТО, КОГО и
  /// СКОЛЬКИМИ движок вообще берётся проверять.
  static const port = -1;

  /// Сколько запусков живо ПРЯМО СЕЙЧАС и сколько их было максимум разом —
  /// этим проверяется настройка одновременности.
  int live = 0;
  int peak = 0;

  @override
  bool get supportsProxyRequests => true;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    for (final e in entries) {
      log.add('${e.server.address}|${e.variant.label}');
    }
    live++;
    if (live > peak) peak = live;
    // Уступаем очередь: без await всё выполнилось бы синхронно, и пул из трёх
    // работников выглядел бы последовательным независимо от настройки.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return _Handle(this, port);
  }
}

class _Handle implements HarnessHandle {
  _Handle(this.owner, this._port);
  final _LoggingHarness owner;
  final int _port;

  @override
  String get proxyUser => '';
  @override
  String get proxyPassword => '';
  @override
  int proxyPortFor(int index) => _port;
  @override
  Future<int?> delayMs(int index) async => null;
  @override
  Future<void> stop() async => owner.live--;
}

void main() {
  VpnServer srv(String host, {String scheme = 'vless'}) =>
      ShareLinkParser.tryParse(
          '$scheme://00000000-0000-0000-0000-000000000000@$host:443'
          '?type=tcp&security=none#$host')!;

  /// Отвечают по TCP только перечисленные хосты.
  void tcpAlive(Set<String> hosts) {
    AutoConfigEngine.tcpProbe = (host, port, timeout) async => hosts.contains(host)
        ? const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 42,
            latencyMethod: PingMethod.tcp)
        : const PingResult(
            outcome: PingOutcome.failed, latencyMethod: PingMethod.tcp);
  }

  tearDown(() {
    AutoConfigEngine.tcpProbe = (host, port, timeout) =>
        TcpPing.measure(host, port, timeout: timeout);
  });

  const settings = AppSettings(
    autoConfigServices: {ProbeService.youtube},
    tryFragment: true,
    fingerprints: ['chrome'],
  );

  group('Фаза 1: TCP отсеивает до подъёма ядра', () {
    test('⚠️ ГЛАВНОЕ: мёртвый сервер до харнесса не доходит вовсе', () async {
      tcpAlive({'alive.example'});
      final log = <String>[];
      final harness = _LoggingHarness(log);
      await AutoConfigEngine(harnessFactory: () => harness).run(
        servers: [srv('alive.example'), srv('dead.example')],
        settings: settings,
        cancel: CancelToken(),
      );
      expect(log.where((e) => e.startsWith('dead.example')), isEmpty,
          reason: 'ради этого фаза 1 и заведена: сотни запусков ядра ради '
              'серверов, которые не отвечают на TCP-коннект');
      expect(log.where((e) => e.startsWith('alive.example')), isNotEmpty);
    });

    test('итог TCP приходит по КАЖДОМУ серверу, включая непрошедшие', () async {
      // Иначе человек, прождавший прогон по сотне серверов, видит на главном
      // экране прежние «n/a» и жмёт пинг заново, оплачивая ожидание второй раз.
      tcpAlive({'alive.example'});
      final pings = <String, PingResult>{};
      await AutoConfigEngine(harnessFactory: () => _LoggingHarness([])).run(
        servers: [srv('alive.example'), srv('dead.example')],
        settings: settings,
        cancel: CancelToken(),
        onPing: (s, p) => pings[s.address] = p,
      );
      expect(pings.keys, containsAll(['alive.example', 'dead.example']));
      expect(pings['alive.example']!.latencyMs, 42);
      expect(pings['dead.example']!.outcome, PingOutcome.failed);
    });

    test('⚠️ ответивший TCP ещё НЕ значит «рабочий»', () {
      // Тот же урок, что у обычного пинга: открытый порт ничего не проксирует.
      // Рабочим сервер становится только после проверки сервисов.
      tcpAlive({'alive.example'});
      final pings = <PingResult>[];
      return AutoConfigEngine(harnessFactory: () => _LoggingHarness([]))
          .run(
        servers: [srv('alive.example')],
        settings: settings,
        cancel: CancelToken(),
        onPing: (s, p) => pings.add(p),
      )
          .then((_) {
        expect(pings.single.working, isFalse);
      });
    });

    test('⚠️ hysteria2 по TCP не отсеивается — там QUIC', () async {
      // «Не ответил по TCP» для hysteria2 было бы враньём: TCP там нет по
      // определению, и отсев съел бы все такие серверы целиком.
      tcpAlive(const {}); // не отвечает НИКТО
      final log = <String>[];
      await AutoConfigEngine(harnessFactory: () => _LoggingHarness(log)).run(
        servers: [srv('hy2.example', scheme: 'hysteria2')],
        settings: settings,
        cancel: CancelToken(),
      );
      expect(log, isNotEmpty,
          reason: 'сервер обязан дойти до проверки, несмотря на молчание TCP');
    });
  });

  group('Фазы 2 и 3: вариации — только непрошедшим', () {
    test('⚠️ базовая вариация у ВСЕХ идёт раньше любой из остальных', () async {
      // Смысл вариаций — вытащить сервер, который сам по себе не отвечает
      // внятно. Перебирать их до того, как проверена базовая связка, значит
      // платить подъёмом ядра за то, что могло не понадобиться.
      tcpAlive({'a.example', 'b.example'});
      final log = <String>[];
      await AutoConfigEngine(harnessFactory: () => _LoggingHarness(log)).run(
        servers: [srv('a.example'), srv('b.example')],
        settings: settings,
        cancel: CancelToken(),
      );
      final firstExtra = log.indexWhere((e) => !e.endsWith('|как есть'));
      final lastBase = log.lastIndexWhere((e) => e.endsWith('|как есть'));
      expect(firstExtra, greaterThan(lastBase),
          reason: 'фаза 3 не должна начинаться, пока не закончилась фаза 2');
    });
  });

  group('Одновременность настраивается и откатывается', () {
    test('⚠️ 1 = прежнее поведение, строго по очереди', () async {
      tcpAlive({'a.example', 'b.example', 'c.example'});
      final harness = _LoggingHarness([]);
      await AutoConfigEngine(harnessFactory: () => harness).run(
        servers: [srv('a.example'), srv('b.example'), srv('c.example')],
        settings: settings.copyWith(autoConfigConcurrency: 1),
        cancel: CancelToken(),
      );
      expect(harness.peak, 1, reason: 'это и есть путь отката');
    });

    test('3 — три ядра разом, но не больше', () async {
      tcpAlive({'a.example', 'b.example', 'c.example', 'd.example'});
      final harness = _LoggingHarness([]);
      await AutoConfigEngine(harnessFactory: () => harness).run(
        servers: [
          srv('a.example'),
          srv('b.example'),
          srv('c.example'),
          srv('d.example'),
        ],
        settings: settings.copyWith(autoConfigConcurrency: 3),
        cancel: CancelToken(),
      );
      expect(harness.peak, greaterThan(1));
      expect(harness.peak, lessThanOrEqualTo(3),
          reason: 'каждое ядро — это свой локальный порт; на портах уже '
              'обжигались дважды (10085 и 10812)');
    });
  });

  group('Геоблок: сервер рабочий, но не для этой мишени', () {
    CandidateResult res({
      required Map<ProbeService, bool> passed,
      Set<ProbeService> geo = const {},
    }) =>
        CandidateResult(
          server: srv('x.example'),
          variant: OutboundVariant.none,
          passed: passed,
          geoBlocked: geo,
        );

    test('⚠️ геоблок НЕ выкидывает сервер из прошедших', () {
      // Канал живой, всё остальное через него работает — выкинуть значило бы
      // потерять годный сервер из-за одной мишени.
      final r = res(passed: {ProbeService.chatgpt: true},
          geo: {ProbeService.chatgpt});
      expect(r.passedCount, 1);
    });

    test('⚠️ но и безупречным он не считается', () {
      // Именно это число решает порядок: иначе сервер, где ChatGPT отвечает
      // «недоступно в вашей стране», встал бы в список первым и был предложен
      // как лучший тому, кто искал именно ChatGPT.
      final clean = res(passed: {ProbeService.chatgpt: true});
      final geo = res(
          passed: {ProbeService.chatgpt: true}, geo: {ProbeService.chatgpt});
      expect(clean.cleanCount, 1);
      expect(geo.cleanCount, 0);
    });

    test('пометка переживает сохранение', () {
      // Иначе сервер, однажды опознанный как «жив, но ChatGPT недоступен»,
      // после перезапуска снова выглядел бы безупречным.
      final source = AutoConfigResult(
        server: srv('x.example'),
        variant: OutboundVariant.none,
        detail: res(
            passed: {ProbeService.chatgpt: true}, geo: {ProbeService.chatgpt}),
        measuredAt: DateTime.utc(2026, 8, 17),
      );
      final back = AutoConfigResult.fromJson(source.toJson());
      expect(back!.detail.geoBlocked, {ProbeService.chatgpt});
      expect(back.detail.cleanCount, 0);
    });
  });

  group('Замер скорости стоит трафика подписки', () {
    test('⚠️ объём считается в одном месте и называется вслух', () {
      // Цифра показывается у галочки, в подсказке и в предупреждении перед
      // прогоном. Разъехавшиеся числа в предупреждении о расходе — худший вид
      // неправды: человек перестаёт верить всем трём.
      const s = AppSettings(speedTopN: 10);
      expect(s.speedTestTrafficMb, 55, reason: '(10 серверов + свой канал) × 5 МБ');
      expect(const AppSettings(speedTopN: 3).speedTestTrafficMb, 20);
    });

    test('потолок соблюдается даже у испорченных данных на диске', () {
      expect(const AppSettings(speedTopN: 99).effectiveSpeedTopN,
          AppSettings.speedTopNMax);
      expect(const AppSettings(speedTopN: 0).effectiveSpeedTopN, 1);
      expect(const AppSettings(autoConfigConcurrency: 99)
          .effectiveAutoConfigConcurrency, AppSettings.autoConfigConcurrencyMax);
    });
  });
}
