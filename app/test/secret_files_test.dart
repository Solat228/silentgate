import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/secret_files.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/data/settings_storage.dart';
import 'package:silentgate/data/subscriptions_store.dart';

/// Секреты на диске шифруются DPAPI (Windows, не портативная копия) —
/// решение владельца 25.09.2026.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sg_secret_files_');
    // ⚠️ Без подмены корня тест полез бы в боевой %APPDATA% владельца.
    AppPaths.overrideRoot(tmp);
    await AppLog.resetFileForTest();
  });

  tearDown(() async {
    SecretFiles.debugEnabled = null;
    await AppLog.resetFileForTest();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File inRoot(String name) =>
      File('${tmp.path}${Platform.pathSeparator}$name');

  // Ссылка в тестах — с TEST-NET адресом и выдуманным UUID.
  const secretUrl = 'https://panel.example/sub/very-secret-token-42';
  const secretLink =
      'vless://0badc0de-1111-2222-3333-444455556666@203.0.113.7:443?type=tcp';

  test('под тестами по умолчанию выключено, портативный флаг сброшен', () {
    expect(SecretFiles.enabled, isFalse);
    expect(AppPaths.isPortable, isFalse);
  });

  test('выключено — пишется открытый текст, читается как есть', () {
    SecretFiles.debugEnabled = false;
    expect(SecretFiles.encode('{"a":1}'), '{"a":1}');
    expect(SecretFiles.decode('{"a":1}'), '{"a":1}');
  });

  group('DPAPI (только Windows)', () {
    final skip = Platform.isWindows ? false : 'DPAPI есть только на Windows';

    test('блок туда и обратно', () {
      final data = Uint8List.fromList(utf8.encode('привет, $secretLink'));
      final blob = SecretFiles.protect(data);
      expect(blob, isNot(equals(data)));
      expect(SecretFiles.unprotect(blob), data);
    }, skip: skip);

    test('пустые данные тоже шифруются', () {
      final blob = SecretFiles.protect(Uint8List(0));
      expect(SecretFiles.unprotect(blob), isEmpty);
    }, skip: skip);

    test('зашифрованный текст: метка, ни следа секрета', () {
      SecretFiles.debugEnabled = true;
      final plain = jsonEncode({'url': secretUrl, 'servers': [secretLink]});
      final stored = SecretFiles.encode(plain);
      expect(stored, startsWith(SecretFiles.magic));
      expect(stored, isNot(contains('very-secret-token')));
      expect(stored, isNot(contains('0badc0de')));
      expect(SecretFiles.decode(stored), plain);
    }, skip: skip);

    test('открытый текст прошлой версии читается — это и есть миграция', () {
      SecretFiles.debugEnabled = true;
      expect(SecretFiles.decode('{"x":true}'), '{"x":true}');
    }, skip: skip);

    test('испорченный блок — FormatException, а не мусор', () {
      SecretFiles.debugEnabled = true;
      final stored = SecretFiles.encode('{"x":1}');
      final body = base64.decode(stored.substring(SecretFiles.magic.length));
      body[body.length ~/ 2] ^= 0xFF;
      expect(() => SecretFiles.decode('${SecretFiles.magic}${base64.encode(body)}'),
          throwsFormatException);
      expect(() => SecretFiles.decode('${SecretFiles.magic}!!!'),
          throwsFormatException);
    }, skip: skip);

    test('⚠️ нерасшифрованный файл остаётся копией и не перезаписывается',
        () async {
      SecretFiles.debugEnabled = true;
      final f = inRoot('subscriptions.json');
      f.writeAsStringSync('${SecretFiles.magic}AAAA');
      await expectLater(SecretFiles.read(f), throwsA(isA<SecretDecodeException>()));
      final keep = File('${f.path}.undecryptable');
      expect(keep.readAsStringSync(), '${SecretFiles.magic}AAAA');
      // Вторая неудача копию не трогает.
      f.writeAsStringSync('${SecretFiles.magic}BBBB');
      await expectLater(SecretFiles.read(f), throwsA(isA<SecretDecodeException>()));
      expect(keep.readAsStringSync(), '${SecretFiles.magic}AAAA');
    }, skip: skip);

    test('настройки: токен API на диске не виден, загрузка возвращает его',
        () async {
      SecretFiles.debugEnabled = true;
      const token = 'tok-ABCDEFGHIJKLMNOP';
      await SettingsStorage().save(const AppSettings(apiToken: token));
      final raw = inRoot('silentgate_settings.json').readAsStringSync();
      expect(raw, startsWith(SecretFiles.magic));
      expect(raw, isNot(contains(token)));
      expect((await SettingsStorage().load()).apiToken, token);
    }, skip: skip);

    test('подписки: старый открытый файл читается и при записи шифруется',
        () async {
      SecretFiles.debugEnabled = true;
      final f = inRoot('subscriptions.json');
      f.writeAsStringSync(jsonEncode({
        'activeId': 'a',
        'items': [
          {'id': 'a', 'url': secretUrl, 'servers': [secretLink]},
        ],
      }));
      final store = SubscriptionsStore();
      final snap = await store.load();
      expect(snap.items.single.url, secretUrl);
      expect(await store.save(snap), isTrue);
      final raw = f.readAsStringSync();
      expect(raw, startsWith(SecretFiles.magic));
      expect(raw, isNot(contains('very-secret-token')));
      expect((await SubscriptionsStore().load()).items.single.url, secretUrl);
    }, skip: skip);

    test('⚠️ нерасшифрованные подписки не затираются пустым списком',
        () async {
      SecretFiles.debugEnabled = true;
      final f = inRoot('subscriptions.json');
      f.writeAsStringSync('${SecretFiles.magic}AAAA');
      final store = SubscriptionsStore();
      final snap = await store.load();
      expect(snap.isReadable, isFalse);
      expect(File('${f.path}.undecryptable').existsSync(), isTrue);
    }, skip: skip);
  });

  test('все хранилища с секретами читают и пишут через SecretFiles', () {
    const stores = [
      'app_storage',
      'panel_outbounds_store',
      'pinned_store',
      'results_store',
      'server_overrides_store',
      'settings_storage',
      'subscriptions_store',
      'updated_servers_store',
    ];
    for (final name in stores) {
      final src = File('lib/data/$name.dart').readAsStringSync();
      expect(src, contains('SecretFiles.read('), reason: name);
      expect(src, contains('SecretFiles.write('), reason: name);
      expect(src, isNot(contains('AtomicFile.writeString(')), reason: name);
      expect(RegExp(r'await \w+\.readAsString\(\)').hasMatch(src), isFalse,
          reason: '$name читает файл мимо расшифровки');
    }
  });

  test('портативная копия не шифрует', () {
    final src = File('lib/core/platform/secret_files.dart').readAsStringSync();
    expect(src, contains('!AppPaths.isPortable'));
    final paths = File('lib/core/platform/app_paths.dart').readAsStringSync();
    expect(paths, contains('_portableRoot = portable != null;'));
  });
}
