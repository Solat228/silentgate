import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Считать ТОЛЬКО трафик, ушедший через VPN.
  ///
  /// ⚠️ `uploadTotal`/`downloadTotal` в Clash API — ГЛОБАЛЬНЫЕ счётчики ядра.
  /// В них входит всё, что ядро прогнало, включая уведённое мимо VPN: правила
  /// «Прямо», `bypassLan`, локальный DNS. На Windows это не мешало (там
  /// опрашивается ОТДЕЛЬНОЕ прокси-ядро, а туннель считается своим), а на
  /// Android ядро ОДНО — и цифра под кнопкой показывала весь трафик устройства.
  /// Особенно неприятно рядом с остатком по подписке: числа выглядят
  /// сопоставимыми, а меряют разное.
  ///
  /// Включено — суммируем по СОЕДИНЕНИЯМ, отбрасывая те, чья цепочка содержит
  /// наши не-VPN теги. Болезнь отраслевая: у Clash Verge Rev это открытый
  /// запрос #7348, у FlClash решено тем же способом (`onlyProxy`).
  final bool onlyProxy;

  /// Теги outbound'ов, которые НЕ считаются VPN. Задаются нами же в построителе
  /// конфига, поэтому переименование тега там обязано отражаться здесь —
  /// иначе счётчик молча начнёт считать прямой трафик за проксированный.
  static const directTags = {'direct', 'block', 'dns', 'dns-out', 'dns_out'};

  const SingboxStats(
      {this.apiPort = 10085, this.secret = '', this.onlyProxy = false});

  /// `null` — опрос НЕ УДАЛСЯ (таймаут, не-200, мусор в ответе).
  ///
  /// ⚠️ Раньше здесь возвращался ноль, и движок принимал его за настоящий
  /// отсчёт: счётчик «падал» до нуля, а на следующем удачном опросе разница
  /// давала фальшивый всплеск скорости. Плюс `AppState` трактует падение
  /// счётчика как перезапуск ядра — и удваивал трафик «за сессию».
  Future<XrayTrafficSnapshot?> query() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$apiPort/connections'));
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      if (j is! Map) return null;
      if (!onlyProxy) {
        return XrayTrafficSnapshot(
          _int(j['uploadTotal']),
          _int(j['downloadTotal']),
        );
      }
      return _sumProxied(j['connections']);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Сумма по живым соединениям, ушедшим через VPN.
  ///
  /// ⚠️ ЭТО ОЦЕНКА, И ОНА ЗАНИЖЕНА. Снимок `/connections` — только ЖИВЫЕ
  /// соединения; закрытые ядро складывает в кольцо на 1000 штук БЕЗ срока
  /// давности. При активном сёрфинге кольцо перематывается за минуты, поэтому
  /// трафик соединений, родившихся и умерших между тактами опроса, сюда не
  /// попадёт. Честная альтернатива — событийный поток соединений; пока его нет,
  /// лучше занижать, чем показывать чужой трафик своим.
  static XrayTrafficSnapshot _sumProxied(Object? raw) {
    if (raw is! List) return const XrayTrafficSnapshot(0, 0);
    var up = 0, down = 0;
    for (final c in raw) {
      if (c is! Map) continue;
      final chains = c['chains'];
      if (chains is List &&
          chains.any((t) => directTags.contains((t ?? '').toString().toLowerCase()))) {
        continue; // ушло мимо VPN — не наш трафик
      }
      up += _int(c['upload']);
      down += _int(c['download']);
    }
    return XrayTrafficSnapshot(up, down);
  }

  /// Только для тестов: проверить разделение без сети.
  @visibleForTesting
  static XrayTrafficSnapshot sumProxiedForTest(Object? raw) => _sumProxied(raw);

  static int _int(Object? v) =>
      v is int ? v : int.tryParse('${v ?? 0}'.split('.').first) ?? 0;
}
