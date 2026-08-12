import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';
import '../core/util/key_migration.dart';
import 'atomic_file.dart';

/// Простое JSON-хранилище результатов (пинг, автонастройка) в каталоге поддержки приложения.
class ResultsStore {
  final String fileName;
  const ResultsStore(this.fileName);

  static const ping = ResultsStore('ping_results.json');
  static const autoConfig = ResultsStore('autoconfig_results.json');

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  Future<dynamic> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final s = await f.readAsString();
      if (s.trim().isEmpty) return null;
      final data = jsonDecode(s);
      // ⚠️ Ключи приводим к каноническому виду ПРИ ЧТЕНИИ: до 1.4.2 сервер мог
      // храниться в двух написаниях ссылки, и результат пинга осиротевал сразу
      // после смены формата ответа панели. На данных владельца так потерялось
      // 273 записи из 374.
      if (data is Map) {
        return KeyMigration.remapMap<dynamic>(
          data.cast<String, dynamic>(),
          logLabel: fileName,
        );
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Object data) async {
    try {
      final f = await _file();
      await AtomicFile.writeString(f, jsonEncode(data));
    } catch (_) {}
  }
}
