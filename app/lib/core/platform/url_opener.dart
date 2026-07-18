import 'dart:io';

/// Открытие ссылок во внешних приложениях (Windows).
class UrlOpener {
  /// Открыть URL в браузере по умолчанию.
  static Future<void> open(String url) async {
    if (url.trim().isEmpty) return;
    try {
      await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } catch (_) {}
  }

  /// Открыть ссылку на Telegram, отдав приоритет ДЕСКТОП-приложению.
  ///
  /// Для ссылок вида `https://t.me/<name>` или `tg://…` сначала пытаемся отдать
  /// её протоколу `tg://` (его обрабатывает установленный Telegram Desktop), и
  /// только если Telegram на ПК не найден — открываем обычную ссылку в браузере.
  /// Наличие Telegram определяем по зарегистрированному в реестре протоколу
  /// `tg` (HKCR\tg) — так мы не показываем юзеру системный диалог «нет
  /// приложения», когда десктопа нет.
  static Future<void> openTelegram(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final deep = _telegramDeepLink(u);
    if (deep != null && await _telegramInstalled()) {
      try {
        await Process.run('cmd', ['/c', 'start', '', deep], runInShell: true);
        return;
      } catch (_) {}
    }
    await open(u); // запасной вариант — браузер
  }

  /// Преобразует ссылку Telegram в deep-link `tg://…` или null, если это не она.
  static String? _telegramDeepLink(String url) {
    if (url.startsWith('tg://')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host != 't.me' && host != 'telegram.me' && host != 'telegram.dog') {
      return null;
    }
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    // Приглашения/джойны отдаём как есть — их разбирает сам Telegram по ссылке.
    if (segs.first == 'joinchat' || segs.first.startsWith('+')) {
      return 'tg://join?invite=${segs.length > 1 ? segs[1] : segs.first.substring(1)}';
    }
    final domain = segs.first;
    // /<name>/<postId> — ссылка на пост в канале.
    if (segs.length >= 2 && int.tryParse(segs[1]) != null) {
      return 'tg://resolve?domain=$domain&post=${segs[1]}';
    }
    final start = uri.queryParameters['start'];
    return 'tg://resolve?domain=$domain${start != null ? '&start=$start' : ''}';
  }

  /// Зарегистрирован ли в системе протокол `tg://` (признак Telegram Desktop).
  static Future<bool> _telegramInstalled() async {
    try {
      final r = await Process.run(
          'reg', ['query', r'HKCR\tg\shell\open\command'],
          runInShell: true);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    try {
      // Запасная проверка — пользовательская ветка (устанавливается без прав).
      final r = await Process.run(
          'reg', ['query', r'HKCU\Software\Classes\tg\shell\open\command'],
          runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
