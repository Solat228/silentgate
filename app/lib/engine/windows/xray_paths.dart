import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Поиск бинарника xray.exe и каталога гео-ассетов (geoip.dat/geosite.dat).
///
/// Проверяет (по порядку):
///  1. переменную окружения SILENTGATE_XRAY (полный путь к exe);
///  2. рядом с исполняемым файлом приложения (release-раскладка);
///  3. поднимаясь вверх от каталога exe и текущего каталога — ищет
///     engine/windows/bin/xray.exe (dev-раскладка репозитория).
class XrayLocation {
  final String executable;
  final String assetDir;
  const XrayLocation(this.executable, this.assetDir);
}

class XrayPaths {
  static XrayLocation? _cached;

  static XrayLocation? locate() {
    if (_cached != null) return _cached;
    final exe = _findExecutable();
    if (exe == null) return null;
    _cached = XrayLocation(exe, File(exe).parent.path);
    return _cached;
  }

  /// Поиск для ЭЛЕВЕЙТНУТОГО помощника TUN: только от каталога exe.
  ///
  /// ⚠️ БЕЗ `SILENTGATE_XRAY` И БЕЗ ТЕКУЩЕГО КАТАЛОГА. Задача Планировщика
  /// бежит с окружением пользователя, а переменную пользователя может
  /// поставить любой его процесс без прав. Помощник запустил бы
  /// `sing-box.exe` из подсунутого каталога с правами администратора (аудит
  /// 25.10.2026, D2). Не кэшируется: обычный [locate] того же процесса
  /// окружение учитывает.
  static XrayLocation? locateTrusted() {
    final exe = _findExecutable(trusted: true);
    return exe == null ? null : XrayLocation(exe, File(exe).parent.path);
  }

  /// Кандидаты по порядку; вынесено ради теста.
  @visibleForTesting
  static List<String> candidates({required bool trusted}) {
    final candidates = <String>[];

    if (!trusted) {
      final env = Platform.environment['SILENTGATE_XRAY'];
      if (env != null && env.isNotEmpty) candidates.add(env);
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates.add(_join([exeDir, 'xray.exe']));
    candidates.add(_join([exeDir, 'xray', 'xray.exe']));

    for (final base in <String>{
      exeDir,
      if (!trusted) Directory.current.path,
    }) {
      Directory dir = Directory(base).absolute;
      for (int i = 0; i < 10; i++) {
        candidates.add(_join([dir.path, 'engine', 'windows', 'bin', 'xray.exe']));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return candidates;
  }

  static String? _findExecutable({bool trusted = false}) {
    for (final c in candidates(trusted: trusted)) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static String _join(List<String> parts) => parts.join(Platform.pathSeparator);
}
