import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/app.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/ui/log_line_style.dart';

/// РАСКРАСКА ЖУРНАЛА — И ЕЁ ГРАНИЦЫ.
///
/// ⚠️ ПАРНЫЙ ТЕСТ К ПОБАЙТНОЙ СВЕРКЕ ФАЙЛА. «Файл не изменился» проходит и
/// тогда, когда на экране не нарисовано вообще ничего; поэтому здесь стоит
/// ПОЛОЖИТЕЛЬНАЯ половина доказательства — что раскраска действительно идёт от
/// разбора, а строки при этом не потеряны и не украшены лишними символами.
void main() {
  final light = buildAppTheme(Brightness.light);
  final dark = buildAppTheme(Brightness.dark);
  final esc = String.fromCharCode(0x1b);

  TextSpan? findByText(TextSpan root, String text) {
    TextSpan? found;
    root.visitChildren((s) {
      if (s is TextSpan && s.text == text) {
        found = s;
        return false;
      }
      return true;
    });
    return found;
  }

  /// Относительная яркость по WCAG — нужна для проверки контраста.
  double luminance(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  group('Показанный текст = входной', () {
    test('⚠️ раскраска не добавляет в текст ни одного символа', () {
      final raw = [
        '04.08.2026 01:23:33 [INFO] подписка получена',
        '04.08.2026 01:23:34 [ERROR] Ошибка: адрес №3:443 недоступен',
        '#0      main (package:silentgate/main.dart:52:5)',
        '  … ещё 4 строк',
        'чужая строка второй копии приложения',
        '',
      ].join('\n');

      expect(buildLogSpan(raw, light).toPlainText(), raw,
          reason: 'ни отступов, ни глифов, ни выравнивания пробелами');
    });

    test('ANSI снимается — и это УДАЛЕНИЕ, а не добавление', () {
      final raw = '04.08.2026 01:23:33 [ERROR] $esc[31mсбой$esc[0m';
      final shown = buildLogSpan(raw, light).toPlainText();
      expect(shown, '04.08.2026 01:23:33 [ERROR] сбой');
      expect(shown.contains(esc), isFalse);
      expect(shown.length, lessThan(raw.length));
    });

    test('пустой вход не роняет сборку', () {
      expect(buildLogSpan('', light).toPlainText(), '');
    });
  });

  group('Цвет идёт от разбора', () {
    final raw = [
      '04.08.2026 01:23:33 [ERROR] сбой',
      '04.08.2026 01:23:34 [WARN] предупреждение',
      '04.08.2026 01:23:35 [INFO] обычная',
      '04.08.2026 01:23:36 [DEBUG] отладочная',
      '--- запуск sing-box 2026-08-11T02:09:10',
      'непонятная строка',
    ].join('\n');

    test('ошибка — красным, и уровень, и сообщение', () {
      final span = buildLogSpan(raw, light);
      expect(findByText(span, '[ERROR] ')!.style!.color,
          light.colorScheme.error);
      expect(findByText(span, 'сбой\n')!.style!.color, light.colorScheme.error);
    });

    test('отладочная — приглушённым', () {
      final span = buildLogSpan(raw, light);
      expect(findByText(span, 'отладочная\n')!.style!.color,
          light.colorScheme.onSurfaceVariant);
    });

    test('время — отдельным (приглушённым) цветом, а не разметкой', () {
      final span = buildLogSpan(raw, light);
      expect(findByText(span, '04.08.2026 01:23:33 ')!.style!.color,
          light.colorScheme.onSurfaceVariant);
    });

    test('служебная «--- …» — своим цветом', () {
      final span = buildLogSpan(raw, light);
      expect(
          findByText(span, '--- запуск sing-box 2026-08-11T02:09:10\n')!
              .style!
              .color,
          light.colorScheme.primary);
    });

    test('непонятая строка остаётся обычной и НЕ прячется', () {
      final span = buildLogSpan(raw, light);
      expect(findByText(span, 'непонятная строка')!.style!.color,
          light.colorScheme.onSurface);
      expect(span.toPlainText(), contains('непонятная строка'));
    });
  });

  group('Продолжение записи', () {
    test('кадры стека наследуют цвет своей ошибки', () {
      final raw = [
        '04.08.2026 01:23:36 [ERROR] авария',
        '#0      main (package:silentgate/main.dart:52:5)',
        '  … ещё 4 строк',
      ].join('\n');
      final span = buildLogSpan(raw, light);
      expect(
          findByText(span, '#0      main (package:silentgate/main.dart:52:5)\n')!
              .style!
              .color,
          light.colorScheme.error,
          reason: 'стек читается как одна запись, а не как двенадцать сирот');
      expect(findByText(span, '  … ещё 4 строк')!.style!.color,
          light.colorScheme.error);
    });

    test('⚠️ ЧУЖАЯ строка сразу за ошибкой НЕ КРАСНЕЕТ', () {
      // `app.log` общий: в него пишет вторая копия приложения, в `singbox.log`
      // на Android — два независимых писателя. Приписать чужую строку нашей
      // аварии хуже, чем оставить её серой: мусор не потерян, но прочитан как
      // кадр чужого стека.
      final raw = [
        '04.08.2026 01:23:36 [ERROR] авария',
        'строка второй копии приложения',
      ].join('\n');
      final span = buildLogSpan(raw, light);
      expect(findByText(span, 'строка второй копии приложения')!.style!.color,
          light.colorScheme.onSurface);
    });

    test('наследование обрывается и не тянется бесконечно', () {
      final frames = List.generate(
          maxContinuationLines + 4, (i) => '#$i      кадр стека');
      final raw = ['04.08.2026 01:23:36 [ERROR] авария', ...frames].join('\n');
      final span = buildLogSpan(raw, light);
      const last = '#${maxContinuationLines + 3}      кадр стека';
      expect(findByText(span, last)!.style!.color, light.colorScheme.onSurface,
          reason: 'предел наследования обязан существовать');
    });
  });

  group('⚠️ Цвет — не единственный признак уровня', () {
    test('слово уровня остаётся в самой строке', () {
      // Чёрно-белый скриншот и дальтоник обязаны различать строки. Слово —
      // главный признак, и оно физически лежит в тексте.
      for (final w in ['DEBUG', 'INFO', 'WARN', 'ERROR']) {
        final span = buildLogSpan('04.08.2026 01:23:33 [$w] x', light);
        expect(span.toPlainText(), contains('[$w]'));
      }
    });

    test('насыщенность у четырёх уровней разная', () {
      final weights = [
        LogSeverity.debug,
        LogSeverity.info,
        LogSeverity.warn,
        LogSeverity.error,
      ].map(logLevelWeight).toList();
      expect(weights.toSet().length, weights.length,
          reason: 'второй признак помимо цвета — начертание');
    });

    test('глифов в тексте нет — они уехали бы в выделение мышью', () {
      final shown =
          buildLogSpan('04.08.2026 01:23:33 [ERROR] сбой', light).toPlainText();
      for (final glyph in ['✖', '▲', '▸', '●']) {
        expect(shown.contains(glyph), isFalse);
      }
    });
  });

  group('Контраст в обеих темах', () {
    for (final entry in {'светлая': light, 'тёмная': dark}.entries) {
      final theme = entry.value;
      final bg = theme.scaffoldBackgroundColor;
      for (final s in LogSeverity.values) {
        test('${entry.key}: ${s.name} читается на фоне', () {
          expect(contrast(logSeverityColor(s, theme), bg),
              greaterThanOrEqualTo(4.5),
              reason: 'жёлтый на светлой теме — первое, что становится '
                  'нечитаемым, если взять его из головы');
        });
      }
    }
  });
}
