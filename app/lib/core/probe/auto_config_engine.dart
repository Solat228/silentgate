import 'package:flutter/foundation.dart' show visibleForTesting;

import 'service_check.dart';
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
    // ⚠️ Проверяем ВИДЕО-CDN, а не сайт.
    //
    // Владелец: «страница ютуба открывается, но видео не грузятся». Так и есть:
    // в России режут не www.youtube.com, а googlevideo.com — CDN, с которого
    // идёт само видео. Проверка сайта показывала зелёный там, где смотреть
    // нельзя, то есть врала ровно в том случае, ради которого её включают.
    //
    // 404 на /videoplayback без параметров — НОРМАЛЬНЫЙ ответ живого CDN:
    // запрос дошёл и был разобран. Значимо, что хост отвечает по существу, а не
    // код ответа.
    //
    // ⚠️ ЧЕГО ЭТА ПРОВЕРКА НЕ ВИДИТ — и это предел метода, а не недоделка.
    // В России YouTube чаще не блокируют, а ЗАМЕДЛЯЮТ: CDN отвечает нормально,
    // но полосу режут до непригодной для видео. Отличить это лёгкой пробой
    // нельзя — у всех доступных путей googlevideo тела ответов 26–220 байт
    // (замерено живьём), мерить скорость не на чем. Настоящий адрес видео
    // требует расшифровки подписи ссылки: механизм уровня yt-dlp, который
    // ломается каждые пару месяцев. Решением владельца такой ценой точность не
    // покупаем — вместо этого подсказка у чипа говорит об этом прямо.
    ProbeService.youtube: ProbeEndpoint(
      ProbeService.youtube,
      'https://redirector.googlevideo.com/videoplayback',
      _googlevideoAlive,
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
    // ⚠️ Telegram проверяется ДОЗВОНОМ ДО ДАТА-ЦЕНТРА, а не веб-версией.
    //
    // Владелец: «в телеграм не открывается десктопное приложение и на телефоне
    // тоже». Приложение говорит с дата-центрами по MTProto, и блокируют именно
    // их адреса; web.telegram.org при этом продолжает открываться, потому что
    // это обычный сайт на другом хостинге. Проверка веб-версии показывала
    // зелёный ровно тогда, когда мессенджер не работал.
    //
    // Адрес — DC2 (Амстердам), самый нагруженный и стабильный. Проверка идёт
    // методом CONNECT: по HTTP этот адрес не отвечает вовсе, и обычный запрос
    // провалился бы на сертификате при живом канале.
    ProbeService.telegram: ProbeEndpoint(
      ProbeService.telegram,
      'tcp://149.154.167.51:443',
      _alwaysOk,
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

  /// Живой ли видео-CDN YouTube.
  ///
  /// Без параметров `/videoplayback` отвечает 404 — это ответ ПО СУЩЕСТВУ:
  /// запрос дошёл, сервер его разобрал. Заглушка провайдера обычно отдаёт 200 с
  /// HTML, поэтому 200 с телом тут как раз подозрителен.
  static bool _googlevideoAlive(int code, String body) =>
      code == 404 || code == 200 && body.length < 512;

  /// Для проб, где сам факт установленного соединения и есть ответ (CONNECT).
  static bool _alwaysOk(int code, String body) => true;

  static bool _is204(int code, String body) => code == 204;
  static bool _cfTrace(int code, String body) =>
      code == 200 && body.contains('fl=') && body.contains('loc=');
  static bool _discordGateway(int code, String body) =>
      code == 200 && body.contains('wss://');
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

/// Чем прогон занят прямо сейчас.
///
/// ⚠️ ЗАВЕДЕНО ИЗ-ЗА ДЕФЕКТА: фаза замера скорости о себе НЕ ОТЧИТЫВАЛАСЬ.
/// `_rankBySpeed` не звал `onCandidate` ни разу, поэтому прогресс замирал на
/// последнем проверенном кандидате и десятки секунд показывал «тестирую X»,
/// хотя шёл совсем другой этап. Без явной фазы отличить одно от другого в
/// интерфейсе нечем: числа `index/total` у обоих этапов свои.
enum AutoConfigPhase {
  /// Перебор кандидатов (сервер × вариация) с проверкой сервисов.
  probing,

  /// Замер скорости лучших (и собственного канала).
  speed,
}

class AutoConfigProgress {
  final int index;
  final int total;
  final String candidateName;

  /// Ключ сервера, который проверяется сейчас. Нужен экрану, чтобы подсветить
  /// текущего кандидата ПРЯМО В СПИСКЕ: сравнивать по имени нельзя — имена в
  /// подписке повторяются, а ключ уникален.
  final String candidateKey;

  /// Вариация как ДАННЫЕ, а не готовая строка: подпись зависит от языка,
  /// а контроллер строит прогресс без `BuildContext`. UI рендерит её через
  /// `outboundVariantLabel` (`core/i18n/enum_labels.dart`).
  final OutboundVariant variant;
  final Map<ProbeService, ProbeState> services;

  /// Этап прогона. Умолчание — перебор: так старый код, который про фазы не
  /// знает, продолжает работать как раньше.
  final AutoConfigPhase phase;

  AutoConfigProgress({
    required this.index,
    required this.total,
    required this.candidateName,
    required this.variant,
    required this.services,
    this.candidateKey = '',
    this.phase = AutoConfigPhase.probing,
  });
}

class CandidateResult {
  final VpnServer server;
  final OutboundVariant variant;
  final Map<ProbeService, bool> passed;
  final int? avgLatencyMs;

  /// Сервисы, которые ОТКРЫЛИСЬ, но недоступны в стране выхода этого сервера
  /// (ChatGPT отвечает `unsupported_country`, Claude/Gemini — 451).
  ///
  /// ⚠️ ЗАЧЕМ ОТДЕЛЬНОЕ ПОЛЕ, А НЕ ПРОСТО `passed = false`. Такой сервер
  /// исправен: канал живой, всё остальное через него работает. Выкинуть его из
  /// результатов значило бы потерять годный сервер из-за одной мишени. Поэтому
  /// он остаётся в списке, но опускается в сортировке — и, главное, человек
  /// видит ПРИЧИНУ, а не молчаливое понижение.
  ///
  /// ⚠️ И почему до 17.08.2026 этого поля не было вовсе: автонастройка звала
  /// `ServiceChecker.probeEndpoint` напрямую, а гео-проба живёт в
  /// `ServiceChecker.check` — то есть подбор о гео НЕ ЗНАЛ. Сервер, на котором
  /// ChatGPT отвечает «недоступно в вашей стране», засчитывался как полностью
  /// прошедший, и автонастройка честно предлагала его тому, кто искал ChatGPT.
  final Set<ProbeService> geoBlocked;

  CandidateResult({
    required this.server,
    required this.variant,
    required this.passed,
    this.avgLatencyMs,
    this.geoBlocked = const {},
  });

  /// Сколько мишеней прошло. Геоблок сюда ВХОДИТ: сервер рабочий, и по порогу
  /// [AppSettings.requiredServices] он проходит — понижается только сортировкой.
  int get passedCount => passed.values.where((v) => v).length;

  /// Сколько мишеней прошло «начисто», без гео-оговорок.
  int get cleanCount => passed.entries
      .where((e) => e.value && !geoBlocked.contains(e.key))
      .length;
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
        // Без сохранения пометка гео терялась бы при перезапуске, и сервер,
        // однажды опознанный как «жив, но ChatGPT недоступен», снова выглядел
        // бы безупречным — ровно тот класс «поле пишется, но не читается».
        'geoBlocked': detail.geoBlocked.map((s) => s.name).toList(),
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
    final geo = <ProbeService>{
      for (final n in (j['geoBlocked'] as List?) ?? const [])
        ProbeService.values
            .firstWhere((e) => e.name == n, orElse: () => ProbeService.youtube),
    };
    final detail = CandidateResult(
      server: server,
      variant: variant,
      passed: passed,
      avgLatencyMs: (j['avgLatencyMs'] as num?)?.toInt(),
      geoBlocked: geo,
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
/// Подбор невозможен на этой платформе: харнесс не умеет пропускать
/// произвольные запросы через кандидата (см. [ProbeHarness.supportsProxyRequests]).
class AutoConfigUnsupported implements Exception {
  const AutoConfigUnsupported();
  @override
  String toString() => 'AutoConfigUnsupported';
}

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
  /// Чем меряется TCP в фазе 1.
  ///
  /// ⚠️ ПОДМЕНЯЕМО РАДИ ТЕСТОВ, И ЭТО НЕ УДОБСТВО, А НЕОБХОДИМОСТЬ. Фаза 1
  /// отсеивает серверы, не ответившие по TCP, — а в тестах серверы выдуманные и
  /// не отвечают в принципе. Без подмены отсев съедал бы ВСЕХ, и ни одна
  /// следующая фаза не проверялась бы вовсе: тесты перебора вариаций зеленели
  /// бы, ничего не перебрав. Боевое значение задаётся здесь и в приложении не
  /// меняется никогда.
  @visibleForTesting
  static Future<PingResult> Function(String host, int port, Duration timeout)
      tcpProbe = (host, port, timeout) =>
          TcpPing.measure(host, port, timeout: timeout);

  /// Прогнать [items] через [job], держа не более [limit] штук одновременно.
  ///
  /// ⚠️ ИМЕННО ПУЛ, А НЕ `Future.wait` ПО ВСЕМУ СПИСКУ. Каждая задача здесь —
  /// это поднятое ядро со своим локальным портом; запустить их сотней разом
  /// значило бы сотню процессов, исчерпание портов и замеры задержки, которые
  /// врут друг из-за друга. Потолок задаётся настройкой, и **1 возвращает
  /// прежнее поведение — строго по очереди**.
  ///
  /// Отмена: `job` бросает `CancelledException`, она поднимается наружу через
  /// `Future.wait`; оставшиеся работники упрутся в ту же проверку и завершатся.
  static Future<void> _pooled<T>(
    List<T> items,
    int limit,
    Future<void> Function(T item) job,
  ) async {
    if (items.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        await job(items[i]);
      }
    }

    final workers = limit < 1 ? 1 : (limit > items.length ? items.length : limit);
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

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
    // ⚠️ Отдельный отчёт фазы скорости, а не переиспользование [onCandidate]:
    // у этой фазы своя нумерация (три лучших, а не сотня кандидатов) и свой
    // текст. Без него прогресс замирал на последнем кандидате перебора и
    // десятки секунд показывал неправду.
    //
    // `server == null` — замер СВОЕГО канала: он идёт мимо VPN и ни к какому
    // серверу не относится, но занимает столько же времени, сколько один
    // сервер, и молчать о нём значило бы снова показывать застывший экран.
    void Function(int index, int total, VpnServer? server,
            OutboundVariant variant)?
        onSpeedCandidate,
    // ⚠️ Итог TCP-фазы по КАЖДОМУ серверу, а не только по найденным.
    // Фаза 1 меряет ровно то же, что обычный пинг, — не отдать эти цифры на
    // главный экран значило бы заставить человека пинговать второй раз то, за
    // что он уже заплатил ожиданием.
    void Function(VpnServer server, PingResult ping)? onPing,
    // ⚠️ Пара к [onCandidate], и она нужна ровно из-за параллельности.
    // Пока кандидат был один, «текущий» и «последний начатый» — одно и то же.
    // При трёх одновременно подсветка одного кандидата стала бы враньём:
    // проверяются три, а показан тот, кто начался последним.
    void Function(VpnServer server)? onCandidateDone,
  }) async {
    // ⚠️ Подбор ПРОВЕРЯЕТ ДОСТУПНОСТЬ СЕРВИСОВ через кандидата, а для этого
    // нужен порт, в который можно послать произвольный запрос. Там, где
    // платформа меряет сама и порта не даёт (Android: `LibXray.ping`), проверять
    // нечем — и раньше каждый кандидат молча уходил в `continue` по условию
    // `port <= 0`. Пользователь видел ход по всем серверам × вариациям и
    // «найдено 0» на полностью рабочей подписке, а в логе не было ни строчки.
    // Честный отказ лучше молчаливого нуля: он хотя бы объясним.
    if (!_harnessFactory().supportsProxyRequests) {
      AppLog.w('Автонастройка: на этой платформе замер даёт только задержку, '
          'а подбор проверяет доступность сервисов через сам сервер. '
          'Проверять нечем — прогон не начат.');
      throw const AutoConfigUnsupported();
    }
    final variants = variantsOverride ?? _buildVariants(settings);
    final endpoints = AutoConfigCatalog.endpointsFor(settings.autoConfigServices);
    final deadline =
        DateTime.now().add(Duration(seconds: settings.autoConfigBudgetSec));

    // ── ФАЗА 1: TCP ПО ВСЕМ СЕРВЕРАМ ─────────────────────────────────────────
    //
    // ⚠️ РАДИ ЧЕГО ОНА ПОЯВИЛАСЬ. Раньше перебор шёл сразу к делу: на КАЖДОГО
    // кандидата поднималось отдельное ядро, и только потом выяснялось, что
    // сервер вообще мёртв. При сотне серверов и четырёх вариациях это сотни
    // запусков ядра подряд ради того, что дешёвый TCP-коннект отсеивает за
    // миллисекунды. Порядок теперь тот же, что у обычного пинга: сперва TCP до
    // всех, потом дорогая проверка — но только по выжившим.
    final limit = settings.effectiveAutoConfigConcurrency;
    final aliveServers = <VpnServer>[];
    final tcpPings = <String, PingResult>{};
    var tcpDone = 0;
    await _pooled(servers, settings.pingConcurrency, (s) async {
      cancel.throwIfCancelled();
      // ⚠️ У hysteria2 транспорт QUIC — TCP там нет по определению, и «не
      // ответил» было бы враньём. Такой сервер идёт дальше без отсева.
      if (s.protocol == 'hysteria2' || s.core == ProxyCore.singbox) {
        aliveServers.add(s);
        return;
      }
      PingResult ping;
      try {
        final tcp = await tcpProbe(s.address, s.port,
            Duration(milliseconds: settings.pingTimeoutMs));
        final ok = tcp.outcome == PingOutcome.ok;
        if (ok) aliveServers.add(s);
        ping = PingResult(
          outcome: tcp.outcome,
          latencyMs: ok ? tcp.latencyMs : null,
          // ⚠️ `working` здесь НЕ ставится по TCP-ответу: рабочим сервер
          // считается только после проверки сервисов (фаза 2). Ответивший
          // порт ещё ничего не проксирует — этот же урок уже записан у
          // обычного пинга.
          working: false,
          latencyMethod: PingMethod.tcp,
          measuredAt: DateTime.now(),
        );
      } catch (_) {
        ping = PingResult(
          outcome: PingOutcome.failed,
          working: false,
          measuredAt: DateTime.now(),
        );
      }
      tcpDone++;
      tcpPings[s.key] = ping;
      onPing?.call(s, ping);
    });
    cancel.throwIfCancelled();
    AppLog.i('Автонастройка: TCP-отсев — из ${servers.length} серверов '
        'отвечают ${aliveServers.length}, проверено $tcpDone');

    // ── ФАЗЫ 2–3: проверка сервисов у выживших ───────────────────────────────
    //
    // Фаза 2 — базовая вариация («как есть») по всем выжившим. Фаза 3 —
    // остальные вариации, и ТОЛЬКО для тех, кто базовую не прошёл: смысл
    // вариаций в том, чтобы вытащить сервер, который сам по себе не отвечает
    // внятно, а на прошедшем они не добавляют ничего, кроме времени перебора.
    final base = <_Candidate>[
      for (final s in aliveServers) _Candidate(s, OutboundVariant.none),
    ];
    final extra = <_Candidate>[
      for (final s in aliveServers)
        if (s.core != ProxyCore.singbox)
          for (final v in variants)
            if (v != OutboundVariant.none) _Candidate(s, v),
    ];

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

    var done = 0;
    var total = base.length;

    Future<void> probeBody(_Candidate c) async {
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
        done++;
        AppLog.w('Автонастройка: ${c.server.displayName} '
            '(${c.variant.label}) пропущен — $e');
        return;
      }
      final port = handle.proxyPortFor(0);
      if (port <= 0) {
        // Второе ядро не поднялось — проверять нечем.
        done++;
        await handle.stop();
        return;
      }

      final passed = <ProbeService, bool>{};
      final geoBlocked = <ProbeService>{};
      final latencies = <int>[];
      try {
        for (final ep in endpoints) {
          cancel.throwIfCancelled();
          // ⚠️ Способ проверки выбирает ОБЩИЙ код (`ServiceChecker.probeEndpoint`),
          // тот же, что у сервис-чипов. Раньше здесь стоял прямой вызов
          // `ProxyProbe.check`, и мишень Telegram (`tcp://…`) уходила в
          // HTTP-клиент как обычный адрес — она падала ВСЕГДА, при любом
          // сервере, а Telegram входит в набор по умолчанию.
          //
          // Креды харнесса обязательны: без них 407 на КАЖДОМ кандидате и
          // «найдено 0» на полностью исправной подписке.
          final r = await ServiceChecker.probeEndpoint(
            port,
            ep,
            timeout: Duration(milliseconds: settings.pingTimeoutMs),
            proxyUser: handle.proxyUser,
            proxyPassword: handle.proxyPassword,
          );
          passed[ep.service] = r.ok;
          if (r.ok && r.rttMs != null) latencies.add(r.rttMs!);

          // ⚠️ ГЕО-ПРОБА, КОТОРОЙ ЗДЕСЬ НЕ БЫЛО ВОВСЕ (найдено 17.08.2026).
          // Она жила только в `ServiceChecker.check` — то есть у чипов на
          // главном экране. Автонастройка о гео не знала, и сервер, на котором
          // ChatGPT отвечает «недоступно в вашей стране», засчитывался как
          // полностью прошедший — и предлагался тому, кто искал именно ChatGPT.
          //
          // Креды харнесса обязательны и тут: у чипов проба идёт по ЖИВОМУ
          // ядру, где креды опубликованы статикой `ProxyProbe`, а харнесс —
          // отдельное ядро со своим паролем.
          if (r.ok) {
            final geo = AutoConfigCatalog.geoEndpointFor(ep.service);
            if (geo != null) {
              final g = await ProxyProbe.check(
                port,
                geo.url,
                validator: geo.blocked,
                timeout: Duration(milliseconds: settings.pingTimeoutMs),
                proxyUser: handle.proxyUser,
                proxyPassword: handle.proxyPassword,
              );
              // validator == geo.blocked: ok==true ⇒ сервис закрыт в регионе.
              if (g.ok) geoBlocked.add(ep.service);
            }
          }
          onService?.call(ep.service, r.ok);
        }
      } finally {
        await handle.stop();
      }
      done++;

      final passedCount = passed.values.where((v) => v).length;
      final avg = latencies.isEmpty
          ? null
          : latencies.reduce((a, b) => a + b) ~/ latencies.length;
      final detail = CandidateResult(
        server: c.server,
        variant: c.variant,
        passed: passed,
        avgLatencyMs: avg,
        geoBlocked: geoBlocked,
      );

      if (passedCount >= settings.requiredServices) {
        // ⚠️ Проверка ПОВТОРНАЯ и обязательная: между `solved.contains` в начале
        // и этой точкой были await'ы, а кандидатов теперь несколько
        // одновременно — без неё один сервер снова попадал бы в результаты
        // столько раз, сколько его вариаций успело пройти.
        if (solved.contains(c.server.key)) return;
        solved.add(c.server.key);

        // Задержку показываем ТУ ЖЕ, что намерила фаза 1, — второй раз мерить
        // нечего. У hysteria2 TCP нет, там остаётся средний RTT проб.
        final tcp = tcpPings[c.server.key];
        final ping = PingResult(
          outcome: PingOutcome.ok,
          // Показываем TCP или НИЧЕГО. Подставлять сюда прокси-RTT нельзя: на
          // экране он не отличим от TCP, а цифры разной природы.
          latencyMs: tcp?.latencyMs ??
              (c.server.protocol == 'hysteria2' ? avg : null),
          proxyRttMs: avg,
          working: true,
          reachableViaProxy: true,
          latencyMethod:
              tcp?.latencyMs != null ? PingMethod.tcp : PingMethod.proxyGet,
          measuredAt: DateTime.now(),
        );
        final result = AutoConfigResult(
          server: c.server,
          variant: c.variant,
          detail: detail,
          measuredAt: DateTime.now(),
          ping: ping,
        );
        found.add(result);
        onFound?.call(result);
      }
    }

    Future<void> probe(_Candidate c) async {
      cancel.throwIfCancelled();
      // «Мягкий» бюджет только для стратегии bestWithinBudget; иначе сканируем всё.
      if (settings.strategy == AutoConfigStrategy.bestWithinBudget &&
          DateTime.now().isAfter(deadline)) {
        return;
      }
      if (solved.contains(c.server.key)) return;
      onCandidate?.call(done, total, c.server, c.variant);
      // Отметка о завершении — в `finally`, чтобы срабатывать на ЛЮБОМ выходе
      // (отказ харнесса, отсутствие порта, отмена). Иначе кандидат навсегда
      // остался бы подсвеченным как «проверяется».
      try {
        await probeBody(c);
      } finally {
        onCandidateDone?.call(c.server);
      }
    }

    // ФАЗА 2 — «как есть» по всем выжившим.
    await _pooled(base, limit, probe);
    cancel.throwIfCancelled();

    // ФАЗА 3 — вариации, только для тех, кто базовую не прошёл.
    final retry =
        extra.where((c) => !solved.contains(c.server.key)).toList(growable: false);
    if (retry.isNotEmpty) {
      total = base.length + retry.length;
      AppLog.i('Автонастройка: внятного ответа не дали '
          '${aliveServers.length - solved.length} серверов — перебираю вариации '
          '(${retry.length} проверок)');
      await _pooled(retry, limit, probe);
    }

    found.sort((a, b) {
      // ⚠️ СНАЧАЛА «ЧИСТЫЕ», ПОТОМ С ГЕОБЛОКОМ. Сервер, где ChatGPT отвечает
      // «недоступно в вашей стране», формально проходит столько же мишеней,
      // сколько безупречный, — по одному лишь `passedCount` он мог оказаться
      // первым в списке и быть предложенным как лучший.
      final clean = b.detail.cleanCount.compareTo(a.detail.cleanCount);
      if (clean != 0) return clean;
      final c = b.detail.passedCount.compareTo(a.detail.passedCount);
      if (c != 0) return c;
      return (a.detail.avgLatencyMs ?? (1 << 30))
          .compareTo(b.detail.avgLatencyMs ?? (1 << 30));
    });

    if (settings.speedInAutoSelect && found.isNotEmpty) {
      return _rankBySpeed(found, cancel,
          topN: settings.effectiveSpeedTopN,
          onSpeed: onSpeed,
          onSpeedCandidate: onSpeedCandidate);
    }
    return found;
  }

  /// Пересортировать лучших с учётом скорости.
  ///
  /// Своя скорость меряется ОДИН раз и мимо VPN — иначе не с чем сравнивать:
  /// «60 Мбит/с» это отлично на канале 60 и скверно на канале 300.
  ///
  /// ⚠️ [topN] ЗАДАЁТСЯ НАСТРОЙКОЙ, а не константой: замер стоит трафика
  /// ПОДПИСКИ (по 5 МБ на сервер плюс столько же на свой канал), и решать,
  /// сколько за него платить, должен владелец подписки. Умолчание — десять
  /// (решение владельца 17.08.2026), потолок — [AppSettings.speedTopNMax].
  Future<List<AutoConfigResult>> _rankBySpeed(
    List<AutoConfigResult> found,
    CancelToken cancel, {
    required int topN,
    void Function(String message)? onSpeed,
    void Function(int index, int total, VpnServer? server,
            OutboundVariant variant)?
        onSpeedCandidate,
  }) async {
    // Размер задан владельцем: всегда 5 МБ, независимо от настройки замера
    // скорости на экране сервера. Там пользователь выбирает точность для
    // ОДНОГО сервера, здесь мы гоняем несколько подряд и платим трафиком.
    const size = SpeedTestSize.light;
    // Шагов у фазы на один больше числа серверов: свой канал меряется первым и
    // стоит столько же. Считать его «нулевым шагом» — врать полоске прогресса.
    final steps = found.take(topN).length + 1;
    onSpeed?.call('Замеряю скорость своего канала…');
    onSpeedCandidate?.call(0, steps, null, OutboundVariant.none);
    final own = await SpeedTest.download(size: size);
    final ownMbps = own.ok ? own.bitsPerSecond / 1000000 : null;
    AppLog.i('Автонастройка: свой канал '
        '${ownMbps == null ? "замерить не удалось" : "${ownMbps.toStringAsFixed(1)} Мбит/с"}');

    final top = found.take(topN).toList();
    final measured = <AutoConfigResult>[];
    for (var i = 0; i < top.length; i++) {
      cancel.throwIfCancelled();
      final r = top[i];
      onSpeed?.call('Замеряю скорость: ${r.server.displayName} '
          '(${i + 1} из ${top.length})');
      onSpeedCandidate?.call(i + 1, steps, r.server, r.variant);
      double? mbps;
      try {
        final handle = await _harnessFactory()
            .start([HarnessEntry(key: 'sp', server: r.server, variant: r.variant)]);
        try {
          final port = handle.proxyPortFor(0);
          if (port > 0) {
            // Креды харнесса обязательны: без них 407, и скорость не
            // измеряется НИ У ОДНОГО кандидата — молча, без слова о причине.
            final res = await SpeedTest.download(
                size: size,
                proxyPort: port,
                proxyUser: handle.proxyUser,
                proxyPassword: handle.proxyPassword);
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
    return [...measured, ...found.skip(topN)];
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
