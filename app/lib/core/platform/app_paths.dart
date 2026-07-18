import 'dart:io';

/// Единый детерминированный каталог данных приложения: `%APPDATA%\SilentGate`.
/// Фиксированный путь (а не getApplicationSupportDirectory) — чтобы установщик и режим
/// `--cleanup` могли гарантированно вычистить данные при удалении.
class AppPaths {
  static const dirName = 'SilentGate';

  static Directory supportDirSync() {
    final appData = Platform.environment['APPDATA'];
    final base = (appData != null && appData.isNotEmpty)
        ? '$appData${Platform.pathSeparator}$dirName'
        : '${Directory.systemTemp.path}${Platform.pathSeparator}$dirName';
    final dir = Directory(base);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<Directory> supportDir() async => supportDirSync();
}
