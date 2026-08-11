import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/app_log.dart';
import 'api_ports.dart';

/// Сравнение токена в ПОСТОЯННОЕ время: без раннего выхода на первом
/// несовпадающем байте и без утечки через сравнение длин.
///
/// ⚠️ Модель угрозы — любой локальный процесс на машине, без rate-limit'а на
/// порту: обычное `String.==` в Dart останавливается на первом несовпадении,
/// и время ответа зависит от длины совпавшего префикса токена. Разница на
/// порядки меньше джиттера асинхронного стека Dart, поэтому эксплуатация
/// нетривиальна — но для секрета это стандартная практика независимо от
/// канала, а починка дешёвая.
bool _constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  final maxLen = ab.length > bb.length ? ab.length : bb.length;
  // Разницу длин копим В АККУМУЛЯТОР, а не сравниваем веткой: `if (ab.length
  // != bb.length) return false` завершилась бы мгновенно, и токен другой
  // длины отвечал бы быстрее верного префикса — та же утечка, что и ранний
  // выход по байту.
  var diff = ab.length ^ bb.length;
  for (var i = 0; i < maxLen; i++) {
    final x = i < ab.length ? ab[i] : 0;
    final y = i < bb.length ? bb[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

/// Итог команды: успех либо причина отказа.
class ApiResult {
  const ApiResult.ok()
      : code = null,
        message = null;
  const ApiResult.fail(this.code, this.message);

  /// `null` — успех.
  final String? code;
  final String? message;

  bool get isOk => code == null;
}

/// Что умеет отдавать и делать API. Реализация живёт в состоянии приложения —
/// сервер про него ничего не знает и потому тестируется отдельно.
abstract interface class ApiHandlers {
  Future<Map<String, dynamic>> status();
  Future<List<Map<String, dynamic>>> servers();
  Future<List<Map<String, dynamic>>> exits();
  Future<Map<String, dynamic>> traffic();
  Future<Map<String, dynamic>> subscription();
  Future<ApiResult> connect({String? serverKey, String? name, bool auto = false});
  Future<ApiResult> disconnect();
  Future<ApiResult> ping();
}

/// Локальный HTTP-API для автоматизации.
///
/// ⚠️ ТРИ ПРАВИЛА, ВЗЯТЫЕ ИЗ УЖЕ СЛУЧИВШИХСЯ АВАРИЙ.
///
/// 1. Пустой токен означает «канал не поднимается», а не «поднимается без
///    проверки». Полумера опаснее отсутствия: порт, про который написано
///    «закрыт», а на деле пускающий кого угодно, хуже честно выключенного.
/// 2. Токен приходит готовым, одним значением, ДО старта слушателя. Секрет
///    Clash API однажды выдавался лишь на одном пути из нескольких — и порт
///    месяцами стоял открытым при обычных подключениях.
/// 3. Запрос с заголовком `Origin` отвергается. Локальный порт без этого
///    доступен не только процессу на машине, но и любой открытой вкладке
///    браузера.
class LocalApiServer {
  LocalApiServer({
    required this.token,
    required this.handlers,
    this.port = ApiPorts.control,
  });

  final String token;
  final ApiHandlers handlers;
  final int port;

  HttpServer? _server;

  bool get running => _server != null;
  String get address => _server?.address.address ?? '';

  /// Поднять слушатель. `false` — не поднялся (нет токена либо порт занят).
  Future<bool> start() async {
    await stop();
    if (token.isEmpty) {
      AppLog.w('API не поднят: токен не задан. Пустой токен означает '
          '«канал выключен», а не «открыт всем».');
      return false;
    }
    try {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = s;
      s.listen(_handle, onError: (Object e) => AppLog.w('API: сбой приёма: $e'));
      AppLog.i('API для автоматизации слушает 127.0.0.1:$port');
      return true;
    } catch (e) {
      AppLog.w('API не поднят на порту $port: $e');
      return false;
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s == null) return;
    try {
      await s.close(force: true);
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      // ⚠️ Внутри try целиком, включая установку заголовка: клиент мог уже
      // оборвать соединение к этому моменту, и запись в `res` бросает так же,
      // как и любая другая операция ниже.
      res.headers.contentType = ContentType.json;
      // ⚠️ Никаких Access-Control-Allow-*: заголовки, разрешающие браузеру
      // читать ответ, здесь были бы прямой выдачей состояния в веб.
      // Браузер всегда шлёт Origin для кросс-доменных запросов, а обычный
      // клиент (requests, curl) — нет. Это и есть граница.
      if (req.headers.value('origin') != null ||
          req.method == 'OPTIONS') {
        await _fail(res, HttpStatus.forbidden, 'browser_not_allowed',
            'Запросы из браузера не принимаются');
        return;
      }
      final auth = req.headers.value('authorization') ?? '';
      if (!_constantTimeEquals(auth, 'Bearer $token')) {
        await _fail(res, HttpStatus.unauthorized, 'unauthorized',
            'Нужен заголовок Authorization: Bearer <токен>');
        return;
      }
      await _route(req, res);
    } catch (e) {
      await _fail(res, HttpStatus.internalServerError, 'internal', '$e');
    }
  }

  Future<void> _route(HttpRequest req, HttpResponse res) async {
    final path = req.uri.path;
    if (req.method == 'GET') {
      switch (path) {
        case '/v1/status':
          return _ok(res, await handlers.status());
        case '/v1/servers':
          return _ok(res, {'servers': await handlers.servers()});
        case '/v1/exits':
          return _ok(res, {'exits': await handlers.exits()});
        case '/v1/traffic':
          return _ok(res, await handlers.traffic());
        case '/v1/subscription':
          return _ok(res, await handlers.subscription());
      }
    }
    if (req.method == 'POST') {
      final parsed = await _parseBody(req);
      if (parsed.error != null) {
        await _fail(res, HttpStatus.badRequest, 'bad_request', parsed.error!);
        return;
      }
      final body = parsed.value!;
      switch (path) {
        case '/v1/connect':
          return _result(
              res,
              await handlers.connect(
                serverKey: body['server'] as String?,
                name: body['name'] as String?,
                auto: body['auto'] == true,
              ));
        case '/v1/disconnect':
          return _result(res, await handlers.disconnect());
        case '/v1/ping':
          return _result(res, await handlers.ping());
      }
    }
    await _fail(res, HttpStatus.notFound, 'not_found', 'Нет такого пути');
  }

  /// Разобрать тело POST-запроса.
  ///
  /// ⚠️ «Тела нет» и «тело есть, но не разбирается» — разные случаи. Пустое
  /// тело — законный `POST /v1/disconnect` без параметров, поэтому даёт
  /// пустую карту. Битый JSON и JSON, разобравшийся не в объект (число,
  /// массив, строка), молча принятые за пустое значили бы подключить не туда
  /// — раньше оба неотличимо превращались в `connect(null, null, false)` и
  /// отвечали 409 вместо честного 400.
  Future<_BodyParseResult> _parseBody(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.trim().isEmpty) return const _BodyParseResult.ok({});
    final Object? v;
    try {
      v = jsonDecode(text);
    } catch (e) {
      return _BodyParseResult.fail('Тело запроса — не JSON: $e');
    }
    if (v is! Map<String, dynamic>) {
      return const _BodyParseResult.fail('Тело запроса должно быть JSON-объектом');
    }
    return _BodyParseResult.ok(v);
  }

  Future<void> _ok(HttpResponse res, Map<String, dynamic> body) async {
    res.statusCode = HttpStatus.ok;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _result(HttpResponse res, ApiResult r) async {
    if (r.isOk) return _ok(res, {'ok': true});
    return _fail(res, HttpStatus.conflict, r.code!, r.message ?? '');
  }

  Future<void> _fail(
      HttpResponse res, int status, String code, String message) async {
    try {
      res.statusCode = status;
      res.write(jsonEncode({
        'error': {'code': code, 'message': message}
      }));
      await res.close();
    } catch (_) {
      // ⚠️ Клиент мог оборвать соединение, пока мы писали ответ — в том числе
      // ответ ОБ ОШИБКЕ, вызванный из `catch` в `_handle`. Второе исключение
      // здесь уже никто не поймает: писать больше некуда, разбираться не с
      // чем, а необработанное исключение внутри `_handle` (её никто не
      // awaitит из `s.listen`) улетело бы в необработанную ошибку зоны.
    }
  }

  /// Тестовый крючок: прогнать [_fail] на подставном [HttpResponse], который
  /// бросает при закрытии, — не поднимая настоящий сокет. Доказывает, что
  /// вторая ошибка (клиент оборвал соединение, пока сервер писал ответ) не
  /// вылетает никуда неперехваченной.
  @visibleForTesting
  Future<void> failForTest(HttpResponse res) =>
      _fail(res, HttpStatus.internalServerError, 'internal', 'test');

  /// Тестовый крючок для сравнения токена в постоянное время — сам алгоритм
  /// не завязан на состояние сервера, но приватен по умолчанию.
  @visibleForTesting
  static bool constantTimeEqualsForTest(String a, String b) =>
      _constantTimeEquals(a, b);
}

/// Итог разбора тела запроса: успех со значением либо причина отказа (400).
class _BodyParseResult {
  const _BodyParseResult.ok(this.value) : error = null;
  const _BodyParseResult.fail(this.error) : value = null;

  final Map<String, dynamic>? value;
  final String? error;
}
