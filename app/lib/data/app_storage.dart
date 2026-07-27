import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';
import 'atomic_file.dart';

/// Простое JSON-хранилище состояния приложения в каталоге поддержки приложения.
///
/// В MVP хранит: URL подписки, индекс выбранного сервера и кэш сырых share-ссылок
/// (чтобы список серверов был доступен офлайн). Шифрование секретов — этап M6.
class AppStorage {
  static const _fileName = 'silentgate_state.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Map<String, dynamic>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    try {
      final file = await _file();
      await AtomicFile.writeString(file, jsonEncode(data));
    } catch (_) {
      // Потеря настроек не критична для работы туннеля.
    }
  }
}
