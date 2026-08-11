import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/subscription_info.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/util/reorder.dart';

/// Порядок подписок в меню переключателя.
///
/// ⚠️ ЧТО ИМЕННО ЗДЕСЬ СТЕРЕЖЁТСЯ. Владелец попросил убрать сортировку и
/// расставлять подписки по дате добавления, а порядок разрешить менять руками.
/// Значит порядок — это ДАННЫЕ, и у него два требования: он переживает
/// перезапуск (иначе перетаскивание бессмысленно) и не сбивается при
/// обновлении подписки (иначе список перестраивается сам собой).
void main() {
  SubscriptionProfile p(String url, {DateTime? at}) => SubscriptionProfile(
        id: SubscriptionProfile.idFor(url),
        url: url,
        info: SubscriptionInfo.empty,
        addedAt: at,
      );

  List<String> urls(List<SubscriptionProfile> l) =>
      l.map((e) => e.url).toList();

  group('Перестановка (правила ReorderableListView)', () {
    final items = ['a', 'b', 'c', 'd'];

    test('вниз: индекс приходит ДО изъятия и уменьшается на один', () {
      // Тащим «a» в самый конец. Виджет отдаёт newIndex == 4 (длина списка).
      // Без поправки элемент встал бы предпоследним — ровно та жалоба,
      // из-за которой поправка вообще существует.
      expect(reordered(items, 0, 4), ['b', 'c', 'd', 'a']);
    });

    test('вниз на одну позицию', () {
      expect(reordered(items, 0, 2), ['b', 'a', 'c', 'd']);
    });

    test('вверх: поправка НЕ применяется', () {
      expect(reordered(items, 3, 0), ['d', 'a', 'b', 'c']);
    });

    test('на своё же место — список не меняется', () {
      expect(reordered(items, 1, 1), items);
      expect(reordered(items, 1, 2), items);
    });

    test('исходный список не мутируется', () {
      final src = ['a', 'b', 'c'];
      reordered(src, 0, 3);
      expect(src, ['a', 'b', 'c']);
    });

    test('индекс за пределами списка не роняет', () {
      expect(reordered(items, 9, 0), items);
      expect(reordered(items, -1, 0), items);
      expect(reordered(items, 0, 99), ['b', 'c', 'd', 'a']);
    });

    test('список из одного элемента', () {
      expect(reordered(['a'], 0, 1), ['a']);
    });

    test('пустой список', () {
      expect(reordered(<String>[], 0, 0), <String>[]);
    });
  });

  group('Дата добавления переживает диск', () {
    test('записывается и читается обратно', () {
      final at = DateTime.utc(2026, 8, 11, 2, 9, 8);
      final back = SubscriptionProfile.fromJson(p('https://x/y', at: at).toJson());
      expect(back.addedAt, at);
    });

    test('старый файл без поля читается без даты, а не падает', () {
      final back = SubscriptionProfile.fromJson({
        'id': 'sub_1',
        'url': 'https://x/y',
        'servers': <String>[],
      });
      expect(back.addedAt, isNull);
      expect(back.url, 'https://x/y');
    });

    test('copyWith сохраняет дату', () {
      final at = DateTime.utc(2026, 1, 1);
      expect(p('https://x/y', at: at).copyWith(url: 'https://z').addedAt, at);
    });
  });

  group('Порядок — это данные, а не сортировка', () {
    test('переставленный порядок сохраняется как есть', () {
      // Имена нарочно НЕ по алфавиту и число серверов не по возрастанию:
      // любая сортировка выдала бы себя, изменив этот список.
      final list = [p('https://a'), p('https://b'), p('https://c')];
      final moved = reordered(list, 2, 0);
      expect(urls(moved), ['https://c', 'https://a', 'https://b']);
      // Круг через диск — порядок обязан остаться тем же.
      final onDisk = moved.map((e) => e.toJson()).toList();
      final loaded = onDisk.map(SubscriptionProfile.fromJson).toList();
      expect(urls(loaded), ['https://c', 'https://a', 'https://b']);
    });
  });
}
