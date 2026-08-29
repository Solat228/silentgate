import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ping_result.dart';

/// Ответ HTTP-транспорта: только код и тело. Свой тип, а не `HttpClientResponse`,
/// чтобы тест подменял транспорт целиком и не поднимал ни одного сокета.
class ClashHttpResponse {
  final int status;
  final String body;
  const ClashHttpResponse(this.status, this.body);
}

/// Транспорт запроса к Clash API. [bearer] — секрет сессии (пустой = без
/// авторизации), [timeout] — на весь запрос целиком.
typedef ClashHttpGet = Future<ClashHttpResponse> Function(Uri url,
    {required String bearer, required Duration timeout});

/// Итог замера ядром.
///
/// [PingOutcome.failed] и «замерить не удалось» — РАЗНЫЕ новости, поэтому
/// рядом с исходом живёт [unavailable]: провал теста говорит про канал
/// (ядро не смогло открыть тестовый адрес через сервер), а недоступность API —
/// про нас самих (не тот порт, не тот секрет, ядро уже погашено). Слить их в
/// один «failed» значило бы красить рабочий сервер в мёртвый из-за своей же
/// ошибки конфигурации — ровно тот класс вранья, который здесь чинится.
class ClashDelayResult {
  final PingOutcome outcome;
  final int? delayMs;

  /// Ядро НЕ СПРОШЕНО (соединение с API не удалось, 4xx про наш запрос).
  /// Про сервер такой итог не говорит ничего — вердикт ему ставить нельзя.
  final bool unavailable;

  const ClashDelayResult(this.outcome, {this.delayMs, this.unavailable = false});

  bool get ok => outcome == PingOutcome.ok && delayMs != null;
}

/// Замер задержки текущего сервера **самим ядром** — `GET /proxies/{tag}/delay`
/// Clash API sing-box.
///
/// ⚠️ ЗАЧЕМ, ЕСЛИ ЕСТЬ TCP-ПИНГ. При поднятом TUN `Socket.connect` приложения
/// затягивается в туннель, и рукопожатие завершает ЛОКАЛЬНЫЙ стек sing-box за
/// 1–3 мс — цифра не про сервер вовсе. Проверено живыми замерами в VM:
/// не помогли ни `route_exclude_address` (адреса из списка исключений всё
/// равно давали 1 мс), ни привязка сокета к физическому адаптеру. Так меряют
/// и другие клиенты (v2rayN, NekoBox, Hiddify): запрос выполняет сам процесс
/// ядра через нужный outbound, до сетевого стека системы — самозахвата нет.
///
/// ⚠️ ИЗМЕРЯЕТСЯ ДРУГАЯ ВЕЛИЧИНА: время ПОЛНОГО запроса к тестовому адресу
/// через туннель (TCP + TLS + HTTP), а не рукопожатие до узла. Смешивать её с
/// TCP-цифрами без пометки нельзя — потребитель обязан подписать способ
/// (`PingMethod.coreUrl`).
class ClashDelayProbe {
  final int port;
  final String secret;

  /// Тег outbound'а в конфиге ядра. У нас он всегда `proxy` — так его именует
  /// `SingboxConfigBuilder` во всех трёх вариантах (готовый outbound, группа
  /// «Авто» urltest, переход в SOCKS соседнего Xray). Переименование тега там
  /// обязано отразиться здесь.
  final String tag;

  final ClashHttpGet _get;

  ClashDelayProbe({
    required this.port,
    this.secret = '',
    this.tag = 'proxy',
    ClashHttpGet? httpGet,
  }) : _get = httpGet ?? _realGet;

  /// Один замер. Не бросает никогда: любой сбой транспорта — это
  /// `unavailable`, а не исключение, которое валит весь прогон пинга.
  Future<ClashDelayResult> measure(
      {required String testUrl, required Duration timeout}) async {
    // Оба параметра ОБЯЗАТЕЛЬНЫ явно: без `timeout` Clash API отвечает 400,
    // а на дефолтный url ядра полагаться нельзя — мерить надо тот же адрес,
    // которым ходит проверка канала (`settings.testUrl`).
    final uri = Uri.parse('http://127.0.0.1:$port/proxies/'
            '${Uri.encodeComponent(tag)}/delay')
        .replace(queryParameters: {
      'url': testUrl,
      'timeout': '${timeout.inMilliseconds}',
    });
    try {
      // Запас поверх таймаута теста: ядро само оборвёт замер по своему
      // `timeout` и ответит 504 — дать ему это сделать честнее, чем оборвать
      // соединение с API на полуслове и получить неотличимый от сбоя обрыв.
      final resp = await _get(uri,
          bearer: secret,
          timeout: timeout + const Duration(milliseconds: 1500));
      return parse(resp.status, resp.body);
    } on TimeoutException {
      // Сам API не ответил за таймаут+запас — ядро занято или подвисло.
      // Про сервер это не говорит ничего.
      return const ClashDelayResult(PingOutcome.failed, unavailable: true);
    } catch (_) {
      return const ClashDelayResult(PingOutcome.failed, unavailable: true);
    }
  }

  /// Разбор ответа Clash API. Вынесен статикой ради тестов без сети.
  ///
  /// Карта кодов (сверено с clash-совместимым API sing-box):
  ///   200 `{"delay": N}` — успех;
  ///   504/408 — тест не уложился в свой таймаут: канал не отвечает;
  ///   400/401/403/404 — ошибка НАШЕГО запроса (плохие параметры, чужой
  ///     секрет, нет такого тега) — ядро не спрошено, вердикта серверу нет;
  ///   прочее (5xx) — ядро пробовало и не смогло: канал не работает.
  static ClashDelayResult parse(int status, String body) {
    switch (status) {
      case 200:
        final delay = _delayFrom(body);
        // 200 с мусором внутри — это не «сервер плохой», это «мы не поняли
        // ядро»: вердикт по непонятому ответу был бы выдумкой.
        if (delay == null || delay <= 0) {
          return const ClashDelayResult(PingOutcome.failed, unavailable: true);
        }
        return ClashDelayResult(PingOutcome.ok, delayMs: delay);
      case 504:
      case 408:
        return const ClashDelayResult(PingOutcome.timeout);
      case 400:
      case 401:
      case 403:
      case 404:
        return const ClashDelayResult(PingOutcome.failed, unavailable: true);
      default:
        return const ClashDelayResult(PingOutcome.failed);
    }
  }

  static int? _delayFrom(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final d = j['delay'];
      if (d is int) return d;
      if (d is num) return d.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Боевой транспорт. Отдельный `HttpClient` на запрос: клиент со связкой
  /// keep-alive пережил бы перезапуск ядра и стучался в мёртвый порт.
  static Future<ClashHttpResponse> _realGet(Uri url,
      {required String bearer, required Duration timeout}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final req = await client.getUrl(url);
      if (bearer.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      final resp = await req.close().timeout(timeout);
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return ClashHttpResponse(resp.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }
}
