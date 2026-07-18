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
  static Future<ProbeOutcome> check(
    int proxyPort,
    String url, {
    bool head = false,
    Duration timeout = const Duration(seconds: 5),
    ResponseValidator? validator,
    int maxBodyBytes = 64 * 1024,
  }) async {
    final client = HttpClient();
    client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
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
