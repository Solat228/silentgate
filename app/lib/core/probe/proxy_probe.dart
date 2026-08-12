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
  /// Креды локального инбаунда проб текущей сессии.
  ///
  /// ⚠️ ЖИВУТ ТОЛЬКО В ПАМЯТИ. На Android loopback не изолирован между
  /// приложениями, поэтому инбаунд проб закрыт паролем (см. `probeUser` в
  /// `SingboxConfigBuilder`) — и клиент обязан его предъявлять, иначе ядро
  /// ответит 407, и КАЖДЫЙ сервис покажется недоступным при исправном
  /// соединении. Ровно на этом сгорел v2rayNG (#5549): включили
  /// аутентификацию, забыли прокинуть в потребителя, получили «подключено,
  /// интернета нет». Поэтому оба конца меняются одним коммитом.
  ///
  /// Пусто — инбаунд без пароля (Windows: туда ходит системный прокси, а
  /// WinINET креденшелов не несёт).
  static String user = '';
  static String password = '';

  /// Значение заголовка `Proxy-Authorization`, либо null если пароля нет.
  static String? get authHeader {
    if (user.isEmpty) return null;
    return 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
  }
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
      final auth = authHeader;
      final req = 'CONNECT ' + host + ':' + port.toString() + ' HTTP/1.1' +
          '\r\n' +
          'Host: ' + host + ':' + port.toString() + '\r\n' +
          (auth == null ? '' : 'Proxy-Authorization: ' + auth + '\r\n') +
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

    /// Креды ИМЕННО ЭТОГО порта. `null` — взять сессионные [user]/[password].
    ///
    /// ⚠️ Понадобились, когда проб стало два вида сразу: активный сервер
    /// проверяется через ЖИВОЕ ядро (его пароль — в статиках), а остальные —
    /// через харнесс со СВОИМ паролем на прогон. Общие статики тут молча
    /// подставили бы чужой пароль, и половина серверов получила бы 407, то есть
    /// «не работает» на исправном канале.
    String? proxyUser,
    String? proxyPassword,
  }) async {
    final client = HttpClient();
    // 0 — идти НАПРЯМУЮ, мимо туннеля. Нужно для замера «до подключения»:
    // без него сравнивать «до/после» было бы не с чем, а прописать прокси на
    // несуществующий порт значило бы получить отказ вместо честного замера.
    if (proxyPort > 0) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
      // Пароль инбаунда проб — без него ядро ответит 407, и все сервис-чипы
      // покрасятся в красный при живом соединении.
      final u = proxyUser ?? user;
      final p = proxyPassword ?? password;
      if (u.isNotEmpty) {
        client.addProxyCredentials(
            '127.0.0.1', proxyPort, '', HttpClientBasicCredentials(u, p));
      }
    } else {
      // ⚠️ «Напрямую» ЗАДАЁТСЯ ЯВНО, а не оставляется на умолчание SDK.
      // Раньше в этой ветке `findProxy` не трогали вовсе, и куда пойдёт запрос,
      // решал Dart: его умолчание — `HttpClient.findProxyFromEnvironment`-подобное
      // поведение, зависящее от переменных окружения (`http_proxy`/`all_proxy`).
      // На машине, где они выставлены, замер «без VPN» тихо уходил бы через
      // ЧУЖОЙ прокси — и сравнение «до/после» сравнивало бы не то, что обещает.
      client.findProxy = (_) => 'DIRECT';
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
