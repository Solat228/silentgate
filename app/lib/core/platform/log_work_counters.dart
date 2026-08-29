import 'package:meta/meta.dart';


/// ⚠️ ОТДЕЛЬНЫЙ ФАЙЛ, И ЭТО НЕ ВКУСОВЩИНА. Счётчики жили рядом с разборщиком
/// (`log_line.dart`), а `tidySingboxLog` инкрементирует [tidyCalls] — значит
/// `singbox_log_format.dart` начинал импортировать разборщик. Его же
/// импортируют ОБА отчёта поддержки, то есть писатели журнала стали
/// транзитивно зависеть от его показа: ровно тот инвариант, который стережёт
/// `test/log_parser_no_io_test.dart`, и стерёг он его только по ПРЯМЫМ
/// импортам — мостик прошёл молча. Счётчики ни от чего не зависят, поэтому
/// живут отдельно, и оба разбора могут считать их, ни о чём не зная друг о друге.
/// Счётчики ФАКТИЧЕСКИ ВЫПОЛНЕННОЙ работы показа — ⚠️ ТОЛЬКО ДЛЯ ТЕСТОВ.
///
/// ⚠️ ЗАЧЕМ ОНИ ЕСТЬ И ПОЧЕМУ ИХ ПЯТЬ, А НЕ ОДИН. Экран логов уже один раз
/// стал дороже, чем был, и по коду это не видно: разбор строки и раскладка
/// абзаца выглядят одинаково невинно на любом размере буфера. Сторож
/// производительности обязан считать РАБОТУ, а не вызовы, которых не было, —
/// прошлая его версия крутила пять пустых `pump()`, ни один из которых не
/// помечал виджет грязным: `build()` не выполнялся вовсе, и тест был зелен при
/// ЛЮБОЙ стоимости кадра.
///
/// ⚠️ [tidyCalls] СЧИТАЕТСЯ ЗДЕСЬ ЖЕ, хотя `tidySingboxLog` живёт в другом
/// файле. Разборов формата ядра в проекте два, и вернуть в кадр можно любой;
/// сторож, считающий половину дорогой работы, снова ничего не поймает.
///
/// ⚠️ ПОЛЯ ЗАКРЫТЫ, наружу торчат только чтение и [reset]. Прежний счётчик был
/// публичной изменяемой глобальной в боевом `lib/` — то есть боевым API,
/// которым мог воспользоваться (и сломать) кто угодно.
class LogWorkCounters {
  LogWorkCounters._();

  static int _parsedLines = 0;
  static int _builtSpans = 0;
  static int _zoneLookups = 0;
  static int _tidyCalls = 0;
  static int _scannedChars = 0;

  /// Сколько строк прошло через [parseLogLine].
  @visibleForTesting
  static int get parsedLines => _parsedLines;

  /// Сколько [InlineSpan] собрано для показа.
  @visibleForTesting
  static int get builtSpans => _builtSpans;

  /// Сколько раз спросили у системы местное смещение часового пояса.
  /// ⚠️ На проход разбора допустим ОДИН: системный вызов Windows стоит ~3.7
  /// мкс, а строк формата ядра в восьмимегабайтном логе — полсотни тысяч.
  @visibleForTesting
  static int get zoneLookups => _zoneLookups;

  /// Сколько раз позвали `tidySingboxLog` (второй разбор того же формата).
  @visibleForTesting
  static int get tidyCalls => _tidyCalls;

  /// Сколько символов прошло через оба разбора — грубая мера объёма работы.
  @visibleForTesting
  static int get scannedChars => _scannedChars;

  @visibleForTesting
  static void reset() {
    _parsedLines = 0;
    _builtSpans = 0;
    _zoneLookups = 0;
    _tidyCalls = 0;
    _scannedChars = 0;
  }

  // Инкременты — боевой код (их зовут разбор, раскраска и `tidySingboxLog`),
  // поэтому они без аннотации: помеченный `@visibleForTesting` метод,
  // вызванный из `lib/`, — это замечание анализатора, а не защита.
  static void countParsedLine(int chars) {
    _parsedLines++;
    _scannedChars += chars;
  }

  static void countSpans(int n) => _builtSpans += n;

  static void countZoneLookup() => _zoneLookups++;

  static void countTidy(int chars) {
    _tidyCalls++;
    _scannedChars += chars;
  }
}
