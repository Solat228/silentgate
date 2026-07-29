import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/block_page_server.dart';

/// Страница отдаётся по петле и никуда наружу не ходит: тест поднимает сервер и
/// стучится в него обычным http-клиентом.
void main() {
  const texts = BlockPageTexts(
    windowTitle: 'Заблокировано — SilentGate',
    heading: 'Сайт заблокирован',
    hint: 'Настройки → Раздельное туннелирование → Сайты',
    note: 'Это страница приложения, а не ошибка сети.',
    body: _body,
  );

  late BlockPageServer server;

  setUp(() async {
    server = (await BlockPageServer.start(texts: texts))!;
  });

  tearDown(() async => server.stop());

  Future<HttpClientResponse> get(String host) async {
    final c = HttpClient();
    final req = await c.get('127.0.0.1', server.port, '/');
    req.headers.set(HttpHeaders.hostHeader, host);
    return req.close();
  }

  test('отвечает 403 и html с именем сайта', () async {
    final res = await get('ads.example');
    expect(res.statusCode, 403);
    expect(res.headers.contentType?.mimeType, 'text/html');
    // Без объявленной кодировки браузер прочитает кириллицу мусором.
    expect(res.headers.contentType?.charset, 'utf-8');

    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('Сайт заблокирован'));
    expect(body, contains('ads.example'));
    expect(body, contains('Настройки'));
  });

  test('не кэшируется: сняв блокировку, пользователь увидит сам сайт', () async {
    final res = await get('ads.example');
    expect(res.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    await res.drain<void>();
  });

  test('порт из заголовка Host в текст не попадает', () async {
    final res = await get('ads.example:80');
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('ads.example'));
    expect(body.contains('ads.example:80'), isFalse);
  });

  // Имя хоста приходит из заголовка запроса — то есть снаружи. Без
  // экранирования страница-заглушка сама стала бы дырой: чужая разметка
  // выполнилась бы в контексте нашего ответа.
  test('разметка из заголовка Host экранируется', () async {
    final res = await get('<script>alert(1)</script>');
    final body = await res.transform(utf8.decoder).join();
    expect(body.contains('<script>alert(1)</script>'), isFalse);
    expect(body, contains('&lt;script&gt;'));
  });

  test('повторный запуск освобождает прежний порт', () async {
    final first = server.port;
    final second = (await BlockPageServer.start(texts: texts))!;
    addTearDown(second.stop);
    // Прежний сокет закрыт — иначе правило маршрутизации указывало бы на порт,
    // который уже никто не обслуживает.
    await expectLater(
      HttpClient().get('127.0.0.1', first, '/').then((r) => r.close()),
      throwsA(isA<SocketException>()),
    );
  });
}

String _body(String host) => 'Адрес $host заблокирован правилом.';
