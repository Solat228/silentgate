import 'dart:convert';
import 'dart:io';

import 'xray_stats.dart';

/// Счётчики трафика sing-box через **Clash API**.
///
/// У sing-box нет аналога `xray api statsquery`, зато включённый в конфиге
/// `experimental.clash_api` отдаёт по HTTP `GET /connections` суммарные
/// `uploadTotal`/`downloadTotal` с момента старта ядра. Скорость приложение
/// считает само по разнице снимков — как и для Xray, поэтому наружу отдаётся
/// тот же [XrayTrafficSnapshot].
class SingboxStats {
  final int apiPort;

  /// Пароль Clash API этой сессии (см. [SingboxProxyConfigBuilder.apiSecret]).
  final String secret;
  const SingboxStats({this.apiPort = 10085, this.secret = ''});

  Future<XrayTrafficSnapshot> query() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$apiPort/connections'));
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return XrayTrafficSnapshot.zero;
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      if (j is! Map) return XrayTrafficSnapshot.zero;
      return XrayTrafficSnapshot(
        _int(j['uploadTotal']),
        _int(j['downloadTotal']),
      );
    } catch (_) {
      return XrayTrafficSnapshot.zero;
    } finally {
      client.close(force: true);
    }
  }

  static int _int(Object? v) =>
      v is int ? v : int.tryParse('${v ?? 0}'.split('.').first) ?? 0;
}
