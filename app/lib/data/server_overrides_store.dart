import 'dart:convert';
import 'dart:io';

import '../core/models/server_override.dart';
import '../core/platform/app_paths.dart';
import '../core/util/key_migration.dart';
import 'atomic_file.dart';

/// Хранилище override'ов серверов (ключ = rawLink сервера). Переживает перезапуск.
class ServerOverridesStore {
  static const _fileName = 'server_overrides.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Map<String, ServerOverride>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final data = jsonDecode(await f.readAsString());
      if (data is! Map) return {};
      final result = <String, ServerOverride>{};
      data.forEach((k, v) {
        if (v is Map) {
          result['$k'] = ServerOverride.fromJson(v.cast<String, dynamic>());
        }
      });
      // ⚠️ Ручные правки сервера — самое дорогое из хранимого по ключу: их
      // вводил человек. До 1.4.2 они молча отвязывались от сервера, когда
      // панель меняла формат ответа и ссылка получала другое написание.
      return KeyMigration.remapMap<ServerOverride>(result,
          logLabel: 'правки серверов');
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, ServerOverride> overrides) async {
    try {
      final f = await _file();
      final map = <String, dynamic>{};
      overrides.forEach((k, v) {
        if (!v.isEmpty) map[k] = v.toJson();
      });
      await AtomicFile.writeString(f, jsonEncode(map));
    } catch (_) {}
  }
}
