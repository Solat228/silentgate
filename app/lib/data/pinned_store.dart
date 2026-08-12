import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';
import '../core/util/key_migration.dart';
import 'atomic_file.dart';

/// Хранилище закреплённых/правленых серверов (список share-ссылок). Переживает удаление подписки.
class PinnedStore {
  static const _fileName = 'pinned_servers.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<List<String>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return [];
      // ⚠️ Ключи приводим к каноническому виду ПРИ ЧТЕНИИ. До 1.4.2 один и тот
      // же сервер мог храниться в двух написаниях ссылки, и пин переставал
      // находиться сразу после того, как панель сменила формат ответа.
      return KeyMigration.remapList(data.cast<String>(), logLabel: 'пины');
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<String> links) async {
    try {
      final f = await _file();
      await AtomicFile.writeString(f, jsonEncode(links));
    } catch (_) {}
  }
}
