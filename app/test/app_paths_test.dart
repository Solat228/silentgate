import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';

/// `AppPaths` — единственная точка платформозависимости всего дискового слоя
/// (восемь сторов, логи, кэши, отчёты поддержки). Ошибка здесь тихо уводит
/// данные пользователя в другую папку, поэтому поведение закреплено тестом.
void main() {
  tearDown(AppPaths.resetForTests);

  group('AppPaths', () {
    test('overrideRoot задаёт корень и создаёт каталог', () {
      final tmp = Directory.systemTemp.createTempSync('sg_paths_');
      final root = Directory('${tmp.path}${Platform.pathSeparator}nested');
      expect(root.existsSync(), isFalse);

      AppPaths.overrideRoot(root);

      expect(root.existsSync(), isTrue);
      expect(AppPaths.supportDirSync().path, root.path);

      tmp.deleteSync(recursive: true);
    });

    test('supportDir() отдаёт тот же каталог, что и синхронный геттер',
        () async {
      final tmp = Directory.systemTemp.createTempSync('sg_paths_');
      AppPaths.overrideRoot(tmp);

      expect((await AppPaths.supportDir()).path, AppPaths.supportDirSync().path);

      tmp.deleteSync(recursive: true);
    });

    test('init() идемпотентна', () async {
      final first = await AppPaths.init();
      final second = await AppPaths.init();
      expect(identical(first, second), isTrue);
    });

    test('на Windows путь считается синхронно и без init()', () {
      // Windows-контракт: путь ФИКСИРОВАН (%APPDATA%\SilentGate), потому что
      // установщик и режим --cleanup обязаны уметь его вычистить. Ломать это
      // нельзя даже ради единообразия с Android.
      if (!Platform.isWindows) return;

      final appData = Platform.environment['APPDATA'];
      final dir = AppPaths.supportDirSync();

      expect(dir.existsSync(), isTrue);
      expect(dir.path, endsWith(AppPaths.dirName));
      if (appData != null && appData.isNotEmpty) {
        expect(dir.path, startsWith(appData));
      }
    });

    test('вне Windows синхронный геттер без init() падает понятной ошибкой', () {
      if (Platform.isWindows) return;
      expect(AppPaths.supportDirSync, throwsA(isA<StateError>()));
    });
  });
}
