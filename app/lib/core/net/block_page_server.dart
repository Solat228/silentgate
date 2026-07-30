import 'dart:io';

/// Локальный веб-сервер, отдающий страницу «сайт заблокирован правилом».
///
/// ## Что это даёт и чего НЕ даёт
///
/// Работает **только для plain HTTP**. Подменить страницу у `https://` без
/// своего корневого сертификата в системе НЕВОЗМОЖНО: браузер увидит чужой
/// сертификат и покажет ошибку TLS, а не нашу заглушку. Ставить в систему
/// собственный CA ради этого — цена несоразмерная: он позволяет расшифровывать
/// весь TLS-трафик пользователя, и это ровно то, от чего VPN должен защищать.
///
/// Поэтому обещание пользователю звучит так: по http откроется наша страница;
/// по https — обычная ошибка соединения, но домен всё равно заблокирован.
///
/// ## Почему сервер, а не DNS-ответ
///
/// Действие `predefined` в DNS-правилах появилось в sing-box 1.12, а на Windows
/// у нас 1.11.15 — ядро отвергает конфиг целиком («unknown DNS rule action»).
/// Проверено запуском. Зато `override_address`/`override_port` НА ПРАВИЛЕ
/// маршрутизации принимаются и 1.11, и 1.13 (у outbound те же поля объявлены
/// устаревшими и удалены в 1.13 — их брать нельзя).
/// Тексты страницы. Приходят снаружи уже переведёнными: сервер живёт в движке,
/// где нет `BuildContext`, а страницу читает пользователь — на своём языке.
class BlockPageTexts {
  const BlockPageTexts({
    required this.windowTitle,
    required this.heading,
    required this.body,
    required this.hint,
    required this.note,
  });

  final String windowTitle;
  final String heading;

  /// Текст с подставленным адресом: имя хоста известно только в момент запроса.
  final String Function(String host) body;

  final String hint;
  final String note;
}

class BlockPageServer {
  BlockPageServer._(this._server, this.port);

  final HttpServer _server;

  /// Порт, на который правила маршрутизации перенаправляют заблокированные
  /// соединения. 0 — сервер не поднят.
  final int port;

  static BlockPageServer? _current;
  static BlockPageServer? get current => _current;

  /// Поднять на свободном порту петли. `null` — не удалось; вызывающий обязан
  /// продолжить без заглушки, а не падать: блокировка важнее объяснения.
  static Future<BlockPageServer?> start({required BlockPageTexts texts}) async {
    // Порт запекается в конфиг ядра при подключении, поэтому прошлый сервер
    // гасим: иначе правило указывало бы на порт, который уже никто не слушает.
    await stopCurrent();
    try {
      // Только петля: наружу порт не выставляется никогда.
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final self = BlockPageServer._(srv, srv.port);
      srv.listen(
        (req) => self._handle(req, texts),
        onError: (_) {},
        cancelOnError: false,
      );
      return _current = self;
    } catch (_) {
      return null;
    }
  }

  static Future<void> stopCurrent() async => _current?.stop();

  Future<void> stop() async {
    if (identical(_current, this)) _current = null;
    try {
      await _server.close(force: true);
    } catch (_) {}
  }

  /// Прямая ссылка на заглушку для домена — в обход браузерного повышения.
  ///
  /// ⚠️ Зачем нужна. Перехватывается только plain HTTP, а браузеры давно
  /// повышают `http://` до `https://` сами (HSTS, HTTPS-First). Пользователь
  /// набирает адрес заблокированного сайта, браузер молча уходит на 443, там
  /// его встречает `reject` — и вместо объяснения человек видит обычную ошибку
  /// соединения. На петлю это повышение не распространяется: у `127.0.0.1`
  /// нет и не может быть HSTS-политики.
  static String? urlFor(String domain) {
    final port = _current?.port ?? 0;
    if (port <= 0) return null;
    return 'http://127.0.0.1:$port/?host=${Uri.encodeComponent(domain)}';
  }

  void _handle(HttpRequest req, BlockPageTexts t) {
    try {
      // Заголовок Host — это тот адрес, который набрал пользователь; сокет
      // ведёт на петлю и имени домена не знает. При заходе ПО ПРЯМОЙ ССЫЛКЕ
      // (кнопка в правилах) домен приходит параметром: иначе на странице стояло
      // бы «127.0.0.1» и объяснение теряло бы смысл.
      final host = _hostOnly(req.uri.queryParameters['host'] ??
          req.headers.host ??
          req.uri.host);
      req.response
        ..statusCode = HttpStatus.forbidden
        // Никакого кеша: разблокировав сайт, пользователь должен увидеть его
        // сразу, а не сохранённую заглушку.
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.contentType = ContentType.html
        ..write(_html(t, host));
      req.response.close();
    } catch (_) {}
  }

  /// Отрезать порт: `example.org:80` в тексте страницы выглядит мусором.
  static String _hostOnly(String value) {
    final i = value.lastIndexOf(':');
    if (i <= 0 || value.contains(']')) return value;
    return int.tryParse(value.substring(i + 1)) == null
        ? value
        : value.substring(0, i);
  }

  /// Экранирование: имя хоста приходит из заголовка запроса, то есть снаружи.
  /// Без него страница-заглушка сама стала бы дырой — вставкой чужой разметки
  /// в наш же ответ.
  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Страница намеренно самодостаточна: без внешних шрифтов, картинок и
  /// скриптов — она показывается ровно тогда, когда сеть до этого домена
  /// заблокирована, и любая внешняя ссылка тоже не загрузится.
  static String _html(BlockPageTexts t, String host) => '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(t.windowTitle)}</title>
<style>
 :root{color-scheme:light dark}
 body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
      font:16px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
      background:#f6f7f9;color:#1a1c1e}
 @media (prefers-color-scheme:dark){body{background:#16181a;color:#e6e7e9}
   .card{background:#1f2225!important;border-color:#2d3134!important}
   code{background:#2a2e31!important}}
 .card{max-width:34rem;margin:1.5rem;padding:1.75rem 2rem;background:#fff;
       border:1px solid #e3e6e8;border-radius:14px}
 h1{margin:0 0 .35rem;font-size:1.3rem}
 .host{font-size:1.02rem;overflow-wrap:anywhere}
 p{margin:.7rem 0}
 .muted{color:#6b7075;font-size:.92rem}
 code{background:#eef0f2;padding:.15rem .4rem;border-radius:5px;font-size:.9rem}
</style></head><body><div class="card">
<h1>${_esc(t.heading)}</h1>
<p class="host">${_esc(t.body(host))}</p>
<p class="muted">${_esc(t.hint)}</p>
<p class="muted">${_esc(t.note)}</p>
</div></body></html>
''';
}
