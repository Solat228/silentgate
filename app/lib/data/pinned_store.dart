import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';

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
      return data is List ? data.cast<String>() : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<String> links) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(links));
    } catch (_) {}
  }
}
