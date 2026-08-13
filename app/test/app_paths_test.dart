import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';

/// `AppPaths` — единственная точка платформозависимости всего дискового слоя
/// (восемь сторов, логи, кэши, отчёты поддержки). Ошибка здесь тихо уводит
/// данные пользователя в другую папку, поэтому поведение закреплено тестом.
void main() {
  tearDown(() {
    AppPaths.resetForTests();
    AppPaths.productionRootAllowedInTests = false;
  });

  group('⚠️ Предохранитель: боевой каталог под тестами', () {
    // Ради чего он стоит: 14.08.2026 тест поднял настоящий AppState, а импорт
    // подписки уходит в unawaited — тест успел закончиться и сбросить подмену
    // раньше, чем цепочка досчитала. Дальше она резолвила путь заново, получала
    // %APPDATA%\SilentGate и переписала боевой subscriptions.json: 37 КБ с
    // четырьмя реальными подписками стали 501 байтом с выдуманной. Уцелело
    // только потому, что клиент был запущен и переписал файл из памяти.
    test('без overrideRoot синхронный геттер отказывается работать', () {
      expect(AppPaths.supportDirSync, throwsA(isA<StateError>()));
    });

    test('без overrideRoot init() тоже отказывается', () {
      expect(AppPaths.init, throwsA(isA<StateError>()));
    });

    test('в отказе назван и виновник, и лечение', () {
      try {
        AppPaths.supportDirSync();
        fail('предохранитель не сработал');
      } on StateError catch (e) {
        expect(e.message, contains('overrideRoot'),
            reason: 'тест обязан узнать, ЧТО делать, а не только что упало');
        expect(e.message, contains('subscriptions.json'),
            reason: 'цена ошибки должна стоять рядом с самой ошибкой');
      }
    });

    test('overrideRoot снимает отказ', () {
      final tmp = Directory.systemTemp.createTempSync('sg_paths_');
      AppPaths.overrideRoot(tmp);
      expect(AppPaths.supportDirSync().path, tmp.path);
      tmp.deleteSync(recursive: true);
    });
  });

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
      // Проверяем вычисление БОЕВОГО пути — единственный случай, где снимать
      // предохранитель законно: иначе проверять было бы нечего.
      AppPaths.productionRootAllowedInTests = true;
      final first = await AppPaths.init();
      final second = await AppPaths.init();
      expect(identical(first, second), isTrue);
    });

    test('на Windows путь считается синхронно и без init()', () {
      AppPaths.productionRootAllowedInTests = true;
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
