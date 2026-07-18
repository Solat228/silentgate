import '../settings/app_settings.dart';

enum PingOutcome { untested, testing, ok, failed, timeout }

/// Результат пинга сервера.
///
/// Модель проверки: сначала **TCP** до адреса сервера (быстро, без ядра); кто не
/// ответил — «мёртв» и дальше не проверяется. Кто ответил — верифицируется через
/// **GET/HEAD** (по настройке), это и отделяет «по-настоящему рабочие» сервера от
/// тех, что просто отвечают на TCP, но трафик не проксируют (типично для Reality).
///
/// **Показываем везде только [latencyMs] — задержку TCP.** Никакой второй цифры
/// «через прокси»: результат GET/HEAD — это флаг [working] (рабочий/нет), а не
/// величина. Исключение — hysteria2: у него нет TCP (QUIC/UDP), там [latencyMs]
/// приходит из пробы через прокси, иначе показать было бы нечего.
class PingResult {
  final PingOutcome outcome;
  final int? latencyMs; // задержка TCP (для hysteria2 — через прокси)
  final int? proxyRttMs; // RTT пробы GET/HEAD, для диагностики
  final double? lossPct; // потери (ICMP)
  final bool reachableViaProxy; // прошла ли проба GET/HEAD

  /// Сервер **по-настоящему рабочий**: ответил по TCP И прошёл GET/HEAD.
  /// Когда двухфазная проверка выключена — рабочим считается любой TCP-ответивший.
  /// Влияет только на цвет/пометку; показываемая цифра всегда TCP.
  final bool working;

  final PingMethod? latencyMethod;
  final DateTime? measuredAt;

  const PingResult({
    this.outcome = PingOutcome.untested,
    this.latencyMs,
    this.proxyRttMs,
    this.lossPct,
    this.reachableViaProxy = false,
    this.working = true,
    this.latencyMethod,
    this.measuredAt,
  });

  static const untested = PingResult();
  static const testing = PingResult(outcome: PingOutcome.testing);

  /// Достижим (ответил по TCP либо, для hysteria2, по прокси).
  bool get isOk => outcome == PingOutcome.ok;

  /// Достижим И проверен как рабочий.
  bool get isWorking => outcome == PingOutcome.ok && working;

  /// Терминальные результаты (имеет смысл сохранять).
  bool get isTerminal =>
      outcome == PingOutcome.ok ||
      outcome == PingOutcome.failed ||
      outcome == PingOutcome.timeout;

  Map<String, dynamic> toJson() => {
        'outcome': outcome.name,
        'latencyMs': latencyMs,
        'proxyRttMs': proxyRttMs,
        'lossPct': lossPct,
        'reachableViaProxy': reachableViaProxy,
        'working': working,
        'latencyMethod': latencyMethod?.name,
        'measuredAt': measuredAt?.toIso8601String(),
      };

  factory PingResult.fromJson(Map<String, dynamic> j) {
    PingMethod? lm;
    final lmName = j['latencyMethod'];
    if (lmName != null) {
      lm = PingMethod.values.firstWhere((m) => m.name == lmName,
          orElse: () => PingMethod.tcp);
    }
    return PingResult(
      outcome: PingOutcome.values.firstWhere((o) => o.name == j['outcome'],
          orElse: () => PingOutcome.untested),
      latencyMs: (j['latencyMs'] as num?)?.toInt(),
      proxyRttMs: (j['proxyRttMs'] as num?)?.toInt(),
      lossPct: (j['lossPct'] as num?)?.toDouble(),
      reachableViaProxy: j['reachableViaProxy'] as bool? ?? false,
      working: j['working'] as bool? ?? true,
      latencyMethod: lm,
      measuredAt:
          j['measuredAt'] != null ? DateTime.tryParse('${j['measuredAt']}') : null,
    );
  }
}
