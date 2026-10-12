import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../app_info.dart';
import '../geo/sha256.dart';

/// Закачка не удалась. Сообщение — на русском и без имени класса в
/// `toString()`: по этому тексту интерфейс выбирает объяснение для человека
/// (см. `geoErrorKind` в разделе гео-баз), а «DownloadException: …» в начале
/// строки — мусор, который пришлось бы вырезать.
class DownloadException implements Exception {
  final String message;

  const DownloadException(this.message);

  @override
  String toString() => message;
}

/// Скачать [url] в [target] потоком; вернуть sha256 (hex, нижний регистр)
/// скачанного.
///
/// Общий путь для всего, что качает большие файлы: гео-базы (25 МБ) и
/// установщики обновлений (десятки МБ). Тело — прежний `GeoBases._fetchTo`,
/// вынесенный сюда, чтобы у самообновления не завелась своя копия с
/// собственным набором дыр.
///
/// ⚠️ ЧТО ЗДЕСЬ ГАРАНТИРУЕТСЯ, И ПОЧЕМУ.
///
///  * **Пишем в `<target>.part`, переименовываем в конце.** Оборванная закачка
///    иначе оставила бы обрезанный файл под настоящим именем — а обрезанный
///    `geoip.dat` ядро принимает за настоящий, обрезанный установщик человек
///    запускает. После ЛЮБОЙ неудачи `.part` удалён, [target] не тронут.
///  * **Хэш считается по ходу**, вторым проходом по 25 МБ ради той же цифры
///    платили бы секундой и лишним чтением флеш-памяти телефона.
///  * **Редиректам следуем сами**, а не через `followRedirects` клиента:
///    `package:http` при авто-следовании повторяет запрос БЕЗ заголовков,
///    и на втором хопе сервер видит `Dart/3.x` вместо нашего User-Agent (на
///    этом уже горела подписка — см. `SubscriptionService._fetchFollowing`).
///    Здесь UA ставится на каждом хопе, петля рвётся на [maxRedirects]+1.
///  * **Напрямую, мимо системного прокси** (`findProxy = DIRECT`, идиома
///    `ProxyProbe`): умолчание `HttpClient` смотрит на `http_proxy`/`all_proxy`
///    окружения, и закачка тихо ушла бы через чужой прокси. Действует только
///    для клиента по умолчанию — подставленный [client] настраивает вызывающий.
///  * **Три проверки размера.** [expectedSize] сверяется с `Content-Length`
///    ДО тела (узнать о несовпадении после 60 МБ — худший вариант), с числом
///    принятых байт — после; [maxBytes] — потолок, чтобы подменённый сервер
///    не залил диск. `Content-Length` без [expectedSize] тоже обязателен к
///    исполнению: недобор — обрыв, а не «скачано».
///  * **Пустой ответ — отказ.** Ноль байт с кодом 200 — это не файл.
///  * [expectedSha256] сравнивается без учёта регистра: `.sha256sum` и
///    манифесты пишут кто как.
///
/// [onProgress] зовётся на каждом принятом куске: `received` не убывает,
/// `total` — из `Content-Length` (иначе `null`), последний вызов — с итоговым
/// размером.
///
/// [connectTimeout] — на установление соединения, [idleTimeout] — на ожидание
/// заголовков и каждого следующего куска тела: замолчавший сервер иначе держал
/// бы «Скачивание…» вечно. Оба применяются к клиенту по умолчанию;
/// у подставленного [client] соединение настраивает его владелец.
Future<String> downloadToFile(
  Uri url,
  File target, {
  int? expectedSize,
  String? expectedSha256,
  void Function(int received, int? total)? onProgress,
  http.Client? client,
  int maxRedirects = 5,
  int maxBytes = 600 * 1024 * 1024,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration idleTimeout = const Duration(seconds: 60),
}) async {
  final own = client == null;
  final c = client ?? _directClient(connectTimeout);
  final part = File('${target.path}.part');
  try {
    final sum = await _downloadPart(
      c,
      url,
      part,
      expectedSize: expectedSize,
      onProgress: onProgress,
      maxRedirects: maxRedirects,
      maxBytes: maxBytes,
      idleTimeout: idleTimeout,
    );
    final want = expectedSha256?.trim().toLowerCase();
    if (want != null && want != sum) {
      throw const DownloadException(
          'контрольная сумма не совпала — закачка повреждена');
    }
    try {
      await part.rename(target.path);
    } on FileSystemException catch (e) {
      throw DownloadException('не удалось положить файл на место: $e');
    }
    return sum;
  } catch (e) {
    await _deleteQuiet(part);
    if (e is DownloadException) rethrow;
    // Обрыв сокета, TLS, таймаут — текст исходной ошибки сохраняем: по нему
    // интерфейс отличает «нет связи» от прочего.
    throw DownloadException('обрыв закачки: $e');
  } finally {
    if (own) c.close();
  }
}

/// Клиент по умолчанию: напрямую и с нашим UA на транспорте (вторая линия —
/// заголовок ставится и на каждом запросе явно).
http.Client _directClient(Duration connectTimeout) {
  final io = HttpClient()
    ..connectionTimeout = connectTimeout
    ..userAgent = AppInfo.userAgent;
  // Отдельной строкой, а не в каскаде: тело лямбды `(_) => 'DIRECT'` иначе
  // поглощает следующие `..` как продолжение выражения.
  io.findProxy = (_) => 'DIRECT';
  return IOClient(io);
}

/// Сама закачка в [part]: редиректы, проверки размера, хэш по ходу.
/// Возвращает sha256; за уборку `.part` при ошибке отвечает вызывающий.
Future<String> _downloadPart(
  http.Client c,
  Uri start,
  File part, {
  required int? expectedSize,
  required void Function(int received, int? total)? onProgress,
  required int maxRedirects,
  required int maxBytes,
  required Duration idleTimeout,
}) async {
  if (expectedSize != null && expectedSize > maxBytes) {
    throw DownloadException(
        'ожидаемый размер $expectedSize байт больше потолка maxBytes=$maxBytes');
  }
  final resp = await _openFollowing(c, start,
      maxRedirects: maxRedirects, idleTimeout: idleTimeout);
  if (resp.statusCode != 200) {
    await _drainQuiet(resp);
    throw DownloadException('HTTP ${resp.statusCode}');
  }
  final total = resp.contentLength;
  if (total != null) {
    if (expectedSize != null && total != expectedSize) {
      await _drainQuiet(resp);
      throw DownloadException(
          'размер файла на сервере $total байт, ожидался $expectedSize');
    }
    if (total > maxBytes) {
      await _drainQuiet(resp);
      throw DownloadException(
          'размер файла на сервере $total байт больше потолка maxBytes=$maxBytes');
    }
  }

  await part.parent.create(recursive: true);
  final hash = Sha256Sink();
  var received = 0;
  final sink = part.openWrite();
  try {
    // ⚠️ Таймаут на КАЖДЫЙ кусок, а не на весь ответ: 60 МБ по медленному
    // каналу законно идут дольше минуты, а вот минута без единого байта —
    // это мёртвый сервер.
    await for (final chunk in resp.stream.timeout(idleTimeout)) {
      received += chunk.length;
      if (received > maxBytes) {
        throw DownloadException(
            'получено больше потолка maxBytes=$maxBytes байт — закачка остановлена');
      }
      sink.add(chunk);
      hash.add(chunk);
      onProgress?.call(received, total);
    }
  } finally {
    // Сначала закрыть файл, потом удалять его: на Windows открытый файл не
    // удалится, и `.part` остался бы на диске.
    await sink.close();
  }
  if (received == 0) throw const DownloadException('пустой ответ');
  if (total != null && received != total) {
    throw DownloadException('получено $received из $total байт');
  }
  if (expectedSize != null && received != expectedSize) {
    throw DownloadException(
        'размер скачанного $received байт, ожидался $expectedSize');
  }
  return hash.close();
}

/// GET с ручным следованием за 301/302/303/307/308 и нашим UA на каждом хопе.
Future<http.StreamedResponse> _openFollowing(
  http.Client c,
  Uri start, {
  required int maxRedirects,
  required Duration idleTimeout,
}) async {
  var current = start;
  for (var hop = 0;; hop++) {
    final req = http.Request('GET', current)..followRedirects = false;
    req.headers[HttpHeaders.userAgentHeader] = AppInfo.userAgent;
    req.headers[HttpHeaders.acceptHeader] = '*/*';
    final resp = await c.send(req).timeout(idleTimeout);
    final code = resp.statusCode;
    final isRedirect =
        code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
    final location = resp.headers['location'];
    if (!isRedirect || location == null || location.isEmpty) return resp;
    await _drainQuiet(resp);
    if (hop >= maxRedirects) {
      throw DownloadException('слишком много редиректов (больше $maxRedirects)');
    }
    current = current.resolve(location);
  }
}

Future<void> _drainQuiet(http.StreamedResponse resp) async {
  try {
    await resp.stream.drain<void>();
  } catch (_) {}
}

Future<void> _deleteQuiet(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
