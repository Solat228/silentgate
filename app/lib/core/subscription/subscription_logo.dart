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

  static final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final _srcAttr =
      RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _altLogo =
      RegExp(r'''alt\s*=\s*["']\s*logo\s*["']''', caseSensitive: false);
  static final _linkTag = RegExp(r'<link\b[^>]*>', caseSensitive: false);
  static final _hrefAttr =
      RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _relAttr =
      RegExp(r'''rel\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  final http.Client _client;
  SubscriptionLogo({http.Client? client}) : _client = client ?? http.Client();

  /// Автоматический поиск URL логотипа по ссылке подписки. Возвращает абсолютный
  /// URL либо null. Порядок: брендинг панели (`/assets/.app-config-v2.json`) →
  /// разбор HTML-страницы.
  ///
  /// Страницу подписки тянем ОДИН раз: она даёт и cookie `session` (ключ к
  /// `/assets/*`), и HTML для фолбэка.
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
    return extractLogoUrl(page.body, base: uri);
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
  ///  2) `<link rel="apple-touch-icon">` — крупная иконка сайта (180×180);
  ///  3) `<link rel="icon" ...>` c PNG — обычный favicon.
  /// ФОЛБЭК к брендингу панели (см. `_logoFromBranding`): страница подписки
  /// Remnawave — SPA, `<img>` рисуется скриптом и в статическом HTML его нет.
  /// Метод остаётся публичным: им же разбирается HTML обычных сайтов в
  /// `SiteFaviconService`. Относительные пути разрешаются от [base].
  static String? extractLogoUrl(String html, {Uri? base}) {
    String? resolve(String? src) {
      if (src == null || src.isEmpty || src.startsWith('data:')) return null;
      final parsed = Uri.tryParse(src);
      if (parsed == null) return null;
      return parsed.hasScheme
          ? parsed.toString()
          : (base?.resolveUri(parsed).toString() ?? src);
    }

    for (final m in _imgTag.allMatches(html)) {
      final tag = m.group(0)!;
      if (!_altLogo.hasMatch(tag)) continue;
      final url = resolve(_srcAttr.firstMatch(tag)?.group(1));
      if (url != null) return url;
    }

    String? touchIcon, pngIcon;
    for (final m in _linkTag.allMatches(html)) {
      final tag = m.group(0)!;
      final rel = _relAttr.firstMatch(tag)?.group(1)?.toLowerCase() ?? '';
      final url = resolve(_hrefAttr.firstMatch(tag)?.group(1));
      if (url == null) continue;
      if (rel.contains('apple-touch-icon')) {
        touchIcon ??= url;
      } else if (rel.contains('icon') && url.toLowerCase().endsWith('.png')) {
        pngIcon ??= url;
      }
    }
    return touchIcon ?? pngIcon;
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
