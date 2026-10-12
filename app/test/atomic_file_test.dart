import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/data/atomic_file.dart';

/// Атомарная запись защищает от обрезанного файла при внезапной смерти
/// процесса: битый `silentgate_settings.json` = молчаливый сброс настроек
/// в дефолты, битый `subscriptions.json` = потеря всех подписок.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sg_atomic_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File f(String name) => File('${tmp.path}${Platform.pathSeparator}$name');

  group('AtomicFile', () {
    test('создаёт файл и пишет содержимое', () async {
      final file = f('new.json');
      expect(await AtomicFile.writeString(file, '{"a":1}'), isTrue);
      expect(file.readAsStringSync(), '{"a":1}');
    });

    test('перезаписывает существующий файл целиком', () async {
      final file = f('old.json');
      file.writeAsStringSync('{"было":"длинное-длинное содержимое"}');

      expect(await AtomicFile.writeString(file, '{"b":2}'), isTrue);
      expect(file.readAsStringSync(), '{"b":2}');
    });

    test('не оставляет после себя .tmp', () async {
      final file = f('clean.json');
      await AtomicFile.writeString(file, 'x');

      final leftovers =
          tmp.listSync().where((e) => e.path.endsWith('.tmp')).toList();
      expect(leftovers, isEmpty);
    });

    test('неудача записи не бросает исключение и чистит времянку', () async {
      // Каталога не существует — запись обязана вернуть false, а не упасть:
      // сторы исторически глотают ошибки сохранения (потеря настроек не
      // должна ронять туннель).
      final file = File(
          '${tmp.path}${Platform.pathSeparator}нет-каталога${Platform.pathSeparator}f.json');

      expect(await AtomicFile.writeString(file, 'x'), isFalse);
      expect(file.existsSync(), isFalse);
    });

    test('содержимое читается целиком после серии перезаписей', () async {
      final file = f('series.json');
      for (var i = 0; i < 20; i++) {
        expect(await AtomicFile.writeString(file, '{"i":$i}'), isTrue);
      }
      expect(file.readAsStringSync(), '{"i":19}');
    });
      test('⚠️ записи без ожидания: побеждает ПОСЛЕДНИЙ вызов, ни одна не теряется',
        () async {
      // Так пишут результаты пинга: сохранение на каждый сервер без await.
      // Раньше записи делили одну времянку — вторая падала на занятом файле
      // или первая ложилась поверх второй.
      final file = f('burst.json');
      final big = 'x' * 200000;
      final futures = [
        for (var i = 0; i < 30; i++)
          AtomicFile.writeString(file, '{"i":$i,"pad":"$big"}'),
      ];
      final ok = await Future.wait(futures);
      expect(ok, everyElement(isTrue));
      expect(file.readAsStringSync(), startsWith('{"i":29,'));
    });
  });
}
