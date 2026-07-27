/// Преобразование веб-ссылки Telegram в deep-link `tg://…`.
///
/// Чистая функция без `dart:io`: на Windows результат отдаётся протоколу `tg`
/// (Telegram Desktop), на Android — интенту `ACTION_VIEW`. Логика разбора
/// одинакова, поэтому живёт в общем коде.
///
/// Возвращает `null`, если ссылка не телеграмная — вызывающий тогда открывает
/// её как обычный URL.
String? telegramDeepLink(String url) {
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
