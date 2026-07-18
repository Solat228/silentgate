// Служебный тул для i18n-миграции: сливает ARB-заготовки агентов в основные ARB.
//
// Использование:
//   dart run tool/merge_l10n.dart <dir-с-json>
//
// В <dir> лежат файлы вида <что-угодно>.json со структурой:
//   { "ru": {"key": "…"}, "en": {"key": "…"}, "es": {"key": "…"} }
// Скрипт добавляет эти ключи в lib/l10n/app_{ru,en,es}.arb (перед последней
// закрывающей скобкой, сохраняя существующее). Дубли ключей — ошибка (стоп).
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Укажите папку с json: dart run tool/merge_l10n.dart <dir>');
    exit(2);
  }
  final dir = Directory(args[0]);
  if (!dir.existsSync()) {
    stderr.writeln('Папка не найдена: ${args[0]}');
    exit(1);
  }

  // Все локали, что реально лежат в lib/l10n (app_<code>.arb).
  final locales = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .map((f) => RegExp(r'app_([a-z]{2})\.arb$').firstMatch(f.path)?.group(1))
      .whereType<String>()
      .toList()
    ..sort();
  final add = {for (final l in locales) l: <String, String>{}};

  final jsons = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in jsons) {
    final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final loc in locales) {
      final m = (data[loc] as Map?) ?? const {};
      m.forEach((k, v) {
        final key = '$k';
        if (add[loc]!.containsKey(key)) {
          stderr.writeln('Дубликат ключа "$key" ($loc) в ${f.path} — стоп.');
          exit(1);
        }
        add[loc]![key] = '$v';
      });
    }
  }

  for (final loc in locales) {
    final path = 'lib/l10n/app_$loc.arb';
    final file = File(path);
    final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    var added = 0, dup = 0;
    add[loc]!.forEach((k, v) {
      if (map.containsKey(k)) {
        dup++;
      } else {
        map[k] = v;
        added++;
      }
    });
    file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(map) + '\n');
    stdout.writeln('$path: +$added ключей (уже были: $dup).');
  }
  stdout.writeln('Готово. Запусти: flutter gen-l10n');
}
