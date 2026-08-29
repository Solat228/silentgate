import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/core/platform/log_work_counters.dart';
import 'package:silentgate/core/platform/singbox_log_format.dart';

/// РАЗБОР СТРОКИ ЖУРНАЛА — БЕЗ ВИДЖЕТОВ И БЕЗ ФАЙЛОВ.
///
/// ⚠️ ГЛАВНОЕ УТВЕРЖДЕНИЕ ВСЕГО ФАЙЛА — ИНВАРИАНТ ДОСЛОВНОСТИ: собранная
/// обратно строка (`timePart + zonePart + levelPart + message`) равна входной
/// строке после снятия ANSI ЗНАК В ЗНАК. Это то же самое требование, что
/// «файл не изменился», только на уровне содержимого строки: разбор ничего не
/// теряет и ничего не выдумывает.
///
/// ⚠️ ГАРАНТИЯ АСИММЕТРИЧНА, И ЭТО НАДО ГОВОРИТЬ ВСЛУХ. Она даётся формату
/// НАШЕГО журнала ([LogLineKind.app]) и неразобранным строкам. У формата ядра
/// её нет и быть не может: там дата переставляется в наш вид, а вокруг уровня
/// синтезируются скобки — ради того самого единого вида двух вкладок, которого
/// просил владелец. Именно `app.log` целиком уезжает в отчёт поддержки,
/// поэтому выбор такой, а не обратный.
void main() {
  // Символ ESC пишем кодом, а не самим байтом: невидимый управляющий символ в
  // исходнике не увидеть и не сверить глазами (проект уже терял его при
  // правке).
  final esc = String.fromCharCode(0x1b);
  final localZone = formatZoneOffset(DateTime.now().timeZoneOffset);

  /// Строка с НЕВОССТАНОВИМО битым байтом — ровно то, что отдаёт
  /// `utf8.decode(..., allowMalformed: true)` при чтении чужой кодировки.
  final broken = utf8.decode([0x82, 0xd0, 0xbf], allowMalformed: true);

  /// Корпус: все виды физических строк, которые реально лежат в одном файле.
  final corpus = <String>[
    // 1. Наш формат, все четыре уровня.
    '04.08.2026 01:23:33 [INFO] подписка получена, серверов 12',
    '04.08.2026 01:23:33 [DEBUG] пинг узла',
    '04.08.2026 01:23:33 [WARN] сервер не ответил',
    '04.08.2026 01:23:33 [ERROR] не удалось подключиться',
    // 2. Наш формат с маской адреса — пробел и «№» внутри сообщения.
    '04.08.2026 01:23:34 [INFO] переключаюсь на адрес №3:443',
    // 3. Наш формат с пустым сообщением.
    '04.08.2026 01:23:35 [INFO] ',
    // 4. Кадры стека — продолжение одной записи, без метки и уровня.
    '#0      main (package:silentgate/main.dart:52:5)',
    '  … ещё 4 строк',
    // 5. Наши строки в логе ядра: третий формат времени, ISO с микросекундами.
    '--- запуск прокси-ядра 2026-08-11T02:09:10.184221',
    // 6. Две строки tun_helper БЕЗ префикса «--- ».
    'НЕ ЗАПУСКАЮ ЯДРО: kill switch включён, но блокировка не поднялась.',
    'НЕ УДАЛОСЬ ЗАПУСТИТЬ sing-box: Ошибка 2',
    // 7. Вывод харнесса — вообще без метки времени.
    'warn found 0 outbounds',
    // 8. Мусор, пустота, одни пробелы, битый байт, обрывок посреди строки.
    '',
    '    ',
    broken,
    '04.08.2026 01:23:3',
    // 9. Формат ядра — сырой (смещение ПЕРЕД датой) и причёсанный (после).
    '+0700 2026-08-11 02:09:08 INFO router: тест',
    '2026-08-11 02:09:08 +0700 INFO router: тест',
    '2026-08-11 02:09:08 INFO router: без зоны',
    '+0700 2026-08-11 02:09:08 $esc[31mERROR$esc[0m dial failed',
  ];

  group('Инвариант дословности', () {
    test('⚠️ разбор не теряет и не выдумывает ни одного знака', () {
      for (final s in corpus) {
        final v = parseLogLine(s, localZoneOffset: Duration.zero);
        if (v.kind == LogLineKind.core) continue; // гарантия сюда не даётся
        expect(v.text, stripAnsiSequences(s),
            reason: 'строка «$s» собралась обратно не дословно');
      }
    });

    test('очень длинная строка не режется', () {
      // «$e» из tun_helper может дать одну физическую строку в десятки
      // килобайт — обрезать её нельзя, там причина отказа.
      final long = 'x' * 50000;
      final v = parseLogLine(long);
      expect(v.parsed, isFalse);
      expect(v.message.length, 50000);
    });

    test('строка из нулевых байт не роняет разбор', () {
      // Порча файла нулями уже случалась (её специально считает
      // `AppLog.statOf`), и показ обязан её пережить.
      final zeros = String.fromCharCodes(List.filled(40, 0));
      final v = parseLogLine(zeros);
      expect(v.parsed, isFalse);
      expect(v.message, zeros);
    });
  });

  group('Неразобранная строка не исчезает', () {
    for (final s in [
      '#0      main (package:silentgate/main.dart:52:5)',
      '  … ещё 4 строк',
      '--- запуск прокси-ядра 2026-08-11T02:09:10.184221',
      'warn found 0 outbounds',
      '',
      '    ',
      '04.08.2026 01:23:3',
    ]) {
      test('«${s.isEmpty ? "(пусто)" : s}» отдаётся целиком', () {
        final v = parseLogLine(s);
        expect(v.parsed, isFalse);
        expect(v.message, s, reason: 'сообщение обязано быть ВСЕЙ строкой');
        expect(v.timePart, isEmpty, reason: 'время не выдумываем');
        expect(v.levelPart, isEmpty);
      });
    }

    test('битый байт доходит до показа как есть', () {
      final v = parseLogLine(broken);
      expect(v.parsed, isFalse);
      expect(v.message, broken);
    });
  });

  group('Формат журнала приложения', () {
    test('время, уровень и сообщение разложены по местам', () {
      final v = parseLogLine('04.08.2026 01:23:33 [ERROR] не удалось');
      expect(v.kind, LogLineKind.app);
      expect(v.timePart, '04.08.2026 01:23:33 ');
      expect(v.levelPart, '[ERROR] ');
      expect(v.message, 'не удалось');
      expect(v.severity, LogSeverity.error);
      expect(v.zonePart, isEmpty, reason: 'у нашего журнала зоны нет вовсе');
    });

    test('все четыре уровня узнаются', () {
      const expected = {
        'DEBUG': LogSeverity.debug,
        'INFO': LogSeverity.info,
        'WARN': LogSeverity.warn,
        'ERROR': LogSeverity.error,
      };
      expected.forEach((word, sev) {
        final v = parseLogLine('04.08.2026 01:23:33 [$word] x');
        expect(v.severity, sev, reason: word);
      });
    });

    test('⚠️ чужой уровень записью не притворяется', () {
      // Список уровней ЗАКРЫТ (`enum LogLevel`, четыре значения). Будь тут
      // `\w+`, строка постороннего процесса вида «… [OK] …» разобралась бы
      // как наша запись и получила бы наш цвет.
      final v = parseLogLine('04.08.2026 01:23:33 [OK] всё хорошо');
      expect(v.parsed, isFalse);
      expect(v.message, '04.08.2026 01:23:33 [OK] всё хорошо');
    });

    test('сообщение с пробелами и «№» не режется', () {
      final v = parseLogLine('04.08.2026 01:23:34 [INFO] адрес №3:443 → 87 мс');
      expect(v.message, 'адрес №3:443 → 87 мс');
    });

    test('пустое сообщение сохраняет хвостовой пробел', () {
      const raw = '04.08.2026 01:23:35 [INFO] ';
      final v = parseLogLine(raw);
      expect(v.text, raw);
      expect(v.message, isEmpty);
    });
  });

  group('Формат журнала ядра', () {
    test('⚠️ СЫРАЯ строка из файла разбирается — со смещением ВПЕРЕДИ', () {
      // Это самая частая строка вкладки «TUN»: экран читает файл, а не выход
      // `tidySingboxLog`. Отбраковка «по индексам 2 и 4» убила бы разбор
      // формата ядра целиком — и молча.
      final v = parseLogLine('+0700 2026-08-11 02:09:08 INFO router: тест',
          localZoneOffset: const Duration(hours: 7));
      expect(v.kind, LogLineKind.core);
      expect(v.timePart, '11.08.2026 02:09:08 ');
      expect(v.levelPart, '[INFO] ');
      expect(v.message, 'router: тест');
    });

    test('уже причёсанная строка — смещение ПОЗАДИ — тоже', () {
      final v = parseLogLine('2026-08-11 02:09:08 +0700 INFO router: тест',
          localZoneOffset: const Duration(hours: 7));
      expect(v.kind, LogLineKind.core);
      expect(v.timePart, '11.08.2026 02:09:08 ');
      expect(v.message, 'router: тест');
    });

    test('строка без смещения зоны', () {
      final v = parseLogLine('2026-08-11 02:09:08 INFO без зоны');
      expect(v.kind, LogLineKind.core);
      expect(v.timePart, '11.08.2026 02:09:08 ');
      expect(v.zonePart, isEmpty);
    });

    test('ANSI снимается, уровень остаётся словом', () {
      final v = parseLogLine(
          '+0700 2026-08-11 02:09:08 $esc[31mERROR$esc[0m dial failed',
          localZoneOffset: const Duration(hours: 7));
      expect(v.levelPart, '[ERROR] ');
      expect(v.message, 'dial failed');
      expect(v.text.contains(esc), isFalse);
    });

    test('уровни ядра сводятся к нашей четвёрке', () {
      const map = {
        'TRACE': '[DEBUG] ',
        'DEBUG': '[DEBUG] ',
        'INFO': '[INFO] ',
        'WARN': '[WARN] ',
        'WARNING': '[WARN] ',
        'ERROR': '[ERROR] ',
        'FATAL': '[ERROR] ',
        'PANIC': '[ERROR] ',
      };
      map.forEach((word, level) {
        final v = parseLogLine('2026-08-11 02:09:08 $word x');
        expect(v.levelPart, level, reason: word);
      });
    });

    test('единый вид: дата ядра переписана в вид журнала приложения', () {
      // Пункт (Б) задания: соседние вкладки должны читаться как один
      // источник, а не как два.
      final core = parseLogLine('$localZone 2026-08-11 02:09:08 INFO x');
      final ours = parseLogLine('11.08.2026 02:09:08 [INFO] x');
      expect(core.timePart, ours.timePart);
      expect(core.levelPart, ours.levelPart);
      expect(core.timePart.length, 20,
          reason: 'ширина метки фиксирована — на ней держатся колонки');
    });
  });

  group('Часовой пояс', () {
    test('своё смещение не показывается — это и было «чё за +700»', () {
      final v = parseLogLine('+0700 2026-08-11 02:09:08 INFO x',
          localZoneOffset: const Duration(hours: 7));
      expect(v.zonePart, isEmpty);
      expect(v.text, '11.08.2026 02:09:08 [INFO] x');
    });

    test('⚠️ ЧУЖОЕ смещение показывается — иначе время врало бы на часы', () {
      // Лог мог остаться от сессии до перевода часов или смены зоны.
      final v = parseLogLine('+0700 2026-08-11 02:09:08 INFO x',
          localZoneOffset: const Duration(hours: 3));
      expect(v.zonePart, '+0700 ');
      expect(v.text, '11.08.2026 02:09:08 +0700 [INFO] x');
    });

    test('смещение форматируется как у ядра', () {
      expect(formatZoneOffset(const Duration(hours: 7)), '+0700');
      expect(formatZoneOffset(const Duration(hours: -5)), '-0500');
      expect(formatZoneOffset(const Duration(hours: 5, minutes: 30)), '+0530');
      expect(formatZoneOffset(Duration.zero), '+0000');
    });
  });

  group('Служебные строки', () {
    test('«--- …» — свой цвет, текст дословный', () {
      const raw = '--- запуск sing-box 2026-08-11T02:09:10: sing-box.exe run';
      final v = parseLogLine(raw);
      expect(v.severity, LogSeverity.service);
      expect(v.message, raw);
    });

    test('⚠️ две строки tun_helper БЕЗ префикса краснеют', () {
      // Именно они объясняют, почему ядро не поднялось. Оставить их серым
      // «неизвестно» нельзя.
      for (final p in tunHelperFailurePrefixes) {
        final v = parseLogLine('$p: подробности');
        expect(v.severity, LogSeverity.error, reason: p);
        expect(v.message, '$p: подробности');
      }
    });
  });

  group('Согласие с tidySingboxLog', () {
    // ⚠️ РАЗБОРОВ ФОРМАТА ЯДРА В ПРОЕКТЕ ДВА: новый (экран логов) и старый
    // (отчёт поддержки на обеих платформах). Переписывать второй поверх
    // первого в этой задаче НЕ стали — цена ошибки там непропорциональна.
    // Значит, согласованность обязана проверяться, иначе они разъедутся на
    // первой же смене формата ядра.
    test('оба снимают одни и те же последовательности цвета', () {
      for (final s in corpus) {
        expect(stripAnsiSequences(s).contains(esc), isFalse, reason: s);
        expect(tidySingboxLog(s).contains(esc), isFalse, reason: s);
      }
    });

    test('оба одинаково решают, что строка — формата ядра со смещением', () {
      for (final s in corpus) {
        final movedByTidy = tidySingboxLog(s) != stripAnsiSequences(s);
        final v = parseLogLine(s, localZoneOffset: Duration.zero);
        final leadingZone =
            v.kind == LogLineKind.core && RegExp(r'^[+-]\d{4}\s').hasMatch(s);
        expect(movedByTidy, leadingZone,
            reason: 'расхождение двух разборов на строке «$s»');
      }
    });
  });

  group('Продолжение записи', () {
    test('кадр стека узнаётся, чужая строка — нет', () {
      expect(looksLikeContinuation('#0      main (…)'), isTrue);
      expect(looksLikeContinuation('  … ещё 4 строк'), isTrue);
      expect(looksLikeContinuation('at foo'), isTrue);
      expect(looksLikeContinuation(''), isFalse);
      expect(looksLikeContinuation('Чужая строка второй копии'), isFalse);
    });
  });

  group('Счётчики выполненной работы', () {
    test('разобранные строки растут ровно на число строк', () {
      final before = LogWorkCounters.parsedLines;
      for (final s in corpus) {
        parseLogLine(s);
      }
      expect(LogWorkCounters.parsedLines - before, corpus.length);
    });

    test('⚠️ зона спрашивается у системы ТОЛЬКО без переданного смещения', () {
      // Положительный контроль: без параметра строка формата ядра ОБЯЗАНА
      // сходить к системе — иначе следующая проверка ничего не значит.
      const zoneLine = '+0700 2026-08-11 02:09:08 INFO router: тест';
      var before = LogWorkCounters.zoneLookups;
      parseLogLine(zoneLine);
      expect(LogWorkCounters.zoneLookups - before, 1,
          reason: 'контроль: без localZoneOffset вызов к системе есть');

      before = LogWorkCounters.zoneLookups;
      for (var i = 0; i < 500; i++) {
        parseLogLine(zoneLine, localZoneOffset: Duration.zero);
      }
      expect(LogWorkCounters.zoneLookups - before, 0,
          reason: 'переданное смещение обязано избавлять от системного вызова: '
              'на восьмимегабайтном логе это 224-230 мс из 447 мс кадра');
    });

    test('⚠️ tidySingboxLog считается тем же счётчиком, что и разбор', () {
      // Иначе сторож производительности видел бы половину дорогой работы —
      // ровно ту, которая раньше и стояла в кадре.
      final before = LogWorkCounters.tidyCalls;
      tidySingboxLog('+0700 2026-08-11 02:09:08 INFO x');
      expect(LogWorkCounters.tidyCalls - before, 1);
    });

    test('reset обнуляет всё', () {
      parseLogLine('04.08.2026 01:23:33 [INFO] x');
      LogWorkCounters.reset();
      expect(LogWorkCounters.parsedLines, 0);
      expect(LogWorkCounters.builtSpans, 0);
      expect(LogWorkCounters.zoneLookups, 0);
      expect(LogWorkCounters.tidyCalls, 0);
      expect(LogWorkCounters.scannedChars, 0);
    });
  });

  group('⚠️ Формат ядра ВНУТРИ app.log не переписывается', () {
    // `engine_base` пишет «Последние строки вывода <ядро>:» и следом сам хвост
    // вывода ядра — телом ОДНОЙ нашей записи. На вкладке «Приложение» разбор
    // формата ядра выключен, и эти строки обязаны оставаться дословными.
    const line = '+0700 2026-08-11 02:09:08 INFO router: тест';

    test('с coreFormat: false строка остаётся дословной', () {
      final v = parseLogLine(line, coreFormat: false);
      expect(v.kind, LogLineKind.unparsed);
      expect(v.text, line, reason: 'ни переставленной даты, ни новых скобок');
    });

    test('с coreFormat: true (вкладка «TUN») — разбирается, как и раньше', () {
      final v = parseLogLine(line,
          coreFormat: true, localZoneOffset: Duration.zero);
      expect(v.kind, LogLineKind.core);
      expect(v.timePart, '11.08.2026 02:09:08 ');
    });

    test('наш формат разбирается в обоих режимах', () {
      // ⚠️ На Android во вкладку «TUN» при пустом singbox.log подставляется
      // `app.log`, а в `app.log` наши строки — основные.
      for (final core in [true, false]) {
        final v = parseLogLine('04.08.2026 01:23:33 [ERROR] сбой',
            coreFormat: core);
        expect(v.kind, LogLineKind.app, reason: 'coreFormat: $core');
        expect(v.severity, LogSeverity.error);
      }
    });
  });
}
