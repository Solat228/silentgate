import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/support/dev_report_service.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/app_update_defaults.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/support_report_dialog.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_dev_report_test_');
    AppPaths.overrideRoot(tmp);
    setDeviceIdProviderForTests(_TestDeviceId());
  });

  tearDown(() {
    setDeviceIdProviderForTests(null);
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('DevReportService hashing & desk linking', () {
    test('sub_hash matches Site/app.py _support_sub_hash byte-for-byte', () {
      const token = 'TEST_SHORT_UUID_01';
      final expected = Sha256.ofBytes(utf8.encode('sub:$token'));

      expect(
        DevReportService.computeSubHash(
          'https://sub.silentgate.lol/sub/$token',
        ),
        expected,
      );
      expect(
        DevReportService.computeSubHash(
          'https://s.silentgate.lol/silentgate/$token',
        ),
        expected,
      );
      expect(DevReportService.computeSubHash(''), isNull);
    });

    test('hwid_hash and anon_device_id are deterministic and hide raw HWID', () {
      const hwid = '40B53B77D344659B';
      final expectedHwidHash =
          Sha256.ofBytes(utf8.encode('hwid:40b53b77d344659b'));
      expect(DevReportService.computeHwidHash(hwid), expectedHwidHash);

      final anon1 = DevReportService.computeAnonDeviceId(hwid);
      final anon2 = DevReportService.computeAnonDeviceId(hwid.toLowerCase());
      expect(anon1, anon2);
      expect(anon1.length, 16);
      expect(anon1, isNot(contains('40b53b')));
    });
  });

  group('DevReportService.anonymizeReportText', () {
    test('scrubs HWID, user paths, carrier/LAN IPs while keeping diagnostics',
        () {
      const sample = '''
SilentGate: 1.18.8+103
HWID: 40b53b77d344659b
Подписка: https://my-private-panel.org/****(скрыто)
Выбран: Yandex Telemost IT1 (ядро sing-box)
16.11.2026 18:25:47 [INFO] Каталог: /data/app/~~sjhiX57==/lol.silentgate-8eQN==/lib/arm64/librelay.so
16.11.2026 18:25:48 [INFO] Профиль ПК: C:\\Users\\SlavaAdmin\\AppData\\Roaming\\SilentGate\\app.log
16.11.2026 18:25:49 [WARN] Сеть изменилась: [192.168.1.165,2a00:1fa2:c628:1aa6::/64] -> [100.84.19.22,2a00:1fa2:c210:617::/64]
16.11.2026 18:25:52 [INFO] Сторож: проба через 127.0.0.1:10811, TUN 172.19.0.2:853, DNS 1.1.1.1:53
2026-11-16 18:25:53 +0700 ERROR connection to 93.184.216.34:22: rejected
''';

      final anon = DevReportService.anonymizeReportText(
        sample,
        rawHwid: '40b53b77d344659b',
        rawSubscriptionUrl: 'https://my-private-panel.org/sub/abcdef123456',
        reportCode: 'SG-TEST99',
      );

      expect(anon, contains('Код отчёта: SG-TEST99'));
      expect(anon, isNot(contains('40b53b77d344659b')));
      expect(anon, contains('HWID: anon:'));
      expect(anon, isNot(contains('my-private-panel.org')));
      expect(anon, contains('<сторонний-провайдер>'));
      expect(anon, isNot(contains('SlavaAdmin')));
      expect(anon, contains(r'C:\Users\<user>\AppData'));
      expect(anon, contains('/data/app/<pkg>/lib/arm64/librelay.so'));
      expect(anon, isNot(contains('192.168.1.165')));
      expect(anon, contains('<lan-v4-#1>'));
      expect(anon, isNot(contains('100.84.19.22')));
      expect(anon, contains('<cgnat-v4-#1>'));
      expect(anon, isNot(contains('2a00:1fa2')));
      expect(anon, contains('<isp-v6-#1>/64'));
      expect(anon, contains('<isp-v6-#2>/64'));
      expect(anon, isNot(contains('93.184.216.34')));
      expect(anon, contains('<ext-v4-#1>:22'));

      // Диагностика сохранена нетронутой:
      expect(anon, contains('1.18.8+103'));
      expect(anon, contains('16.11.2026 18:25:47'));
      expect(anon, contains('Yandex Telemost IT1'));
      expect(anon, contains('127.0.0.1:10811'));
      expect(anon, contains('172.19.0.2:853'));
      expect(anon, contains('1.1.1.1:53'));
    });
  });

  group('SupportReportDialog UI & dev-only upload', () {
    testWidgets(
        'allows 1-click dev-only report with empty description and selected chip',
        (tester) async {
      final fakeReporter = _FakeSupportReporter(tmp);
      Map<String, dynamic>? uploadedJson;
      Map<String, String>? uploadedHeaders;

      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showSupportReportDialog(
                  ctx,
                  reporterOverride: fakeReporter,
                  httpSenderOverride: (uri, headers, body) async {
                    uploadedHeaders = headers;
                    uploadedJson = jsonDecode(body) as Map<String, dynamic>;
                    return (
                      200,
                      jsonEncode({
                        'ok': true,
                        'report_code': uploadedJson!['report_code'],
                        'linked': true,
                      }),
                    );
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Выбираем быстрый чип без ввода единого символа в текстовое поле.
      await tester.tap(find.byKey(const Key('supportChip_site_or_youtube')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('supportSendDevOnlyButton')));
      await tester.pumpAndSettle();

      expect(uploadedJson, isNotNull);
      expect(uploadedJson!['tags'], equals(['site_or_youtube']));
      expect(uploadedJson!['has_description'], isFalse);
      expect(uploadedJson!['hwid_hash'], isNotEmpty);
      expect(
        '${uploadedJson!['report_text']}',
        isNot(contains('RAW-HWID-SECRET')),
      );
      expect(uploadedHeaders!['X-SilentGate-Hwid-Hash'], isNotEmpty);
      expect(fakeReporter.revealCalls, 0);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('Stealth vs normal APK update isolation', () {
    const releaseJson = '''
{
  "tag_name": "v1.18.8-beta.1",
  "prerelease": true,
  "html_url": "https://github.com/Solat228/silentgate/releases/tag/v1.18.8-beta.1",
  "assets": [
    {
      "name": "SilentGate-ROOT-Stealth-1.18.8-beta.1-arm64-v8a.apk",
      "size": 42180991,
      "browser_download_url": "https://github.com/Solat228/silentgate/releases/download/v1.18.8-beta.1/SilentGate-ROOT-Stealth-1.18.8-beta.1-arm64-v8a.apk"
    }
  ]
}
''';

    test('normal Android build never picks ROOT-Stealth APK', () {
      final normalHint = platformAssetHint(
        android: true,
        androidAbi: 'arm64-v8a',
        stealth: false,
      );
      final r = AppUpdate.parseGithubRelease(releaseJson, assetHint: normalHint);
      expect(r, isNotNull);
      expect(r!.downloadUrl, isNull);
    });

    test('stealth Android build matches ROOT-Stealth APK', () {
      final stealthHint = platformAssetHint(
        android: true,
        androidAbi: 'arm64-v8a',
        stealth: true,
      );
      final r =
          AppUpdate.parseGithubRelease(releaseJson, assetHint: stealthHint);
      expect(r, isNotNull);
      expect(
        r!.assetName,
        'SilentGate-ROOT-Stealth-1.18.8-beta.1-arm64-v8a.apk',
      );
    });
  });
}

class _TestDeviceId implements DeviceIdProvider {
  @override
  Future<String> hwid() async => 'RAW-HWID-SECRET';

  @override
  String osName() => 'windows';

  @override
  Future<String> osVersion() async => '11';

  @override
  Future<String> deviceModel() async => 'TestPC';
}

class _FakeSupportReporter implements SupportReporter {
  final Directory dir;
  int revealCalls = 0;

  _FakeSupportReporter(this.dir);

  @override
  Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  }) async {
    final f = File('${dir.path}${Platform.pathSeparator}fake-report.txt');
    f.writeAsStringSync(
      '${ctx.header}\nHWID: RAW-HWID-SECRET\nВыбран: ${ctx.activeServer}\n',
    );
    return f.path;
  }

  @override
  Future<void> reveal(String path) async {
    revealCalls++;
  }
}
