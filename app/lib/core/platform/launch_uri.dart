/// Проверка ссылки перед тем, как отдать её системе на открытие.
///
/// ⚠️ ССЫЛКИ ПРИХОДЯТ ОТ ЧУЖИХ СЕРВЕРОВ. Адрес поддержки — заголовок
/// `support-url` любой панели подписки, адрес подписки вставляет человек.
/// На Windows ссылка уходила в `cmd /c start "" <ссылка>`, а Dart берёт
/// аргумент в кавычки только при пробеле, табуляции или кавычке: ссылка
/// `https://x/?a&calc` доходила до `cmd` голой, и всё после `&` исполнялось
/// отдельной командой. Аудит 25.10.2026.
///
/// Поэтому две защиты, и обе нужны:
///  * схема только из белого списка — `file:`, путь к exe или общая папка
///    сети открывались бы системой как программа;
///  * ссылка пересобирается через [Uri]: кавычки, пробелы, `^`, `|`, `<`, `>`
///    и управляющие символы становятся `%XX`, сырыми до системы не доходят.
library;

/// Схемы, которые приложение вообще открывает.
const Set<String> kLaunchSchemes = {
  'http',
  'https',
  'tg',
  'mailto',
  'ms-windows-store',
};

/// Безопасная форма [raw] или `null`, если открывать её нельзя.
String? safeLaunchUri(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final u = Uri.tryParse(t);
  if (u == null) return null;
  final scheme = u.scheme.toLowerCase();
  if (!kLaunchSchemes.contains(scheme)) return null;
  if ((scheme == 'http' || scheme == 'https') && u.host.isEmpty) return null;
  final s = u.toString();
  // Uri кодирует опасное сам; проверка — на случай, если что-то проскочит.
  for (final c in s.codeUnits) {
    if (c <= 0x20 || c == 0x7f || c == 0x22) return null;
  }
  return s;
}
