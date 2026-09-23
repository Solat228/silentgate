import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/platform/apk_installer_android.dart';
import 'package:silentgate/core/update/update_installer.dart';
import 'package:silentgate/core/update/update_installer_android.dart';

/// Dart-сторона установки APK: канал, таблица ABI и предохранители `launch`.
///
/// Нативной стороны в тесте нет — каналы подменены. Стережётся то, что
/// статикой не видно: какой метод и с каким аргументом уходит в Kotlin, и
/// что при отказе (нет разрешения, файл подменён) установщик НЕ вызывается.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const device = MethodChannel('lol.silentgate/device');
  const launcher = MethodChannel('lol.silentgate/launcher');

  final calls = <MethodCall>[];
  Object? abiAnswer;
  bool canInstall = true;
  bool installAnswer = true;

  setUp(() {
    calls.clear();
    abiAnswer = 'arm64-v8a';
    canInstall = true;
    installAnswer = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(device, (call) async {
        calls.add(call);
        if (call.method == 'abi') return abiAnswer;
        return null;
      })
      ..setMockMethodCallHandler(launcher, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'canInstallPackages':
            return canInstall;
          case 'openInstallPermission':
            return true;
          case 'installApk':
            return installAnswer;
        }
        return false;
      });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(device, null)
      ..setMockMethodCallHandler(launcher, null);
  });

  group('ApkInstallerAndroid.assetHintForAbi', () {
    test('таблица: только те ABI, под которые есть сборки', () {
      expect(ApkInstallerAndroid.assetHintForAbi('arm64-v8a'), '-arm64-v8a.apk');
      expect(ApkInstallerAndroid.assetHintForAbi('x86_64'), '-x86_64.apk');
      // 32-битных сборок нет — честный null, а не подбор «похожей».
      expect(ApkInstallerAndroid.assetHintForAbi('armeabi-v7a'), isNull);
      expect(ApkInstallerAndroid.assetHintForAbi('x86'), isNull);
      expect(ApkInstallerAndroid.assetHintForAbi(null), isNull);
      expect(ApkInstallerAndroid.assetHintForAbi(''), isNull);
    });

    test('пробелы и регистр не ломают сопоставление', () {
      expect(ApkInstallerAndroid.assetHintForAbi(' ARM64-v8a '), '-arm64-v8a.apk');
    });
  });

  group('ApkInstallerAndroid (канал)', () {
    test('deviceAbi спрашивает device.abi', () async {
      final apk = ApkInstallerAndroid();
      expect(await apk.deviceAbi(), 'arm64-v8a');
      expect(calls.single.method, 'abi');
    });

    test('deviceAbi: пустой ответ и сбой канала → null', () async {
      abiAnswer = '  ';
      expect(await ApkInstallerAndroid().deviceAbi(), isNull);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(device, null);
      expect(await ApkInstallerAndroid().deviceAbi(), isNull);
    });

    test('canInstallPackages: сбой канала → false, а не исключение', () async {
      canInstall = false;
      expect(await ApkInstallerAndroid().canInstallPackages(), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null);
      expect(await ApkInstallerAndroid().canInstallPackages(), isFalse);
    });

    test('installApk передаёт путь под ключом path', () async {
      await ApkInstallerAndroid().installApk('/data/cache/updates/a.apk');
      final call = calls.single;
      expect(call.method, 'installApk');
      expect(call.arguments, {'path': '/data/cache/updates/a.apk'});
    });

    test('installApk: нативная сторона ответила false → ApkInstallRefused',
        () async {
      installAnswer = false;
      expect(
        () => ApkInstallerAndroid().installApk('/x.apk'),
        throwsA(isA<ApkInstallRefused>()),
      );
    });

    test('openInstallPermission зовёт метод канала', () async {
      await ApkInstallerAndroid().openInstallPermission();
      expect(calls.single.method, 'openInstallPermission');
    });
  });

  group('UpdateInstallerAndroid', () {
    late Directory tmp;
    late UpdateInstallerAndroid installer;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_apk_inst_');
      installer = UpdateInstallerAndroid(
        apk: ApkInstallerAndroid(),
        tempDir: () async => tmp,
      );
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<File> stagedApk(String name, List<int> bytes) async {
      final dir = await installer.stagingDir();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      return f;
    }

    test('stagingDir = <temp>/updates, создаётся', () async {
      final dir = await installer.stagingDir();
      expect(dir.path.replaceAll('\\', '/'),
          '${tmp.path.replaceAll('\\', '/')}/updates');
      expect(dir.existsSync(), isTrue);
    });

    test('launch: файл цел и разрешение есть → installApk + pending.json',
        () async {
      final bytes = utf8.encode('apk-bytes');
      final f = await stagedApk('SilentGate-1.14.1-arm64-v8a.apk', bytes);
      await installer.launch(f,
          version: '1.14.1', expectedSha256: Sha256.ofBytes(bytes));
      final install = calls.where((c) => c.method == 'installApk');
      expect(install, hasLength(1));
      expect(install.single.arguments, {'path': f.path});

      final pending = File('${(await installer.stagingDir()).path}/pending.json');
      expect(pending.existsSync(), isTrue);
      final json = jsonDecode(pending.readAsStringSync()) as Map;
      expect(json['version'], '1.14.1');
      expect(json['exePath'], f.path);
      expect(json['logPath'], '', reason: 'журнала установщика на Android нет');
      expect(json['startedAt'], isA<String>());
    });

    test('⚠️ нет разрешения → NeedsInstallPermission, installApk НЕ вызван',
        () async {
      canInstall = false;
      final bytes = utf8.encode('apk');
      final f = await stagedApk('a.apk', bytes);
      await expectLater(
        installer.launch(f, version: '1.14.1', expectedSha256: Sha256.ofBytes(bytes)),
        throwsA(isA<NeedsInstallPermission>()),
      );
      expect(calls.any((c) => c.method == 'installApk'), isFalse);
      expect(
          File('${(await installer.stagingDir()).path}/pending.json')
              .existsSync(),
          isFalse);
    });

    test('⚠️ sha256 не совпал (файл подменён после проверки) → ни вызова, ни pending',
        () async {
      final f = await stagedApk('a.apk', utf8.encode('apk'));
      await expectLater(
        installer.launch(f,
            version: '1.14.1',
            expectedSha256: Sha256.ofBytes(utf8.encode('other'))),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(calls.any((c) => c.method == 'installApk'), isFalse);
      expect(calls.any((c) => c.method == 'canInstallPackages'), isFalse,
          reason: 'хэш сверяется раньше всего остального');
      expect(
          File('${(await installer.stagingDir()).path}/pending.json')
              .existsSync(),
          isFalse);
    });

    test('launch: установщик отказал → UpdateInstallException, pending снят',
        () async {
      installAnswer = false;
      final bytes = utf8.encode('apk');
      final f = await stagedApk('a.apk', bytes);
      await expectLater(
        installer.launch(f, version: '1.14.1', expectedSha256: Sha256.ofBytes(bytes)),
        throwsA(allOf(isA<UpdateInstallException>(),
            isNot(isA<NeedsInstallPermission>()))),
      );
      expect(
          File('${(await installer.stagingDir()).path}/pending.json')
              .existsSync(),
          isFalse);
    });

    group('reconcileAfterStart', () {
      Future<void> writePending(String version, DateTime startedAt) async {
        final dir = await installer.stagingDir();
        File('${dir.path}/pending.json').writeAsStringSync(jsonEncode({
          'version': version,
          'startedAt': startedAt.toUtc().toIso8601String(),
          'exePath': '${dir.path}/a.apk',
          'logPath': '',
        }));
        File('${dir.path}/a.apk').writeAsStringSync('apk');
      }

      test('нет pending.json → null', () async {
        expect(await installer.reconcileAfterStart(currentVersion: '1.14.0'), isNull);
      });

      test('версия совпала → updated, staging очищен', () async {
        await writePending('1.14.0', DateTime.now());
        final r = await installer.reconcileAfterStart(currentVersion: '1.14.0');
        expect(r, isNotNull);
        expect(r!.outcome, PendingOutcome.updated);
        expect(r.pending.version, '1.14.0');
        final dir = await installer.stagingDir();
        expect(File('${dir.path}/pending.json').existsSync(), isFalse);
        expect(File('${dir.path}/a.apk').existsSync(), isFalse);
      });

      test('версия не совпала, свежий → failed, хвоста лога нет', () async {
        await writePending('1.14.1', DateTime.now());
        final r = await installer.reconcileAfterStart(currentVersion: '1.14.0');
        expect(r!.outcome, PendingOutcome.failed);
        expect(r.logTail, isNull);
        expect(
            File('${(await installer.stagingDir()).path}/pending.json')
                .existsSync(),
            isFalse,
            reason: 'отчёт одноразовый — второй запуск не должен повторять его');
      });

      test('версия не совпала, старше 24 ч → stale', () async {
        await writePending(
            '1.14.1', DateTime.now().subtract(const Duration(hours: 25)));
        final r = await installer.reconcileAfterStart(currentVersion: '1.14.0');
        expect(r!.outcome, PendingOutcome.stale);
      });

      test('битый pending.json → null и файл убран', () async {
        final dir = await installer.stagingDir();
        File('${dir.path}/pending.json').writeAsStringSync('{not json');
        expect(await installer.reconcileAfterStart(currentVersion: '1.14.0'), isNull);
        expect(File('${dir.path}/pending.json').existsSync(), isFalse);
      });
    });

    test('purgeStaging удаляет всё, кроме keepVersion', () async {
      await stagedApk('SilentGate-1.14.1-arm64-v8a.apk', [1]);
      await stagedApk('SilentGate-1.14.2-arm64-v8a.apk', [2]);
      await stagedApk('SilentGate-1.14.3-arm64-v8a.apk.part', [3]);
      await installer.purgeStaging(keepVersion: '1.14.2');
      final dir = await installer.stagingDir();
      final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(names, {'SilentGate-1.14.2-arm64-v8a.apk'});
      await installer.purgeStaging();
      expect(dir.listSync(), isEmpty);
    });

    test('capability на Android всегда ready', () async {
      expect((await installer.capability()).name, 'ready');
    });

    // ⚠️ Выдача разрешения убивает процесс (живой прогон 24.09.2026): спросить
    // нужно ДО закачки, тем же вопросом, что задаёт launch.
    test('canInstallNow спрашивает canInstallPackages', () async {
      canInstall = false;
      expect(await installer.canInstallNow(), isFalse);
      canInstall = true;
      expect(await installer.canInstallNow(), isTrue);
      expect(calls.where((c) => c.method == 'canInstallPackages'), hasLength(2));
    });
  });
}
