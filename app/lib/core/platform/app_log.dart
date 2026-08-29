import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'app_paths.dart';
import 'rotating_log.dart';

/// ⚠️ ПОРЯДОК ЗНАЧИМ: чем дальше по списку, тем важнее. На этом держится
/// сравнение в [AppLog.minLevel] — «писать всё, что не тише выбранного».
/// Переставив значения местами, вы молча отключите половину журнала.
enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime at;
  final LogLevel level;
  final String message;
  const LogEntry(this.at, this.level, this.message);

  /// ⚠️ ДАТА ЧЕЛОВЕКОЧИТАЕМАЯ, а не ISO.
  ///
  /// Раньше строка начиналась с `2026-08-04T01:23:33.794745` — семь знаков
  /// микросекунд, которые никто никогда не читал, зато глаз спотыкался о `T`
  /// посреди даты. Лог читают люди: владелец, когда ищет момент обрыва, и я,
  /// когда разбираю его жалобу. Формат `04.08.2026 01:23:33` находится взглядом
  /// сразу.
  static String _two(int v) => v < 10 ? '0$v' : '$v';

  String get stamp => '${_two(at.day)}.${_two(at.month)}.${at.year} '
      '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}';

  String get line => '$stamp [${level.name.toUpperCase()}] $message';
}

/// Лог приложения: последние записи в памяти (для экрана «Логи») + дозапись в
/// `%APPDATA%\SilentGate\app.log`.
///
/// Нужен, чтобы диагностировать то, что раньше было невидимым: в каком формате
/// пришла подписка, сколько серверов получили конфиг панели, как отработали пинг
/// и автонастройка, почему не поднялось подключение.
class AppLog {
  static const _maxMemory = 500;

  /// Имя файла лога приложения — вынесено в константу, потому что на него
  /// же ссылается классификация в [LogInventory] (там же живёт `_tunLogName`
  /// для симметрии).
  static const _appLogName = 'app.log';
  static const _maxBytes = 512 * 1024;

  static final Queue<LogEntry> _memory = Queue<LogEntry>();

  /// Слушатели (экран логов обновляется вживую).
  static final List<void Function()> _listeners = [];

  static List<LogEntry> get entries => List.unmodifiable(_memory);

  static void addListener(void Function() l) => _listeners.add(l);
  static void removeListener(void Function() l) => _listeners.remove(l);

  /// ⚠️ ПОРОГ ЗАПИСИ. Ниже него строки не попадают ни в файл, ни в память —
  /// то есть и в отчёт поддержки тоже.
  ///
  /// Умолчание `info` — ровно то поведение, что было до появления порога:
  /// отладочных вызовов в коде тогда не существовало, а `info` и выше писались
  /// всегда. Менять умолчание нельзя: разбирать чужую аварию по журналу, где
  /// половины строк нет, невозможно, а человек про настройку не вспомнит.
  ///
  /// `debug` включают осознанно и ненадолго: ядро на этом уровне пишет сотни
  /// строк в секунду (замерено), и журнал за минуты доходит до сотен мегабайт.
  static LogLevel minLevel = LogLevel.info;

  /// Отладочная строка. Пишется, ТОЛЬКО когда порог опущен до [LogLevel.debug].
  static void d(String message) => _add(LogLevel.debug, message);
  static void i(String message) => _add(LogLevel.info, message);
  static void w(String message) => _add(LogLevel.warn, message);
  static void e(String message) => _add(LogLevel.error, message);

  /// Первые кадры стека — те, где обычно и лежит причина.
  ///
  /// ⚠️ РЕЖЕМ НАРОЧНО. Полный стек Flutter — сотня строк служебных кадров
  /// движка; в журнале объёмом 512 КБ одна авария вытеснила бы всю историю до
  /// неё, то есть ровно тот контекст, по которому аварию и разбирают.
  static String shortStack(StackTrace stack, {int lines = 12}) {
    final all = stack.toString().split('\n');
    final head = all.take(lines).join('\n');
    return all.length > lines
        ? '$head\n  … ещё ${all.length - lines} строк'
        : head;
  }

  /// Записать АВАРИЮ так, чтобы она пережила смерть процесса.
  ///
  /// ⚠️ СИНХРОННО И МИМО ОЧЕРЕДИ — в этом весь смысл метода. Обычная запись
  /// уходит в `_pending` и доходит до диска через микрозадачу; процесс,
  /// который в этот момент падает, до неё не доживает — и в журнале не
  /// оказывается ровно той строки, ради которой журнал и ведут. Владелец
  /// спрашивал прямо: «если что-то упадёт, запишется ли это в логи или
  /// пропадёт?» — вот ответ на этот вопрос.
  ///
  /// Цена честная и названа: счётчик размера в [RotatingLog] об этой строке не
  /// знает, поэтому ротация случится на её длину позже, а при совпадении с
  /// записью из очереди строки могут лечь в другом порядке. Обе платы ничтожны
  /// против потери причины падения.
  ///
  /// Порог [minLevel] здесь НЕ проверяется: аварию нельзя отключить
  /// настройкой.
  static void fatalSync(String message) {
    final entry = LogEntry(DateTime.now(), LogLevel.error, scrubSecrets(message));
    _memory.addLast(entry);
    while (_memory.length > _maxMemory) {
      _memory.removeFirst();
    }
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
    if (!_fileWrites) return;
    try {
      // ⚠️ Путь берём СИНХРОННО и мирно переживаем его отсутствие: до
      // `AppPaths.init()` (а на Android он только асинхронный) корня данных
      // ещё нет. Тогда строка остаётся в памяти — это всё равно больше, чем
      // было, и уж точно лучше, чем исключение внутри обработчика падения.
      final path = _pathOverride ??
          '${AppPaths.supportDirSync().path}${Platform.pathSeparator}app.log';
      File(path).writeAsStringSync('${entry.line}\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Диагностика не имеет права ронять приложение — тем более уже падающее.
    }
  }

  static void _add(LogLevel level, String message) {
    // ⚠️ ОТСЕКАЕМ ДО ВСЕГО ОСТАЛЬНОГО — включая `scrubSecrets`, которая гоняет
    // регулярные выражения по каждой строке. Отладочный вызов в горячем цикле
    // не должен стоить ничего, когда его не пишут.
    if (level.index < minLevel.index) return;
    final entry = LogEntry(DateTime.now(), level, scrubSecrets(message));
    _memory.addLast(entry);
    while (_memory.length > _maxMemory) {
      _memory.removeFirst();
    }
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
    _write(entry);
  }

  /// Путь файла лога. [_pathOverride] задают тесты — боевой `%APPDATA%` они
  /// трогать не должны.
  static String? _pathOverride;

  static Future<String> filePath() async =>
      _pathOverride ??
      '${(await AppPaths.supportDir()).path}${Platform.pathSeparator}app.log';

  /// Прогон тестов не должен писать в БОЕВОЙ `%APPDATA%\SilentGate\app.log`.
  ///
  /// Иначе `flutter test` подмешивает в лог пользователя строки тестовых
  /// движков — и они неотличимы от продакшена. На этом уже обожглись: строки
  /// «Автопереподключение: обрыв → попытка N» с фиктивным сервером `b` были
  /// приняты за реальный сбой у пользователя и легли в основу неверного
  /// диагноза. Flutter выставляет FLUTTER_TEST в окружении тестов.
  static final bool _underTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  static bool _fileWrites = !_underTest;

  /// Файловая часть лога — ОДИН объект на процесс.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО ПЕРЕПИСАНО. Раньше поток открывался здесь
  /// (`openWrite(FileMode.append)`), а обрезался в `clear()` отдельным
  /// `writeAsString('')`. `IOSink` запоминает смещение при открытии и после
  /// такой обрезки продолжает писать по старому адресу — Windows заполняет
  /// пропуск нулями. У владельца это дало 434 847 нулевых байт подряд (93 %
  /// файла) при 218 реальных строках. Теперь и запись, и обрезка идут через
  /// один [RotatingLog], который поток ПЕРЕСОЗДАЁТ.
  static Future<RotatingLog>? _file;

  /// Очередь записи.
  ///
  /// ⚠️ ВТОРОЙ ДЕФЕКТ ТОЙ ЖЕ СТРОЧКИ: раньше `_write` был `async void` и
  /// ставил флаг «инициализация начата» ДО своих `await`. Пока первый вызов
  /// ждал открытия файла, следующие видели флаг, шли сразу на `_sink?.writeln`
  /// — а `_sink` был ещё `null`, и строки МОЛЧА ТЕРЯЛИСЬ. Замерено на этой же
  /// машине: из десяти подряд идущих записей в файл попадала ОДНА. Именно
  /// поэтому в 457-килобайтном файле оказалось всего 218 строк. Цепочка
  /// `_pending` держит порядок и не теряет ничего.
  static Future<void> _pending = Future<void>.value();

  static Future<RotatingLog> _fileLog() => _file ??= _openFile();

  static Future<RotatingLog> _openFile() async {
    final log = RotatingLog(await filePath(), maxBytes: _maxBytes);
    await log.open();
    return log;
  }

  static void _write(LogEntry entry) {
    if (!_fileWrites) return;
    _pending = _pending.then((_) async {
      try {
        await (await _fileLog()).write(entry.line);
      } catch (_) {
        // Диагностика не имеет права ронять приложение.
      }
    }).catchError((_) {});
  }

  /// Дождаться, пока всё записанное реально окажется на диске.
  ///
  /// Без этого экран логов и отчёт поддержки читают файл БЕЗ последних строк —
  /// то есть ровно без тех, ради которых лог и открывали.
  static Future<void> flushFile() async {
    try {
      // ⚠️ СНАЧАЛА ждём очередь, и только потом смотрим, открыт ли файл.
      // Обратный порядок выглядит экономнее и молча не работает: `_write`
      // ставит задачу в `_pending`, а сам файл открывается уже ВНУТРИ неё, так
      // что на момент синхронной проверки `_file` ещё null — и «сбрасывать
      // нечего» возвращалось ровно тогда, когда сбрасывать было что.
      await _pending;
      final opened = _file;
      if (opened == null) return; // файл ни разу не открывали
      await (await opened).flush();
    } catch (_) {}
  }

  /// Ведёт ли файл лога ЭТОТ экземпляр приложения.
  ///
  /// `false` означает, что запущена вторая копия и файл принадлежит ей: строки
  /// туда попадают от обеих, а обрезать его нам нельзя. Признак нужен отчёту
  /// поддержки — «две копии на одном логе» иначе неотличимо от порчи файла.
  static Future<bool> ownsFile() async {
    if (_file == null) return true;
    try {
      return (await _fileLog()).isOwner;
    } catch (_) {
      return true;
    }
  }

  /// Открыт ли уже файловый лог (чистка по сроку хранения спрашивает: обрезать
  /// его через владельца или можно просто удалить файл).
  static bool get fileOpened => _file != null;

  /// Весь текст лога (память + файл) для показа и копирования.
  ///
  /// ⚠️ Читаем БАЙТАМИ с `allowMalformed`, а не `readAsString()`. Строгое
  /// чтение падает на первом же неверном байте, а он там появляется: в лог
  /// попадают строки сторонних процессов и системные сообщения в кодировке
  /// консоли. У владельца из-за ОДНОГО байта `0x82` в середине 239-килобайтного
  /// файла отчёт поддержки отдавал ПУСТОЙ раздел `[app.log]` — и диагноз по
  /// нему поставить было нельзя, хотя лог исправно писался. Молчаливая пустота
  /// хуже мусора: она выглядит как «логов нет», а не как «прочитать не смог».
  /// ⚠️ ЧТО ОТДАЁМ, ТО И МАСКИРУЕМ ЕЩЁ РАЗ. Строки, записанные ДО того, как
  /// список серверов собрался (ранний старт), и строки, оставшиеся в файле от
  /// прошлых запусков и прошлых версий, реестра адресов не проходили —
  /// [SensitiveAddresses] тогда был пуст. Файл живёт до 512 КБ, то есть днями,
  /// и именно он целиком уезжает в отчёт поддержки. Прогон здесь стоит один
  /// проход регулярки по тексту и делает исправление обратным: адрес,
  /// записанный вчера, наружу уже не уйдёт.
  static Future<String> dump() async {
    try {
      await flushFile();
      final f = File(await filePath());
      if (await f.exists()) {
        return SensitiveAddresses.mask(
            utf8.decode(await f.readAsBytes(), allowMalformed: true));
      }
    } catch (_) {}
    return SensitiveAddresses.mask(_memory.map((e) => e.line).join('\n'));
  }

  static Future<void> clear() async {
    _memory.clear();
    // ⚠️ Обрезаем ЧЕРЕЗ ТОТ ЖЕ объект, который пишет. Прежний код звал
    // `File.writeAsString('')` мимо потока — и следующая же строка ложилась по
    // старому смещению, оставляя перед собой сотни килобайт нулей.
    if (_fileWrites || _file != null) {
      try {
        await _pending;
        await (await _fileLog()).truncate();
      } catch (_) {}
    }
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
  }

  /// Направить файловый лог в тестовый файл (боевой `%APPDATA%` не трогается).
  @visibleForTesting
  static Future<void> useFileForTest(String path) async {
    await resetFileForTest();
    _pathOverride = path;
    _fileWrites = true;
  }

  /// Вернуть всё как было: закрыть тестовый файл, снять подмену пути.
  @visibleForTesting
  static Future<void> resetFileForTest() async {
    final open = _file;
    _file = null;
    try {
      await _pending;
    } catch (_) {}
    _pending = Future<void>.value();
    try {
      await (await open)?.close();
    } catch (_) {}
    _pathOverride = null;
    _fileWrites = !_underTest;
    _memory.clear();
  }
}

/// Размер и наполнение одного файла лога.
class LogFileStat {
  /// Имя файла (`app.log`) — его и показываем пользователю.
  final String name;
  final String path;
  final int bytes;
  final int lines;

  /// Сколько из [bytes] — нулевые байты.
  ///
  /// ⚠️ Считается не из любопытства: именно нулевые байты были 93 % `app.log`
  /// и 98 % `singbox.log` у владельца. Ненулевое значение здесь означает, что
  /// порча вернулась, и увидеть это надо в отчёте, а не через год по жалобе.
  final int zeros;

  /// Время последней записи — по нему считается и «не удалять живой файл»
  /// в [LogMaintenance.clean], и период накопления на экране логов.
  final DateTime modified;

  const LogFileStat({
    required this.name,
    required this.path,
    required this.bytes,
    required this.lines,
    required this.zeros,
    required this.modified,
  });
}

/// Имя файла лога TUN-ядра — единственное, что классификация знает по имени
/// явно (наряду с `app.log`). Всё остальное «*.log» — прокси-ядра и
/// маршрутизаторы; их список НЕ перечисляется, чтобы шестой лог сам попал в
/// нужную корзину на экране логов, а не выпал из неё молча.
const _tunLogName = 'singbox.log';

/// Что логи и отчёты занимают на диске.
class LogInventory {
  final List<LogFileStat> logs;
  final int reportCount;
  final int reportBytes;

  /// Время последней записи САМОГО СТАРОГО и САМОГО НОВОГО файла (логи и
  /// отчёты вместе) — «за какой период накоплены логи» на экране очистки.
  /// `null` — на диске вообще ничего нет.
  final DateTime? oldest;
  final DateTime? newest;

  const LogInventory({
    required this.logs,
    required this.reportCount,
    required this.reportBytes,
    this.oldest,
    this.newest,
  });

  int get logBytes => logs.fold(0, (a, b) => a + b.bytes);
  int get totalBytes => logBytes + reportBytes;

  /// Лог приложения — или `null`, если его ещё нет.
  LogFileStat? get appLog => _byName(AppLog._appLogName);

  /// Лог TUN-ядра (`singbox.log`) — предыдущая ротированная часть
  /// (`singbox.prev.log`) в него не входит, но чистится той же категорией
  /// (см. [LogMaintenance.cleanSelected]).
  LogFileStat? get tunLog => _byName(_tunLogName);

  /// Всё остальное «*.log»: прокси-ядра (hysteria2, xray) и маршрутизаторы
  /// выходов. Специально не список имён — новый лог попадёт сюда сам.
  List<LogFileStat> get proxyLogs => logs
      .where((f) =>
          f.name != AppLog._appLogName &&
          f.name != _tunLogName &&
          f.name != 'singbox.prev.log')
      .toList();

  int get proxyBytes => proxyLogs.fold(0, (a, b) => a + b.bytes);

  LogFileStat? _byName(String name) {
    for (final f in logs) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Сколько дней накапливаются логи и отчёты — включительно (день первой
  /// записи считается тоже). `null`, если данных ещё нет.
  int? get periodDays {
    final a = oldest, b = newest;
    if (a == null || b == null) return null;
    return b.difference(a).inDays + 1;
  }
}

/// Итог чистки по сроку хранения.
class LogCleanupResult {
  final int files;
  final int bytes;
  const LogCleanupResult(this.files, this.bytes);
  static const empty = LogCleanupResult(0, 0);
  bool get isEmpty => files == 0;
}

/// Хозяйство логов: сколько занимают и что удалять по сроку хранения.
///
/// ⚠️ ПОЯВИЛОСЬ ПО ЖИВЫМ ДАННЫМ: у владельца 18 отчётов поддержки на 4,3 МБ,
/// ни один никогда не удалялся, и каждый следующий больше предыдущего (78 КБ в
/// июле → 525 КБ в августе), потому что отчёт включает логи целиком. Размер при
/// этом нельзя было узнать иначе как проводником.
class LogMaintenance {
  /// Папка отчётов поддержки внутри каталога данных.
  static const reportsDirName = 'support';

  /// Перепись: все `*.log` каталога данных + папка отчётов.
  ///
  /// Имена файлов НЕ перечисляются списком: логов пять (`app`, `singbox`,
  /// `singbox_proxy`, `singbox_exit_router`, `xray`), список устареет с шестым,
  /// и новый лог молча не попадёт ни на экран, ни в отчёт.
  static Future<LogInventory> inventory({Directory? dir}) async {
    final root = dir ?? await AppPaths.supportDir();
    final logs = <LogFileStat>[];
    // «С какой по какую дату копятся логи» — по факту последней записи
    // ЛЮБОГО файла (лога или отчёта), поэтому считаем по ходу обоих обходов.
    DateTime? oldest;
    DateTime? newest;
    void track(DateTime t) {
      if (oldest == null || t.isBefore(oldest!)) oldest = t;
      if (newest == null || t.isAfter(newest!)) newest = t;
    }

    try {
      final entries = root.listSync().whereType<File>().where(
          (f) => f.path.toLowerCase().endsWith('.log'));
      for (final f in entries) {
        final stat = await statOf(f);
        logs.add(stat);
        track(stat.modified);
      }
    } catch (_) {}
    logs.sort((a, b) => a.name.compareTo(b.name));

    var reportCount = 0;
    var reportBytes = 0;
    try {
      final reports =
          Directory('${root.path}${Platform.pathSeparator}$reportsDirName');
      if (reports.existsSync()) {
        for (final f in reports.listSync().whereType<File>()) {
          reportCount++;
          reportBytes += await f.length();
          try {
            track(await f.lastModified());
          } catch (_) {}
        }
      }
    } catch (_) {}

    return LogInventory(
      logs: logs,
      reportCount: reportCount,
      reportBytes: reportBytes,
      oldest: oldest,
      newest: newest,
    );
  }

  /// Размер, число строк и число нулевых байт одного файла.
  ///
  /// Файл читается ПОТОКОМ: `singbox.log` наблюдался размером 758 МБ, и
  /// `readAsBytes()` ради подсчёта строк подвесил бы приложение — ровно так уже
  /// вело себя «Написать в поддержку» до 1.0.2.
  static Future<LogFileStat> statOf(File f) async {
    final name = f.uri.pathSegments.isEmpty ? f.path : f.uri.pathSegments.last;
    var bytes = 0;
    var lines = 0;
    var zeros = 0;
    var last = 0;
    var modified = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      bytes = await f.length();
      modified = await f.lastModified();
      await for (final chunk in f.openRead()) {
        for (final b in chunk) {
          if (b == 10) {
            lines++;
          } else if (b == 0) {
            zeros++;
          }
        }
        if (chunk.isNotEmpty) last = chunk.last;
      }
      // Последняя строка без перевода строки — тоже строка.
      if (bytes > 0 && last != 10) lines++;
    } catch (_) {}
    return LogFileStat(
        name: name,
        path: f.path,
        bytes: bytes,
        lines: lines,
        zeros: zeros,
        modified: modified);
  }

  /// Удалить логи и отчёты старше [maxAge]. `null` — «никогда не удалять».
  ///
  /// ⚠️ Возраст берётся по времени ПОСЛЕДНЕЙ ЗАПИСИ. Живой лог (в него сейчас
  /// пишет ядро или вторая копия приложения) поэтому кандидатом не станет — и
  /// его нельзя удалять: у пишущего в него потока смещение зафиксировано, и
  /// файл, созданный заново, тут же получил бы нулевую дыру до этого смещения.
  ///
  /// Собственный `app.log` не удаляется, а ОБРЕЗАЕТСЯ через владеющий им
  /// [RotatingLog] — по той же причине.
  static Future<LogCleanupResult> clean({
    required Duration? maxAge,
    Directory? dir,
    DateTime? now,
  }) async {
    if (maxAge == null) return LogCleanupResult.empty;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    final root = dir ?? await AppPaths.supportDir();
    final appLogPath = await AppLog.filePath();
    var files = 0;
    var bytes = 0;

    Future<bool> isOld(File f) async {
      try {
        return (await f.lastModified()).isBefore(cutoff);
      } catch (_) {
        return false;
      }
    }

    try {
      for (final f in root.listSync().whereType<File>()) {
        if (!f.path.toLowerCase().endsWith('.log')) continue;
        if (!await isOld(f)) continue;
        final size = await f.length();
        if (f.path == appLogPath && AppLog.fileOpened) {
          // ⚠️ Свой открытый лог ОБРЕЗАЕМ через владельца, а не удаляем:
          // у потока смещение уже зафиксировано, и созданный заново файл тут
          // же получил бы нулевую дыру до этого смещения.
          if (size == 0) continue; // и так пуст — «удалять нечего»
          await AppLog.clear();
        } else {
          await f.delete();
        }
        files++;
        bytes += size;
      }
    } catch (_) {}

    try {
      final reports =
          Directory('${root.path}${Platform.pathSeparator}$reportsDirName');
      if (reports.existsSync()) {
        for (final f in reports.listSync().whereType<File>()) {
          if (!await isOld(f)) continue;
          final size = await f.length();
          await f.delete();
          files++;
          bytes += size;
        }
      }
    } catch (_) {}

    return LogCleanupResult(files, bytes);
  }

  /// Очистить ВЫБРАННЫЕ категории немедленно, без учёта возраста.
  ///
  /// От [clean] отличается тем, для чего его вызывают: [clean] — автоматика
  /// по сроку хранения (не трогает свежее), а это — ручная кнопка «Очистить
  /// логи» с диалогом-выбором: пользователь только что смотрел в лог и явно
  /// попросил стереть ИМЕННО его, независимо от даты последней записи.
  ///
  /// ⚠️ Свой `app.log` по-прежнему ОБРЕЗАЕТСЯ через владельца, а не удаляется
  /// файлом — причина та же, что в [clean]: у открытого потока смещение
  /// зафиксировано, и удалённый файл вернулся бы дырой из нулей.
  static Future<LogCleanupResult> cleanSelected({
    bool app = false,
    bool tun = false,
    bool proxy = false,
    bool reports = false,
    Directory? dir,
  }) async {
    final root = dir ?? await AppPaths.supportDir();
    final appLogPath = await AppLog.filePath();
    var files = 0;
    var bytes = 0;

    try {
      for (final f in root.listSync().whereType<File>()) {
        if (!f.path.toLowerCase().endsWith('.log')) continue;
        final name =
            f.uri.pathSegments.isEmpty ? f.path : f.uri.pathSegments.last;
        final isApp = f.path == appLogPath || name == AppLog._appLogName;
        final isTun = name == _tunLogName || name == 'singbox.prev.log';
        if (isApp && !app) continue;
        if (isTun && !tun) continue;
        if (!isApp && !isTun && !proxy) continue;

        final size = await f.length();
        if (size == 0) continue; // и так пуст — «удалять нечего»
        if (isApp && AppLog.fileOpened) {
          await AppLog.clear();
        } else {
          await f.delete();
        }
        files++;
        bytes += size;
      }
    } catch (_) {}

    if (reports) {
      try {
        final reportsDir =
            Directory('${root.path}${Platform.pathSeparator}$reportsDirName');
        if (reportsDir.existsSync()) {
          for (final f in reportsDir.listSync().whereType<File>()) {
            final size = await f.length();
            await f.delete();
            files++;
            bytes += size;
          }
        }
      } catch (_) {}
    }

    return LogCleanupResult(files, bytes);
  }
}

/// Убрать секреты из строки ПЕРЕД записью в журнал.
///
/// ⚠️ НАЙДЕНО ЖИВЫМ ТЕСТОМ 13.08.2026, статикой такое не видно. В госте не было
/// сети, обновление подписки упало, и текст исключения `http`-клиента лёг в
/// `app.log` ЦЕЛИКОМ — вместе с адресом подписки, а у Remnawave последний
/// сегмент этого адреса и есть токен доступа ко всей подписке.
///
/// Цена ошибки высокая: `app.log` вкладывается в отчёт для поддержки, который
/// пользователь по нашей же кнопке отправляет в чат. Сам отчёт URL маскирует
/// (`SupportReport._maskUrl`), а журнал ВНУТРИ него — нет, и маскировка в
/// шапке создавала ложное ощущение безопасности.
///
/// ⚠️ ЧИСТИМ НА ГРАНИЦЕ, А НЕ В МЕСТЕ ВЫЗОВА. Тот же принцип, что у барьера
/// секретов локального API: обработчик, забывший про новый случай, обошёл бы
/// проверку молча. Здесь через `_add` проходит КАЖДАЯ строка журнала.
///
/// Хост и схему оставляем: без них не разобрать, к какой панели не достучались,
/// а сам по себе хост секретом не является — он виден и в интерфейсе.
String scrubSecrets(String message) {
  var out = message;
  // Адрес подписки: у Remnawave токен лежит в пути (`/sub/<токен>`).
  out = out.replaceAllMapped(
    RegExp(r'(https?://[^\s/?#]+)(/[^\s"<>]*)', caseSensitive: false),
    (m) => '${m[1]}/****',
  );
  // Ссылки на серверы: в них учётные данные (uuid VLESS, пароль trojan/ss,
  // пароль обфускации hysteria2) — целиком, до первого пробела.
  out = out.replaceAllMapped(
    RegExp(r'(vless|vmess|trojan|ss|hysteria2|hy2)://[^\s"<>]+',
        caseSensitive: false),
    (m) => '${m[1]}://****',
  );
  // Адреса СВОИХ серверов — по реестру, а не по виду строки (см.
  // [SensitiveAddresses]): голое `ru1.example.com:443` от полезного
  // `127.0.0.1:10808` ничем не отличается, кроме того, что первое — наш узел.
  return SensitiveAddresses.mask(out);
}

/// Адреса своих серверов — единственное, что журнал маскирует ПО РЕЕСТРУ.
///
/// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТО НАПИСАНО. `VpnServer.displayName` при пустом
/// имени вырождается в «адрес:порт», и в `AppLog` он уходит из девяти мест
/// сразу: `app_state`, `engine_base` (запасной сервер, «не удалось
/// отрезолвить»), `probe_controller`, `auto_config_engine`, `exit_outbounds`.
/// Один такой путь (диф подписки) закрыли в месте вызова — и этого хватило
/// ровно на один день: остальные восемь продолжали писать боевой адрес узла в
/// `app.log`, а он целиком вкладывается в отчёт поддержки, который владелец
/// пересылает в чат. Поэтому чистка стоит на ГРАНИЦЕ — в [scrubSecrets], через
/// который проходит КАЖДАЯ строка журнала, включая ту, что напишут завтра.
///
/// ⚠️ И ПОЭТОМУ ЖЕ — РЕЕСТР, А НЕ «ВЫРЕЗАТЬ ВСЁ, ЧТО ПОХОЖЕ НА АДРЕС». В
/// журнале полно адресов, без которых он перестаёт годиться для разбора, ради
/// которого и существует: `127.0.0.1` с портами ядра, адрес TUN-адаптера
/// `172.19.0.x`, резолверы вроде `1.1.1.1`, мишени проб. Приложение при этом
/// ЗНАЕТ адреса своих серверов — они все в списке серверов
/// (`AppState._rebuild` / `allSubscriptionServers`). Маскируем ровно их.
///
/// ⚠️ МЕТКА ОБЯЗАНА БЫТЬ УЗНАВАЕМОЙ. Разные строки об одном узле должны
/// оставаться сопоставимыми, иначе журнал нечем разбирать: одному адресу
/// соответствует одна метка «адрес №N», и порт рядом с ней сохраняется
/// («адрес №3:443» и «адрес №3:8443» — разные узлы на одном хосте).
/// Номер выдаётся по порядку ПЕРВОЙ ВСТРЕЧИ и живёт до конца запуска
/// приложения. Сквозной стабильности между запусками здесь НЕТ и не
/// обещается: реестр на диск не пишется, после перезапуска нумерация может
/// смениться.
///
/// ⚠️ САМ РЕЕСТР НАРУЖУ НЕ ОТДАЁТСЯ. У класса нет геттера, возвращающего
/// адреса, — только [count]. Барьер, который можно прочитать через отчёт или
/// `GET /v1/…`, был бы просто ещё одним местом утечки.
///
/// ЧЕГО ЭТО НЕ ЗАКРЫВАЕТ (чтобы не считать закрытым лишнего):
/// * логи ЯДЕР (`singbox.log`, `xray.log`) — там адреса пишет не приложение, и
///   в отчёт поддержки они попадают своим путём, мимо [AppLog];
/// * адрес, отрезолвленный из имени узла, если само имя в реестре, а
///   получившийся IP — нет;
/// * поддомены известного адреса (`x.node.example` при известном
///   `node.example`) — сканер сверяет кусок целиком.
///
/// Цена по времени замерена, а не предположена: 10 000 строк журнала при
/// реестре в 262 адреса — 78 мс (≈8 мкс на строку), 650 КБ текста одним
/// проходом (это случай [AppLog.dump]) — 38 мс.
class SensitiveAddresses {
  SensitiveAddresses._();

  /// Адрес (нижний регистр, без скобок IPv6) → метка.
  static final Map<String, String> _labels = <String, String>{};

  /// Сколько адресов маскируется. Числа достаточно и отчёту, и тесту; сами
  /// адреса не отдаются никому.
  static int get count => _labels.length;

  /// Кусок текста, который в принципе может оказаться адресом: непрерывная
  /// цепочка «адресных» символов, содержащая хотя бы одну точку или
  /// двоеточие.
  ///
  /// ⚠️ ОДИН И ТОТ ЖЕ РАЗБОР И ПРИ ЗАПОМИНАНИИ, И ПРИ МАСКИРОВКЕ. Разойдись
  /// они — реестр принимал бы то, чего сканер журнала не находит, и дыра
  /// выглядела бы закрытой. Тот же урок, что с `needsToken` и
  /// `controlAction`: разрешение и исполнение обязаны спрашивать один код.
  static final RegExp _token =
      RegExp(r'[0-9A-Za-z\[][0-9A-Za-z_%\[\]-]*(?:[.:][0-9A-Za-z_%\[\]-]*)+');

  /// `хост:порт`. Порт секретом не является и остаётся в журнале.
  static final RegExp _hostPort = RegExp(r'^(.+):(\d{1,5})$');

  static final RegExp _hexDigit = RegExp('[0-9a-f]');

  /// Хвостовая пунктуация: «не достучались до a.b.com:» и «(***.***.***.***)».
  static const _tail = '.:%-_';

  /// Запомнить адрес сервера — в любом виде (домен, IPv4, IPv6).
  ///
  /// [name] — название узла от панели. Панель раздаёт узлы по домену, а зовёт
  /// по IP («DE-1 (***.***.***.***)»), и тогда боевой адрес лежит ещё и в имени, а
  /// поле [address] его не содержит.
  static void remember(String address, {String name = ''}) {
    _remember(address);
    if (name.isEmpty) return;
    for (final m in _token.allMatches(name)) {
      final token = _core(m[0]!);
      // ⚠️ Из ИМЕНИ берём только IP-литералы. Доменное имя внутри названия
      // почти всегда часть самого названия («YouTube.com Fast»), а настоящий
      // хост узла и так пришёл сюда полем [address]. Маскируй мы по имени всё
      // подряд — из журнала пропали бы названия сервисов, по которым и
      // разбирают проверки доступности.
      if (_isIpLiteral(token)) _remember(token);
    }
  }

  static void _remember(String value) {
    final key = _unbracket(_core(value.trim())).toLowerCase();
    if (key.isEmpty) return;
    // ⚠️ Без точки и двоеточия кусок не поймает [_token] — запись в реестре
    // была бы, а маскировки не было бы НИКОГДА. Такой случай хуже открытого:
    // он выглядит закрытым. Публичный адрес сервера всегда содержит либо
    // точку (IPv4, домен), либо двоеточие (IPv6).
    if (!key.contains('.') && !key.contains(':')) return;
    if (_neverMask(key)) return;
    final before = _labels.length;
    _labels.putIfAbsent(key, () => 'адрес №${_labels.length + 1}');
    // Регулярка второго прохода собирается из самих адресов, поэтому новый
    // адрес обязан её сбросить. Забудь это — и последний импортированный
    // сервер остался бы незамаскированным, а тесты (реестр в них наполняется
    // до первой маскировки) ничего бы не заметили.
    if (_labels.length != before) _gluedRe = null;
  }

  /// Адреса, которые маскировать НЕЛЬЗЯ: на них держится разбор журнала.
  ///
  /// Литералы прописаны здесь, а не взяты из `NetworkWatcher`: там они
  /// приватные, и такие же копии уже лежат в `interference_scanner` и
  /// `singbox_router_windows`.
  static bool _neverMask(String v) =>
      v == 'localhost' ||
      v.startsWith('127.') ||
      v == '::1' ||
      // «Сервер» истёкшей подписки — это сообщение с адресом 0.0.0.0:1.
      v == '0.0.0.0' ||
      v == '::' ||
      v.startsWith('169.254.') ||
      // Наш собственный TUN-адаптер: по нему и разбирают, поднялся ли туннель.
      v.startsWith('172.19.0.') ||
      v.startsWith('fdfe:dcba:9876:');

  /// Заменить в [text] все известные адреса на их метки.
  ///
  /// Пустой реестр — мгновенный выход: до импорта подписки (и в тестах, где
  /// серверов нет) журнал не платит ничего.
  static String mask(String text) {
    if (_labels.isEmpty || text.isEmpty) return text;
    final byToken = text.replaceAllMapped(_token, (m) {
      final token = m[0]!;
      final core = _core(token);
      final label = core.isEmpty ? null : _labelFor(core);
      return label == null ? token : '$label${token.substring(core.length)}';
    });
    return _maskGlued(byToken);
  }

  /// Второй проход: известный адрес, СЛИПШИЙСЯ с окружением.
  ///
  /// ⚠️ ЗАЧЕМ ОН НУЖЕН, ХОТЯ ПЕРВОГО ПРОХОДА «ДОЛЖНО ХВАТАТЬ». Дефис входит в
  /// класс символов адреса (без него не разобрать `my-node.example.com`),
  /// поэтому `NL-185.199.108.153` разбирается как ОДИН кусок — и поиск по
  /// реестру его не находит, хотя внутри лежит боевой IP. А «страна-адрес» —
  /// самая частая схема именования узлов у панелей: ровно на ней уже
  /// споткнулась проверка формы адреса в дифе подписки.
  ///
  /// Ищем сами известные адреса, а не форму: реестр мал (у владельца 131
  /// сервер), а границы заданы так, чтобы не задеть соседей — адрес не
  /// маскируется, если слева или справа от него продолжается ДРУГОЕ имя
  /// (`node.example` внутри `x.node.example` — это поддомен, чужое имя).
  static String _maskGlued(String text) {
    final re = _gluedRe ??= _buildGluedRe();
    if (re == null) return text;
    return text.replaceAllMapped(
        re, (m) => _labels[m[0]!.toLowerCase()] ?? m[0]!);
  }

  static RegExp? _gluedRe;

  static RegExp? _buildGluedRe() {
    if (_labels.isEmpty) return null;
    // Длинные первыми: иначе `a.example` съело бы часть `sub.a.example.com`.
    final keys = _labels.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final body = keys.map(RegExp.escape).join('|');
    // Слева — не продолжение имени (буква, цифра, подчёркивание или точка).
    // Справа — не продолжение имени; точка допускается только как знак
    // препинания, то есть если за ней не идёт буква или цифра.
    return RegExp('(?<![0-9A-Za-z_.])(?:$body)(?![0-9A-Za-z_-])(?!\\.[0-9A-Za-z])',
        caseSensitive: false);
  }

  static String? _labelFor(String core) {
    final direct = _labels[_unbracket(core).toLowerCase()];
    if (direct != null) return direct;
    final hostPort = _hostPort.firstMatch(core);
    if (hostPort == null) return null;
    final host = _labels[_unbracket(hostPort.group(1)!).toLowerCase()];
    return host == null ? null : '$host:${hostPort.group(2)}';
  }

  static String _core(String token) {
    var end = token.length;
    while (end > 0 && _tail.contains(token[end - 1])) {
      end--;
    }
    return token.substring(0, end);
  }

  static String _unbracket(String v) =>
      v.length > 2 && v.startsWith('[') && v.endsWith(']')
          ? v.substring(1, v.length - 1)
          : v;

  static bool _isIpLiteral(String token) {
    final bare = _unbracket(token).split('%').first.toLowerCase();
    // ⚠️ Одной `tryParse` мало: «::» она принимает за адрес, а в названии узла
    // это оформление («🇩🇪 DE :: 01»). Настоящий IPv6 содержит хотя бы одну
    // шестнадцатеричную цифру.
    return InternetAddress.tryParse(bare) != null && _hexDigit.hasMatch(bare);
  }

  /// Забыть всё. В приложении реестр живёт до конца запуска — чистка нужна
  /// тестам, иначе адреса одного теста маскировали бы строки следующего.
  @visibleForTesting
  static void forgetAllForTest() => _labels.clear();
}
