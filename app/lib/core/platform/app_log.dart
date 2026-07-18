import 'dart:collection';
import 'dart:io';

import 'app_paths.dart';

enum LogLevel { info, warn, error }

class LogEntry {
  final DateTime at;
  final LogLevel level;
  final String message;
  const LogEntry(this.at, this.level, this.message);

  String get line =>
      '${at.toIso8601String()} [${level.name.toUpperCase()}] $message';
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

  static void _write(LogEntry entry) async {
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
  static Future<String> dump() async {
    try {
      await _sink?.flush();
      final f = File(await filePath());
      if (await f.exists()) return await f.readAsString();
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
