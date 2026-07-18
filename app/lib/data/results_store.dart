import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';

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
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Object data) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}
