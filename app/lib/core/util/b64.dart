import 'dart:convert';

/// Утилиты base64, устойчивые к url-safe алфавиту и отсутствию паддинга —
/// именно в таком виде подписки часто приходят от панелей.
class B64 {
  static String _normalize(String input) {
    var s = input.trim().replaceAll('\n', '').replaceAll('\r', '');
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad > 0) s += '=' * (4 - pad);
    return s;
  }

  /// Декодирует base64 в строку UTF-8. Бросает [FormatException] при ошибке.
  static String decodeToString(String input) {
    return utf8.decode(base64.decode(_normalize(input)), allowMalformed: true);
  }

  /// Декодирует base64 в байты.
  static List<int> decodeToBytes(String input) {
    return base64.decode(_normalize(input));
  }

  /// Пытается декодировать; при неудаче возвращает null.
  static String? tryDecodeToString(String input) {
    try {
      return decodeToString(input);
    } catch (_) {
      return null;
    }
  }
}
