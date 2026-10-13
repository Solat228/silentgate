import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/app_update_defaults.dart';
import 'package:silentgate/core/update/update_manifest.dart';
import 'package:silentgate/core/update/update_signature.dart';

// Самообновление без api.github.com (13.10.2026): у владельца API падает на
// TLS, а github.com открывается. Версия — из ленты releases.atom, манифест,
// подпись и файлы — по прямым адресам releases/download.

const _base = 'https://github.com/Solat228/silentgate';

String _feed(List<(String tag, String html)> entries) {
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<feed>\n');
  for (final (tag, html) in entries) {
    final escaped = html
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    b.write('''
  <entry>
    <id>tag:github.com,2008:Repository/1/$tag</id>
    <updated>2026-10-12T08:25:24Z</updated>
    <link rel="alternate" type="text/html" href="$_base/releases/tag/$tag"/>
    <title>SilentGate $tag</title>
    <content type="html">$escaped</content>
  </entry>
''');
  }
  b.write('</feed>\n');
  return b.toString();
}

void main() {
  late List<int> seed;
  late String publicKey;

  setUpAll(() {
    seed = List<int>.generate(32, (i) => (i * 53 + 7) & 0xff);
    publicKey = base64
        .encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(seed))).bytes);
  });

  String manifestJson(String version, List<(String, int)> assets) =>
      UpdateManifest(
        version: version,
        channel: UpdateManifest.channelStable,
        assets: [
          for (final (name, size) in assets)
            UpdateAsset(name: name, size: size, sha256: 'a' * 64),
        ],
      ).toJson();

  /// Фальшивый GitHub: API лежит, сайт отвечает тем, что положили в [files].
  UpdateFetcher fakeGithub(Map<String, String> files, List<String> seen) =>
      (uri) async {
        final u = uri.toString();
        seen.add(u);
        if (uri.host == 'api.github.com') {
          throw const FormatException('TLS: hostname mismatch');
        }
        final body = files[u];
        return body == null
            ? const UpdateHttpResponse(404, 'Not Found')
            : UpdateHttpResponse(200, body);
      };

  Map<String, String> signedRelease(String tag, String version,
      {bool legacy = false, List<(String, int)>? assets}) {
    final json = manifestJson(
        version,
        assets ??
            [
              ('SilentGateSetup-$version.exe', 70000000),
              ('SilentGate-$version-arm64-v8a.apk', 80000000),
            ]);
    final sig = UpdateSignature.sign(utf8.encode(json), seed);
    final prefix = legacy ? '' : 'update-';
    return {
      '$_base/releases/download/$tag/${prefix}SilentGate-$version.manifest.json':
          json,
      '$_base/releases/download/$tag/${prefix}SilentGate-$version.manifest.sig':
          '$sig\n',
    };
  }

  setUp(() => debugSetUpdateApiOverride(null));
  tearDown(debugResetUpdateApiOverride);

  group('лента релизов', () {
    test('разбор: тег, версия, заметки текстом без тегов и сущностей', () {
      final entries = AppUpdate.parseReleasesFeed(_feed([
        (
          'v9.0.1',
          '<p>Стабильный выпуск.</p>\n<ul>\n<li>Пункт &quot;один&quot;</li>\n'
              '<li>Пункт два</li>\n</ul>'
        ),
        ('v9.0.0-beta.1', '<p>Бета</p>'),
      ]));
      expect(entries.map((e) => e.tag), ['v9.0.1', 'v9.0.0-beta.1']);
      expect(entries.first.version, '9.0.1');
      expect(entries.first.notes, 'Стабильный выпуск.\n\n- Пункт "один"\n- Пункт два');
      expect(entries.first.updated, DateTime.utc(2026, 10, 12, 8, 25, 24));
    });

    test('⚠️ стабильный канал не берёт бету, даже если она новее и выше', () {
      final entries = AppUpdate.parseReleasesFeed(_feed([
        ('v9.1.0-beta.1', ''),
        ('v9.0.1', ''),
        ('v9.0.0', ''),
      ]));
      expect(AppUpdate.pickFeedEntry(entries, beta: false)?.tag, 'v9.0.1');
      expect(AppUpdate.pickFeedEntry(entries, beta: true)?.tag, 'v9.1.0-beta.1');
    });

    test('выбор по номеру версии, а не по порядку записей', () {
      final entries = AppUpdate.parseReleasesFeed(_feed([
        ('v9.0.0', ''),
        ('v9.0.2', ''),
        ('v9.0.1', ''),
      ]));
      expect(AppUpdate.pickFeedEntry(entries, beta: false)?.tag, 'v9.0.2');
    });

    test('мусор вместо ленты — ни одной записи', () {
      expect(AppUpdate.parseReleasesFeed('<html>captcha</html>'), isEmpty);
      expect(AppUpdate.pickFeedEntry(const [], beta: false), isNull);
    });
  });

  group('check(): api.github.com недоступен, отвечает github.com', () {
    test('⚠️ самообновление по подписанному манифесту с новым именем',
        () async {
      final seen = <String>[];
      final files = {
        '$_base/releases.atom': _feed([('v9.0.1', '<p>Новое</p>')]),
        ...signedRelease('v9.0.1', '9.0.1'),
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(files, seen),
        publicKeyBase64: publicKey,
      );
      expect(r.state, UpdateCheckState.available);
      final rel = r.release!;
      expect(rel.version, '9.0.1');
      expect(rel.canSelfUpdate, isTrue);
      expect(rel.assetName, 'SilentGateSetup-9.0.1.exe');
      expect(rel.assetSize, 70000000);
      expect(rel.downloadUrl,
          '$_base/releases/download/v9.0.1/SilentGateSetup-9.0.1.exe');
      expect(rel.manifestUrl,
          '$_base/releases/download/v9.0.1/update-SilentGate-9.0.1.manifest.json');
      expect(rel.signatureUrl,
          '$_base/releases/download/v9.0.1/update-SilentGate-9.0.1.manifest.sig');
      expect(rel.notes, 'Новое');
      expect(rel.pageUrl, '$_base/releases/tag/v9.0.1');
      // Запасной сайт не спрашивали: GitHub ответил сам.
      expect(seen.where((u) => u.contains('silentgate.lol')), isEmpty);
    });

    test('Android: файл под ABI берётся из манифеста', () async {
      final files = {
        '$_base/releases.atom': _feed([('v9.0.1', '')]),
        ...signedRelease('v9.0.1', '9.0.1'),
      };
      final r = await AppUpdate.check(
        assetHint: '-arm64-v8a.apk',
        fetcher: fakeGithub(files, []),
        publicKeyBase64: publicKey,
      );
      expect(r.release!.assetName, 'SilentGate-9.0.1-arm64-v8a.apk');
      expect(r.release!.canSelfUpdate, isTrue);
    });

    test('выпуск со старыми именами (1.14.0–1.15.1) тоже годится', () async {
      final files = {
        '$_base/releases.atom': _feed([('v9.0.1', '')]),
        ...signedRelease('v9.0.1', '9.0.1', legacy: true),
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(files, []),
        publicKeyBase64: publicKey,
      );
      expect(r.release!.canSelfUpdate, isTrue);
      expect(r.release!.manifestUrl,
          '$_base/releases/download/v9.0.1/SilentGate-9.0.1.manifest.json');
    });

    test('⚠️ чужая подпись — версия известна, но только ссылка', () async {
      final files = {
        '$_base/releases.atom': _feed([('v9.0.1', '')]),
        ...signedRelease('v9.0.1', '9.0.1'),
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(files, []),
        // Вшитый ключ: тестовым seed подписано не им.
      );
      expect(r.state, UpdateCheckState.available);
      expect(r.release!.canSelfUpdate, isFalse);
      expect(r.release!.pageUrl, '$_base/releases/tag/v9.0.1');
    });

    test('манифест другой версии под именем этой — не принимается', () async {
      final wrong = signedRelease('v9.0.1', '9.0.0');
      final files = {
        '$_base/releases.atom': _feed([('v9.0.1', '')]),
        for (final e in wrong.entries)
          e.key.replaceAll('9.0.0.manifest', '9.0.1.manifest'): e.value,
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(files, []),
        publicKeyBase64: publicKey,
      );
      expect(r.release!.canSelfUpdate, isFalse);
    });

    test('в манифесте нет файла под платформу — только ссылка', () async {
      final files = {
        '$_base/releases.atom': _feed([('v9.0.1', '')]),
        ...signedRelease('v9.0.1', '9.0.1',
            assets: [('SilentGate-9.0.1-arm64-v8a.apk', 10)]),
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(files, []),
        publicKeyBase64: publicKey,
      );
      expect(r.state, UpdateCheckState.available);
      expect(r.release!.canSelfUpdate, isFalse);
    });

    test('версия не новее — «последняя», манифест не качается', () async {
      final seen = <String>[];
      final files = {
        '$_base/releases.atom': _feed([('v0.0.1', '')]),
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(files, seen),
        publicKeyBase64: publicKey,
      );
      expect(r.state, UpdateCheckState.upToDate);
      expect(seen.where((u) => u.contains('manifest')), isEmpty);
    });

    test('бета-канал берёт пре-релиз из ленты', () async {
      final files = {
        '$_base/releases.atom':
            _feed([('v9.0.2-beta.1', ''), ('v9.0.1', '')]),
        ...signedRelease('v9.0.2-beta.1', '9.0.2-beta.1'),
      };
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        beta: true,
        fetcher: fakeGithub(files, []),
        publicKeyBase64: publicKey,
      );
      expect(r.release!.version, '9.0.2-beta.1');
      expect(r.release!.isBeta, isTrue);
      expect(r.release!.canSelfUpdate, isTrue);
    });

    test('лента не открылась — дальше запасной сайт, как раньше', () async {
      final seen = <String>[];
      await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: fakeGithub(const {}, seen),
      );
      expect(seen, [
        'https://api.github.com/repos/Solat228/silentgate/releases/latest',
        '$_base/releases.atom',
        'https://silentgate.lol/api/app-version',
      ]);
    });
  });

  group('API GitHub: имена манифеста', () {
    Map<String, Object> asset(String name) => {
          'name': name,
          'browser_download_url': 'https://x/$name',
          'size': 100,
        };

    test('⚠️ новое имя важнее старого, пара не смешивается', () {
      final r = AppUpdate.parseGithubRelease(
        jsonEncode({
          'tag_name': 'v9.0.1',
          'assets': [
            asset('SilentGateSetup-9.0.1.exe'),
            asset('SilentGate-9.0.1.manifest.json'),
            asset('SilentGate-9.0.1.manifest.sig'),
            asset('update-SilentGate-9.0.1.manifest.json'),
            asset('update-SilentGate-9.0.1.manifest.sig'),
          ],
        }),
        assetHint: 'Setup.exe',
      )!;
      expect(r.manifestUrl, 'https://x/update-SilentGate-9.0.1.manifest.json');
      expect(r.signatureUrl, 'https://x/update-SilentGate-9.0.1.manifest.sig');
    });

    test('только старые имена — берутся они', () {
      final r = AppUpdate.parseGithubRelease(
        jsonEncode({
          'tag_name': 'v9.0.1',
          'assets': [
            asset('SilentGateSetup-9.0.1.exe'),
            asset('SilentGate-9.0.1.manifest.json'),
            asset('SilentGate-9.0.1.manifest.sig'),
          ],
        }),
        assetHint: 'Setup.exe',
      )!;
      expect(r.manifestUrl, 'https://x/SilentGate-9.0.1.manifest.json');
      expect(r.canSelfUpdate, isTrue);
    });

    test('новый манифест без новой подписи — пара целиком старая', () {
      final r = AppUpdate.parseGithubRelease(
        jsonEncode({
          'tag_name': 'v9.0.1',
          'assets': [
            asset('SilentGateSetup-9.0.1.exe'),
            asset('update-SilentGate-9.0.1.manifest.json'),
            asset('SilentGate-9.0.1.manifest.json'),
            asset('SilentGate-9.0.1.manifest.sig'),
          ],
        }),
        assetHint: 'Setup.exe',
      )!;
      expect(r.manifestUrl, 'https://x/SilentGate-9.0.1.manifest.json');
      expect(r.signatureUrl, 'https://x/SilentGate-9.0.1.manifest.sig');
    });
  });

  test('под тестовым override лента и файлы уходят на стенд', () {
    debugSetUpdateApiOverride('http://127.0.0.1:8080/');
    expect(kGithubReleasesFeed,
        'http://127.0.0.1:8080/Solat228/silentgate/releases.atom');
    expect(githubDownloadUrl('v1.0.0', 'a.exe'),
        'http://127.0.0.1:8080/Solat228/silentgate/releases/download/v1.0.0/a.exe');
    // Страница для человека — всегда настоящая.
    expect(githubTagPage('v1.0.0'), '$_base/releases/tag/v1.0.0');
  });
}
