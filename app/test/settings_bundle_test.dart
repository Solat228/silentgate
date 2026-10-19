import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/backup/settings_bundle.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/data/settings_backup.dart';

/// Экспорт и импорт настроек одним файлом (P11). Адреса — только TEST-NET.
void main() {
  const sub = 'https://sub.example.test/sub/TOKEN123';
  const server = 'vless://00000000-0000-0000-0000-000000000000@203.0.113.10:443#DE';

  Map<String, Object?> settingsJson() {
    final j = AppSettings.defaults
        .copyWith(
          killSwitch: true,
          localProxyUser: 'me',
          localProxyPassword: 'secret-pass',
          apiToken: 'api-token-1',
          apiEnabled: true,
          apiExitServerKeys: [server],
          deviceInfoConsent: true,
          launchAtLogin: true,
          languageCode: 'de',
        )
        .toJson();
    j['splitTunnel'] = {
      'mode': 'onlySelected',
      'apps': [
        {'path': 'chrome.exe', 'byName': true, 'action': 'tunnel', 'serverKey': server},
      ],
      'sites': [
        {'domain': 'example.com', 'action': 'tunnel', 'serverKey': server},
      ],
    };
    return j;
  }

  Map<String, Object?> subsJson() => {
        'activeId': 'a1',
        'items': [
          {'id': 'a1', 'url': sub, 'logoPath': r'C:\x\sub_logo_a1.png', 'servers': [server]},
        ],
      };

  Map<String, Object?> files() => {
        SettingsBundle.settingsFile: settingsJson(),
        SettingsBundle.subscriptionsFile: subsJson(),
        SettingsBundle.pinnedFile: [
          {'link': server}
        ],
        SettingsBundle.overridesFile: {server: {'variant': {}}},
        SettingsBundle.panelFile: {},
      };

  group('Сборка файла', () {
    test('⚠️ секреты устройства не уходят никогда', () {
      final b = SettingsBundle.build(
          files: files(),
          includeSubscriptions: true,
          platform: 'windows',
          appVersion: '1.17.0');
      final text = SettingsBundle.encode(b);
      expect(text, isNot(contains('secret-pass')));
      expect(text, isNot(contains('api-token-1')));
      final s = (b['files'] as Map)[SettingsBundle.settingsFile] as Map;
      for (final k in SettingsBundle.deviceOnlyKeys) {
        expect(s.containsKey(k), isFalse, reason: k);
      }
      expect(s['killSwitch'], isTrue);
    });

    test('с подписками: все файлы, путь к логотипу срезан', () {
      final b = SettingsBundle.build(
          files: files(),
          includeSubscriptions: true,
          platform: 'windows',
          appVersion: '1.17.0');
      final f = b['files'] as Map;
      expect(f.keys, containsAll(SettingsBundle.allFiles));
      expect(b['subscriptions'], isTrue);
      final item = ((f[SettingsBundle.subscriptionsFile] as Map)['items'] as List)
          .single as Map;
      expect(item.containsKey('logoPath'), isFalse);
      expect(item['url'], sub);
    });

    test('⚠️ без подписок: ни адреса подписки, ни ключей серверов', () {
      final b = SettingsBundle.build(
          files: files(),
          includeSubscriptions: false,
          platform: 'windows',
          appVersion: '1.17.0');
      final text = SettingsBundle.encode(b);
      expect(text, isNot(contains('TOKEN123')));
      expect(text, isNot(contains('203.0.113.10')),
          reason: 'ключ сервера = share-ссылка с UUID');
      expect((b['files'] as Map).keys, [SettingsBundle.settingsFile]);
      expect(b['subscriptions'], isFalse);
      // Сами правила остаются — только без выхода.
      final split = ((b['files'] as Map)[SettingsBundle.settingsFile]
          as Map)['splitTunnel'] as Map;
      expect((split['sites'] as List).single, {'domain': 'example.com', 'action': 'tunnel'});
    });

    test('настройки переживают круг «файл → AppSettings»', () {
      final b = SettingsBundle.build(
          files: files(),
          includeSubscriptions: true,
          platform: 'windows',
          appVersion: '1.17.0');
      final parsed = SettingsBundle.parse(SettingsBundle.encode(b))!;
      final s = AppSettings.fromJson(Map<String, dynamic>.from(
          parsed.files[SettingsBundle.settingsFile] as Map));
      expect(s.killSwitch, isTrue);
      expect(s.languageCode, 'de');
      expect(s.localProxyPassword, isEmpty);
    });
  });

  group('Разбор', () {
    test('чужой, битый и будущий формат — null', () {
      expect(SettingsBundle.parse('not json'), isNull);
      expect(SettingsBundle.parse('{"format":"other","version":1,"files":{}}'),
          isNull);
      expect(
          SettingsBundle.parse(
              '{"format":"silentgate-settings","version":99,"files":{}}'),
          isNull,
          reason: 'формат новее — читать нельзя, потеряем новое молча');
      expect(
          SettingsBundle.parse(
              '{"format":"silentgate-settings","version":1,"files":[]}'),
          isNull);
    });

    test('BOM и лишние файлы не мешают', () {
      final p = SettingsBundle.parse('\uFEFF${jsonEncode({
            'format': 'silentgate-settings',
            'version': 1,
            'platform': 'android',
            'files': {
              'silentgate_settings.json': {'killSwitch': true},
              'evil.json': {'x': 1},
            },
          })}')!;
      expect(p.platform, 'android');
      expect(p.files.keys, ['silentgate_settings.json']);
      expect(p.hasSubscriptions, isFalse);
    });
  });

  group('Слияние при импорте', () {
    BundleContents bundle(String platform, {bool subs = true}) =>
        SettingsBundle.parse(SettingsBundle.encode(SettingsBundle.build(
            files: files(),
            includeSubscriptions: subs,
            platform: platform,
            appVersion: '1.17.0')))!;

    final local = <String, Object?>{
      'localProxyPassword': 'local-pass',
      'apiToken': 'local-token',
      'deviceInfoConsent': false,
      'captureMode': 'tun',
      'apiExitServerKeys': ['local-key'],
      'splitTunnel': {
        'mode': 'all',
        'apps': [
          {'path': 'org.telegram', 'byName': true, 'action': 'direct'}
        ],
        'sites': [],
      },
    };

    test('⚠️ секреты и согласие этого устройства остаются местными', () {
      final out = SettingsBundle.merge(bundle('windows'),
          localSettings: local, platform: 'windows', includeSubscriptions: true);
      final s = out[SettingsBundle.settingsFile] as Map;
      expect(s['localProxyPassword'], 'local-pass');
      expect(s['apiToken'], 'local-token');
      expect(s['deviceInfoConsent'], isFalse,
          reason: 'согласие даёт человек на каждом устройстве сам');
      expect(s.containsKey('launchAtLogin'), isFalse);
    });

    test('та же платформа: приложения и режим захвата из файла', () {
      final out = SettingsBundle.merge(bundle('windows'),
          localSettings: local, platform: 'windows', includeSubscriptions: true);
      final s = out[SettingsBundle.settingsFile] as Map;
      expect(s['captureMode'], AppSettings.defaults.captureMode.name);
      final apps = (s['splitTunnel'] as Map)['apps'] as List;
      expect((apps.single as Map)['path'], 'chrome.exe');
      expect(out.keys, containsAll(SettingsBundle.subscriptionFiles));
    });

    test('⚠️ другая платформа: приложения и платформенное — местные', () {
      final out = SettingsBundle.merge(bundle('windows'),
          localSettings: local, platform: 'android', includeSubscriptions: true);
      final s = out[SettingsBundle.settingsFile] as Map;
      expect(s['captureMode'], 'tun');
      expect(s['apiExitServerKeys'], ['local-key']);
      final split = s['splitTunnel'] as Map;
      expect((split['apps'] as List).single, containsPair('path', 'org.telegram'),
          reason: 'путь exe на телефоне бессмыслен');
      expect((split['sites'] as List).single, containsPair('domain', 'example.com'));
      expect(split['mode'], 'onlySelected');
    });

    test('без подписок: файлы подписок не трогаются, ссылки на серверы сняты', () {
      final out = SettingsBundle.merge(bundle('windows'),
          localSettings: local, platform: 'windows', includeSubscriptions: false);
      expect(out.keys, [SettingsBundle.settingsFile]);
      final s = out[SettingsBundle.settingsFile] as Map;
      expect(s['apiExitServerKeys'], ['local-key']);
      final split = s['splitTunnel'] as Map;
      expect((split['sites'] as List).single, isNot(contains('serverKey')));
      expect((split['apps'] as List).single, isNot(contains('serverKey')));
    });

    test('файл без подписок при галочке «с подписками» — подписки целы', () {
      final out = SettingsBundle.merge(bundle('windows', subs: false),
          localSettings: local, platform: 'windows', includeSubscriptions: true);
      expect(out.keys, [SettingsBundle.settingsFile]);
    });
  });

  group('Диск: отложенный импорт и снимок', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_backup_');
      AppPaths.overrideRoot(tmp);
      SettingsBackup.restoredOnStart = null;
    });
    tearDown(() {
      AppPaths.resetForTests();
      tmp.deleteSync(recursive: true);
    });

    File f(String name) => File('${tmp.path}${Platform.pathSeparator}$name');

    void writeAll() {
      files().forEach((k, v) => f(k).writeAsStringSync(jsonEncode(v)));
      f('silentgate_state.json').writeAsStringSync(jsonEncode({
        'subscriptionUrl': sub,
        'selectedIndex': 3,
        'geoOfferDismissed': 'never',
      }));
    }

    test('экспорт → импорт: применяется только на следующем старте', () async {
      writeAll();
      final text = await SettingsBackup.exportText(includeSubscriptions: true);
      // Другое устройство: свой пароль, другие подписки.
      f(SettingsBundle.settingsFile).writeAsStringSync(
          jsonEncode({'localProxyPassword': 'mine', 'killSwitch': false}));
      f(SettingsBundle.subscriptionsFile)
          .writeAsStringSync(jsonEncode({'activeId': 'z', 'items': []}));

      final ok = await SettingsBackup.stageImport(SettingsBundle.parse(text)!,
          includeSubscriptions: true);
      expect(ok, isTrue);
      expect(
          jsonDecode(f(SettingsBundle.settingsFile).readAsStringSync())['killSwitch'],
          isFalse,
          reason: 'живые файлы до перезапуска не трогаются');

      expect(await SettingsBackup.applyPending(), isTrue);
      expect(SettingsBackup.restoredOnStart, RestoreSource.importFile);
      expect(f(SettingsBackup.pendingFile).existsSync(), isFalse);
      final s = jsonDecode(f(SettingsBundle.settingsFile).readAsStringSync());
      expect(s['killSwitch'], isTrue);
      expect(s['localProxyPassword'], 'mine');
      expect(f(SettingsBundle.subscriptionsFile).readAsStringSync(),
          contains('TOKEN123'));
      final state = jsonDecode(f('silentgate_state.json').readAsStringSync());
      expect(state.containsKey('selectedIndex'), isFalse,
          reason: 'выбор указывал на старые подписки');
      expect(state['geoOfferDismissed'], 'never');
      expect(await SettingsBackup.applyPending(), isFalse);
    });

    test('битый отложенный импорт удаляется и не ломает старт', () async {
      f(SettingsBackup.pendingFile).writeAsStringSync('{oops');
      expect(await SettingsBackup.applyPending(), isFalse);
      expect(f(SettingsBackup.pendingFile).existsSync(), isFalse);
    });

    test('снимок: не переписывается без изменений, восстанавливает новую установку',
        () async {
      writeAll();
      await SettingsBackup.writeSnapshot(includeSubscriptions: true);
      final snap = f('${SettingsBackup.snapshotDir}${Platform.pathSeparator}'
          '${SettingsBackup.snapshotFile}');
      expect(snap.existsSync(), isTrue);
      expect(snap.readAsStringSync(), isNot(contains('secret-pass')));
      final stamp = snap.lastModifiedSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await SettingsBackup.writeSnapshot(includeSubscriptions: true);
      expect(snap.lastModifiedSync(), stamp);

      // Настроенное приложение снимок не трогает.
      expect(await SettingsBackup.restoreSnapshotIfFresh(), isFalse);

      // Новая установка: система вернула только каталог снимка.
      for (final name in [...SettingsBundle.allFiles, 'silentgate_state.json']) {
        if (f(name).existsSync()) f(name).deleteSync();
      }
      expect(await SettingsBackup.restoreSnapshotIfFresh(), isTrue);
      expect(SettingsBackup.restoredOnStart, RestoreSource.googleBackup);
      expect(f(SettingsBundle.subscriptionsFile).readAsStringSync(),
          contains('TOKEN123'));
    });

    test('⚠️ снимок без подписок не несёт их адреса', () async {
      writeAll();
      await SettingsBackup.writeSnapshot(includeSubscriptions: false);
      final snap = f('${SettingsBackup.snapshotDir}${Platform.pathSeparator}'
          '${SettingsBackup.snapshotFile}');
      final text = snap.readAsStringSync();
      expect(text, isNot(contains('TOKEN123')));
      expect(text, isNot(contains('203.0.113.10')));
    });
  });
}
