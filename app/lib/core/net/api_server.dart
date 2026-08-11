import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/app_log.dart';
import 'api_ports.dart';

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
    res.headers.contentType = ContentType.json;
    // ⚠️ Никаких Access-Control-Allow-*: заголовки, разрешающие браузеру читать
    // ответ, здесь были бы прямой выдачей состояния в веб.
    try {
      // Браузер всегда шлёт Origin для кросс-доменных запросов, а обычный
      // клиент (requests, curl) — нет. Это и есть граница.
      if (req.headers.value('origin') != null ||
          req.method == 'OPTIONS') {
        await _fail(res, HttpStatus.forbidden, 'browser_not_allowed',
            'Запросы из браузера не принимаются');
        return;
      }
      final auth = req.headers.value('authorization') ?? '';
      if (auth != 'Bearer $token') {
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
      final body = await _body(req);
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

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    try {
      final text = await utf8.decoder.bind(req).join();
      if (text.trim().isEmpty) return const {};
      final v = jsonDecode(text);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
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
    res.statusCode = status;
    res.write(jsonEncode({
      'error': {'code': code, 'message': message}
    }));
    await res.close();
  }
}
