import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_store.dart';
import 'package:silentgate/core/platform/package_identity_windows.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/update/msix_packaging.dart';
import 'package:silentgate/data/settings_storage.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/tun/tun_task_auto_setup.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// Пакет MSIX (Microsoft Store): путь запуска, права для TUN, умолчания,
/// манифест. Разведка — VM SG-Test 21.10.2026.
void main() {
  final sep = Platform.pathSeparator;
  String repo(String rel) => '..$sep${rel.replaceAll('/', sep)}';

  group('Путь запуска', () {
    test('псевдоним — в WindowsApps профиля', () {
      expect(
          PackageIdentity.aliasPath(env: {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'}),
          r'C:\Users\u\AppData\Local\Microsoft\WindowsApps\silentgate.exe');
      expect(PackageIdentity.aliasPath(env: const {}), isNull);
      expect(PackageIdentity.aliasPath(env: {'LOCALAPPDATA': ''}), isNull);
    });

    test('⚠️ в пакете — псевдоним: папка пакета меняется с версией', () {
      const exe =
          r'C:\Program Files\WindowsApps\SilentGate_1.17.0.0_x64__abc\silentgate.exe';
      const alias = r'C:\Users\u\AppData\Local\Microsoft\WindowsApps\silentgate.exe';
      expect(
          PackageIdentity.launchPathFor(packaged: true, exe: exe, alias: alias),
          alias);
      expect(
          PackageIdentity.launchPathFor(packaged: false, exe: exe, alias: alias),
          exe);
      expect(
          PackageIdentity.launchPathFor(packaged: true, exe: exe, alias: null),
          exe,
          reason: 'без LOCALAPPDATA — хоть что-то, а не пустая строка');
    });

    test('процесс тестов не пакет', () {
      PackageIdentity.debugPackaged = null;
      expect(PackageIdentity.isPackaged, isFalse);
    });
  });

  group('Права для TUN в пакете', () {
    const tun = AppSettings(captureMode: CaptureMode.tun);

    test('задача ставится сама только в пакете, в TUN и без отказа', () {
      expect(TunTaskAutoSetup.wanted(packaged: true, settings: tun), isTrue);
      expect(TunTaskAutoSetup.wanted(packaged: false, settings: tun), isFalse);
      expect(
          TunTaskAutoSetup.wanted(
              packaged: true,
              settings: tun.copyWith(captureMode: CaptureMode.systemProxy)),
          isFalse);
      expect(
          TunTaskAutoSetup.wanted(
              packaged: true, settings: tun.copyWith(tunTaskDeclined: true)),
          isFalse,
          reason: 'человек выбрал окно UAC на каждое подключение');
    });

    test('задача есть — не ставится повторно', () async {
      var installs = 0;
      await TunTaskAutoSetup.ensure(tun,
          packaged: true,
          configured: () async => true,
          install: () async {
            installs++;
            return PrivilegeSetupResult.done;
          });
      expect(installs, 0);
    });

    test('задачи нет — ставится один раз', () async {
      var installs = 0;
      await TunTaskAutoSetup.ensure(tun,
          packaged: true,
          configured: () async => false,
          install: () async {
            installs++;
            return PrivilegeSetupResult.done;
          });
      expect(installs, 1);
    });

    test('⚠️ отказ в UAC останавливает подключение, второй раз не спрашивает',
        () async {
      await expectLater(
          TunTaskAutoSetup.ensure(tun,
              packaged: true,
              configured: () async => false,
              install: () async => PrivilegeSetupResult.denied),
          throwsA(isA<TunElevationDenied>()));
    });

    test('сбой постановки — прежний путь (окно UAC), без исключения', () async {
      await TunTaskAutoSetup.ensure(tun,
          packaged: true,
          configured: () async => false,
          install: () async => PrivilegeSetupResult.failed);
    });

    test('вне пакета не трогает ни проверку, ни постановку', () async {
      var calls = 0;
      await TunTaskAutoSetup.ensure(tun,
          packaged: false,
          configured: () async {
            calls++;
            return false;
          },
          install: () async {
            calls++;
            return PrivilegeSetupResult.done;
          });
      expect(calls, 0);
    });

    test('отказ от задачи переживает сохранение настроек', () {
      final j = tun.copyWith(tunTaskDeclined: true).toJson();
      expect(AppSettings.fromJson(j).tunTaskDeclined, isTrue);
      expect(AppSettings.fromJson(const {}).tunTaskDeclined, isFalse);
    });
  });

  group('Умолчания пакета', () {
    test('первый запуск в пакете — TUN, вне пакета — прежнее умолчание', () {
      expect(SettingsStorage.firstRunDefaults(packaged: true).captureMode,
          CaptureMode.tun);
      expect(SettingsStorage.firstRunDefaults(packaged: false).captureMode,
          AppSettings.defaults.captureMode);
    });

    testWidgets('плитка «Обновления» в пакете ведёт в Microsoft Store',
        (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          l = AppLocalizations.of(context);
          return const SizedBox();
        }),
      ));
      expect(updatesTileSubtitle(l, msStorePackage: true),
          l.updatesSettingsTileMsStore);
      expect(
          updatesTileSubtitle(l, store: AppStore.msstore, msStorePackage: false),
          l.updatesSettingsTileSubtitle,
          reason: 'флаг сборки Store без пакета — обычная установка');
      expect(updatesTileSubtitle(l, store: AppStore.play, msStorePackage: false),
          l.updatesSettingsTilePlay);
    });
  });

  group('Сборка пакета', () {
    test('версия пакета: четвёртое число — ноль, номер сборки не идёт', () {
      expect(msixVersion('1.17.0+88'), '1.17.0.0');
      expect(msixVersion('1.17.0-beta.1+90'), '1.17.0.0');
      expect(() => msixVersion('1.17'), throwsFormatException);
    });

    test('в пакет не едут .bak и uninstall.bat', () {
      expect(msixExcluded('geoip.dat.bak'), isTrue);
      expect(msixExcluded('uninstall.bat'), isTrue);
      expect(msixExcluded(r'data\flutter_assets\x.bak'), isTrue);
      expect(msixExcluded('geoip.dat'), isFalse);
      expect(msixExcluded('wintun.dll'), isFalse);
      expect(msixExcluded(r'licenses\GPL-3.0.txt'), isFalse);
    });

    String render({String publisher = 'CN=TEST'}) => renderMsixManifest(
          File(repo('installer/msix/AppxManifest.xml')).readAsStringSync(),
          identityName: 'Test.SilentGate',
          publisher: publisher,
          publisherDisplayName: 'SilentGate',
          displayName: 'SilentGate',
          description: 'SilentGate VPN',
          version: '1.17.0.0',
        );

    test('шаблон заполняется целиком', () {
      final m = render(publisher: 'CN=A & B, O="C"');
      expect(m, isNot(contains('{{')));
      expect(m, contains('Name="Test.SilentGate"'));
      expect(m, contains('Publisher="CN=A &amp; B, O=&quot;C&quot;"'));
      expect(m, contains('Version="1.17.0.0"'));
      for (final lang in msixLanguages) {
        expect(m, contains('<Resource Language="$lang"/>'));
      }
    });

    test('пустая идентификация — ошибка, а не пакет с дырой', () {
      expect(() => render(publisher: ''), throwsFormatException);
    });

    test('⚠️ псевдоним манифеста = PackageIdentity.aliasName', () {
      final m = render();
      final alias = RegExp(r'ExecutionAlias Alias="([^"]+)"').firstMatch(m);
      expect(alias?.group(1), PackageIdentity.aliasName,
          reason: 'иначе задача Планировщика, автозапуск и перезапуск '
              'указывали бы в пустоту');
    });

    test('⚠️ манифест: схема silentgate://, права, без unvirtualizedResources',
        () {
      final m = render();
      expect(m, contains('<uap:Protocol Name="silentgate">'));
      expect(m, contains('rescap:Capability Name="runFullTrust"'));
      expect(m, contains('rescap:Capability Name="allowElevation"'));
      expect(m, isNot(contains('unvirtualizedResources')),
          reason: 'разведка: без него всё работает, а Store его проверяет '
              'строже');
      expect(m, contains('Executable="silentgate.exe"'));
    });

    test('картинки, на которые ссылается манифест, лежат в Assets', () {
      final m = render();
      final refs = RegExp(r'Assets\\([A-Za-z0-9_.-]+\.png)')
          .allMatches(m)
          .map((e) => e[1]!)
          .toSet();
      expect(refs, isNotEmpty);
      for (final r in refs) {
        expect(File(repo('installer/msix/Assets/$r')).existsSync(), isTrue,
            reason: r);
      }
    });

    test('языки пакета — те же, что у интерфейса', () {
      final arbs = Directory('lib${sep}l10n')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('app_') && n.endsWith('.arb'))
          .map((n) => n.substring(4, n.length - 4))
          .toSet();
      final pkg = msixLanguages.map((l) => l.split('-').first).toSet();
      expect(pkg, arbs);
    });
  });
}
