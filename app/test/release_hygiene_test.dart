import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Гигиена релиза: что НЕ должно доехать до пользователя.
///
/// ⚠️ ЗАЧЕМ ЭТО ОТДЕЛЬНЫМ ТЕСТОМ. Требование владельца — «в финальной версии
/// приложения юнит-тестов быть не должно, только в тестовой разработке». Во
/// Flutter это и так правда: папка `test/` не участвует ни в сборке exe, ни в
/// APK. Но «и так правда» перестаёт быть правдой молча — достаточно одному
/// файлу из `test/` переехать в `lib/`, попасть в `pubspec.yaml` как ассет или
/// утянуть за собой `flutter_test` в зависимости приложения. Тест ловит именно
/// это: не сам факт сборки, а способы его испортить.
void main() {
  final appDir = Directory.current; // app/
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('Тесты и диагностика не едут в релиз', () {
    test('в lib/ нет файлов с тестами', () {
      // Тест внутри lib/ уехал бы в сборку вместе с приложением — и утянул бы
      // за собой flutter_test, которого в релизе быть не должно.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('package:flutter_test') ||
            src.contains('package:test/test.dart')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'эти файлы попадут в релизную сборку: $offenders');
    });

    test('flutter_test только в dev_dependencies', () {
      // Если он окажется в основных зависимостях, тестовый фреймворк уедет
      // в приложение целиком.
      final devIdx = pubspec.indexOf('dev_dependencies:');
      final testIdx = pubspec.indexOf('flutter_test:');
      expect(testIdx, greaterThanOrEqualTo(0));
      expect(devIdx, greaterThanOrEqualTo(0));
      expect(testIdx, greaterThan(devIdx),
          reason: 'flutter_test обязан быть в dev_dependencies, иначе он '
              'станет частью приложения');
    });

    test('папка test/ не объявлена ассетом', () {
      // Ассеты копируются в сборку как есть — так тесты попали бы в APK
      // отдельными файлами, даже не будучи скомпилированными.
      for (final line in pubspec.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('-')) continue;
        expect(t.contains('test/'), isFalse,
            reason: 'строка ассетов тянет тесты в сборку: $t');
      }
    });

    test('каждый файл в test/ — настоящий тест, а не забытый черновик', () {
      // ⚠️ За агентами в этом проекте уже оставался мусор вида
      // `tmp_race_probe_test.dart`. Такой файл не ломает сборку, но живёт
      // в дереве и создаёт ложное ощущение покрытия.
      final stray = <String>[];
      for (final f in Directory('test').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        if (name.startsWith('tmp_')) {
          stray.add(name);
          continue;
        }
        if (!name.endsWith('_test.dart')) continue;
        final src = f.readAsStringSync();
        if (!src.contains('void main(')) stray.add(name);
      }
      expect(stray, isEmpty, reason: 'временные или пустые файлы: $stray');
    });

    test('диагностические тесты не идут в обычном прогоне', () {
      // Тесты с тегом `diag` ходят в сеть и требуют изолированного APPDATA:
      // в обычном прогоне они обязаны скипаться, иначе набор станет цветным
      // и его перестанут запускать.
      final cfg = File('dart_test.yaml');
      expect(cfg.existsSync(), isTrue,
          reason: 'без него diag-тесты пойдут в общий прогон');
      expect(cfg.readAsStringSync(), contains('diag'));
    });

    test('в app/ нет незакоммиченных временных каталогов сборки в pubspec', () {
      // Дешёвая страховка от «положил папку с отладкой в ассеты и забыл».
      expect(appDir.existsSync(), isTrue);
      for (final bad in ['scratchpad', 'debug/', 'tmp/']) {
        expect(pubspec.contains('- $bad'), isFalse,
            reason: '«$bad» объявлен ассетом и уедет в сборку');
      }
    });
  });
}
