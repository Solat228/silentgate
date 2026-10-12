import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_info.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/net/file_download.dart';

/// Общая закачка файла (`downloadToFile`) — на НАСТОЯЩЕМ локальном
/// `HttpServer` (127.0.0.1, порт 0), а не на подделке клиента.
///
/// ⚠️ ПОЧЕМУ НАСТОЯЩИЙ СЕРВЕР. Половина того, что здесь проверяется, — обрыв
/// посреди тела, молчание сервера, редиректная петля — это поведение
/// ТРАНСПОРТА, и `MockClient` его не воспроизводит: он отдаёт тело целиком
/// одним куском и никогда не рвёт соединение. Единственный способ убедиться,
/// что `.part` не остаётся на диске после обрыва, — оборвать по-настоящему.
void main() {
  late HttpServer server;
  late Directory tmp;

  /// Что сервер видел: путь и User-Agent каждого запроса. По нему проверяем,
  /// что UA стоит на КАЖДОМ хопе редиректа, а не только на первом.
  final seen = <(String, String?)>[];

  /// Ответы, которые сервер нарочно держит открытыми («завис»): закрываются
  /// в tearDown, иначе сервер не остановится.
  final hanging = <HttpResponse>[];

  /// Детерминированное тело: 300 КБ — заведомо больше одного чанка сокета,
  /// чтобы прогресс был многошаговым.
  final body = List<int>.generate(300 * 1024, (i) => (i * 31 + 7) & 0xff);
  final bodySha = Sha256.ofBytes(body);

  Uri url(String path) =>
      Uri.parse('http://127.0.0.1:${server.port}$path');

  File target() => File('${tmp.path}${Platform.pathSeparator}out.bin');
  File part() => File('${target().path}.part');

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sg_dl_');
    seen.clear();
    hanging.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      seen.add((req.uri.path, req.headers.value(HttpHeaders.userAgentHeader)));
      final resp = req.response;
      final path = req.uri.path;
      switch (path) {
        case '/ok':
          resp.statusCode = 200;
          resp.contentLength = body.length;
          resp.add(body);
          await resp.close();
        case '/nolen':
          // Без Content-Length: сервер шлёт chunked, размер заранее неизвестен.
          resp.statusCode = 200;
          resp.add(body);
          await resp.close();
        case '/empty':
          resp.statusCode = 200;
          resp.contentLength = 0;
          await resp.close();
        case '/redir':
          resp.statusCode = 302;
          resp.headers.set(HttpHeaders.locationHeader, '/ok');
          await resp.close();
        case '/redir-relative':
          // Относительный Location — резолвится от текущего адреса.
          resp.statusCode = 301;
          resp.headers.set(HttpHeaders.locationHeader, 'ok');
          await resp.close();
        case '/loop':
          resp.statusCode = 302;
          resp.headers.set(HttpHeaders.locationHeader, '/loop');
          await resp.close();
        case '/404':
          resp.statusCode = 404;
          resp.write('not here');
          await resp.close();
        case '/cut':
          // Обещаем весь файл, отдаём треть и рвём сокет: так выглядит обрыв
          // связи посреди закачки.
          // `detachSocket` возможен только ДО тела: он сам пишет заголовки
          // (статус, Content-Length), дальше сокет наш — треть тела и обрыв.
          resp.statusCode = 200;
          resp.contentLength = body.length;
          final socket = await resp.detachSocket();
          socket.add(body.sublist(0, body.length ~/ 3));
          await socket.flush();
          socket.destroy();
        case '/hang':
          // Кусок отдан — и тишина. Единственное, что тут спасает, — таймаут
          // простоя.
          resp.statusCode = 200;
          resp.contentLength = body.length;
          resp.bufferOutput = false;
          resp.add(body.sublist(0, 1024));
          await resp.flush();
          hanging.add(resp);
        default:
          resp.statusCode = 500;
          resp.write('unexpected $path');
          await resp.close();
      }
    });
  });

  tearDown(() async {
    for (final r in hanging) {
      try {
        await r.close();
      } catch (_) {}
    }
    await server.close(force: true);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('успех', () {
    test('файл на месте, sha256 совпал, .part убран', () async {
      final sum = await downloadToFile(url('/ok'), target(),
          expectedSha256: bodySha);
      expect(sum, bodySha);
      expect(await target().readAsBytes(), body);
      expect(part().existsSync(), isFalse,
          reason: 'временный файл после переименования жить не должен');
    });

    test('sha256 сравнивается без учёта регистра', () async {
      final sum = await downloadToFile(url('/ok'), target(),
          expectedSha256: bodySha.toUpperCase());
      expect(sum, bodySha, reason: 'возвращаем нижний регистр, как Sha256');
      expect(target().existsSync(), isTrue);
    });

    test('без Content-Length — качается, total в прогрессе null', () async {
      final totals = <int?>[];
      final sum = await downloadToFile(url('/nolen'), target(),
          onProgress: (r, t) => totals.add(t));
      expect(sum, bodySha);
      expect(totals, isNotEmpty);
      expect(totals.every((t) => t == null), isTrue);
      expect(await target().length(), body.length);
    });

    test('expectedSize совпал — принято', () async {
      await downloadToFile(url('/ok'), target(), expectedSize: body.length);
      expect(await target().length(), body.length);
    });

    test('каталог назначения создаётся сам', () async {
      final deep = File('${tmp.path}${Platform.pathSeparator}a'
          '${Platform.pathSeparator}b${Platform.pathSeparator}f.bin');
      await downloadToFile(url('/ok'), deep);
      expect(deep.existsSync(), isTrue);
    });

    test('существующий файл назначения заменяется', () async {
      target().writeAsBytesSync([1, 2, 3]);
      await downloadToFile(url('/ok'), target());
      expect(await target().length(), body.length);
    });
  });

  group('редиректы', () {
    test('302 → 200: файл скачан, UA стоит на ОБОИХ хопах', () async {
      final sum = await downloadToFile(url('/redir'), target());
      expect(sum, bodySha);
      expect(seen.map((s) => s.$1).toList(), ['/redir', '/ok']);
      for (final (path, ua) in seen) {
        expect(ua, AppInfo.userAgent,
            reason: 'хоп $path ушёл без нашего User-Agent — ровно так '
                'терялся формат подписки при авто-следовании package:http');
      }
    });

    test('относительный Location резолвится от текущего адреса', () async {
      final sum = await downloadToFile(url('/redir-relative'), target());
      expect(sum, bodySha);
      expect(seen.last.$1, '/ok');
    });

    test('петля → DownloadException после maxRedirects, .part нет', () async {
      await expectLater(
        downloadToFile(url('/loop'), target(), maxRedirects: 3),
        throwsA(isA<DownloadException>()),
      );
      // Стартовый запрос + ровно maxRedirects переходов, дальше — стоп.
      expect(seen.length, 4,
          reason: 'после лимита переходов запросы продолжаться не должны');
      expect(part().existsSync(), isFalse);
      expect(target().existsSync(), isFalse);
    });
  });

  group('отказы: .part удалён, файла нет, DownloadException', () {
    Future<void> expectClean(Future<String> f, {Pattern? message}) async {
      Object? caught;
      try {
        await f;
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<DownloadException>(),
          reason: 'любой отказ обязан быть DownloadException, а не сырой '
              'ошибкой транспорта: ${caught.runtimeType}');
      if (message != null) {
        expect((caught as DownloadException).message, contains(message));
      }
      expect(part().existsSync(), isFalse, reason: '.part остался на диске');
      expect(target().existsSync(), isFalse,
          reason: 'файл назначения появился при неудаче');
    }

    test('обрыв соединения посреди тела', () async {
      await expectClean(downloadToFile(url('/cut'), target()));
    });

    test('сервер замолчал → таймаут простоя', () async {
      await expectClean(downloadToFile(url('/hang'), target(),
          idleTimeout: const Duration(milliseconds: 300)));
    });

    test('sha256 не совпал', () async {
      await expectClean(
        downloadToFile(url('/ok'), target(),
            expectedSha256: 'a' * 64),
        message: 'контрольная сумма',
      );
    });

    test('expectedSize ≠ Content-Length — отказ ДО закачки тела', () async {
      await expectClean(
        downloadToFile(url('/ok'), target(), expectedSize: body.length + 1),
        message: 'размер',
      );
    });

    test('expectedSize ≠ фактическому при неизвестном Content-Length',
        () async {
      await expectClean(
        downloadToFile(url('/nolen'), target(),
            expectedSize: body.length - 1),
        message: 'размер',
      );
    });

    test('maxBytes превышен (Content-Length известен)', () async {
      await expectClean(
        downloadToFile(url('/ok'), target(), maxBytes: body.length - 1),
        message: 'maxBytes',
      );
    });

    test('maxBytes превышен по ходу (Content-Length неизвестен)', () async {
      await expectClean(
        downloadToFile(url('/nolen'), target(), maxBytes: 100 * 1024),
        message: 'maxBytes',
      );
    });

    test('статус 404', () async {
      await expectClean(downloadToFile(url('/404'), target()),
          message: 'HTTP 404');
    });

    test('пустой ответ', () async {
      await expectClean(downloadToFile(url('/empty'), target()),
          message: 'пустой ответ');
    });

    test('сервера нет вовсе', () async {
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      await expectClean(downloadToFile(
        Uri.parse('http://127.0.0.1:$port/ok'),
        target(),
        connectTimeout: const Duration(seconds: 2),
      ));
    });
  });

  group('прогресс', () {
    test('монотонный, total = Content-Length, последний вызов = размеру',
        () async {
      final calls = <(int, int?)>[];
      await downloadToFile(url('/ok'), target(),
          onProgress: (r, t) => calls.add((r, t)));
      expect(calls, isNotEmpty);
      var prev = -1;
      for (final (r, t) in calls) {
        expect(r, greaterThanOrEqualTo(prev), reason: 'прогресс пошёл назад');
        expect(t, body.length);
        prev = r;
      }
      expect(calls.last.$1, body.length);
      expect(calls.length, greaterThan(1),
          reason: '300 КБ одним куском — значит, прогресс не потоковый');
    });
  });

  test('DownloadException.toString() — только сообщение', () {
    expect(const DownloadException('HTTP 503').toString(), 'HTTP 503',
        reason: 'по этому тексту гео-раздел выбирает объяснение для '
            'человека (geoErrorKind); префикс класса его бы сломал');
  });
}
