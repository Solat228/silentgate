import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/data/pinned_store.dart';

/// ФОРМАТ pinned_servers.json РАСШИРЕН ИСТОЧНИКОМ ПОДПИСКИ.
///
/// Причина — значок «чужая подписка» у закреплённого сервера гас, если та же
/// ссылка находилась и в активной подписке: происхождение нигде не хранилось
/// и вычислялось заново по текущему состоянию подписок. Файл теперь хранит
/// пары (ссылка, id подписки-источника), а старый формат (голый список строк)
/// обязан читаться без миграции файла и без потери закреплений.
void main() {
  late Directory tmp;
  late PinnedStore store;

  setUp(() {
    // Боевой каталог данных тесты не трогают никогда.
    tmp = Directory.systemTemp.createTempSync('sg_pinned_');
    AppPaths.overrideRoot(tmp);
    store = PinnedStore();
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> pinnedFile() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}pinned_servers.json');
  }

  // ⚠️ Ссылки уже в КАНОНИЧЕСКОМ виде (с `encryption=none`): `PinnedStore.load`
  // прогоняет их через `ShareLinkParser.canonicalKey`, и без этого поля тест
  // сравнивал бы записанное с пересобранным, а не проверял бы формат хранения.
  const linkA = 'vless://11111111-1111-1111-1111-111111111111@a.example:443'
      '?type=tcp&security=none&encryption=none#A';
  const linkB = 'vless://22222222-2222-2222-2222-222222222222@b.example:443'
      '?type=tcp&security=none&encryption=none#B';

  test('пустое хранилище — пустой список', () async {
    expect(await store.load(), isEmpty);
  });

  test('round-trip нового формата: ссылка и источник переживают запись/чтение',
      () async {
    await store.save(const [
      PinnedEntry(linkA, sourceSubscriptionId: 'sub-rush'),
      PinnedEntry(linkB, sourceSubscriptionId: ''),
    ]);

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded[0].link, linkA);
    expect(loaded[0].sourceSubscriptionId, 'sub-rush');
    expect(loaded[1].link, linkB);
    expect(loaded[1].sourceSubscriptionId, '');
  });

  test('СТАРЫЙ формат (список строк) — источник пуст, закрепления не теряются',
      () async {
    final f = await pinnedFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode([linkA, linkB]));

    final loaded = await store.load();
    expect(loaded.map((e) => e.link), [linkA, linkB]);
    expect(loaded.every((e) => e.sourceSubscriptionId.isEmpty), isTrue,
        reason: 'у старого формата источника не было и взяться ему неоткуда');
  });

  test('битый JSON целиком — не роняет, отдаёт пустой список', () async {
    final f = await pinnedFile();
    await f.parent.create(recursive: true);
    await f.writeAsString('{ не json вовсе');

    expect(await store.load(), isEmpty);
  });

  test('один битый элемент внутри списка не топит остальные записи', () async {
    final f = await pinnedFile();
    await f.parent.create(recursive: true);
    // Второй элемент — не строка и не объект с `link`: должен быть пропущен,
    // а не обрушить чтение всего файла.
    await f.writeAsString(jsonEncode([
      {'link': linkA, 'sub': 'sub-rush'},
      {'no_link_field': true},
      42,
      linkB, // смешанный файл: старая запись рядом с новыми — тоже не теряется
    ]));

    final loaded = await store.load();
    expect(loaded.map((e) => e.link), [linkA, linkB]);
    expect(loaded.firstWhere((e) => e.link == linkA).sourceSubscriptionId,
        'sub-rush');
    expect(
        loaded.firstWhere((e) => e.link == linkB).sourceSubscriptionId, '');
  });
}
