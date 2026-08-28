/// Разбор флаг-эмодзи в имени сервера/подписки. Эмодзи-флаги не рендерятся на Windows,
/// поэтому вытаскиваем ISO-код и рисуем картинку-флаг отдельной ячейкой (пакет country_flags).
class FlagUtil {
  static const _base = 0x1F1E6; // regional indicator 'A'
  static const _last = 0x1F1FF; // regional indicator 'Z'

  /// До ДВУХ ISO 3166-1 alpha-2 кодов из флаг-эмодзи в [name], в порядке
  /// появления (мост «вход · выход» несёт два флага подряд).
  ///
  /// ⚠️ После найденной пары индекс двигаем на i+2, а не на i+1: иначе вторая
  /// руна первой пары склеится с первой руной второй и даст мусорный код
  /// (например из 🇳🇱🇨🇿 вместо NL/CZ вышло бы NL/LC).
  static List<String> isoCodesFromName(String name) {
    final runes = name.runes.toList();
    final result = <String>[];
    var i = 0;
    while (i < runes.length - 1 && result.length < 2) {
      final a = runes[i];
      final b = runes[i + 1];
      if (a >= _base && a <= _last && b >= _base && b <= _last) {
        final c1 = String.fromCharCode(0x41 + (a - _base));
        final c2 = String.fromCharCode(0x41 + (b - _base));
        result.add('$c1$c2');
        i += 2;
      } else {
        i++;
      }
    }
    return result;
  }

  /// Первый ISO 3166-1 alpha-2 код из флаг-эмодзи в [name], либо null.
  /// Обёртка над [isoCodesFromName] — на неё завязаны другие экраны.
  static String? isoFromName(String name) {
    final codes = isoCodesFromName(name);
    return codes.isEmpty ? null : codes.first;
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
