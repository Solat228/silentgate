import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_store.dart';
import 'package:silentgate/core/privacy/device_info_consent.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/data_consent_dialog.dart';

/// Согласие на данные устройства в сборке Microsoft Store и раскрытие без
/// выбора в сборке GitHub (MS1 S8, решение владельца 19.10.2026).
void main() {
  const s = AppSettings.defaults;

  group('Сборка Microsoft Store', () {
    test('узнаётся по SILENTGATE_STORE, Play важнее', () {
      expect(AppStoreInfo.storeOf('', store: 'msstore'), AppStore.msstore);
      expect(AppStoreInfo.storeOf('', store: ' MSStore '), AppStore.msstore);
      expect(AppStoreInfo.storeOf('', store: 'store'), AppStore.github,
          reason: 'неизвестное имя — GitHub');
      expect(AppStoreInfo.storeOf('play', store: 'msstore'), AppStore.play);
      expect(AppStoreInfo.asksDataConsent(AppStore.msstore), isTrue);
      expect(AppStoreInfo.asksDataConsent(AppStore.play), isTrue);
      expect(AppStoreInfo.asksDataConsent(AppStore.github), isFalse);
    });

    test('⚠️ без ответа спрашиваем и до ответа НЕ отправляем', () {
      expect(DeviceInfoConsent.needsAsking(s, store: AppStore.msstore), isTrue);
      expect(DeviceInfoConsent.allowed(s, store: AppStore.msstore), isFalse);
      expect(DeviceInfoConsent.needsNotice(s, store: AppStore.msstore),
          isFalse,
          reason: 'в магазине вместо сообщения — окно согласия');
    });

    test('отзыв согласия действует сразу', () {
      final yes = s.copyWith(deviceInfoConsent: true);
      final revoked = yes.copyWith(deviceInfoConsent: false);
      expect(DeviceInfoConsent.allowed(yes, store: AppStore.msstore), isTrue);
      expect(
          DeviceInfoConsent.allowed(revoked, store: AppStore.msstore), isFalse);
      expect(DeviceInfoConsent.needsAsking(revoked, store: AppStore.msstore),
          isFalse,
          reason: 'отказ — тоже ответ, переспрашивать на старте нельзя');
    });
  });

  group('Сборка GitHub: только сообщение', () {
    test('один раз, данные уходят как раньше', () {
      expect(DeviceInfoConsent.needsNotice(s, store: AppStore.github), isTrue);
      expect(DeviceInfoConsent.allowed(s, store: AppStore.github), isTrue);
      final shown = s.copyWith(deviceInfoNoticeShown: true);
      expect(
          DeviceInfoConsent.needsNotice(shown, store: AppStore.github), isFalse);
    });

    test('флаг переживает запись на диск', () {
      final back = AppSettings.fromJson(
          s.copyWith(deviceInfoNoticeShown: true).toJson());
      expect(back.deviceInfoNoticeShown, isTrue);
      expect(AppSettings.fromJson(const {}).deviceInfoNoticeShown, isFalse);
    });
  });

  group('Окно', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(1200, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: w),
      ));
    }

    testWidgets('сообщение GitHub: одна кнопка, без «Не отправлять»',
        (t) async {
      await pump(t, const DataConsentDialog(noticeOnly: true, windows: true));
      expect(find.byKey(const Key('consentNoticeOk')), findsOneWidget);
      expect(find.byKey(const Key('consentDecline')), findsNothing);
      expect(find.byKey(const Key('consentAccept')), findsNothing);
      expect(find.textContaining('HWID'), findsOneWidget);
    });

    testWidgets('согласие: два равноправных ответа, текст по платформе',
        (t) async {
      await pump(t, const DataConsentDialog(windows: false));
      expect(find.byKey(const Key('consentDecline')), findsOneWidget);
      expect(find.byKey(const Key('consentAccept')), findsOneWidget);
      expect(find.textContaining('Android ID'), findsOneWidget);
    });
  });
}
