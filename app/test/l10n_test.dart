import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Тесты полноты локализации: гарантируют, что переводы не «половинчатые».
/// Если добавить ключ в базовый app_ru.arb и забыть про en/es (или наоборот) —
/// эти тесты упадут. Читают ARB прямо с диска (cwd теста = корень пакета app).
void main() {
  const base = 'lib/l10n/app_ru.arb';
  // Динамически: проверяем ВСЕ файлы переводов app_<code>.arb (кроме базы ru).
  // Добавил язык — тест сам его подхватит.
  final locales = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .map((f) => RegExp(r'app_([a-z]{2})\.arb$').firstMatch(f.path)?.group(1))
      .whereType<String>()
      .where((c) => c != 'ru')
      .toList()
    ..sort();

  /// Ключи сообщений (без метаданных `@…` и служебного `@@locale`).
  Set<String> messageKeys(String path) {
    final raw = File(path).readAsStringSync();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('базовый ARB (ru) существует и непустой', () {
    expect(File(base).existsSync(), isTrue, reason: '$base не найден');
    expect(messageKeys(base), isNotEmpty);
  });

  for (final loc in locales) {
    final path = 'lib/l10n/app_$loc.arb';

    test('$loc: файл перевода существует', () {
      expect(File(path).existsSync(), isTrue, reason: '$path не найден');
    });

    test('$loc: набор ключей ТОЧНО совпадает с базой (ru)', () {
      final ruKeys = messageKeys(base);
      final locKeys = messageKeys(path);
      final missing = ruKeys.difference(locKeys); // есть в ru, нет в переводе
      final extra = locKeys.difference(ruKeys); // лишние, которых нет в базе
      expect(missing, isEmpty,
          reason: 'В $path не переведены ключи: ${missing.join(", ")}');
      expect(extra, isEmpty,
          reason: 'В $path лишние ключи (нет в базе ru): ${extra.join(", ")}');
    });

    test('$loc: у каждого ключа непустое значение', () {
      final map = jsonDecode(File(path).readAsStringSync())
          as Map<String, dynamic>;
      for (final e in map.entries) {
        if (e.key.startsWith('@')) continue;
        expect((e.value as String).trim(), isNotEmpty,
            reason: 'Пустой перевод ключа "${e.key}" в $path');
      }
    });

    test('$loc: объявлен корректный @@locale', () {
      final map = jsonDecode(File(path).readAsStringSync())
          as Map<String, dynamic>;
      expect(map['@@locale'], loc);
    });
  }

  test('плейсхолдеры совпадают во всех локалях (нет потерянных {…})', () {
    final re = RegExp(r'\{(\w+)\}');
    Map<String, Set<String>> placeholders(String path) {
      final map = jsonDecode(File(path).readAsStringSync())
          as Map<String, dynamic>;
      final out = <String, Set<String>>{};
      for (final e in map.entries) {
        if (e.key.startsWith('@')) continue;
        out[e.key] =
            re.allMatches(e.value as String).map((m) => m.group(1)!).toSet();
      }
      return out;
    }

    final basePh = placeholders(base);
    for (final loc in locales) {
      final locPh = placeholders('lib/l10n/app_$loc.arb');
      for (final key in basePh.keys) {
        expect(locPh[key], basePh[key],
            reason: 'Плейсхолдеры ключа "$key" в $loc не совпадают с базой');
      }
    }
  });

  // Порядок параметров сгенерированного метода задаётся порядком объявления в
  // `@ключ.placeholders`, а БЕЗ метаданных gen_l10n сортирует их ПО АЛФАВИТУ.
  // Вызовы пишутся в порядке появления в строке, поэтому расхождение молча
  // меняет значения местами: так «6.1 ГБ из 1100 ГБ» превращалось в
  // «1100 ГБ из 6.1 ГБ». Компилятор такое не ловит — типы совпадают.
  test('порядок плейсхолдеров объявлен и совпадает с порядком в строке', () {
    final re = RegExp(r'\{(\w+)\}');
    final map = jsonDecode(File(base).readAsStringSync())
        as Map<String, dynamic>;

    for (final e in map.entries) {
      if (e.key.startsWith('@') || e.value is! String) continue;
      final inString = <String>[
        for (final m in re.allMatches(e.value as String)) m.group(1)!,
      ].toSet().toList();
      if (inString.length < 2) continue;

      final meta = map['@${e.key}'] as Map<String, dynamic>?;
      final declared =
          (meta?['placeholders'] as Map<String, dynamic>?)?.keys.toList();
      expect(declared, isNotNull,
          reason: 'У ключа "${e.key}" ${inString.length} плейсхолдеров, но нет '
              '@${e.key}.placeholders — порядок параметров станет алфавитным');
      expect(declared, inString,
          reason: 'Порядок плейсхолдеров "${e.key}" объявлен как $declared, '
              'а в строке идёт $inString — аргументы вызова поменяются местами');
    }
  });

  // ⚠️ Проверять, что перевод сохраняет ПОРЯДОК плейсхолдеров, НЕЛЬЗЯ: именованные
  // плейсхолдеры на то и именованные, чтобы язык ставил их по своей грамматике
  // («{total} hizmetten {ok} tanesi» = «из {total} сервисов {ok}»). Значения
  // ломает не перевод, а порядок ОБЪЯВЛЕНИЯ выше — он общий для всех локалей.

  // Жалоба владельца 10.09.2026: «убери нахуй свои длинные тире… должно
  // конкретно расписывать по пунктам». `serviceChecksInfo` переписан с
  // абзаца на пять блоков с маркерами «• »; три стража ниже держат именно
  // ЭТУ форму — падают, если кто-то вернёт абзац или тире.
  group('serviceChecksInfo — пояснение по пунктам, не абзацем', () {
    // ⚠️ Все локали разом (ru — база, остальные — locales), а не только ru:
    // требование «ни одного длинного тире» — про ВСЕ языки, не только про
    // русский (дословно из жалобы), и перевод легко принести с тире внутри.
    final allCodes = ['ru', ...locales];

    String infoOf(String code) {
      final map = jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
          as Map<String, dynamic>;
      return map['serviceChecksInfo'] as String;
    }

    for (final code in allCodes) {
      test('$code: нет длинного тире (—, U+2014)', () {
        final text = infoOf(code);
        expect(text.contains('—'), isFalse,
            reason: 'В "$code" serviceChecksInfo нашлось длинное тире — '
                'владелец просил заменить абзац на пункты именно из-за него');
      });

      test('$code: все пять смысловых блоков на месте', () {
        // Пункты считаем по маркеру «• »: в шаблоне владельца их 14
        // (3+2+4+3+2) — по блокам «два значка», «когда снимается замер»,
        // «цвет кольца», «знак в углу», «что можно нажать». Число — не
        // самоцель, а сторож: если блок потеряется при переводе или правке,
        // сумма пунктов сдвинется и тест покажет ГДЕ считать, а не просто
        // упадёт молча.
        final text = infoOf(code);
        final bulletCount = '• '.allMatches(text).length;
        expect(bulletCount, 14,
            reason: 'В "$code" serviceChecksInfo пунктов "• " ${bulletCount != 14 ? 'не ' : ''}'
                '14 — блок потерялся или добавился лишний');
        // Пустые строки между блоками (двойной перенос) — заголовков ровно 5.
        final headers = text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('•'))
            .length;
        expect(headers, 5,
            reason: 'В "$code" serviceChecksInfo заголовков блоков не 5');
      });
    }

    // ⚠️ Страж «пара значков» не ослаблен: прежний абзацный текст объяснял
    // связку «слева — без VPN, справа — через VPN» одним предложением,
    // новая форма прячет её в первом блоке под пунктами — проверяем, что
    // само содержание никуда не делось, а не только форму.
    test('ru: первый блок по-прежнему объясняет пару значков (без VPN / через VPN)',
        () {
      final text = infoOf('ru');
      final firstBlock = text.split('\n\n').first;
      expect(firstBlock, contains('VPN'));
      expect(firstBlock.split('\n').length, 4, // заголовок + 3 пункта
          reason: 'Первый блок должен объяснять оба значка и стрелку между ними');
    });
  });
}
