import '../models/vpn_server.dart';
import '../net/speed_test.dart';
import 'speed_score.dart';
import '../parser/share_link_parser.dart';
import '../platform/app_log.dart';
import '../settings/app_settings.dart';
import '../xray/outbound_variant.dart';
import 'cancel_token.dart';
import 'ping_result.dart';
import 'tcp_ping.dart';
import 'probe_harness.dart';
import 'proxy_probe.dart';

/// Проба одного сервиса: URL + метод + валидатор ответа (защита от заглушек провайдера).
class ProbeEndpoint {
  final ProbeService service;
  final String url;
  final bool head;
  final ResponseValidator validator;
  const ProbeEndpoint(this.service, this.url, this.validator, {this.head = false});
}

/// Отдельная гео-проба ИИ-сервиса: сервис ОТКРЫВАЕТСЯ, но недоступен в стране
/// выхода VPN. [blocked] возвращает true, если ответ говорит «регион не
/// поддерживается» (403/451, `unsupported_country`, «not available in your…»).
class GeoEndpoint {
  final ProbeService service;
  final String url;
  final bool Function(int code, String body) blocked;
  const GeoEndpoint(this.service, this.url, this.blocked);
}

/// Каталог проверок. Валидаторы проверяют не «2xx», а сигнатуру ответа —
/// заглушка провайдера (обычно 200 + HTML) их не пройдёт, а TLS отсекает подмену.
class AutoConfigCatalog {
  static const _all = <ProbeService, ProbeEndpoint>{
    ProbeService.youtube: ProbeEndpoint(
      ProbeService.youtube,
      'https://www.youtube.com/generate_204',
      _is204,
    ),
    ProbeService.chatgpt: ProbeEndpoint(
      ProbeService.chatgpt,
      'https://chatgpt.com/cdn-cgi/trace',
      _cfTrace,
    ),
    ProbeService.discord: ProbeEndpoint(
      ProbeService.discord,
      'https://discord.com/api/v9/gateway',
      _discordGateway,
    ),
    ProbeService.telegram: ProbeEndpoint(
      ProbeService.telegram,
      'https://web.telegram.org/',
      _telegramWeb,
    ),
    ProbeService.claude: ProbeEndpoint(
      ProbeService.claude,
      'https://claude.ai/cdn-cgi/trace',
      _cfTrace,
    ),
    ProbeService.gemini: ProbeEndpoint(
      ProbeService.gemini,
      'https://gemini.google.com/',
      _hasGemini,
    ),
    ProbeService.x: ProbeEndpoint(
      ProbeService.x,
      'https://x.com/robots.txt',
      _robots,
    ),
    ProbeService.instagram: ProbeEndpoint(
      ProbeService.instagram,
      'https://www.instagram.com/robots.txt',
      _robots,
    ),
    ProbeService.google: ProbeEndpoint(
      ProbeService.google,
      'https://www.google.com/generate_204',
      _is204,
    ),
  };

  /// Гео-пробы ИИ-сервисов (недоступность в стране выхода — отдельный сигнал).
  static const _geo = <ProbeService, GeoEndpoint>{
    // Классический публичный сигнал OpenAI: 403 + `unsupported_country`.
    ProbeService.chatgpt: GeoEndpoint(
      ProbeService.chatgpt,
      'https://api.openai.com/compliance/cookie_requirements',
      _openAiBlocked,
    ),
    ProbeService.claude: GeoEndpoint(
      ProbeService.claude,
      'https://claude.ai/',
      _regionBlocked,
    ),
    ProbeService.gemini: GeoEndpoint(
      ProbeService.gemini,
      'https://gemini.google.com/',
      _regionBlocked,
    ),
  };

  static List<ProbeEndpoint> endpointsFor(Set<ProbeService> services) =>
      [for (final s in services) if (_all[s] != null) _all[s]!];

  /// Проба сервиса по одному значению (для живой проверки у кнопки).
  static ProbeEndpoint? endpointFor(ProbeService s) => _all[s];

  /// Гео-проба сервиса (или null, если сервис не гео-ограничен).
  static GeoEndpoint? geoEndpointFor(ProbeService s) => _geo[s];

  static bool _is204(int code, String body) => code == 204;
  static bool _cfTrace(int code, String body) =>
      code == 200 && body.contains('fl=') && body.contains('loc=');
  static bool _discordGateway(int code, String body) =>
      code == 200 && body.contains('wss://');
  static bool _telegramWeb(int code, String body) =>
      code == 200 && body.toLowerCase().contains('telegram');
  static bool _hasGemini(int code, String body) =>
      code == 200 && body.toLowerCase().contains('gemini');
  static bool _robots(int code, String body) =>
      code == 200 && body.toLowerCase().contains('user-agent');

  // ── Гео-валидаторы ─────────────────────────────────────────────────────────
  // ГОЛЫЙ 403 гео-блоком НЕ считаем: у OpenAI/Cloudflare это ещё и бот-челлендж/
  // rate-limit на доступном регионе (иначе — ложная «страна заблокирована»).
  // Надёжный сигнал OpenAI — маркер `unsupported_country` в теле; для Claude/
  // Gemini — 451 (юридический гео-блок) либо текст «недоступно в вашем регионе».
  static bool _openAiBlocked(int code, String body) =>
      body.toLowerCase().contains('unsupported_country');
  static bool _regionBlocked(int code, String body) {
    if (code == 451) return true;
    // Типографскую апострофу (U+2019, её ставят Google/Anthropic) сводим к ASCII,
    // иначе `isn't` из живого ответа не совпал бы с шаблоном.
    final b = body.toLowerCase().replaceAll('’', "'");
    return b.contains('not available in your') ||
        b.contains("isn't available") ||
        b.contains('unavailable in your') ||
        b.contains('unsupported_country');
  }
}

enum ProbeState { pending, testing, ok, fail }

class AutoConfigProgress {
  final int index;
  final int total;
  final String candidateName;

  /// Вариация как ДАННЫЕ, а не готовая строка: подпись зависит от языка,
  /// а контроллер строит прогресс без `BuildContext`. UI рендерит её через
  /// `outboundVariantLabel` (`core/i18n/enum_labels.dart`).
  final OutboundVariant variant;
  final Map<ProbeService, ProbeState> services;
  AutoConfigProgress({
    required this.index,
    required this.total,
    required this.candidateName,
    required this.variant,
    required this.services,
  });
}

class CandidateResult {
  final VpnServer server;
  final OutboundVariant variant;
  final Map<ProbeService, bool> passed;
  final int? avgLatencyMs;
  CandidateResult({
    required this.server,
    required this.variant,
    required this.passed,
    this.avgLatencyMs,
  });
  int get passedCount => passed.values.where((v) => v).length;
}

class AutoConfigResult {
  final VpnServer server;
  final OutboundVariant variant;
  final CandidateResult detail;
  final DateTime? measuredAt;

  /// #3.1 — задержка, измеренная тем же методом, что и обычный пинг (TCP/ICMP из настроек).
  /// Не путать с [CandidateResult.avgLatencyMs] — там среднее RTT proxy-проб (GET).
  final PingResult? ping;

  /// Скорость скачивания через этот сервер, Мбит/с. null — не замеряли.
  final double? mbps;

  /// Какую долю СВОЕГО канала даёт сервер, в процентах. Без этого числа голая
  /// скорость ни о чём не говорит: 60 Мбит/с — это прекрасно на канале 60 и
  /// скверно на канале 300.
  final int? sharePercent;

  AutoConfigResult({
    required this.server,
    required this.variant,
    required this.detail,
    this.measuredAt,
    this.ping,
    this.mbps,
    this.sharePercent,
  });

  AutoConfigResult withSpeed({double? mbps, int? sharePercent}) =>
      AutoConfigResult(
        server: server,
        variant: variant,
        detail: detail,
        measuredAt: measuredAt,
        ping: ping,
        mbps: mbps,
        sharePercent: sharePercent,
      );

  Map<String, dynamic> toJson() => {
        'server': server.rawLink,
        'variant': variant.toJson(),
        'passed': {
          for (final e in detail.passed.entries) e.key.name: e.value,
        },
        'avgLatencyMs': detail.avgLatencyMs,
        'measuredAt': measuredAt?.toIso8601String(),
        if (ping != null) 'ping': ping!.toJson(),
        // ⚠️ Замер скорости стоит трафика ПОДПИСКИ (5 МБ на сервер). Не сохранив
        // его, мы теряли бы результат при первом же перезапуске, и пользователь
        // платил бы за него заново. Это тот самый класс багов «поле пишется, но
        // не читается», который компилятор не ловит.
        if (mbps != null) 'mbps': mbps,
        if (sharePercent != null) 'sharePercent': sharePercent,
      };

  static AutoConfigResult? fromJson(Map<String, dynamic> j) {
    final server = ShareLinkParser.tryParse(j['server'] as String? ?? '');
    if (server == null) return null;
    final variant = OutboundVariant.fromJson(
        (j['variant'] as Map?)?.cast<String, dynamic>() ?? const {});
    final passed = <ProbeService, bool>{};
    ((j['passed'] as Map?) ?? const {}).forEach((k, v) {
      final s = ProbeService.values
          .firstWhere((e) => e.name == k, orElse: () => ProbeService.youtube);
      passed[s] = v == true;
    });
    final detail = CandidateResult(
      server: server,
      variant: variant,
      passed: passed,
      avgLatencyMs: (j['avgLatencyMs'] as num?)?.toInt(),
    );
    return AutoConfigResult(
      mbps: (j['mbps'] as num?)?.toDouble(),
      sharePercent: (j['sharePercent'] as num?)?.toInt(),
      server: server,
      variant: variant,
      detail: detail,
      measuredAt:
          j['measuredAt'] != null ? DateTime.tryParse('${j['measuredAt']}') : null,
      ping: j['ping'] is Map
          ? PingResult.fromJson((j['ping'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

class _Candidate {
  final VpnServer server;
  final OutboundVariant variant;
  _Candidate(this.server, this.variant);
}

/// Перебирает кандидатов (сервер × вариация обхода), проверяя сервисы через проброс-харнесс.
/// Не включает системный прокси. Возвращает первый прошедший (firstMatch) или лучший за бюджет.
class AutoConfigEngine {
  final ProbeHarness Function() _harnessFactory;

  AutoConfigEngine({
    ProbeHarness Function()? harnessFactory,
  }) : _harnessFactory = harnessFactory ?? _mustProvide;

  static ProbeHarness _mustProvide() =>
      throw StateError('harnessFactory не задан');

  /// Перебирает ВСЕ кандидаты (не останавливается на первом рабочем), эмитит каждую
  /// найденную рабочую связку через [onFound] и возвращает полный список (отсортированный:
  /// больше пройденных сервисов → меньше задержка).
  /// Широкий набор вариаций для «умного подбора» по одному ключу: перебор fingerprint × fragment.
  static List<OutboundVariant> deepVariants() {
    const fps = ['chrome', 'firefox', 'safari', 'edge', 'ios', 'android', 'randomized'];
    final list = <OutboundVariant>[
      OutboundVariant.none,
      const OutboundVariant(fragment: true),
    ];
    for (final fp in fps) {
      list.add(OutboundVariant(fingerprint: fp));
      list.add(OutboundVariant(fingerprint: fp, fragment: true));
    }
    return list;
  }

  Future<List<AutoConfigResult>> run({
    required List<VpnServer> servers,
    required AppSettings settings,
    required CancelToken cancel,
    List<OutboundVariant>? variantsOverride,
    void Function(int index, int total, VpnServer server, OutboundVariant variant)?
        onCandidate,
    void Function(ProbeService service, bool ok)? onService,
    void Function(AutoConfigResult found)? onFound,
    void Function(String message)? onSpeed,
  }) async {
    final variants = variantsOverride ?? _buildVariants(settings);
    final candidates = <_Candidate>[
      for (final s in servers)
        // Вариации (fragment/fingerprint) — приёмы Xray поверх TLS-рукопожатия.
        // У hysteria2 транспорт QUIC и своё ядро, перебирать там нечего:
        // такой сервер проверяем один раз «как есть».
        if (s.core == ProxyCore.singbox)
          _Candidate(s, OutboundVariant.none)
        else
          for (final v in variants) _Candidate(s, v),
    ];
    final endpoints = AutoConfigCatalog.endpointsFor(settings.autoConfigServices);
    final deadline =
        DateTime.now().add(Duration(seconds: settings.autoConfigBudgetSec));

    final found = <AutoConfigResult>[];

    // Серверы, для которых рабочая вариация уже найдена.
    //
    // ⚠️ Без этого один сервер попадал в результаты СТОЛЬКО РАЗ, сколько у него
    // прошло вариаций (обычная + fragment + отпечатки — до четырёх). Владелец
    // видел это как «сервер отображается по несколько раз». Со включённым
    // замером скорости беда удваивалась: тремя «лучшими» кандидатами могли
    // оказаться три вариации ОДНОГО сервера, и 15 МБ трафика уходили на замер
    // одного и того же канала вместо сравнения разных серверов.
    //
    // Смысл вариаций — найти ту, что работает; когда она нашлась, остальные не
    // добавляют ничего, кроме времени перебора. Кандидаты идут сгруппированными
    // по серверу, поэтому пропуск оставшихся — заодно и заметное ускорение.
    final solved = <String>{};

    for (var i = 0; i < candidates.length; i++) {
      cancel.throwIfCancelled();
      // «Мягкий» бюджет только для стратегии bestWithinBudget; иначе сканируем всё.
      if (settings.strategy == AutoConfigStrategy.bestWithinBudget &&
          DateTime.now().isAfter(deadline)) {
        break;
      }

      final c = candidates[i];
      if (solved.contains(c.server.key)) continue;
      onCandidate?.call(i, candidates.length, c.server, c.variant);

      // Харнесс может не подняться (нет sing-box.exe, битый узел, занятый порт).
      // Раньше это обрывало ВЕСЬ прогон на середине; теперь кандидат просто
      // считается непрошедшим, и перебор идёт дальше.
      final HarnessHandle handle;
      try {
        handle = await _harnessFactory().start(
            [HarnessEntry(key: 'ac', server: c.server, variant: c.variant)]);
      } on CancelledException {
        rethrow;
      } catch (e) {
        AppLog.w('Автонастройка: ${c.server.displayName} '
            '(${c.variant.label}) пропущен — $e');
        continue;
      }
      final port = handle.proxyPortFor(0);
      if (port <= 0) {
        // Второе ядро не поднялось — проверять нечем.
        await handle.stop();
        continue;
      }

      final passed = <ProbeService, bool>{};
      final latencies = <int>[];
      try {
        for (final ep in endpoints) {
          cancel.throwIfCancelled();
          final r = await ProxyProbe.check(
            port,
            ep.url,
            head: ep.head,
            timeout: Duration(milliseconds: settings.pingTimeoutMs),
            validator: ep.validator,
          );
          passed[ep.service] = r.ok;
          if (r.ok && r.rttMs != null) latencies.add(r.rttMs!);
          onService?.call(ep.service, r.ok);
        }
      } finally {
        await handle.stop();
      }

      final passedCount = passed.values.where((v) => v).length;
      final avg = latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a + b) ~/ latencies.length;
      final detail = CandidateResult(
          server: c.server, variant: c.variant, passed: passed, avgLatencyMs: avg);

      if (passedCount >= settings.requiredServices) {
        // Сервер уже подтверждён рабочим (сервисы прошли). Показываем, как везде,
        // задержку TCP; hysteria2 без TCP — средний RTT проб.
        PingResult? ping;
        try {
          if (c.server.protocol == 'hysteria2') {
            ping = PingResult(
              outcome: PingOutcome.ok,
              latencyMs: avg,
              proxyRttMs: avg,
              working: true,
              reachableViaProxy: true,
              latencyMethod: PingMethod.proxyGet,
              measuredAt: DateTime.now(),
            );
          } else {
            final tcp = await TcpPing.measure(
                c.server.address, c.server.port,
                timeout: Duration(milliseconds: settings.pingTimeoutMs));
            final tcpOk = tcp.outcome == PingOutcome.ok;
            // Показываем TCP или НИЧЕГО. Подставлять сюда прокси-RTT нельзя: на
            // экране он не отличим от TCP, а цифры разной природы. Сервер и так
            // помечен рабочим (сервисы прошли) — цвет это покажет и без числа.
            ping = PingResult(
              outcome: PingOutcome.ok,
              latencyMs: tcpOk ? tcp.latencyMs : null,
              proxyRttMs: avg,
              working: true,
              reachableViaProxy: true,
              latencyMethod: tcpOk ? PingMethod.tcp : PingMethod.proxyGet,
              measuredAt: DateTime.now(),
            );
          }
        } catch (_) {}
        final result = AutoConfigResult(
          server: c.server,
          variant: c.variant,
          detail: detail,
          measuredAt: DateTime.now(),
          ping: ping,
        );
        found.add(result);
        solved.add(c.server.key);
        onFound?.call(result);
      }
    }

    found.sort((a, b) {
      final c = b.detail.passedCount.compareTo(a.detail.passedCount);
      if (c != 0) return c;
      return (a.detail.avgLatencyMs ?? (1 << 30))
          .compareTo(b.detail.avgLatencyMs ?? (1 << 30));
    });

    if (settings.speedInAutoSelect && found.isNotEmpty) {
      return _rankBySpeed(found, cancel, onSpeed: onSpeed);
    }
    return found;
  }

  /// Сколько кандидатов реально замеряем.
  ///
  /// Замер стоит трафика ПОДПИСКИ, и это не абстракция: 5 МБ на сервер, плюс
  /// 5 МБ на собственный канал. Мерить сотню серверов означало бы полгигабайта
  /// и минуты ожидания ради выбора, который на 90 % уже сделан отбором по
  /// сервисам и задержке. Трёх лучших достаточно, чтобы развести «быстрый, но
  /// далёкий» и «близкий, но узкий» — а именно этот выбор и не даётся пингу.
  static const _speedTopN = 3;

  /// Пересортировать лучших с учётом скорости.
  ///
  /// Своя скорость меряется ОДИН раз и мимо VPN — иначе не с чем сравнивать:
  /// «60 Мбит/с» это отлично на канале 60 и скверно на канале 300.
  Future<List<AutoConfigResult>> _rankBySpeed(
    List<AutoConfigResult> found,
    CancelToken cancel, {
    void Function(String message)? onSpeed,
  }) async {
    // Размер задан владельцем: всегда 5 МБ, независимо от настройки замера
    // скорости на экране сервера. Там пользователь выбирает точность для
    // ОДНОГО сервера, здесь мы гоняем несколько подряд и платим трафиком.
    const size = SpeedTestSize.light;
    onSpeed?.call('Замеряю скорость своего канала…');
    final own = await SpeedTest.download(size: size);
    final ownMbps = own.ok ? own.bitsPerSecond / 1000000 : null;
    AppLog.i('Автонастройка: свой канал '
        '${ownMbps == null ? "замерить не удалось" : "${ownMbps.toStringAsFixed(1)} Мбит/с"}');

    final top = found.take(_speedTopN).toList();
    final measured = <AutoConfigResult>[];
    for (var i = 0; i < top.length; i++) {
      cancel.throwIfCancelled();
      final r = top[i];
      onSpeed?.call('Замеряю скорость: ${r.server.displayName} '
          '(${i + 1} из ${top.length})');
      double? mbps;
      try {
        final handle = await _harnessFactory()
            .start([HarnessEntry(key: 'sp', server: r.server, variant: r.variant)]);
        try {
          final port = handle.proxyPortFor(0);
          if (port > 0) {
            final res = await SpeedTest.download(size: size, proxyPort: port);
            if (res.ok) mbps = res.bitsPerSecond / 1000000;
          }
        } finally {
          await handle.stop();
        }
      } on CancelledException {
        rethrow;
      } catch (e) {
        AppLog.w('Автонастройка: скорость ${r.server.displayName} не замерена — $e');
      }
      measured.add(r.withSpeed(
        mbps: mbps,
        sharePercent:
            SpeedScore.sharePercent(serverMbps: mbps, ownMbps: ownMbps),
      ));
    }

    // Опорная величина, когда свой канал замерить не вышло: лучший из серверов.
    final best = measured
        .map((e) => e.mbps ?? 0)
        .fold<double>(0, (a, b) => b > a ? b : a);
    measured.sort((a, b) => SpeedScore.of(
          serverMbps: b.mbps,
          ownMbps: ownMbps,
          latencyMs: b.detail.avgLatencyMs,
          bestServerMbps: best,
        ).compareTo(SpeedScore.of(
          serverMbps: a.mbps,
          ownMbps: ownMbps,
          latencyMs: a.detail.avgLatencyMs,
          bestServerMbps: best,
        )));

    // Остальные идут следом в прежнем порядке: их не мерили, и делать вид, что
    // мы про них что-то знаем, нельзя.
    return [...measured, ...found.skip(_speedTopN)];
  }

  /// Порядок: сначала «обычный», затем fragment, затем варианты fingerprint.
  List<OutboundVariant> _buildVariants(AppSettings settings) {
    final variants = <OutboundVariant>[OutboundVariant.none];
    if (settings.tryFragment) {
      variants.add(const OutboundVariant(fragment: true));
    }
    for (final fp in settings.fingerprints) {
      if (fp == 'chrome') continue; // обычно уже дефолт сервера
      variants.add(OutboundVariant(fingerprint: fp));
    }
    return variants;
  }
}
