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
      final global = XrayTrafficSnapshot(
        _int(j['uploadTotal']),
        _int(j['downloadTotal']),
      );
      if (!onlyProxy) return global;
      final proxied = _sumProxied(j['connections']);
      // ⚠️ ПАДАЕМ ОБРАТНО НА ГЛОБАЛЬНЫЕ СЧЁТЧИКИ, ЕСЛИ РАЗБОР ДАЛ НОЛЬ.
      //
      // Сумма по соединениям видит только ЖИВЫЕ соединения. Их может не быть
      // вовсе в момент опроса (всё уже закрылось), а у некоторых сборок ядра
      // поле `chains` приходит иначе — и тогда фильтр отбрасывает всё подряд.
      // Итог одинаковый: пользователь видит нули при работающем VPN, то есть
      // мы врём ему в самом заметном месте. Лучше показать чуть больше (с
      // прямым трафиком), чем ноль при идущей закачке.
      if (proxied.uplink == 0 && proxied.downlink == 0 &&
          (global.uplink > 0 || global.downlink > 0)) {
        return global;
      }
      return proxied;
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

  /// ЖИВ ЛИ ВЫХОД `exit-<id>` — по его собственной задержке.

  /// ⚠️ ЗАЧЕМ ОТДЕЛЬНАЯ ПРОБА. Выходы раздельного туннелирования живут внутри
  /// того же sing-box и порта наружу не имеют: сторож канала щупает только
  /// основной прокси, и смерть выхода в Эстонию не замечал никто. Clash API
  /// умеет спросить конкретный outbound по тегу — этим и пользуемся.
  ///
  /// ⚠️ ОТВЕТ 200 — ЭТО «ОТВЕТИЛ», А НЕ «БЫСТРО». Само значение задержки нам
  /// не нужно: решение принимает [ExitHealth] по числу промахов подряд, и
  /// порог по миллисекундам здесь означал бы «рвём выход за медленность».
  Future<bool> exitAlive(String tag,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final url = Uri.parse('http://127.0.0.1:$apiPort/proxies/'
          '${Uri.encodeComponent(tag)}/delay'
          '?timeout=${timeout.inMilliseconds}'
          '&url=${Uri.encodeComponent(_delayTarget)}');
      final req = await client.getUrl(url);
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(timeout);
      // Тело дочитываем всегда: брошенный ответ оставляет сокет висеть.
      await resp.drain<void>();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Переключить группу-выход [groupTag] на участника [memberTag].
  ///
  /// Возвращает `true`, если ядро приняло команду.
  ///
  /// ⚠️ ЭТО ЕДИНСТВЕННЫЙ СПОСОБ ПЕРЕКЛЮЧИТЬ `selector`. Группа сама не решает
  /// ничего — тем и хороша: в отличие от `urltest` она не пробует участников и
  /// не будит радио на телефоне каждые три минуты. Решение принимает сторож
  /// выходов по факту трёх промахов подряд и отдаёт его сюда.
  ///
  /// ⚠️ КОД ОТВЕТА ПРОВЕРЯЕТСЯ. Ядро отвечает 204 на успех и 400 на
  /// несуществующего участника; вернуть `true` не глядя значило бы отрапортовать
  /// о переключении, которого не было, — а именно на этом в проекте уже горели
  /// («ядро приняло конфиг» не значит «правило работает»).
  Future<bool> selectExitMember(String groupTag, String memberTag,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final url = Uri.parse('http://127.0.0.1:$apiPort/proxies/'
          '${Uri.encodeComponent(groupTag)}');
      final req = await client.putUrl(url);
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'name': memberTag}));
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Куда ходит проба задержки. Тот же адрес, что у сторожа канала: лёгкий,
  /// без тела, и не принадлежит ни одному сервису из проверяемых.
  static const _delayTarget = 'http://www.gstatic.com/generate_204';

  static int _int(Object? v) =>
      v is int ? v : int.tryParse('${v ?? 0}'.split('.').first) ?? 0;
}
