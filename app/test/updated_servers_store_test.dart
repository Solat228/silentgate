import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/data/updated_servers_store.dart';

/// Хранилище значка «сервер обновился» — переживает перезапуск приложения,
/// как и пины (см. `pinned_store_test.dart`), но полностью перезаписывается
/// на каждое обновление подписки: метка держит только «что изменилось В
/// ПОСЛЕДНЕМ обновлении», а не историю.
void main() {
  late Directory tmp;
  late UpdatedServersStore store;

  setUp(() {
    // Боевой каталог данных тесты не трогают никогда.
    tmp = Directory.systemTemp.createTempSync('sg_updated_servers_');
    AppPaths.overrideRoot(tmp);
    store = UpdatedServersStore();
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('пустое хранилище — пустая карта', () async {
    expect(await store.load(), isEmpty);
  });

  test('round-trip: ключ и поля переживают запись/чтение', () async {
    await store.save({
      'vless://a': ['address', 'shortId'],
      'vless://b': [], // поля совпали, разошлась только запись ссылки
    });

    final loaded = await store.load();
    expect(loaded['vless://a'], ['address', 'shortId']);
    expect(loaded['vless://b'], isEmpty);
  });

  test('save целиком заменяет прежнее содержимое — истории не остаётся',
      () async {
    await store.save({
      'vless://a': ['address']
    });
    await store.save({
      'vless://b': ['sni']
    });

    final loaded = await store.load();
    expect(loaded.containsKey('vless://a'), isFalse,
        reason: 'старая пометка обязана исчезнуть на следующем обновлении');
    expect(loaded['vless://b'], ['sni']);
  });

  test('битый файл на диске не роняет чтение', () async {
    final dir = await AppPaths.supportDir();
    final f = File('${dir.path}${Platform.pathSeparator}updated_servers.json');
    f.writeAsStringSync('{ не json');
    expect(await store.load(), isEmpty);
  });

  test('элемент неверного вида молча пропускается, остальные — нет', () async {
    final dir = await AppPaths.supportDir();
    final f = File('${dir.path}${Platform.pathSeparator}updated_servers.json');
    f.writeAsStringSync(jsonEncode({
      'vless://good': ['address'],
      'vless://bad': 'не список',
    }));

    final loaded = await store.load();
    expect(loaded['vless://good'], ['address']);
    expect(loaded.containsKey('vless://bad'), isFalse);
  });
}
