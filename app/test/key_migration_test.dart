import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/util/key_migration.dart';

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
}
