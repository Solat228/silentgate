import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';
import '../core/singbox/tun_autotune.dart';
import 'atomic_file.dart';

/// Запоминает комбинацию параметров TUN, на которой туннель реально поднялся.
///
/// Хранится отдельно от настроек: это не выбор пользователя, а результат подбора,
/// и перезаписывать им явно выставленные значения нельзя.
class TunTuningStore {
  static const _fileName = 'tun_tuning.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<TunCombo?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString());
      if (data is! Map) return null;
      return TunCombo.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TunCombo combo) async {
    try {
      final f = await _file();
      await AtomicFile.writeString(f, jsonEncode(combo.toJson()));
    } catch (_) {}
  }
}
