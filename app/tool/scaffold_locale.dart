// Быстрое добавление нового языка интерфейса.
//
// Использование:
//   dart run tool/scaffold_locale.dart <код> [ISO-страна-для-флага]
//   пример: dart run tool/scaffold_locale.dart de DE
//
// Что делает: читает базовый lib/l10n/app_ru.arb и создаёт lib/l10n/app_<код>.arb
// со ВСЕМИ ключами (значения — копии из ru как заготовка, чтобы тест паритета сразу
// был зелёным и язык «работал», показывая русский до перевода). Метаданные `@…`
// не копируются (они только в шаблоне-базе). Затем печатает оставшиеся 2 шага.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Укажите код языка: dart run tool/scaffold_locale.dart <код> [страна]');
    exit(2);
  }
  final code = args[0].trim().toLowerCase();
  final country = (args.length > 1 ? args[1] : code).trim().toUpperCase();

  final base = File('lib/l10n/app_ru.arb');
  if (!base.existsSync()) {
    stderr.writeln('Не найден базовый lib/l10n/app_ru.arb (запускать из папки app).');
    exit(1);
  }
  final target = File('lib/l10n/app_$code.arb');
  if (target.existsSync()) {
    stderr.writeln('Файл ${target.path} уже существует — не перезаписываю.');
    exit(1);
  }

  final src = jsonDecode(base.readAsStringSync()) as Map<String, dynamic>;
  // Порядок ключей сохраняем как в базе; значения-заготовки = русские.
  final out = <String, dynamic>{'@@locale': code};
  for (final e in src.entries) {
    if (e.key == '@@locale' || e.key.startsWith('@')) continue;
    out[e.key] = e.value; // заготовка: перевести вручную
  }
  target.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(out) + '\n');

  stdout.writeln('Создан ${target.path} (${out.length - 1} ключей, значения = ru-заготовки).');
  stdout.writeln('');
  stdout.writeln('Осталось 2 шага:');
  stdout.writeln("  1) Добавь язык в lib/core/i18n/app_locales.dart → supportedLanguages:");
  stdout.writeln("       AppLanguage('$code', '<Самоназвание>', '$country'),");
  stdout.writeln('  2) flutter gen-l10n');
  stdout.writeln('');
  stdout.writeln('Потом переведи значения в ${target.path} (ключи трогать НЕЛЬЗЯ — паритет).');
}
