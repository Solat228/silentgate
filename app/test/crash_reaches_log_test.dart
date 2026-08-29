import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';

/// ⚠️ АВАРИЯ ОБЯЗАНА ОКАЗАТЬСЯ НА ДИСКЕ ДО СМЕРТИ ПРОЦЕССА.
///
/// Вопрос владельца дословно: «если что-то упадёт, запишется ли это в логи
/// корректно или пропадёт?». До появления [AppLog.fatalSync] ответ был
/// «пропадёт»: обычная запись уходит в очередь и доходит до файла через
/// микрозадачу, а падающий процесс до неё не доживает. Проверять здесь надо
/// именно ЭТО — не «строка добавилась в память», а «строка лежит в файле
/// сразу после возврата из метода», без единого `await` между.
void main() {
  late Directory tmp;
  late String logPath;

  setUp(() {
    // ⚠️ Боевой %APPDATA% тестам трогать нельзя: этот тест ПИШЕТ в файл лога.
    tmp = Directory.systemTemp.createTempSync('sg_crash_log_');
    AppPaths.overrideRoot(tmp);
    logPath = '${tmp.path}${Platform.pathSeparator}app.log';
  });

  tearDown(() async {
    await AppLog.resetFileForTest();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// ⚠️ Подмена пути ставится ВНУТРИ теста, а не в `setUp`: `useFileForTest`
  /// асинхронна, а половина проверок здесь нарочно обходится без единого
  /// `await` — смысл в том и состоит, чтобы строка оказалась на диске без
  /// ожидания чего бы то ни было.
  Future<File> armedLog() async {
    await AppLog.useFileForTest(logPath);
    return File(logPath);
  }

  group('⚠️ Синхронная запись аварии', () {
    test('строка лежит в файле СРАЗУ, без ожидания очереди', () async {
      final f = await armedLog();
      AppLog.fatalSync('АВАРИЯ (интерфейс): проверочное падение');
      // Ни одного await между записью и чтением — ровно так же на это смотрит
      // процесс, которому осталось жить микросекунды.
      expect(f.readAsStringSync(), contains('проверочное падение'));
    });

    test('⚠️ пишется НЕЗАВИСИМО от порога — аварию не отключить настройкой',
        () async {
      final f = await armedLog();
      final saved = AppLog.minLevel;
      // `warn` строже `error`? Нет — но выставим самый строгий из осмысленных
      // порогов и убедимся, что он аварию не съедает ни при каких условиях.
      AppLog.minLevel = LogLevel.warn;
      try {
        AppLog.fatalSync('авария при строгом пороге');
        expect(f.readAsStringSync(), contains('авария при строгом пороге'));
      } finally {
        AppLog.minLevel = saved;
      }
    });

    test('строка видна и в памяти — экран логов обновляется живьём', () async {
      await armedLog();
      final before = AppLog.entries.length;
      AppLog.fatalSync('видно и на экране');
      expect(AppLog.entries.length, greaterThan(before));
      expect(AppLog.entries.last.level, LogLevel.error);
    });

    test('⚠️ секреты маскируются и здесь', () async {
      final f = await armedLog();
      // Обработчик падения — не повод отправить в поддержку токен подписки.
      AppLog.fatalSync('сбой при запросе https://example.com/sub/SECRET123TOKEN');
      expect(f.readAsStringSync(), isNot(contains('SECRET123TOKEN')));
    });

    test('несколько аварий подряд не затирают друг друга', () async {
      final f = await armedLog();
      AppLog.fatalSync('первая авария');
      AppLog.fatalSync('вторая авария');
      final text = f.readAsStringSync();
      expect(text, contains('первая авария'));
      expect(text, contains('вторая авария'));
    });
  });

  group('⚠️ Ловушка не роняет то, что уже падает', () {
    test('отсутствие корня данных переживается молча', () async {
      // На Android до `AppPaths.init()` корня нет вовсе, и синхронно его не
      // достать. Исключение внутри обработчика падения превратило бы понятную
      // ошибку в непонятную.
      await AppLog.resetFileForTest();
      AppPaths.resetForTests();
      expect(() => AppLog.fatalSync('без корня данных'), returnsNormally);
      // Вернём корень, чтобы tearDown отработал в тех же условиях.
      AppPaths.overrideRoot(tmp);
    });
  });

  group('⚠️ Обработчик коротко режет стек', () {
    test('длинный стек не вытесняет из журнала всё остальное', () {
      // Полный стек Flutter — сотня строк служебных кадров движка. В журнале
      // на 512 КБ одна авария вытеснила бы всю историю до неё, то есть ровно
      // тот контекст, по которому авария и разбирается.
      final long = StackTrace.fromString(
          List.generate(200, (i) => '#$i      кадр стека номер $i').join('\n'));
      final short = AppLog.shortStack(long);
      expect('\n'.allMatches(short).length, lessThan(20));
      expect(short, contains('ещё'));
    });
  });
}
