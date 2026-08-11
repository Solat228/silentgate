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

void main() {
  late LocalApiServer server;

  Future<HttpClientResponse> req(String path,
      {String? token, String? origin, String method = 'GET'}) async {
    final c = HttpClient();
    final r = await c.openUrl(
        method, Uri.parse('http://127.0.0.1:${ApiPortsForTest.port}$path'));
    if (token != null) r.headers.set('Authorization', 'Bearer $token');
    if (origin != null) r.headers.set('Origin', origin);
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
}

/// Порт для тестов — не штатный, чтобы прогон не спорил с живым приложением.
class ApiPortsForTest {
  static const int port = 18770;
}
