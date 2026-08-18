import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/platform/app_paths.dart';

/// УДАЛЕНИЕ ОДНОЙ ПОДПИСКИ НЕ ТРОГАЕТ ЗАКРЕПЛЁННЫЕ СЕРВЕРЫ ДРУГИХ.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 18.08.2026: «при удалении чужой подписки всё равно
/// предлагает удалить закреплённые серверы, которые принадлежат ДРУГОЙ
/// подписке».
///
/// Так и было: по галочке вызывался `_pinned.clear()` — то есть удаление ОДНОЙ
/// подписки сносило закрепления ВСЕХ остальных. Пользователь соглашался убрать
/// «закреплённые серверы этой подписки», а терял чужие, ничем не связанные с
/// удаляемой.
///
/// Пины здесь ОБЩИЕ по построению: они переживают переключение подписки, и в
/// одном списке лежат серверы из разных подписок — ради этого и заведён значок
/// «чужая подписка» (`AppState.foreignSubscriptionOf`). Значит и чистка обязана
/// быть адресной.
///
/// ⚠️ Тест работает с чистой логикой принадлежности, без поднятия `AppState`:
/// поднимать его здесь значит тянуть обновление подписки по сети и таймеры, а
/// проверяемое правило от них не зависит.
void main() {
  late Directory tmp;

  setUp(() {
    // Боевой каталог данных тесты не трогают никогда.
    tmp = Directory.systemTemp.createTempSync('sg_delpins_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const linkA = 'vless://11111111-1111-1111-1111-111111111111@a.example:443'
      '?type=tcp&security=none#A';
  const linkB = 'vless://22222222-2222-2222-2222-222222222222@b.example:443'
      '?type=tcp&security=none#B';
  const linkShared = 'vless://33333333-3333-3333-3333-333333333333@c.example:443'
      '?type=tcp&security=none#C';

  SubscriptionProfile profile(String id, List<String> links) =>
      SubscriptionProfile(
        id: id,
        url: 'https://example.invalid/$id',
        serverLinks: links,
      );

  /// Та же арифметика, что в `AppState.deleteSubscription`: ссылки удаляемой
  /// подписки минус всё, что осталось у других.
  Set<String> orphaned(
      SubscriptionProfile removed, List<SubscriptionProfile> rest) {
    final links = {...removed.serverLinks};
    for (final p in rest) {
      links.removeAll(p.serverLinks);
    }
    return links;
  }

  group('Что осиротело при удалении', () {
    test('⚠️ ГЛАВНОЕ: серверы другой подписки не осиротели', () {
      final a = profile('a', [linkA]);
      final b = profile('b', [linkB]);
      final gone = orphaned(a, [b]);

      expect(gone, {linkA});
      expect(gone, isNot(contains(linkB)),
          reason: 'ЗДЕСЬ БЫЛА ПОТЕРЯ: `_pinned.clear()` сносил закрепления '
              'ВСЕХ подписок, хотя удаляли одну');
    });

    test('⚠️ сервер, лежащий в ДВУХ подписках, остаётся закреплённым', () {
      // Он не осиротел: вторая подписка его по-прежнему содержит. Тот же
      // принцип, по которому такой сервер считается «своим» в индексе
      // владельцев, а не помечается чужим значком.
      final a = profile('a', [linkA, linkShared]);
      final b = profile('b', [linkShared]);
      final gone = orphaned(a, [b]);

      expect(gone, {linkA});
      expect(gone, isNot(contains(linkShared)),
          reason: 'снимать закрепление не за что — сервер никуда не делся');
    });

    test('последняя подписка: осиротело всё её содержимое', () {
      final a = profile('a', [linkA, linkShared]);
      expect(orphaned(a, const []), {linkA, linkShared});
    });

    test('⚠️ у последней подписки чистка ПОЛНАЯ, и это не противоречие', () {
      // Жалоба владельца была про МУЛЬТИподписку: удаление одной уносило
      // закреплённые серверы других. Когда других не осталось, уносить не у
      // кого — и галочка значит ровно то, что на ней написано: список пустеет
      // целиком, вместе с правками и конфигами панели. Иначе человек соглашается
      // очистить список, а тот остаётся непустым и необъяснимым.
      //
      // Асимметрию стережём здесь, чтобы её не «выправили» под общий вид: у
      // двух веток разный смысл, а не разное качество кода.
      final src = File('lib/state/app_state.dart').readAsStringSync();
      // ⚠️ Ищем ВНУТРИ метода, а не по всему файлу: `indexOf` от начала файла
      // находил маркер в другом методе, и срез охватывал не то. Поймано первым
      // же прогоном — ровно та ошибка, из-за которой тест мог бы «проверять»
      // чужой код и оставаться зелёным.
      final mStart = src.indexOf('Future<void> deleteSubscription');
      final mEnd = src.indexOf('Future<void> _dropPinnedFor', mStart);
      expect(mStart, greaterThan(0));
      expect(mEnd, greaterThan(mStart));
      // ⚠️ КОММЕНТАРИИ ВЫРЕЗАЕМ. Объяснение дефекта рядом с правкой цитирует
      // старый вызов дословно — и текстовый тест ловил ЕГО, а не код. Проверять
      // надо то, что исполняется; иначе честный комментарий про «здесь было
      // так» роняет страж, и его правят удалением объяснения.
      final method = src
          .substring(mStart, mEnd)
          .split(String.fromCharCode(10))
          .map((l) {
            final i = l.indexOf('//');
            return i >= 0 ? l.substring(0, i) : l;
          })
          .join(String.fromCharCode(10));

      final split = method.indexOf('_subscriptionUrl = null;');
      expect(split, greaterThan(0), reason: 'разметка метода изменилась');
      final withOthers = method.substring(0, split);
      final lastOne = method.substring(split);

      expect(lastOne, contains('_pinned.clear()'),
          reason: 'ветка последней подписки обязана чистить полностью');
      expect(withOthers, contains('_dropPinnedFor(removedLinks)'),
          reason: 'а ветка «остались другие» — только осиротевшее');
      expect(withOthers, isNot(contains('_pinned.clear()')),
          reason: 'ЗДЕСЬ БЫЛА ПОТЕРЯ ЧУЖИХ ЗАКРЕПЛЁННЫХ СЕРВЕРОВ');
    });

    test('пин, не принадлежащий ни одной подписке, не в списке на снятие', () {
      // Сервер, добавленный руками (импорт ссылки, свой JSON), подписке не
      // принадлежит — удаление подписки его не касается.
      final a = profile('a', [linkA]);
      final gone = orphaned(a, const []);
      expect(gone, isNot(contains(linkB)));
    });

    test('пустая подписка не уносит ничего', () {
      expect(orphaned(profile('a', const []), [profile('b', [linkB])]), isEmpty);
    });
  });
}
