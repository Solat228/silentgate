import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_server.dart';

/// Аутентификация локального API.
///
/// ⚠️ Три правила ниже взяты из уже случившихся в этом проекте аварий, а не
/// придуманы: пустой секрет однажды означал «открыто всем», секрет выдавался
/// лишь на одном пути из нескольких, а порт без правильных заголовков читала
/// любая открытая вкладка браузера.
class _StubHandlers implements ApiHandlers {
  @override
  Future<Map<String, dynamic>> status() async => {'state': 'disconnected'};
  @override
  Future<List<Map<String, dynamic>>> servers() async => const [];
  @override
  Future<List<Map<String, dynamic>>> exits() async => const [];
  @override
  Future<Map<String, dynamic>> traffic() async => const {};
  @override
  Future<Map<String, dynamic>> subscription() async => const {};
  @override
  Future<ApiResult> connect({String? serverKey, String? name, bool auto = false}) async =>
      const ApiResult.ok();
  @override
  Future<ApiResult> disconnect() async => const ApiResult.ok();
  @override
  Future<ApiResult> ping() async => const ApiResult.ok();
}

/// Ответ, который бросает при закрытии, — имитирует клиента, оборвавшего
/// соединение, пока сервер писал ответ. `noSuchMethod` закрывает все члены
/// `HttpResponse`, которые в этом тесте не вызываются вовсе.
class _BrokenResponse implements HttpResponse {
  @override
  int statusCode = 200;

  @override
  void write(Object? object) {}

  @override
  Future<void> close() async {
    throw const SocketException('оборвано (тест)');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalApiServer server;

  Future<HttpClientResponse> req(String path,
      {String? token, String? origin, String method = 'GET', String? body}) async {
    final c = HttpClient();
    final r = await c.openUrl(
        method, Uri.parse('http://127.0.0.1:${ApiPortsForTest.port}$path'));
    if (token != null) r.headers.set('Authorization', 'Bearer $token');
    if (origin != null) r.headers.set('Origin', origin);
    if (body != null) r.write(body);
    final resp = await r.close();
    return resp;
  }

  tearDown(() async => server.stop());

  test('пустой токен — сервер НЕ поднимается', () async {
    server = LocalApiServer(
        token: '', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    expect(await server.start(), isFalse);
    expect(server.running, isFalse);
  });

  test('без токена — 401', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    expect(await server.start(), isTrue);
    expect((await req('/v1/status')).statusCode, 401);
  });

  test('неверный токен — 401', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/status', token: 'bad')).statusCode, 401);
  });

  test('верный токен — 200 и JSON', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    final r = await req('/v1/status', token: 'good');
    expect(r.statusCode, 200);
    final body = jsonDecode(await utf8.decoder.bind(r).join());
    expect(body['state'], 'disconnected');
  });

  test('⚠️ запрос с Origin отвергается даже с верным токеном', () async {
    // Локальный HTTP-порт без этого атакуется не только процессом на машине, но
    // и любой открытой вкладкой браузера: sing-box с пустым секретом отдавал
    // метаданные соединений с CORS `*` — ровно тот же класс.
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    final r = await req('/v1/status',
        token: 'good', origin: 'https://evil.example');
    expect(r.statusCode, 403);
  });

  test('OPTIONS отвергается — preflight не пройдёт', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/status', method: 'OPTIONS')).statusCode, 403);
  });

  test('неизвестный путь — 404', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/nope', token: 'good')).statusCode, 404);
  });

  test('слушает ТОЛЬКО loopback', () async {
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    expect(server.address, InternetAddress.loopbackIPv4.address);
  });

  test('⚠️ пустой токен — порт РЕАЛЬНО свободен, а не просто поле false',
      () async {
    // Поле могло бы быть false, а сокет — жить (например, если бы `bind`
    // случился раньше проверки токена). Доказательство — бинд напрямую: если
    // порт занят, он бросит.
    server = LocalApiServer(
        token: '', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    expect(await server.start(), isFalse);
    final probe = await HttpServer.bind(
        InternetAddress.loopbackIPv4, ApiPortsForTest.port);
    await probe.close(force: true);
  });

  group('⚠️ Сравнение токена в постоянное время (раунд ревью 1)', () {
    // Обычное `String.==` выходит на первом несовпадающем байте — время
    // ответа зависит от длины совпавшего префикса. Тесты ниже проверяют
    // КОРРЕКТНОСТЬ алгоритма замены (без раннего выхода), а не время ответа:
    // тест на время был бы «мигающим» — джиттер асинхронного стека Dart
    // перекрывает разницу на порядки, сам замер ничего бы не доказал.
    test('равные строки совпадают', () {
      expect(LocalApiServer.constantTimeEqualsForTest('good', 'good'), isTrue);
    });

    test('разная длина не совпадает — ни короче, ни длиннее', () {
      expect(
          LocalApiServer.constantTimeEqualsForTest('good', 'good-extra'),
          isFalse);
      expect(
          LocalApiServer.constantTimeEqualsForTest('good-extra', 'good'),
          isFalse);
    });

    test('общий префикс, разный хвост той же длины — не совпадает', () {
      // Именно этот случай ловит регресс на раннем выходе по байту: первые
      // три символа совпадают, дальше — нет.
      expect(LocalApiServer.constantTimeEqualsForTest('goox', 'good'), isFalse);
    });

    test('пустые строки совпадают между собой, пустая с непустой — нет', () {
      expect(LocalApiServer.constantTimeEqualsForTest('', ''), isTrue);
      expect(LocalApiServer.constantTimeEqualsForTest('', 'good'), isFalse);
    });
  });

  test('⚠️ токен-префикс и токен-с-довеском верного всё равно отвергаются',
      () async {
    server = LocalApiServer(
        token: 'good-token',
        handlers: _StubHandlers(),
        port: ApiPortsForTest.port);
    await server.start();
    expect((await req('/v1/status', token: 'good')).statusCode, 401);
    expect(
        (await req('/v1/status', token: 'good-token-extra')).statusCode, 401);
  });

  group('⚠️ Тело POST-запроса: 400 на нечитаемое, а не тихий пустой (раунд '
      'ревью 1)', () {
    // «Тела нет» и «тело есть, но не разбирается» — разные случаи. Раньше
    // оба неотличимо превращались в connect(null, null, false) → 409.
    test('битый JSON — 400', () async {
      server = LocalApiServer(
          token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
      await server.start();
      final r = await req('/v1/connect',
          token: 'good', method: 'POST', body: 'not json');
      expect(r.statusCode, 400);
    });

    test('валидный JSON, но не объект (массив) — 400', () async {
      server = LocalApiServer(
          token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
      await server.start();
      final r = await req('/v1/connect',
          token: 'good', method: 'POST', body: '[1,2,3]');
      expect(r.statusCode, 400);
    });

    test('валидный JSON, но не объект (строка) — 400', () async {
      server = LocalApiServer(
          token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
      await server.start();
      final r = await req('/v1/connect',
          token: 'good', method: 'POST', body: '"auto"');
      expect(r.statusCode, 400);
    });

    test('пустое тело — НЕ 400: законный вызов без параметров', () async {
      server = LocalApiServer(
          token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
      await server.start();
      final r = await req('/v1/disconnect', token: 'good', method: 'POST');
      expect(r.statusCode, 200);
    });

    test('валидный JSON-объект — тело разбирается как раньше', () async {
      server = LocalApiServer(
          token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
      await server.start();
      final r = await req('/v1/connect',
          token: 'good', method: 'POST', body: '{"auto":true}');
      expect(r.statusCode, 200);
    });
  });

  test('⚠️ вторая ошибка при записи ответа не улетает необработанной',
      () async {
    // Клиент оборвал соединение, пока сервер писал ответ ОБ ОШИБКЕ (из
    // catch в _handle) — до фикса это исключение никто бы не поймал.
    server = LocalApiServer(
        token: 'good', handlers: _StubHandlers(), port: ApiPortsForTest.port);
    await server.start();
    await expectLater(server.failForTest(_BrokenResponse()), completes);
  });
}

/// Порт для тестов — не штатный, чтобы прогон не спорил с живым приложением.
class ApiPortsForTest {
  static const int port = 18770;
}
