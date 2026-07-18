/// Разбор флаг-эмодзи в имени сервера/подписки. Эмодзи-флаги не рендерятся на Windows,
/// поэтому вытаскиваем ISO-код и рисуем картинку-флаг отдельной ячейкой (пакет country_flags).
class FlagUtil {
  static const _base = 0x1F1E6; // regional indicator 'A'
  static const _last = 0x1F1FF; // regional indicator 'Z'

  /// Первый ISO 3166-1 alpha-2 код из флаг-эмодзи в [name], либо null.
  static String? isoFromName(String name) {
    final runes = name.runes.toList();
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i];
      final b = runes[i + 1];
      if (a >= _base && a <= _last && b >= _base && b <= _last) {
        final c1 = String.fromCharCode(0x41 + (a - _base));
        final c2 = String.fromCharCode(0x41 + (b - _base));
        return '$c1$c2';
      }
    }
    return null;
  }

  /// Имя без флаг-эмодзи (и схлопнутых пробелов).
  static String strip(String name) {
    final sb = StringBuffer();
    for (final r in name.runes) {
      if (r >= _base && r <= _last) continue;
      sb.writeCharCode(r);
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
