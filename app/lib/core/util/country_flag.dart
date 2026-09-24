/// Кусок провайдерского текста (notice-сервер, объявление подписки) после
/// разбора на обычный текст и флаг-пары: у части задано РОВНО одно из полей.
/// Используется тем, кто рисует текст флагами вместо голых regional-indicator
/// эмодзи (Windows их не рендерит — см. класс [FlagUtil] ниже).
class FlagTextPart {
  final String? text;
  final String? flagCode; // ISO 3166-1 alpha-2, если это флаг-пара
  const FlagTextPart.text(this.text) : flagCode = null;
  const FlagTextPart.flag(this.flagCode) : text = null;
}

/// Разбор флаг-эмодзи в имени сервера/подписки. Эмодзи-флаги не рендерятся на Windows,
/// поэтому вытаскиваем ISO-код и рисуем картинку-флаг отдельной ячейкой (пакет country_flags).
class FlagUtil {
  static const _base = 0x1F1E6; // regional indicator 'A'
  static const _last = 0x1F1FF; // regional indicator 'Z'

  static bool _isIndicator(int rune) => rune >= _base && rune <= _last;

  /// Весь [text] целиком, куском по кускам: обычный текст и флаг-пары в
  /// порядке появления. В отличие от [isoCodesFromName] (только ДВЕ первых
  /// пары, для моста «вход · выход»), здесь пар может быть сколько угодно —
  /// нужно для длинного текста notice/announce, где панель может вставить
  /// несколько флагов подряд.
  ///
  /// Непарный regional-indicator (одна половина без соседа) остаётся ПРОСТЫМ
  /// ТЕКСТОМ — рисовать нечего, а откусывать символ значило бы портить текст.
  static List<FlagTextPart> splitFlagPairs(String text) {
    final runes = text.runes.toList();
    final parts = <FlagTextPart>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        parts.add(FlagTextPart.text(buf.toString()));
        buf.clear();
      }
    }

    var i = 0;
    while (i < runes.length) {
      if (i < runes.length - 1 &&
          _isIndicator(runes[i]) &&
          _isIndicator(runes[i + 1])) {
        flush();
        final c1 = String.fromCharCode(0x41 + (runes[i] - _base));
        final c2 = String.fromCharCode(0x41 + (runes[i + 1] - _base));
        parts.add(FlagTextPart.flag('$c1$c2'));
        i += 2;
      } else {
        buf.writeCharCode(runes[i]);
        i++;
      }
    }
    flush();
    return parts;
  }

  /// Первые [cap] «рун» [text] (не UTF-16 code unit — иначе резать посреди
  /// суррогатной пары), но не РОВНО на границе флаг-пары: обрезать после
  /// первой половины значило бы оставить висячий непарный индикатор вместо
  /// текста или флага. В этом случае откусываем ещё и её саму.
  ///
  /// ⚠️ «ОБА СОСЕДА — ИНДИКАТОРЫ» ЕЩЁ НЕ ЗНАЧИТ «ГРАНИЦА ВНУТРИ ПАРЫ». Пары
  /// считаются от НАЧАЛА подряд идущих индикаторов (offset чётный = первая
  /// половина, нечётный = вторая): при `(I0I1)(I2I3)` резка после `I1` режет
  /// МЕЖДУ парами и трогать ничего не нужно, хотя оба соседних символа —
  /// индикаторы. Поэтому чётность считаем от начала подряд идущей группы.
  static String truncateRunes(String text, int cap) {
    final runes = text.runes.toList();
    if (runes.length <= cap) return text;
    var end = cap;
    if (end > 0 && _isIndicator(runes[end - 1]) && _isIndicator(runes[end])) {
      var runStart = end - 1;
      while (runStart > 0 && _isIndicator(runes[runStart - 1])) {
        runStart--;
      }
      final offset = (end - 1) - runStart;
      if (offset.isEven) end -= 1; // руна end-1 — первая половина своей пары
    }
    return String.fromCharCodes(runes.sublist(0, end));
  }

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
