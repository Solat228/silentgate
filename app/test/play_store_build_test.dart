import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_store.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/platform/play_store_android.dart';
import 'package:silentgate/core/privacy/device_info_consent.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// Сборка Google Play против сборки GitHub: что их различает в Dart.
///
/// ⚠️ Две вещи здесь — требования правил Google Play, а не вкус:
///  * данные устройства (ANDROID_ID, модель, версия ОС) не уходят провайдеру
///    подписки, пока человек не согласился в окне раскрытия;
///  * сборка Play не обновляет себя мимо Play (это стережёт
///    `app_update_controller_test`, здесь — только определение сборки).
class _FakeDevice implements DeviceIdProvider {
  @override
  Future<String> hwid() async => 'a1b2c3d4e5f60718';
  @override
  String osName() => 'Android';
  @override
  Future<String> osVersion() async => '14';
  @override
  Future<String> deviceModel() async => 'Pixel 8';
}

void main() {
  group('AppStoreInfo', () {
    test('play — только флейвор play', () {
      expect(AppStoreInfo.storeOf('play'), AppStore.play);
      expect(AppStoreInfo.storeOf(' Play '), AppStore.play);
      expect(AppStoreInfo.storeOf('github'), AppStore.github);
      expect(AppStoreInfo.storeOf(''), AppStore.github,
          reason: 'Windows и тесты собираются без флейвора');
      expect(AppStoreInfo.storeOf('playstore'), AppStore.github,
          reason: 'неизвестное имя — GitHub: лишить сборку обновлений хуже');
    });

    test('тесты идут как сборка GitHub', () {
      expect(AppStoreInfo.current, AppStore.github);
      expect(AppStoreInfo.isPlay, isFalse);
    });

    test('адреса страницы в Play и политики', () {
      expect(AppStoreInfo.playStoreUrl,
          'https://play.google.com/store/apps/details?id=lol.silentgate');
      expect(AppStoreInfo.privacyPolicyUrl, startsWith('https://'));
    });

    test('⚠️ Play-first выключен, пока страница в Play не открыта всем', () {
      // На закрытом тесте страницу видят только тестировщики: остальным
      // кнопка «Обновить в Google Play» открыла бы «приложение не найдено».
      // Переключать в выпуске ПОСЛЕ публикации в production.
      expect(AppStoreInfo.playListingLive, isFalse);
    });
  });

  group('DeviceInfoConsent', () {
    const asked = AppSettings.defaults;

    test('GitHub: не спрашиваем, данные уходят как раньше', () {
      expect(DeviceInfoConsent.needsAsking(asked, store: AppStore.github),
          isFalse);
      expect(DeviceInfoConsent.allowed(asked, store: AppStore.github), isTrue);
      expect(
          DeviceInfoConsent.allowed(
              asked.copyWith(deviceInfoConsent: false),
              store: AppStore.github),
          isTrue,
          reason: 'в сборке GitHub окна нет, и ответ ничего не меняет');
    });

    test('⚠️ Play без ответа: спрашиваем, и до ответа НЕ отправляем', () {
      expect(DeviceInfoConsent.needsAsking(asked, store: AppStore.play),
          isTrue);
      expect(DeviceInfoConsent.allowed(asked, store: AppStore.play), isFalse);
    });

    test('Play: «Разрешить» и «Не отправлять»', () {
      final yes = asked.copyWith(deviceInfoConsent: true);
      final no = asked.copyWith(deviceInfoConsent: false);
      expect(DeviceInfoConsent.needsAsking(yes, store: AppStore.play), isFalse);
      expect(DeviceInfoConsent.needsAsking(no, store: AppStore.play), isFalse);
      expect(DeviceInfoConsent.allowed(yes, store: AppStore.play), isTrue);
      expect(DeviceInfoConsent.allowed(no, store: AppStore.play), isFalse);
    });

    test('фильтр убирает данные устройства и оставляет остальное', () {
      final h = {
        'X-HWID': 'x',
        'X-Device-OS': 'Android',
        'X-Ver-OS': '14',
        'X-Device-Model': 'Pixel',
        'X-App-Version': '1.15.3',
      };
      expect(DeviceInfoConsent.filter(h, allowed: true), h);
      expect(DeviceInfoConsent.filter(h, allowed: false),
          {'X-App-Version': '1.15.3'});
    });

    test('⚠️ каждый заголовок DeviceHeaders.build под согласием', () async {
      // Новый заголовок устройства, добавленный в build() и забытый здесь,
      // ушёл бы провайдеру без согласия — и окно раскрытия стало бы враньём.
      setDeviceIdProviderForTests(_FakeDevice());
      addTearDown(() => setDeviceIdProviderForTests(null));
      final built = await DeviceHeaders.build();
      expect(built, isNotEmpty);
      expect(DeviceInfoConsent.gatedHeaders, containsAll(built.keys));
      expect(DeviceInfoConsent.filter(built, allowed: false), isEmpty);
    });

    test('согласие переживает запись настроек на диск', () {
      for (final v in [null, true, false]) {
        final s = AppSettings.fromJson(
            AppSettings.defaults.copyWith(deviceInfoConsent: v).toJson());
        expect(s.deviceInfoConsent, v);
      }
      expect(AppSettings.fromJson({'deviceInfoConsent': 'yes'})
          .deviceInfoConsent, isNull,
          reason: 'мусор в файле = «ещё не спрашивали», а не «разрешено»');
    });

    test('⚠️ запросы подписки идут через фильтр согласия', () {
      // Единственное место, где собираются заголовки подписки: оба вызова
      // `fetch` берут их из `_deviceHeaders()`.
      final src = File('lib/state/app_state.dart').readAsStringSync()
          .replaceAll('\r\n', '\n');
      final at = src.indexOf('Future<Map<String, String>> _deviceHeaders()');
      expect(at, greaterThan(0));
      final body = src.substring(at, src.indexOf('\n  }\n', at));
      expect(body, contains('DeviceInfoConsent.filter('));
      expect(body, contains('DeviceInfoConsent.allowed('));
      expect(
          RegExp(r'DeviceHeaders\.build\(\)').allMatches(src).length, 1,
          reason: 'второй сборщик заголовков обошёл бы согласие');
    });
  });

  test('⚠️ плитка «Обновления» в сборке Play не обещает закачку', () {
    final l = AppLocalizationsRu();
    expect(updatesTileSubtitle(l, store: AppStore.play),
        l.updatesSettingsTilePlay);
    expect(updatesTileSubtitle(l, store: AppStore.play),
        isNot(contains('скач')));
    expect(updatesTileSubtitle(l, store: AppStore.github),
        l.updatesSettingsTileSubtitle);
    expect(updatesTileSubtitle(l), l.updatesSettingsTileSubtitle,
        reason: 'тесты идут как сборка GitHub');
  });

  group('PlayStoreAndroid', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('методы канала и ответы', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      final p = PlayStoreAndroid(launcher: channel);
      expect(await p.installed(), isTrue);
      expect(await p.open(), isTrue);
      expect(calls, ['playStoreInstalled', 'openPlayStore']);
    });

    test('сбой канала — «Play нет», без исключения', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'x'));
      final p = PlayStoreAndroid(launcher: channel);
      expect(await p.installed(), isFalse);
      expect(await p.open(), isFalse);
    });
  });
}
