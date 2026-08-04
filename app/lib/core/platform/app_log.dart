import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

enum LogLevel { info, warn, error }

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
  static const _maxBytes = 512 * 1024;

  static final Queue<LogEntry> _memory = Queue<LogEntry>();
  static IOSink? _sink;
  static bool _initTried = false;

  /// Слушатели (экран логов обновляется вживую).
  static final List<void Function()> _listeners = [];

  static List<LogEntry> get entries => List.unmodifiable(_memory);

  static void addListener(void Function() l) => _listeners.add(l);
  static void removeListener(void Function() l) => _listeners.remove(l);

  static void i(String message) => _add(LogLevel.info, message);
  static void w(String message) => _add(LogLevel.warn, message);
  static void e(String message) => _add(LogLevel.error, message);

  static void _add(LogLevel level, String message) {
    final entry = LogEntry(DateTime.now(), level, message);
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

  static Future<String> filePath() async =>
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

  static void _write(LogEntry entry) async {
    if (_underTest) return;
    try {
      if (!_initTried) {
        _initTried = true;
        final f = File(await filePath());
        if (await f.exists() && await f.length() > _maxBytes) {
          await f.writeAsString(''); // простая ротация
        }
        _sink = f.openWrite(mode: FileMode.append);
      }
      _sink?.writeln(entry.line);
    } catch (_) {}
  }

  /// Весь текст лога (память + файл) для показа и копирования.
  ///
  /// ⚠️ Читаем БАЙТАМИ с `allowMalformed`, а не `readAsString()`. Строгое
  /// чтение падает на первом же неверном байте, а он там появляется: в лог
  /// попадают строки сторонних процессов и системные сообщения в кодировке
  /// консоли. У владельца из-за ОДНОГО байта `0x82` в середине 239-килобайтного
  /// файла отчёт поддержки отдавал ПУСТОЙ раздел `[app.log]` — и диагноз по
  /// нему поставить было нельзя, хотя лог исправно писался. Молчаливая пустота
  /// хуже мусора: она выглядит как «логов нет», а не как «прочитать не смог».
  static Future<String> dump() async {
    try {
      await _sink?.flush();
      final f = File(await filePath());
      if (await f.exists()) {
        return utf8.decode(await f.readAsBytes(), allowMalformed: true);
      }
    } catch (_) {}
    return _memory.map((e) => e.line).join('\n');
  }

  static Future<void> clear() async {
    _memory.clear();
    try {
      await _sink?.flush();
      await File(await filePath()).writeAsString('');
    } catch (_) {}
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
  }
}
