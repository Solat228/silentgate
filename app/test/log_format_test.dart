import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';

/// Страж читаемости лога. Обе проверки — про человека, который в лог смотрит:
/// владельца, когда он ищет момент обрыва, и меня, когда разбираю его жалобу.
void main() {
  group('Дата в логе человекочитаемая', () {
    test('формат ДД.ММ.ГГГГ ЧЧ:ММ:СС, без ISO и микросекунд', () {
      final e = LogEntry(
          DateTime(2026, 8, 4, 1, 23, 33, 794, 745), LogLevel.info, 'тест');
      expect(e.stamp, '04.08.2026 01:23:33');
      expect(e.line, startsWith('04.08.2026 01:23:33 [INFO] '));
      expect(e.line, isNot(contains('T')),
          reason: 'ISO-разделитель посреди даты — то, обо что спотыкался глаз');
      expect(e.line, isNot(contains('794745')),
          reason: 'микросекунды не читал никто и никогда');
    });

    test('однозначные день, месяц и время дополняются нулём', () {
      final e = LogEntry(DateTime(2026, 1, 2, 3, 4, 5), LogLevel.warn, 'x');
      expect(e.stamp, '02.01.2026 03:04:05',
          reason: 'разная ширина строк ломает выравнивание при беглом чтении');
    });

    test('уровень остаётся в строке — по нему фильтруют', () {
      expect(LogEntry(DateTime(2026, 8, 4), LogLevel.error, 'бум').line,
          contains('[ERROR]'));
    });
  });
}
