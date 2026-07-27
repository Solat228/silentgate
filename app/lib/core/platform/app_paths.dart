import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Единый каталог данных приложения — ЕДИНСТВЕННАЯ точка платформозависимости
/// всего дискового слоя: восемь сторов, логи, кэши иконок и отчёты поддержки
/// строят пути только отсюда.
///
/// **Windows:** фиксированный `%APPDATA%\SilentGate`, а не
/// `getApplicationSupportDirectory` — сознательно, чтобы установщик и режим
/// `--cleanup` могли гарантированно вычистить данные при удалении.
///
/// **Android:** `getApplicationSupportDirectory()` — путь известен только
/// асинхронно, поэтому перед первым синхронным обращением обязателен [init]
/// (зовётся из `main`). Систему очистки там писать не нужно: данные удаляет
/// сама ОС вместе с приложением.
class AppPaths {
  static const dirName = 'SilentGate';

  static Directory? _cached;

  /// Разово вычисляет корень данных. Вызывать из `main` ДО построения UI и
  /// любых сторов. Идемпотентна; на Windows не обязательна (там путь
  /// вычисляется синхронно), на Android — обязательна.
  static Future<Directory> init() async {
    final known = _cached;
    if (known != null) return known;

    Directory dir;
    if (Platform.isWindows) {
      dir = Directory(_windowsBase());
    } else {
      try {
        final base = await getApplicationSupportDirectory();
        dir = Directory('${base.path}${Platform.pathSeparator}$dirName');
      } catch (_) {
        // Сюда попадают host-тесты вне Flutter-биндингов (плагина нет,
        // MissingPluginException) и отказ платформы отдать каталог — уходим во
        // временную папку, как и при пустом APPDATA на Windows.
        dir = Directory(_tempBase());
      }
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cached = dir;
  }

  /// Подменить корень данных (тесты и изолированные копии).
  ///
  /// На Windows изоляция исторически делается подменой переменной `APPDATA`;
  /// на других платформах переменной среды нет, поэтому нужен явный хук.
  static void overrideRoot(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cached = dir;
  }

  /// Сбросить кэш (между тестами).
  static void resetForTests() => _cached = null;

  static Directory supportDirSync() {
    final known = _cached;
    if (known != null) return known;

    // Windows умеет вычислить путь синхронно — сохраняем прежнее поведение
    // (и работоспособность до вызова init, например в режиме `--cleanup`).
    if (Platform.isWindows) {
      final dir = Directory(_windowsBase());
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return _cached = dir;
    }

    throw StateError(
      'AppPaths.init() не был вызван: на ${Platform.operatingSystem} корень '
      'данных известен только асинхронно. Вызовите AppPaths.init() в main() '
      'до обращения к хранилищам.',
    );
  }

  static Future<Directory> supportDir() async => _cached ?? await init();

  static String _windowsBase() {
    final appData = Platform.environment['APPDATA'];
    return (appData != null && appData.isNotEmpty)
        ? '$appData${Platform.pathSeparator}$dirName'
        : _tempBase();
  }

  static String _tempBase() =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}$dirName';
}
