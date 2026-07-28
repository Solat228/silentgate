import 'dart:convert';
import 'dart:io';

import '../platform/app_paths.dart';
import '../subscription/subscription_logo.dart';

/// Иконка (favicon) сайта для списка раздельного туннелирования.
///
/// Сначала пробуем взять иконку НАПРЯМУЮ с самого сайта (apple-touch-icon / png),
/// без посредников. Если не вышло — запасной вариант через сервис Google
/// (`s2/favicons`, отдаёт PNG для большинства сайтов). Результат кэшируется в
/// `%APPDATA%\SilentGate\site_icons\<домен>.png`, чтобы не ходить в сеть на
/// каждую перерисовку. Flutter рисует только PNG, поэтому `.ico` не берём.
class SiteFaviconService {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static final Map<String, String?> _mem = {};
  static final Map<String, Future<String?>> _pending = {};

  /// Путь к PNG-иконке домена или null. Кэшируется в памяти и на диске.
  static Future<String?> iconFor(String domain) {
    final d = domain.trim().toLowerCase();
    if (d.isEmpty) return Future.value(null);
    if (_mem.containsKey(d)) return Future.value(_mem[d]);
    return _pending.putIfAbsent(d, () => _resolve(d)).then((path) {
      _mem[d] = path;
      _pending.remove(d);
      return path;
    });
  }

  static Future<String?> _resolve(String domain) async {
    try {
      final dir = await AppPaths.supportDir();
      final cacheDir =
          Directory('${dir.path}${Platform.pathSeparator}site_icons');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final safe = domain.replaceAll(RegExp(r'[^a-z0-9.\-]'), '_');
      final file =
          File('${cacheDir.path}${Platform.pathSeparator}$safe.png');
      if (await file.exists() && await file.length() > 0) return file.path;

      // 1) Иконка, объявленная на самой странице сайта (apple-touch-icon/icon):
      //    работает там, где типовые пути пустые.
      final fromHtml = await _iconFromHtml(domain);
      // sub.domain → корневой домен (favicon чаще лежит на корне).
      final root = rootDomain(domain);
      // 2) Типовые пути напрямую. 3) Сервисы-агрегаторы фавиконок (отдают PNG
      //    даже там, где у сайта только .ico — напр. steam.com).
      final sources = <String>[
        if (fromHtml != null) fromHtml,
        'https://$domain/apple-touch-icon.png',
        'https://$domain/apple-touch-icon-precomposed.png',
        'https://$domain/favicon.png',
        if (root != domain) 'https://$root/apple-touch-icon.png',
        // Агрегатор — отдаёт настоящий PNG даже для сайтов с одним лишь .ico
        // (напр. steam.com), где прямые пути и Google s2 пустуют.
        'https://favicone.com/$domain?s=64',
        'https://www.google.com/s2/favicons?sz=64&domain=$domain',
        // По корню — только если он отличается (иначе дубль того же запроса).
        if (root != domain)
          'https://www.google.com/s2/favicons?sz=64&domain=$root',
      ];
      for (final url in sources) {
        final bytes = await _getPng(url);
        if (bytes != null) {
          await file.writeAsBytes(bytes, flush: true);
          return file.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Достаёт URL иконки со страницы сайта (`<link rel="apple-touch-icon">` и т.п.),
  /// разбором HTML — той же логикой, что и логотип подписки.
  static Future<String?> _iconFromHtml(String domain) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = _ua;
    try {
      final uri = Uri.parse('https://$domain/');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final ct = resp.headers.contentType?.mimeType ?? '';
      if (!ct.contains('html')) return null;
      final bytes = <int>[];
      await for (final c in resp.timeout(const Duration(seconds: 8))) {
        bytes.addAll(c);
        if (bytes.length > 512 * 1024) break; // хватит на <head>
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      return SubscriptionLogo.extractLogoUrl(body, base: uri);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Скачивает URL, если это PNG. Один повтор на случай флапа сервера.
  /// Корневой домен: `www.sub.example.co.uk` → `example.co.uk`. Простой разбор
  /// с учётом двухуровневых суффиксов (co.uk, com.br и т.п.) — фавикон чаще
  /// лежит на корне, чем на конкретном поддомене. Публичный ради юнит-теста.
  static String rootDomain(String domain) {
    final parts = domain.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return domain;
    const twoLevel = {
      'co', 'com', 'org', 'net', 'gov', 'edu', 'ac', 'or', 'ne', 'go'
    };
    // Если предпоследняя метка — типичный «второй уровень» (co.uk, com.br), берём
    // три. Последняя метка при этом — ДВУХбуквенный ccTLD (uk/br/au): условие
    // `== 2` отсекает ложный `X.go.com` (com — 3-буквенный gTLD, не ccTLD).
    if (twoLevel.contains(parts[parts.length - 2]) &&
        parts[parts.length - 1].length == 2) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  static Future<List<int>?> _getPng(String url) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6)
        ..userAgent = _ua;
      try {
        var uri = Uri.parse(url);
        var req = await client.getUrl(uri);
        var resp = await req.close().timeout(const Duration(seconds: 8));
        // Google отдаёт 301 на CDN — идём по редиректу вручную.
        var hops = 0;
        while ((resp.statusCode == 301 || resp.statusCode == 302) &&
            resp.headers.value(HttpHeaders.locationHeader) != null &&
            hops < 3) {
          uri = uri.resolve(resp.headers.value(HttpHeaders.locationHeader)!);
          req = await client.getUrl(uri);
          resp = await req.close().timeout(const Duration(seconds: 8));
          hops++;
        }
        if (resp.statusCode != 200) {
          client.close(force: true);
          continue;
        }
        final ct = resp.headers.contentType?.mimeType ?? '';
        // Ограничиваем и объём (фавикон — килобайты; иначе враждебный/битый ответ
        // раздул бы память), и время чтения тела (иначе зависший поток висел бы).
        const maxBytes = 512 * 1024;
        final bytes = <int>[];
        await for (final c in resp.timeout(const Duration(seconds: 8))) {
          bytes.addAll(c);
          if (bytes.length >= maxBytes) break;
        }
        client.close(force: true);
        // Признак PNG — либо Content-Type, либо магические байты.
        final isPng = ct == 'image/png' ||
            (bytes.length > 8 &&
                bytes[0] == 0x89 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x4e &&
                bytes[3] == 0x47);
        if (isPng && bytes.isNotEmpty) return bytes;
        return null; // ответ есть, но не PNG — другие источники пробовать смысла нет
      } catch (_) {
        client.close(force: true);
      }
    }
    return null;
  }
}
