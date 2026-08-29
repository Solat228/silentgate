import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/core/platform/log_work_counters.dart';

/// СТРАЖ НА ИСХОДНИКАХ: КРАСИВЫЙ ПОКАЗ НЕ МОЖЕТ ПИСАТЬ В ЖУРНАЛ — И НЕ МОЖЕТ
/// БЫТЬ ПОЗВАН ИЗ ТОГО, КТО ПИШЕТ.
///
/// ⚠️ ЗАЧЕМ ОН НУЖЕН ПОМИМО ПОБАЙТНОЙ СВЕРКИ ФАЙЛА. Поведенческий тест
/// (`log_render_no_write_test.dart`) говорит «сегодня по пройденной дороге не
/// написал». Этот говорит «написать физически неоткуда»: разборщик не умеет
/// работать с файлами, а ни один писатель журнала про разборщик не знает.
/// Первый ловит ту дорогу, которую успел пройти; второй закрывает все сразу.
///
/// В культуре проекта такие тесты на ИСХОДНИК уже есть — так же ловятся
/// невидимые управляющие байты, которые глазами не увидеть.
void main() {
  /// Читает файл и выбрасывает комментарии: в них слова `File` и `dart:io`
  /// стоят НАРОЧНО — как объяснение запрета. Проверять надо код.
  String codeOf(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '$path не найден');
    return f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  }

  List<String> importsOf(String path) => File(path)
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.startsWith('import ') || l.startsWith('export '))
      .toList();

  /// Все файлы проекта, до которых [start] дотягивается импортами — на любую
  /// глубину.
  ///
  /// ⚠️ ПРОВЕРЯТЬ НАДО ТРАНЗИТИВНО. Проверка прямых импортов этот инвариант уже
  /// пропустила: счётчики работы показа лежали в `log_line.dart`,
  /// `tidySingboxLog` их инкрементировал — и оба отчёта поддержки, импортируя
  /// `singbox_log_format.dart`, начинали зависеть от разборщика через один
  /// мостик. Тест при этом оставался зелёным и выглядел доказательством
  /// обратного.
  Set<String> reachableFrom(String start) {
    final seen = <String>{};
    final queue = <String>[start];
    final quoted = RegExp(r"'([^']+)'");
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      if (!seen.add(cur)) continue;
      if (!File(cur).existsSync()) continue;
      for (final imp in importsOf(cur)) {
        final target = quoted.firstMatch(imp)?.group(1) ?? '';
        // Чужие пакеты и ядро языка обходим: инвариант про НАШИ файлы.
        if (target.isEmpty ||
            target.startsWith('package:') ||
            target.startsWith('dart:')) {
          continue;
        }
        final dir = cur.substring(0, cur.lastIndexOf('/') + 1);
        queue.add(Uri.parse(dir + target).normalizePath().toString());
      }
    }
    return seen;
  }

  group('Разборщик не умеет писать', () {
    const parser = 'lib/core/platform/log_line.dart';

    for (final forbidden in [
      'dart:io',
      'File(',
      'RandomAccessFile',
      'writeAs',
      'openWrite',
      'openSync',
      'IOSink',
    ]) {
      test('в $parser нет «$forbidden»', () {
        expect(codeOf(parser).contains(forbidden), isFalse,
            reason: 'разбор строки журнала обязан только ЧИТАТЬ строку; '
                'появление здесь работы с файлом — это и есть регресс 4.2');
      });
    }

    test('⚠️ и без Flutter: разбор не должен знать про виджеты и темы', () {
      expect(importsOf(parser).where((i) => i.contains('package:flutter')),
          isEmpty,
          reason: 'смешав разбор с раскраской, оба стали бы непроверяемыми '
              'без виджет-теста');
    });

    test('модуль раскраски тоже ничего не пишет', () {
      const style = 'lib/ui/log_line_style.dart';
      for (final forbidden in ['dart:io', 'File(', 'writeAs', 'openWrite']) {
        expect(codeOf(style).contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('⚠️ Писатели журнала про показ не знают', () {
    // Все, кто реально пишет строки в файлы логов, плюс оба отчёта поддержки.
    const writers = [
      'lib/core/platform/app_log.dart',
      'lib/core/platform/rotating_log.dart',
      'lib/engine/windows/support_report.dart',
      'lib/engine/android/support_report_android.dart',
      'lib/engine/windows/tun/tun_helper.dart',
      'lib/engine/windows/singbox_process.dart',
      'lib/engine/windows/xray_process.dart',
    ];

    for (final w in writers) {
      test('$w не тянет разборщик и палитру', () {
        final imports = importsOf(w);
        expect(imports.where((i) => i.contains('log_line.dart')), isEmpty,
            reason: 'запись лога начала бы зависеть от его показа — '
                'ровно та дорога, по которой пометки попадают в файл');
        expect(imports.where((i) => i.contains('log_line_style.dart')), isEmpty,
            reason: 'палитра в писателе — это «раскрасить прямо при записи»');
        expect(imports.where((i) => i.contains('package:flutter/material')),
            isEmpty,
            reason: 'виджеты в писателе журнала не нужны ни для чего');
      });

      test('⚠️ $w не дотягивается до показа и ЧЕРЕЗ ПОСРЕДНИКОВ', () {
        final reachable = reachableFrom(w);
        expect(reachable.where((f) => f.endsWith('log_line.dart')), isEmpty,
            reason: 'один мостик уже был: счётчики работы лежали в разборщике, '
                'tidySingboxLog их считал, и отчёты поддержки начали зависеть '
                'от показа молча — прямые импорты этого не видели');
        expect(reachable.where((f) => f.endsWith('log_line_style.dart')),
            isEmpty,
            reason: 'палитра в писателе — это «раскрасить прямо при записи»');
      });
    }
  });

  group('⚠️ В пути отрисовки нет обращений к системным часам', () {
    // ⚠️ ЗАЧЕМ ТЕСТ НА ИСХОДНИК, ЕСЛИ ЕСТЬ СЧЁТЧИК. Счётчик
    // (`LogWorkCounters.zoneLookups`) ловит срабатывание, этот — само
    // ПОЯВЛЕНИЕ такого кода, и переживёт любую перестановку счётчиков.
    // `DateTime.now().timeZoneOffset` — системный вызов Windows ценой ~3.7
    // мкс; на строку он стоил 224-230 мс из 447 мс кадра, больше половины.
    // Смещение обязано считаться ОДИН раз на проход (`currentZoneOffset`) и
    // передаваться параметром.
    for (final path in [
      'lib/ui/log_line_style.dart',
      'lib/ui/logs_screen.dart',
    ]) {
      test('в $path нет DateTime.now()', () {
        expect(codeOf(path).contains('DateTime.now()'), isFalse,
            reason: 'системные часы в пути отрисовки — это вызов на КАЖДУЮ '
                'строку в КАЖДОМ кадре');
      });
    }

    test('счётчики работы показа помечены @visibleForTesting', () {
      // Прежний `debugParsedLines` был публичной изменяемой глобальной в
      // боевом `lib/` — то есть боевым API, которым мог воспользоваться кто
      // угодно.
      // ⚠️ Счётчики ЖИВУТ ОТДЕЛЬНО от разборщика: держи их рядом — и
      // `tidySingboxLog`, который их считает, притащил бы разборщик в
      // оба отчёта поддержки (это и случилось; см. транзитивную
      // проверку выше).
      final code = codeOf('lib/core/platform/log_work_counters.dart');
      expect(code.contains('int debugParsedLines'), isFalse,
          reason: 'голая изменяемая глобальная вернулась');
      // ⚠️ Перевод строки — кодом: невидимый байт в исходнике не
      // сверить глазами (тот же урок, что с ESC).
      final rows = code.split(String.fromCharCode(10));
      for (final name in [
        'get parsedLines',
        'get builtSpans',
        'get zoneLookups',
        'get tidyCalls',
        'get scannedChars',
        'static void reset()',
      ]) {
        final at = rows.indexWhere((r) => r.contains(name));
        expect(at, greaterThan(0), reason: 'счётчик «$name» пропал');
        // Аннотация стоит СТРОКОЙ ВЫШЕ — проверяем именно её, а не наличие
        // слова где-то в файле.
        expect(rows[at - 1].trim(), '@visibleForTesting',
            reason: '«$name» обязан быть помечен @visibleForTesting');
      }
      // И ни одного публичного изменяемого поля: наружу торчат только чтение
      // и reset, инкременты — методы.
      expect(code.contains('static int _parsedLines = 0'), isTrue);
    });
  });

  group('⚠️ Две строки tun_helper, у которых нет префикса «--- »', () {
    // Разборщик красит их по ТОЧНОМУ списку литералов, потому что трогать
    // сам `tun_helper.dart` ради префикса нельзя (это была бы правка ЗАПИСИ
    // лога ради его показа — прямое нарушение 4.2), а выносить литералы в
    // общую константу — значит заставить писателя зависеть от разборщика.
    //
    // Цена такого решения: переименуют строку там — здесь она молча перестанет
    // краснеть. Этот тест и есть плата за неё: расхождение падает красным.
    const tunHelper = 'lib/engine/windows/tun/tun_helper.dart';

    for (final prefix in tunHelperFailurePrefixes) {
      test('«$prefix» всё ещё пишется в лог ядра', () {
        expect(File(tunHelper).readAsStringSync().contains(prefix), isTrue,
            reason: 'строку переименовали в $tunHelper — поправьте '
                'tunHelperFailurePrefixes в log_line.dart, иначе объяснение '
                '«почему ядро не поднялось» перестанет краснеть в журнале');
      });
    }

    test('список не опустел', () {
      expect(tunHelperFailurePrefixes, hasLength(2));
    });
  });
}
