import '../settings/app_settings.dart';

enum PingOutcome { untested, testing, ok, failed, timeout }

/// Состояние проверки «сервер реально пропускает трафик» — запроса GET/HEAD
/// ЧЕРЕЗ сервер (фаза 2 пинга).
///
/// ⚠️ Раньше вместо этого был один булев `working`, и он врал в обе стороны.
/// Пинг ставил его сразу после TCP по признаку «БУДЕТ ли вообще фаза 2», а не
/// «ПРОШЛА ли она»: всё время проверки (секунды-минуты) каждый TCP-ответивший
/// сервер горел зелёным — владелец видел зелёную плашку на сервере, через
/// который не работало НИЧЕГО. Тот же флаг при выключенной двухфазности делал
/// ВСЕ серверы «нерабочими» с подписью «проверка через туннель не прошла», хотя
/// её не запускали, и итог прогона всегда был «рабочих 0 из N».
/// Одно значение на три разных смысла — поэтому состояний теперь четыре.
enum PingVerification {
  /// Проверка НЕ проводилась: двухфазность выключена, платформа её не умеет,
  /// харнесс не поднялся либо прогон отменён. Известна только достижимость.
  notRun,

  /// Проверка идёт прямо сейчас. Итога ещё нет — зелёным красить нельзя.
  pending,

  /// Запрос через сервер прошёл — сервер по-настоящему рабочий.
  passed,

  /// Запрос через сервер НЕ прошёл: порт отвечает, а трафик не идёт
  /// (типичная картина у Reality-сервера, которому закрыли выход).
  failed,
}

/// Результат пинга сервера.
///
/// Модель проверки: сначала **TCP** до адреса сервера (быстро, без ядра); кто не
/// ответил — «мёртв» и дальше не проверяется. Кто ответил — верифицируется через
/// **GET/HEAD** (по настройке), это и отделяет «по-настоящему рабочие» сервера от
/// тех, что просто отвечают на TCP, но трафик не проксируют (типично для Reality).
///
/// **Показываем везде только [latencyMs] — задержку TCP.** Никакой второй цифры
/// «через прокси»: результат GET/HEAD — это [verification] (прошла/не прошла/не
/// проводилась), а не величина. Исключение — hysteria2: у него нет TCP
/// (QUIC/UDP), там [latencyMs] приходит из пробы через прокси, иначе показать
/// было бы нечего.
class PingResult {
  final PingOutcome outcome;
  final int? latencyMs; // задержка TCP (для hysteria2 — через прокси)
  final int? proxyRttMs; // RTT пробы GET/HEAD, для диагностики
  final double? lossPct; // потери (ICMP)
  final bool reachableViaProxy; // прошла ли проба GET/HEAD

  /// Состояние проверки «трафик реально идёт». ⚠️ Это НЕ «достижим»: TCP-ответ
  /// живёт в [outcome], а сюда пишется только итог пробы через сервер.
  final PingVerification verification;

  final PingMethod? latencyMethod;
  final DateTime? measuredAt;

  /// [working] — совместимость: сохранён как ПРОИЗВОДНЫЙ параметр, потому что
  /// его пишет автонастройка (`auto_config_engine`), которая подтверждает сервер
  /// не пробой пинга, а прохождением сервисов. Новый код задаёт [verification]
  /// напрямую; задавать оба одновременно смысла нет — [verification] сильнее.
  const PingResult({
    this.outcome = PingOutcome.untested,
    this.latencyMs,
    this.proxyRttMs,
    this.lossPct,
    this.reachableViaProxy = false,
    PingVerification? verification,
    bool? working,
    this.latencyMethod,
    this.measuredAt,
  }) : verification = verification ??
            (working == null
                ? PingVerification.notRun
                : (working
                    ? PingVerification.passed
                    : PingVerification.failed));

  static const untested = PingResult();
  static const testing = PingResult(outcome: PingOutcome.testing);

  /// Проверка через сервер ПРОШЛА. ⚠️ Читается наружу (локальный API,
  /// `state/api_handlers.dart`), поэтому геттер остался — но он производный от
  /// [verification], а не отдельное поле, которое можно поставить авансом.
  bool get working => verification == PingVerification.passed;

  /// Достижим (ответил по TCP либо, для hysteria2, по прокси).
  bool get isOk => outcome == PingOutcome.ok;

  /// Достижим И подтверждён пробой через сервер.
  bool get isWorking => outcome == PingOutcome.ok && working;

  /// Достижим, но проверки через сервер НЕ было — известна только достижимость.
  /// Отдельно от [isWorking]: в итоге прогона такие серверы считаются по
  /// достижимости (иначе при выключенной двухфазности выходило «0 из N»).
  bool get isReachableUnverified =>
      outcome == PingOutcome.ok && verification == PingVerification.notRun;

  /// Есть ли смысл мерить через этот сервер скорость.
  ///
  /// ⚠️ Гейт по решению владельца: «сначала выполняется GET-пинг, и если сервер
  /// его НЕ проходит, то и скорость проверять не нужно». Замер стоит 5–20 МБ
  /// ТРАФИКА ПОДПИСКИ на сервер — платить их за узел, через который заведомо не
  /// ходит ни один запрос, значит выбрасывать деньги пользователя. Поэтому
  /// пропуск даёт только `passed`: `notRun` — это «не проверяли», а не «можно».
  bool get speedMeasurable =>
      outcome == PingOutcome.ok && verification == PingVerification.passed;

  /// Заведомо НЕ измерить: сервер не отвечает либо проверка канала провалена.
  /// Отличается от «просто не мерили» — в строке сервера на этом месте стоит
  /// прочерк с пояснением, а не пустота (пустоту человек читает как «ещё
  /// считается» и ждёт).
  bool get speedBlocked =>
      outcome == PingOutcome.failed ||
      outcome == PingOutcome.timeout ||
      verification == PingVerification.failed;

  /// Терминальные результаты (имеет смысл сохранять).
  bool get isTerminal =>
      outcome == PingOutcome.ok ||
      outcome == PingOutcome.failed ||
      outcome == PingOutcome.timeout;

  /// Тот же результат с другим состоянием проверки. Нужен там, где измерение
  /// уже сделано, а проверка не состоялась (отмена прогона, падение харнесса):
  /// цифру терять нельзя, но и выдавать её за подтверждённую — тоже.
  PingResult withVerification(PingVerification v) => PingResult(
        outcome: outcome,
        latencyMs: latencyMs,
        proxyRttMs: proxyRttMs,
        lossPct: lossPct,
        reachableViaProxy: reachableViaProxy,
        verification: v,
        latencyMethod: latencyMethod,
        measuredAt: measuredAt,
      );

  Map<String, dynamic> toJson() => {
        'outcome': outcome.name,
        'latencyMs': latencyMs,
        'proxyRttMs': proxyRttMs,
        'lossPct': lossPct,
        'reachableViaProxy': reachableViaProxy,
        'verification': verification.name,
        // Пишется РЯДОМ с verification намеренно: файл результатов читает и
        // прежняя версия приложения (откат сборки), а она знает только это поле.
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
    // ⚠️ КЛАСС БАГОВ «ПОЛЕ ПИШЕТСЯ, НО НЕ ЧИТАЕТСЯ»: в файле, записанном до
    // 1.4.1, ключа `verification` НЕТ вовсе, есть только `working`. Без вывода
    // из него все сохранённые результаты после обновления молча превратились бы
    // в «не проверен», а плашки — в нейтральные. Умолчание при отсутствии обоих
    // ключей — `passed`: у старого поля `working` умолчание было `true`.
    final vName = j['verification'];
    final legacyWorking = j['working'] as bool?;
    final verification = vName != null
        ? PingVerification.values.firstWhere((v) => v.name == vName,
            orElse: () => PingVerification.notRun)
        : (legacyWorking == false
            ? PingVerification.failed
            : PingVerification.passed);
    return PingResult(
      outcome: PingOutcome.values.firstWhere((o) => o.name == j['outcome'],
          orElse: () => PingOutcome.untested),
      latencyMs: (j['latencyMs'] as num?)?.toInt(),
      proxyRttMs: (j['proxyRttMs'] as num?)?.toInt(),
      lossPct: (j['lossPct'] as num?)?.toDouble(),
      reachableViaProxy: j['reachableViaProxy'] as bool? ?? false,
      verification: verification,
      latencyMethod: lm,
      measuredAt:
          j['measuredAt'] != null ? DateTime.tryParse('${j['measuredAt']}') : null,
    );
  }
}

/// Замер скорости скачивания через сервер (Мбит/с) — то, что показано в строке
/// сервера под плашкой пинга.
///
/// ⚠️ ЖИВЁТ ОТДЕЛЬНО ОТ [PingResult], И ЭТО НЕ ЛИШНЯЯ СУЩНОСТЬ. Пинг
/// перезаписывает свой результат ЦЕЛИКОМ на каждом прогоне (`_results[key] =
/// PingResult(...)` встречается в `probe_controller` десяток раз). Держи мы
/// скорость полем внутри — замер, оплаченный мегабайтами подписки, исчезал бы
/// от первого же нажатия «Пинг серверов», причём молча.
class ServerSpeed {
  /// Скорость скачивания, Мбит/с. Единица та же, что у `AutoConfigResult.mbps`,
  /// — иначе перенос замера из автонастройки требовал бы пересчёта, а забытый
  /// пересчёт даёт цифру, отличающуюся в восемь раз, и никто этого не заметит.
  final double mbps;
  final DateTime? measuredAt;

  /// Цифра приехала из автонастройки, а не из ручного замера. Показываем её
  /// сразу и трафик на повтор не тратим — но в подсказке говорим, откуда она.
  final bool fromAutoConfig;

  /// Скорость в МЕГАБАЙТАХ в секунду — то, что видит человек.
  ///
  /// ⚠️ ХРАНИМ В МЕГАБИТАХ, ПОКАЗЫВАЕМ В МЕГАБАЙТАХ, И ЭТО НЕ ПРИДИРКА.
  /// Требование владельца 18.08.2026: «СКОРОСТЬ ВСЕГДА ПИШИ В МБАЙТАХ» — в
  /// мегабитах пишут провайдеры, а человек скачивает файлы и меряет их в
  /// мегабайтах. Единица хранения при этом остаётся прежней: она совпадает с
  /// `AutoConfigResult.mbps` и уже лежит в `speed_results.json` на дисках
  /// пользователей. Поменяй смысл поля — и старые замеры станут врать ровно в
  /// восемь раз, молча.
  ///
  /// Поэтому перевод живёт В ОДНОМ месте — здесь. Три места показа
  /// (плашка сервера, экран автонастройки, карточка «О сервере») обязаны
  /// спрашивать его, а не делить на восемь у себя: разъехавшиеся цифры скорости
  /// нельзя заметить глазом, их можно только вычислить.
  double get megabytesPerSecond => mbps / 8;

  const ServerSpeed({
    required this.mbps,
    this.measuredAt,
    this.fromAutoConfig = false,
  });

  Map<String, dynamic> toJson() => {
        'mbps': mbps,
        'measuredAt': measuredAt?.toIso8601String(),
        'fromAutoConfig': fromAutoConfig,
      };

  static ServerSpeed? fromJson(Map<String, dynamic> j) {
    final mbps = (j['mbps'] as num?)?.toDouble();
    // Нулевая или отрицательная скорость — это не замер, а мусор из чужого
    // файла: показывать «0.0 Мбит/с» как результат хуже, чем не показывать.
    if (mbps == null || mbps <= 0) return null;
    return ServerSpeed(
      mbps: mbps,
      measuredAt: j['measuredAt'] != null
          ? DateTime.tryParse('${j['measuredAt']}')
          : null,
      fromAutoConfig: j['fromAutoConfig'] == true,
    );
  }
}
