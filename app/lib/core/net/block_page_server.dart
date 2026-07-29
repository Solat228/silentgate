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
  static Future<BlockPageServer?> start({
    required String appName,
    required String settingsHint,
  }) async {
    if (_current != null) return _current;
    try {
      // Только петля: наружу порт не выставляется никогда.
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final self = BlockPageServer._(srv, srv.port);
      srv.listen(
        (req) => self._handle(req, appName, settingsHint),
        onError: (_) {},
        cancelOnError: false,
      );
      return _current = self;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    _current = null;
    try {
      await _server.close(force: true);
    } catch (_) {}
  }

  void _handle(HttpRequest req, String appName, String hint) {
    try {
      final host = req.headers.host ?? req.uri.host;
      req.response
        ..statusCode = HttpStatus.forbidden
        // Никакого кеша: разблокировав сайт, пользователь должен увидеть его
        // сразу, а не сохранённую заглушку.
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.contentType = ContentType.html
        ..write(_html(appName, host, hint));
      req.response.close();
    } catch (_) {}
  }

  /// Страница намеренно самодостаточна: без внешних шрифтов, картинок и
  /// скриптов — она показывается ровно тогда, когда сеть до этого домена
  /// заблокирована, и любая внешняя ссылка тоже не загрузится.
  static String _html(String appName, String host, String hint) => '''
<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Заблокировано — $appName</title>
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
 .host{font-weight:600;word-break:break-all}
 p{margin:.7rem 0}
 .muted{color:#6b7075;font-size:.92rem}
 code{background:#eef0f2;padding:.15rem .4rem;border-radius:5px;font-size:.9rem}
</style></head><body><div class="card">
<h1>Сайт заблокирован</h1>
<p>Адрес <span class="host">$host</span> заблокирован правилом раздельного
   туннелирования в <strong>$appName</strong>.</p>
<p class="muted">$hint</p>
<p class="muted">Это страница самого приложения, а не ошибка сети. Сайт не
   открывается потому, что вы сами добавили его в список блокировки.</p>
</div></body></html>
''';
}
