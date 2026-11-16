import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_store.dart';
import 'package:silentgate/core/privacy/device_info_consent.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/ui/update_screen.dart';
import 'package:silentgate/ui/widgets/data_consent_dialog.dart';
import 'package:silentgate/ui/widgets/update_dialog.dart';

import 'helpers/update_ui_harness.dart';

/// Интерфейс двух сборок: Google Play и GitHub.
///
/// Что стережётся:
///  * сборка Play не показывает НИЧЕГО, что качает или ставит APK, — только
///    «Открыть в Google Play» (правило Play «Device and Network Abuse»);
///  * сборка GitHub при установленном Play делает Play главной кнопкой, а
///    закачку с GitHub оставляет запасной — и обе работают;
///  * окно согласия на первом запуске нельзя смахнуть, отказ — равноправный
///    ответ и записывается так же, как согласие.
void main() {
  late UpdateUiHarness h;

  tearDown(() => h.dispose());

  Future<void> show(WidgetTester t, Widget child,
      {Size size = const Size(800, 1400)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(h.wrap(child));
    await t.pumpAndSettle();
  }

  /// Проверка при запуске — там же контроллер узнаёт, есть ли Google Play.
  Future<void> startupWithOffer(WidgetTester t, {bool beta = false}) async {
    final r = h.publish('1.14.1', beta: beta);
    h.checkResult = () => UpdateCheckResult.available(r);
    await t.runAsync(() => h.controller.startup());
  }

  group('Сборка Google Play', () {
    testWidgets('⚠️ экран обновлений: только «Открыть в Google Play»',
        (t) async {
      h = UpdateUiHarness.create(store: AppStore.play);
      await startupWithOffer(t);
      await show(t, const UpdateScreen());

      expect(find.byKey(const Key('updatesOpenPlayButton')), findsOneWidget);
      for (final k in const [
        'updatesDownloadButton',
        'updatesPlayButton',
        'updatesOpenPageButton',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.byType(RadioListTile<AppUpdateMode>), findsNothing,
          reason: 'режимы самообновления в сборке Play не имеют смысла');

      await t.tap(find.byKey(const Key('updatesOpenPlayButton')));
      await t.pump();
      expect(h.playOpened, 1);
      expect(h.installer.launches, isEmpty);
    });

    testWidgets('на телефоне 360 dp без переполнений', (t) async {
      h = UpdateUiHarness.create(store: AppStore.play);
      await show(t, const UpdateScreen(), size: const Size(360, 640));
      expect(t.takeException(), isNull);
    });
  });

  group('Сборка GitHub при установленном Google Play', () {
    testWidgets('экран: Play главной кнопкой, закачка — запасной', (t) async {
      h = UpdateUiHarness.create(playAvailable: true);
      await startupWithOffer(t);
      expect(h.controller.offerViaPlay, isTrue);
      await show(t, const UpdateScreen());

      final play = find.byKey(const Key('updatesPlayButton'));
      final download = find.byKey(const Key('updatesDownloadButton'));
      expect(play, findsOneWidget);
      expect(download, findsOneWidget);
      expect(
          find
              .descendant(of: download, matching: find.byType(Text))
              .evaluate()
              .map((e) => (e.widget as Text).data),
          contains('Скачать с GitHub'));

      await t.tap(play);
      await t.pump();
      expect(h.playOpened, 1);
    });

    testWidgets('окно: «Обновить в Google Play» и «Скачать с GitHub»',
        (t) async {
      h = UpdateUiHarness.create(playAvailable: true);
      await startupWithOffer(t);
      await show(
          t,
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showUpdateDialog(context, h.controller),
                child: const Text('открыть'),
              ),
            ),
          ),
          size: const Size(360, 800));
      await t.tap(find.text('открыть'));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('updateDialogPlay')), findsOneWidget);
      expect(find.byKey(const Key('updateDialogGithub')), findsOneWidget);
      expect(find.byKey(const Key('updateDialogInstall')), findsNothing,
          reason: 'главная кнопка — Play, закачка не дублируется');

      await t.tap(find.byKey(const Key('updateDialogPlay')));
      await t.pumpAndSettle();
      expect(h.playOpened, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('бета — без Play: в Play бет нет', (t) async {
      h = UpdateUiHarness.create(playAvailable: true);
      await startupWithOffer(t, beta: true);
      expect(h.controller.offerViaPlay, isFalse);
      await show(t, const UpdateScreen());
      expect(find.byKey(const Key('updatesPlayButton')), findsNothing);
    });
  });

  group('Окно согласия на данные устройства', () {
    Widget opener({bool mandatory = true}) => Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => askDataConsentIfNeeded(context, h.settings,
                  needsAsking: () => DeviceInfoConsent.needsAsking(
                      h.settings.settings,
                      store: AppStore.play)),
              child: const Text('старт'),
            ),
          ),
        );

    Future<void> openConsent(WidgetTester t,
        {Size size = const Size(360, 640)}) async {
      h = UpdateUiHarness.create();
      await t.runAsync(() => h.settings.init());
      await show(t, opener(), size: size);
      await t.tap(find.text('старт'));
      await t.pumpAndSettle();
    }

    testWidgets('⚠️ первый запуск: смахнуть нельзя, нужен ответ', (t) async {
      await openConsent(t);
      expect(find.byType(DataConsentDialog), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tapAt(const Offset(5, 5)); // мимо окна
      await t.pumpAndSettle();
      expect(find.byType(DataConsentDialog), findsOneWidget);
      expect(h.settings.settings.deviceInfoConsent, isNull);
    });

    testWidgets('«Разрешить» записывает согласие', (t) async {
      await openConsent(t);
      await t.tap(find.byKey(const Key('consentAccept')));
      await t.pumpAndSettle();
      expect(find.byType(DataConsentDialog), findsNothing);
      expect(h.settings.settings.deviceInfoConsent, isTrue);
    });

    testWidgets('«Не отправлять» записывает отказ — второй раз не спросим',
        (t) async {
      await openConsent(t);
      await t.tap(find.byKey(const Key('consentDecline')));
      await t.pumpAndSettle();
      expect(h.settings.settings.deviceInfoConsent, isFalse);

      await t.tap(find.text('старт'));
      await t.pumpAndSettle();
      expect(find.byType(DataConsentDialog), findsNothing,
          reason: 'ответ дан — окно больше не показывается');
    });

    testWidgets('⚠️ ссылка на политику — над длинным текстом, не в конце',
        (t) async {
      // Живьём в эмуляторе кнопка стояла в конце прокрутки и на телефоне не
      // была видна вовсе: человек не знал, что политику можно открыть.
      // Видимость без прокрутки здесь не проверить — тестовый шрифт
      // квадратный и раздувает абзацы; проверяем порядок.
      await openConsent(t, size: const Size(360, 800));
      final policy = find.byKey(const Key('consentPolicyButton'));
      expect(policy, findsOneWidget);
      expect(
          t.getRect(policy).top,
          lessThan(t
              .getRect(find.text('Данные устройства для вашего провайдера'))
              .top));
    });
  });
}
