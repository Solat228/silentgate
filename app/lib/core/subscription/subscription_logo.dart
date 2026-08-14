import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../platform/app_paths.dart';

/// Логотип (аватарка) подписки. Основной источник — брендинг панели Remnawave:
/// `/assets/.app-config-v2.json` → `brandingSettings.logoUrl`.
///
/// Этот путь отдаётся ТОЛЬКО при наличии cookie `session`
/// (`checkAssetsCookieMiddleware`: без куки бэкенд рвёт сокет — снаружи это
/// выглядит как 502 от Caddy, из-за чего раньше ошибочно считалось, что панель
/// блокирует нас по IP). Куку ставит сама страница подписки (`RootService`), и
/// только если User-Agent похож на браузерный. Поэтому порядок такой:
/// страница подписки с браузерным UA → cookie → конфиг брендинга.
/// Разбор HTML (`<img alt="logo">`/`<link rel=…>`) остаётся фолбэком.
///
/// Перебор типовых путей иконок (favicon/apple-touch-icon/logo.png) НЕ делаем:
/// `RootService.isGenericPath()` рвёт сокет для любого пути с расширением
/// картинки — эта стратегия обречена по построению.
///
/// ⚠️ Третья стратегия — для панелей, которые логотипа НЕ ХОСТЯТ ВООБЩЕ.
/// Разобран живой пример (панель на Express, страница подписки по `/s/<токен>`,
/// шаблон в духе `x0sina/marzban-sub`): cookie `session` не ставится, `/assets/*`
/// отдаёт 404, в HTML нет ни одного `<img>` с логотипом — фирменный знак нарисован
/// инлайновым `<svg>`, а `<link rel="icon">` указывает на `data:image/svg+xml` с
/// эмодзи. Отрисовать нечего: `Image.file` не умеет ни SVG, ни ICO. Единственная
/// РАСТРОВАЯ картинка бренда, на которую панель указывает сама, — аватарка
/// её Telegram-страницы из заголовков `profile-web-page-url` / `support-url`.
/// Оттуда её и берём — последней попыткой, уже уйдя с хоста панели.
///
/// Скачанная картинка кэшируется в `%APPDATA%\SilentGate\sub_logo_<id>.<ext>`,
/// чтобы не ходить в сеть при каждом запуске.
class SubscriptionLogo {
  /// UA браузера: с клиентским UA панель вернёт base64-подписку вместо HTML-страницы
  /// и НЕ поставит cookie `session` (RootService.isBrowser).
  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// Путь конфига subscription-page (APP_CONFIG_ROUTE_LEADING_PATH из
  /// @remnawave/subscription-page-types). Имя версионируется — держим запасные.
  static const _configPaths = <String>[
    '/assets/.app-config-v2.json',
    '/assets/app-config.json',
  ];

  /// Заголовки, которыми панель сама называет своё «лицо». Порядок значим:
  /// `profile-web-page-url` — страница профиля у той же панели, `support-url` —
  /// контакт поддержки (у мелких панелей это тот же бот, у крупных — чужой чат).
  static const _brandLinkHeaders = <String>[
    'profile-web-page-url',
    'support-url',
  ];

  static final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final _metaTag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final _srcAttr =
      RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _altLogo =
      RegExp(r'''alt\s*=\s*["']\s*logo\s*["']''', caseSensitive: false);
  static final _linkTag = RegExp(r'<link\b[^>]*>', caseSensitive: false);
  static final _hrefAttr =
      RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _relAttr =
      RegExp(r'''rel\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _typeAttr =
      RegExp(r'''type\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _classOrIdLogo = RegExp(
      r'''(?:class|id)\s*=\s*["'][^"']*logo[^"']*["']''',
      caseSensitive: false);
  static final _contentAttr =
      RegExp(r'''content\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _ogImageProp = RegExp(
      r'''(?:property|name)\s*=\s*["']og:image["']''',
      caseSensitive: false);

  /// Аватарка Telegram-страницы в разметке t.me.
  static final _tgPhotoClass =
      RegExp(r'tgme_page_photo_image', caseSensitive: false);

  /// Имя пользователя/канала/бота в Telegram (минимум 4 — короче не бывает).
  static final _tgUsername = RegExp(r'^[A-Za-z0-9_]{4,32}$');

  /// Служебные пути t.me: аватарки у них нет, тянуть незачем.
  static const _tgReserved = <String>{
    'joinchat',
    'proxy',
    'socks',
    'share',
    'addstickers',
    'addemoji',
    'addtheme',
    'setlanguage',
    'confirmphone',
    'login',
  };

  /// Расширения, которые `Image.file` НЕ отрисует: SVG и ICO Flutter не
  /// декодирует, а скачанный файл превратился бы в «битую картинку» и всё равно
  /// откатился бы на букву. Всё остальное (в том числе адрес без расширения)
  /// пробуем: декодер смотрит на байты, а не на имя.
  static const _unrenderableExt = <String>['.svg', '.ico'];

  final http.Client _client;
  SubscriptionLogo({http.Client? client}) : _client = client ?? http.Client();

  /// Автоматический поиск URL логотипа по ссылке подписки. Возвращает абсолютный
  /// URL либо null. Порядок: брендинг панели (`/assets/.app-config-v2.json`) →
  /// разбор HTML-страницы → аватарка Telegram-страницы из заголовков панели.
  ///
  /// Страницу подписки тянем ОДИН раз: она даёт и cookie `session` (ключ к
  /// `/assets/*`), и HTML для фолбэка, и заголовки со ссылками бренда.
  Future<String?> findUrl(String subscriptionUrl) async {
    final uri = Uri.tryParse(subscriptionUrl);
    if (uri == null) return null;

    final page = await _getRetry(uri, headers: {
      'User-Agent': _browserUa,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });
    if (page == null) return null;

    // 1) Брендинг панели — единственный источник настоящего логотипа.
    final fromBranding = await _logoFromBranding(uri, page);
    if (fromBranding != null) return fromBranding;

    // 2) Фолбэк: разметка страницы (у SPA обычно пусто, но дёшево).
    final fromHtml = extractLogoUrl(page.body, base: uri);
    if (fromHtml != null) return fromHtml;

    // 3) Панель картинки не хостит вовсе — берём аватарку её Telegram-страницы.
    //    Уходим с хоста панели, поэтому только последней попыткой.
    return _logoFromTelegram(page.headers);
  }

  /// Аватарка Telegram-страницы, на которую панель указывает своими заголовками.
  /// Единственная растровая картинка бренда у панелей без хостинга логотипа.
  Future<String?> _logoFromTelegram(Map<String, String> headers) async {
    for (final name in _brandLinkHeaders) {
      final page = telegramProfileUrl(headers[name]);
      if (page == null) continue;
      try {
        // Без `_getRetry`: t.me либо отвечает сразу, либо недоступен, а пять
        // повторов с паузами затянули бы импорт подписки на секунды.
        final resp = await _client.get(page, headers: {
          'User-Agent': _browserUa,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }).timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) continue;
        final avatar = extractTelegramAvatar(utf8.decode(resp.bodyBytes,
            allowMalformed: true));
        if (avatar != null) return avatar;
      } catch (_) {
        // Недоступен — пробуем следующий заголовок.
        // ⚠️ Сам `t.me` из РФ открывается, а вот выдаваемый им адрес картинки
        // (`cdn4.telesco.pe`) режется DPI на рукопожатии TLS — проверено. Тогда
        // упадёт уже `download`, и карточка честно останется с буквой; под
        // включённым VPN логотип скачается и ляжет в кэш насовсем.
      }
    }
    return null;
  }

  /// Нормализует ссылку из заголовка панели в адрес публичной страницы Telegram.
  /// Возвращает null для всего, что страницей с аватаркой не является.
  ///
  /// ⚠️ Запрос и фрагмент ОТБРАСЫВАЮТСЯ: панель кладёт в них идентификатор
  /// пользователя (`?start=profile_v2_<id>`), и отправлять его в Telegram ради
  /// картинки незачем. Одиночный сегмент пути обязателен — этим же отсекаются
  /// приглашения (`t.me/+AbCdEf`, `/joinchat/...`) и служебные пути (`/c/1/2`,
  /// `/i/userpic/...`), у которых публичной аватарки нет.
  static Uri? telegramProfileUrl(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    var host = uri.host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);
    if (host != 't.me' && host != 'telegram.me') return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    final name = segments.first;
    if (!_tgUsername.hasMatch(name)) return null;
    if (_tgReserved.contains(name.toLowerCase())) return null;
    return Uri.https('t.me', '/$name');
  }

  /// Аватарка со страницы t.me: сперва `<img class="tgme_page_photo_image">`
  /// (бот/канал/пользователь), затем `og:image` — им t.me отдаёт ту же картинку.
  /// Публичный ради теста и повторного использования.
  static String? extractTelegramAvatar(String html) {
    for (final m in _imgTag.allMatches(html)) {
      final tag = m.group(0)!;
      if (!_tgPhotoClass.hasMatch(tag)) continue;
      final src = _srcAttr.firstMatch(tag)?.group(1);
      if (_isHttpUrl(src)) return src;
    }
    for (final m in _metaTag.allMatches(html)) {
      final tag = m.group(0)!;
      if (!_ogImageProp.hasMatch(tag)) continue;
      final content = _contentAttr.firstMatch(tag)?.group(1);
      if (_isHttpUrl(content)) return content;
    }
    return null;
  }

  static bool _isHttpUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = Uri.tryParse(url);
    return u != null &&
        (u.scheme == 'https' || u.scheme == 'http') &&
        u.host.isNotEmpty;
  }

  /// Логотип из брендинга панели Remnawave.
  /// Бэкенд отдаёт `/assets/*` только с cookie `session` (checkAssetsCookieMiddleware),
  /// а куку ставит страница подписки — и только при браузерном UA (RootService.isBrowser).
  /// [page] — уже полученный ответ страницы подписки (из него берём Set-Cookie).
  Future<String?> _logoFromBranding(Uri subUri, http.Response page) async {
    final session = _sessionCookie(page.headers['set-cookie']);
    // Нет куки — значит `webpageAllowed: false` в SRR либо UA не сочли браузерным.
    if (session == null) return null;

    for (final path in _configPaths) {
      final url = subUri.replace(
        path: path,
        query: 'v=${DateTime.now().millisecondsSinceEpoch}',
      );
      try {
        final resp = await _client.get(url, headers: {
          'User-Agent': _browserUa,
          'Accept': 'application/json, text/plain, */*',
          'Cookie': 'session=$session',
          'Referer': subUri.toString(),
        }).timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) continue;
        final root = jsonDecode(utf8.decode(resp.bodyBytes));
        if (root is! Map) continue;
        final branding = root['brandingSettings'];
        if (branding is! Map) continue;
        final logo = branding['logoUrl'];
        if (logo is String && logo.trim().isNotEmpty) return logo.trim();
      } catch (_) {
        // битый JSON / оборванный сокет — пробуем следующий путь
      }
    }
    return null;
  }

  /// Значение cookie `session` из Set-Cookie (package:http склеивает их запятой).
  static String? _sessionCookie(String? setCookie) {
    if (setCookie == null) return null;
    return RegExp(r'(?:^|[,;\s])session=([^;,\s]+)')
        .firstMatch(setCookie)
        ?.group(1);
  }

  /// GET с повторами: панель периодически отдаёт 502, один заход почти всегда мимо.
  Future<http.Response?> _getRetry(Uri uri,
      {Map<String, String>? headers, int attempts = 5}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final r = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 12));
        if (r.statusCode >= 200 && r.statusCode < 300) return r;
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
    }
    return null;
  }

  /// Разбор HTML. Приоритет:
  ///  1) `<img alt="logo">` — прямой логотип (если страница отдаёт его в разметке);
  ///  2) `<img class="…logo…">` / `<img id="…logo…">` — та же картинка у панелей,
  ///     которые подпись `alt` не ставят;
  ///  3) `<link rel="apple-touch-icon">` — крупная иконка сайта (180×180);
  ///  4) `<link rel="icon" ...>` — обычный favicon.
  /// ФОЛБЭК к брендингу панели (см. `_logoFromBranding`): страница подписки
  /// Remnawave — SPA, `<img>` рисуется скриптом и в статическом HTML его нет.
  /// Метод остаётся публичным: им же разбирается HTML обычных сайтов в
  /// `SiteFaviconService`. Относительные пути разрешаются от [base].
  ///
  /// ⚠️ Иконки, которые нечем отрисовать (SVG, ICO — см. [_unrenderableExt]),
  /// пропускаются: файл скачался бы, а `Image.file` всё равно упал бы на букву.
  /// Расширение берётся из ПУТИ, а не из хвоста строки, иначе `?v=3` у
  /// `/favicon.png?v=3` прятал бы вполне рабочий favicon.
  static String? extractLogoUrl(String html, {Uri? base}) {
    String? resolve(String? src) {
      if (src == null || src.isEmpty || src.startsWith('data:')) return null;
      final parsed = Uri.tryParse(src);
      if (parsed == null) return null;
      return parsed.hasScheme
          ? parsed.toString()
          : (base?.resolveUri(parsed).toString() ?? src);
    }

    String? byImg(RegExp marker) {
      for (final m in _imgTag.allMatches(html)) {
        final tag = m.group(0)!;
        if (!marker.hasMatch(tag)) continue;
        final url = resolve(_srcAttr.firstMatch(tag)?.group(1));
        if (url != null && _renderable(url)) return url;
      }
      return null;
    }

    final byAlt = byImg(_altLogo);
    if (byAlt != null) return byAlt;
    final byClass = byImg(_classOrIdLogo);
    if (byClass != null) return byClass;

    String? touchIcon, icon;
    for (final m in _linkTag.allMatches(html)) {
      final tag = m.group(0)!;
      final rel = _relAttr.firstMatch(tag)?.group(1)?.toLowerCase() ?? '';
      final type = _typeAttr.firstMatch(tag)?.group(1)?.toLowerCase() ?? '';
      if (type.contains('svg') || type.contains('icon')) continue;
      final url = resolve(_hrefAttr.firstMatch(tag)?.group(1));
      if (url == null || !_renderable(url)) continue;
      if (rel.contains('apple-touch-icon')) {
        touchIcon ??= url;
      } else if (rel.contains('icon')) {
        icon ??= url;
      }
    }
    return touchIcon ?? icon;
  }

  /// Отрисует ли `Image.file` картинку по такому адресу. Отсекаем только заведомо
  /// нерастровые расширения — адрес без расширения (динамический маршрут) вполне
  /// может отдать PNG, декодер смотрит байты.
  static bool _renderable(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return !_unrenderableExt.any(path.endsWith);
  }

  /// Скачивает логотип в кэш и возвращает путь к файлу (null при неудаче).
  /// [cacheName] — имя файла БЕЗ расширения (по подписке, чтобы у разных
  /// подписок были свои логотипы и они не затирали друг друга).
  Future<String?> download(String imageUrl, {String cacheName = 'sub_logo'}) async {
    try {
      final resp = await _getRetry(Uri.parse(imageUrl),
          headers: {'User-Agent': _browserUa});
      if (resp == null || resp.bodyBytes.isEmpty) return null;
      final dir = await AppPaths.supportDir();
      final file = File(
          '${dir.path}${Platform.pathSeparator}$cacheName${_ext(imageUrl)}');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String _ext(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final e in const ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']) {
      if (path.endsWith(e)) return e;
    }
    return '.img';
  }

  void close() => _client.close();
}
