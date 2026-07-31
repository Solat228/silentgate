import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Валидатор ответа: получил статус и (для GET) начало тела — вернуть, «прошло» ли.
typedef ResponseValidator = bool Function(int statusCode, String body);

class ProbeOutcome {
  final bool ok;
  final int? statusCode;
  final int? rttMs;
  const ProbeOutcome({required this.ok, this.statusCode, this.rttMs});
}

/// HTTP-проба через локальный http-прокси порт (inbound проброс-харнесса Xray).
///
/// Dart HttpClient умеет ходить через HTTP-прокси нативно (включая CONNECT для https),
/// поэтому «via Proxy GET/HEAD» реализуется без SOCKS. Системный прокси НЕ трогается.
class ProxyProbe {
  /// Дозвониться до `host:port` ЧЕРЕЗ http-прокси методом CONNECT.
  ///
  /// Нужно там, где сервис говорит не по HTTP. Главный случай — Telegram:
  /// приложение общается с дата-центрами по MTProto, и обычный запрос к ним
  /// провалится на проверке сертификата, хотя канал жив. Значимо здесь ровно
  /// одно — установился ли туннель CONNECT до адреса.
  ///
  /// [proxyPort] == 0 — идём напрямую, мимо прокси (замер «до подключения»).
  static Future<ProbeOutcome> tcpConnect(
    int proxyPort,
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final sw = Stopwatch()..start();
    Socket? sock;
    try {
      if (proxyPort <= 0) {
        sock = await Socket.connect(host, port, timeout: timeout);
        sw.stop();
        return ProbeOutcome(ok: true, rttMs: sw.elapsedMilliseconds);
      }
      sock = await Socket.connect('127.0.0.1', proxyPort, timeout: timeout);
      // Заголовки CONNECT: минимальный корректный запрос без тела.
      final req = 'CONNECT ' + host + ':' + port.toString() + ' HTTP/1.1' +
          '\r\n' +
          'Host: ' + host + ':' + port.toString() + '\r\n' +
          '\r\n';
      sock.write(req);
      await sock.flush();

      // Ответ прокси — одна строка статуса; тело нам не нужно, поэтому берём
      // первые байты и не ждём закрытия соединения.
      final buf = <int>[];
      await for (final chunk in sock.timeout(timeout)) {
        buf.addAll(chunk);
        if (buf.length >= 16 || buf.contains(10)) break;
      }
      sw.stop();
      final head = String.fromCharCodes(buf.take(64));
      final ok = head.contains(' 200');
      return ProbeOutcome(
        ok: ok,
        statusCode: ok ? 200 : null,
        rttMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      return const ProbeOutcome(ok: false);
    } finally {
      try {
        await sock?.close();
      } catch (_) {}
      sock?.destroy();
    }
  }

  static Future<ProbeOutcome> check(
    int proxyPort,
    String url, {
    bool head = false,
    Duration timeout = const Duration(seconds: 5),
    ResponseValidator? validator,
    int maxBodyBytes = 64 * 1024,
  }) async {
    final client = HttpClient();
    // 0 — идти НАПРЯМУЮ, мимо туннеля. Нужно для замера «до подключения»:
    // без него сравнивать «до/после» было бы не с чем, а прописать прокси на
    // несуществующий порт значило бы получить отказ вместо честного замера.
    if (proxyPort > 0) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    }
    client.connectionTimeout = timeout;
    // Сертификат НЕ игнорируем: валидный TLS отсекает заглушки/MITM провайдера.

    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(url);
      final req = await client.openUrl(head ? 'HEAD' : 'GET', uri).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      final code = resp.statusCode;

      String body = '';
      if (!head && validator != null) {
        final bytes = <int>[];
        await for (final chunk in resp.timeout(timeout)) {
          bytes.addAll(chunk);
          if (bytes.length >= maxBodyBytes) break;
        }
        // UTF-8, а не fromCharCodes: иначе не-ASCII текст (типографская
        // апострофа U+2019, кириллица) в валидаторах гео-блока бьётся побайтово.
        body = utf8.decode(bytes, allowMalformed: true);
      } else {
        await resp.drain<void>();
      }
      sw.stop();

      final ok = validator != null
          ? validator(code, body)
          : (code == 204 || (code >= 200 && code < 400));
      return ProbeOutcome(ok: ok, statusCode: code, rttMs: sw.elapsedMilliseconds);
    } catch (_) {
      return const ProbeOutcome(ok: false);
    } finally {
      client.close(force: true);
    }
  }
}
