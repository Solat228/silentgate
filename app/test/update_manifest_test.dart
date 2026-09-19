import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/update/update_manifest.dart';

/// МАНИФЕСТ РЕЛИЗА: РАЗБОР И ПРИЧИНЫ ОТКАЗА.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Подпись доказывает только, что манифест написал
/// владелец ключа. Она НЕ доказывает, что это манифест ТОГО релиза, который
/// приложение собралось ставить: старый, честно подписанный манифест
/// 1.14.0, подсунутый вместо 1.14.1, — это откат с валидной подписью.
/// Поэтому после подписи проверяется версия, канал и ТОЧНОЕ имя актива, и
/// каждая проверка называет причину — интерфейс и журнал обязаны сказать,
/// почему обновление не встало, а не «ошибка».
void main() {
  const sha = 'a3f1c2d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
  const exe = 'SilentGateSetup-1.14.1.exe';

  String manifestJson({
    Object? version = '1.14.1',
    Object? channel = 'stable',
    Object? assets = const [
      {'name': exe, 'size': 34567890, 'sha256': sha},
      {
        'name': 'SilentGate-1.14.1-arm64-v8a.apk',
        'size': 76000000,
        'sha256': sha,
      },
    ],
  }) =>
      jsonEncode({'version': version, 'channel': channel, 'assets': assets});

  group('UpdateManifest.parse', () {
    test('разбирает версию, канал и активы', () {
      final m = UpdateManifest.parse(manifestJson());
      expect(m, isNotNull);
      expect(m!.version, '1.14.1');
      expect(m.channel, 'stable');
      expect(m.assets, hasLength(2));
      expect(m.assets.first.name, exe);
      expect(m.assets.first.size, 34567890);
      expect(m.assets.first.sha256, sha);
    });

    test('sha256 приводится к нижнему регистру — сравнивать будем с Sha256.ofFile',
        () {
      final m = UpdateManifest.parse(manifestJson(assets: [
        {'name': exe, 'size': 1, 'sha256': sha.toUpperCase()},
      ]));
      expect(m!.assets.single.sha256, sha);
    });

    test('мусор → null, не исключение', () {
      for (final junk in [
        '',
        '   ',
        'not json',
        '[]',
        '42',
        '"string"',
        'null',
        '{}',
        '{"version":"1.14.1"}',
        '{"version":"1.14.1","channel":"stable"}',
        '{"version":1.14,"channel":"stable","assets":[]}',
        '{"version":"1.14.1","channel":42,"assets":[]}',
        '{"version":"1.14.1","channel":"stable","assets":{}}',
        '{"version":"1.14.1","channel":"stable","assets":[1]}',
        '{"version":"1.14.1","channel":"stable","assets":[{"name":"a"}]}',
        '{"version":"1.14.1","channel":"stable","assets":[{"name":"a","size":"1","sha256":"$sha"}]}',
        '{"version":"1.14.1","channel":"stable","assets":[{"name":"a","size":1.5,"sha256":"$sha"}]}',
        '{"version":"1.14.1","channel":"stable","assets":[{"name":"a","size":1,"sha256":7}]}',
        '{"version":"1.14.1","channel":"stable","assets":[{"name":7,"size":1,"sha256":"$sha"}]}',
        '{"version":"1.14.1","channel":"stable","assets":[{"name":"","size":1,"sha256":"$sha"}]}',
        '{"version":"","channel":"stable","assets":[]}',
        '\u{1F600}{',
      ]) {
        expect(() => UpdateManifest.parse(junk), returnsNormally, reason: junk);
        expect(UpdateManifest.parse(junk), isNull, reason: junk);
      }
    });

    test('неизвестный канал → null', () {
      // Каналов два, и оба проверяются явно. Третий — либо опечатка в
      // выпуске, либо чужой файл; и там, и там доверять нечему.
      expect(UpdateManifest.parse(manifestJson(channel: 'nightly')), isNull);
      expect(UpdateManifest.parse(manifestJson(channel: 'Stable')), isNull);
    });

    test('пустой список активов допустим для разбора', () {
      expect(UpdateManifest.parse(manifestJson(assets: [])), isNotNull);
    });
  });

  group('UpdateManifest.assetNamed', () {
    final m = UpdateManifest.parse(manifestJson(assets: [
      {'name': exe, 'size': 1, 'sha256': sha},
      {'name': '$exe.bak', 'size': 2, 'sha256': sha},
    ]))!;

    test('только ТОЧНОЕ совпадение, не contains/startsWith', () {
      expect(m.assetNamed(exe)?.size, 1);
      expect(m.assetNamed('$exe.bak')?.size, 2);
      expect(m.assetNamed('SilentGateSetup-1.14.1'), isNull);
      expect(m.assetNamed('SilentGateSetup-1.14.1.ex'), isNull);
      expect(m.assetNamed('silentgatesetup-1.14.1.exe'), isNull);
      expect(m.assetNamed(' $exe'), isNull);
      expect(m.assetNamed(''), isNull);
    });
  });

  group('UpdateManifest.toJson', () {
    test('каноничная сериализация: parse(toJson) даёт то же самое', () {
      final m = UpdateManifest.parse(manifestJson())!;
      final again = UpdateManifest.parse(m.toJson())!;
      expect(again.toJson(), m.toJson());
      expect(again.version, m.version);
      expect(again.channel, m.channel);
      expect(again.assets.map((a) => a.name), m.assets.map((a) => a.name));
    });

    test('порядок ключей и активов фиксирован, пробелов нет', () {
      const m = UpdateManifest(version: '1.14.1', channel: 'beta', assets: [
        UpdateAsset(name: 'b', size: 2, sha256: sha),
        UpdateAsset(name: 'a', size: 1, sha256: sha),
      ]);
      expect(
        m.toJson(),
        '{"version":"1.14.1","channel":"beta","assets":['
        '{"name":"b","size":2,"sha256":"$sha"},'
        '{"name":"a","size":1,"sha256":"$sha"}]}',
      );
    });
  });

  group('validateManifest', () {
    UpdateManifest m({
      String version = '1.14.1',
      String channel = 'stable',
      int size = 100,
      String hash = sha,
      String name = exe,
    }) =>
        UpdateManifest(version: version, channel: channel, assets: [
          UpdateAsset(name: name, size: size, sha256: hash),
        ]);

    test('всё сходится → null', () {
      expect(
        validateManifest(m(),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        isNull,
      );
    });

    test('версия сравнивается строкой после снятия ведущего v', () {
      expect(
        validateManifest(m(version: 'v1.14.1'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        isNull,
      );
      expect(
        validateManifest(m(),
            expectedVersion: 'v1.14.1', assetName: exe, betaAllowed: false),
        isNull,
      );
    });

    test('версия ≠ → versionMismatch (replay старого манифеста = откат)', () {
      expect(
        validateManifest(m(version: '1.14.0'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.versionMismatch,
      );
      // Бета — полная строка тега, суффикс обязан совпасть.
      expect(
        validateManifest(m(version: '1.14.1'),
            expectedVersion: '1.14.1-beta.1', assetName: exe, betaAllowed: true),
        ManifestRejection.versionMismatch,
      );
      // «1.14.10» ≠ «1.14.1» — сравнение строкой, не префиксом.
      expect(
        validateManifest(m(version: '1.14.10'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.versionMismatch,
      );
    });

    test('канал beta без разрешения → channelMismatch', () {
      expect(
        validateManifest(m(channel: 'beta'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.channelMismatch,
      );
      expect(
        validateManifest(m(channel: 'beta'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: true),
        isNull,
      );
      // Стабильный принимается и при включённой бете.
      expect(
        validateManifest(m(channel: 'stable'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: true),
        isNull,
      );
    });

    test('актива с таким именем нет → assetMissing (только точное имя)', () {
      expect(
        validateManifest(m(),
            expectedVersion: '1.14.1',
            assetName: '$exe.bak',
            betaAllowed: false),
        ManifestRejection.assetMissing,
      );
      expect(
        validateManifest(m(name: '$exe.bak'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.assetMissing,
      );
    });

    test('size <= 0 → malformed', () {
      for (final size in [0, -1]) {
        expect(
          validateManifest(m(size: size),
              expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
          ManifestRejection.malformed,
          reason: 'size=$size',
        );
      }
    });

    test('sha256 не 64 hex → malformed', () {
      for (final bad in [
        '',
        sha.substring(1),
        '${sha}0',
        'g${sha.substring(1)}',
        sha.toUpperCase(),
        '${sha.substring(0, 63)} ',
      ]) {
        expect(
          validateManifest(m(hash: bad),
              expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
          ManifestRejection.malformed,
          reason: 'sha256=«$bad»',
        );
      }
    });

    test('порядок отказов: версия раньше канала, канал раньше актива', () {
      // Один манифест с тремя дефектами разом — называем первый по порядку
      // проверки, чтобы журнал был воспроизводим.
      expect(
        validateManifest(m(version: '0.0.1', channel: 'beta', name: 'x'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.versionMismatch,
      );
      expect(
        validateManifest(m(channel: 'beta', name: 'x'),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.channelMismatch,
      );
      expect(
        validateManifest(m(name: 'x', size: 0),
            expectedVersion: '1.14.1', assetName: exe, betaAllowed: false),
        ManifestRejection.assetMissing,
      );
    });
  });

  group('normalizeVersion', () {
    test('снимает ведущий v/V и пробелы, остальное не трогает', () {
      expect(normalizeVersion('v1.14.1'), '1.14.1');
      expect(normalizeVersion('V1.14.1'), '1.14.1');
      expect(normalizeVersion(' 1.14.1 '), '1.14.1');
      expect(normalizeVersion('1.14.1-beta.1'), '1.14.1-beta.1');
      expect(normalizeVersion('vv1'), 'v1');
    });
  });
}
