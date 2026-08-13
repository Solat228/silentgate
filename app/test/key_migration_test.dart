import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/util/key_migration.dart';
import 'package:silentgate/data/results_store.dart';

/// Перенос сохранённого на канонические ключи.
///
/// ⚠️ Это МИГРАЦИЯ ЧУЖИХ ДАННЫХ, и цена ошибки здесь выше обычной: по ключу
/// сервера лежат пин, ручная правка и результат пинга. У владельца на момент
/// правки осиротело 273 результата пинга из 374 — их и должен вернуть этот код.
void main() {
  const uuid = '00000000-0000-0000-0000-000000000000';

  String grpc(String serviceParam, {String remark = 'Москва 1. GRPC'}) =>
      'vless://$uuid@example.com:443?type=grpc&security=reality&encryption=none'
      '&sni=a.example.org&fp=chrome&pbk=KEY&sid=ab&$serviceParam=svc'
      '#${Uri.encodeComponent(remark)}';

  final oldKey = grpc('serviceName');
  final newKey = ShareLinkParser.tryParse(grpc('path'))!.key;

  group('Словарь', () {
    test('запись со старого ключа доезжает на новый', () {
      final out = KeyMigration.remapMap<int>({oldKey: 147});
      expect(out.keys.single, newKey);
      expect(out[newKey], 147);
    });

    test('повторный прогон ничего не меняет', () {
      final once = KeyMigration.remapMap<int>({oldKey: 147});
      final twice = KeyMigration.remapMap<int>(once);
      expect(twice, once, reason: 'миграция зовётся при каждой загрузке');
    });

    test('два написания одного сервера сводятся, побеждает первое', () {
      final out = KeyMigration.remapMap<int>({oldKey: 1, newKey: 2});
      expect(out, hasLength(1));
      expect(out[newKey], 1);
    });

    test('переданный merge решает столкновение сам', () {
      final out = KeyMigration.remapMap<int>({oldKey: 1, newKey: 2},
          merge: (a, b) => a + b);
      expect(out[newKey], 3, reason: 'умолчание «первый» должно быть отменяемым');
    });

    test('неразобранный ключ остаётся как есть — чужое не выбрасываем', () {
      const junk = 'panel://Авто (YouTube)';
      final out = KeyMigration.remapMap<int>({junk: 5});
      expect(out[junk], 5);
    });

    test('пустой словарь возвращается тем же объектом', () {
      final src = <String, int>{};
      expect(identical(KeyMigration.remapMap<int>(src), src), isTrue);
    });
  });

  group('Список пинов', () {
    test('ключ приводится, порядок сохраняется', () {
      final out = KeyMigration.remapList([grpc('serviceName', remark: 'A'), 'x://y']);
      expect(out.first, ShareLinkParser.tryParse(grpc('path', remark: 'A'))!.key);
      expect(out.last, 'x://y');
    });

    test('дубли после сведения убираются, остаётся первое вхождение', () {
      final out = KeyMigration.remapList([oldKey, newKey]);
      expect(out, [newKey]);
    });

    test('повторный прогон ничего не меняет', () {
      final once = KeyMigration.remapList([oldKey, 'x://y']);
      expect(KeyMigration.remapList(once), once);
    });
  });

  group('Смысл миграции', () {
    test('⚠️ БЕЗ неё запись по старому ключу не находится', () {
      // Прямое доказательство, что тесты выше не «зелёные всегда»: так вело
      // себя хранилище до 1.4.2 — сервер тот же, ключ другой, данных нет.
      final stored = {oldKey: 147};
      expect(stored[newKey], isNull);
      expect(KeyMigration.remapMap<int>(stored)[newKey], 147);
    });
  });

  group('Результаты пинга: при сведении побеждает СВЕЖЕЕ', () {
    Map<String, dynamic> res(int ms, String at) =>
        {'outcome': 'ok', 'latencyMs': ms, 'measuredAt': at};

    test('⚠️ старая запись лежит в файле ПЕРВОЙ и по умолчанию побеждала', () {
      // Порядок в файле именно такой: прочитанное с прошлого запуска попадает в
      // словарь раньше всего, свежие замеры дописываются в конец. Умолчание
      // «побеждает первый» показывало бы позапрошлую цифру при живом свежем
      // замере рядом — комментарий обещал обратное, и это была неправда.
      final stored = {
        oldKey: res(900, '2025-01-01T00:00:00.000Z'),
        newKey: res(12, '2026-08-12T00:00:00.000Z'),
      };
      expect(KeyMigration.remapMap<dynamic>(stored)[newKey]['latencyMs'], 900,
          reason: 'таково умолчание — его и отменяет ResultsStore');
      expect(ResultsStore.migrate(stored)[newKey]['latencyMs'], 12);
    });

    test('свежее не перебивается старым, даже если пришло раньше', () {
      final out = ResultsStore.migrate({
        newKey: res(12, '2026-08-12T00:00:00.000Z'),
        oldKey: res(900, '2025-01-01T00:00:00.000Z'),
      });
      expect(out[newKey]['latencyMs'], 12);
    });

    test('без дат остаётся существующая запись — гадать не о чем', () {
      final out = ResultsStore.migrate({
        oldKey: {'latencyMs': 900},
        newKey: {'latencyMs': 12},
      });
      expect(out[newKey]['latencyMs'], 900);
    });

    test('запись с датой сильнее записи без даты', () {
      final out = ResultsStore.migrate({
        oldKey: {'latencyMs': 900},
        newKey: res(12, '2026-08-12T00:00:00.000Z'),
      });
      expect(out[newKey]['latencyMs'], 12);
    });
  });

  group('Шестое хранилище: порты выходов', () {
    test('⚠️ ключ «сервера с отдельным портом» тоже мигрирует', () {
      // Канонизацию 1.4.2 провели по пяти хранилищам, а это — шестое, и его
      // чуть не забыли. Без миграции у того, кто настроил порты выходов,
      // галочки показались бы снятыми, `GET /v1/exits` не отдал бы ни одного
      // сервера, а скрипты получили бы отказ соединения — МОЛЧА, без ошибки и
      // без строки в журнале. Руками это не чинится: чекбокс сравнивает с
      // ключом живого сервера, и мёртвую запись из файла не убрать.
      final s = AppSettings.fromJson({'apiExitServerKeys': [oldKey]});
      expect(s.apiExitServerKeys, [newKey]);
    });

    test('уже канонический ключ не меняется', () {
      final s = AppSettings.fromJson({'apiExitServerKeys': [newKey]});
      expect(s.apiExitServerKeys, [newKey]);
    });

    test('чужую строку не выбрасываем', () {
      final s = AppSettings.fromJson({'apiExitServerKeys': ['panel://Авто']});
      expect(s.apiExitServerKeys, ['panel://Авто']);
    });
  });
}
