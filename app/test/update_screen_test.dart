import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/update_installer.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_update_controller.dart';
import 'package:silentgate/ui/update_screen.dart';
import 'package:silentgate/ui/widgets/update_dialog.dart';

import 'helpers/update_ui_harness.dart';

/// ЭКРАН «ОБНОВЛЕНИЯ».
///
/// Что стережётся:
///  * каждая фаза контроллера показывает СВОИ кнопки — и не показывает чужих
///    (кнопка «Скачать» там, где ставить нельзя, — обманка);
///  * «только ссылка» называет ПРИЧИНУ: «установите вручную» без объяснения
///    человек читает как поломку;
///  * подменённый источник виден сразу — плашкой наверху;
///  * выбор режима пишется в настройки;
///  * на телефоне 360 dp ничего не переполняется (и на арабском — RTL).
void main() {
  late UpdateUiHarness h;

  setUp(() {
    h = UpdateUiHarness.create();
  });

  tearDown(() => h.dispose());

  AppLocalizations ru() => lookupAppLocalizations(const Locale('ru'));

  Future<void> show(WidgetTester t,
      {Size size = const Size(800, 1400),
      Locale locale = const Locale('ru'),
      ReleaseHistoryLoader? history}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        h.wrap(UpdateScreen(releaseHistory: history), locale: locale));
    await t.pumpAndSettle();
  }

  Future<AppRelease> offer({String version = '1.14.1', bool selfUpdate = true}) async {
    final r = h.publish(version, selfUpdate: selfUpdate);
    h.checkResult = () => UpdateCheckResult.available(r);
    await h.controller.checkNow();
    return r;
  }

  /// После запуска установщика фаза остаётся «установка» с бегущей полоской
  /// (на Windows приложение закроет установщик, на Android — ждём системное
  /// окно), поэтому `pumpAndSettle` там не дождётся конца никогда.
  Future<void> pumpSome(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  String statusText(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('updatesStatusText'))).data ?? '';

  group('Фазы — свои кнопки', () {
    testWidgets('нет проверки: только «Проверить сейчас»', (t) async {
      await show(t);
      expect(find.byKey(const Key('updatesCheckButton')), findsOneWidget);
      expect(find.byKey(const Key('updatesDownloadButton')), findsNothing);
      expect(find.byKey(const Key('updatesInstallButton')), findsNothing);
      expect(find.byKey(const Key('updatesOpenPageButton')), findsNothing);
    });

    testWidgets('«Проверить сейчас» → последняя версия', (t) async {
      await show(t);
      await t.tap(find.byKey(const Key('updatesCheckButton')));
      await t.pumpAndSettle();
      expect(h.controller.phase, UpdatePhase.upToDate);
      expect(statusText(t), ru().updatesStatusUpToDate);
    });

    testWidgets('доступна → «Скачать» → готово → «Установить»', (t) async {
      await offer();
      await show(t);
      expect(statusText(t), ru().updatesStatusAvailable('1.14.1'));
      expect(find.byKey(const Key('updatesDownloadButton')), findsOneWidget);

      await t.tap(find.byKey(const Key('updatesDownloadButton')));
      await t.pumpAndSettle();
      expect(h.controller.phase, UpdatePhase.ready);
      expect(find.byKey(const Key('updatesDownloadButton')), findsNothing);
      expect(find.byKey(const Key('updatesInstallButton')), findsOneWidget);

      await t.tap(find.byKey(const Key('updatesInstallButton')));
      await pumpSome(t);
      expect(h.installer.launches, hasLength(1));
      expect(h.installer.launches.single.forceQuit, isFalse);
    });

    testWidgets('идёт загрузка: полоска и «Отмена», отмена возвращает назад',
        (t) async {
      await offer();
      h.downloadGate = Completer<void>();
      await show(t);
      await t.tap(find.byKey(const Key('updatesDownloadButton')));
      await t.pump();
      await t.pump();
      expect(h.controller.phase, UpdatePhase.downloading);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('updatesCancelButton')), findsOneWidget);
      expect(find.byKey(const Key('updatesCheckButton')), findsOneWidget);
      expect(
          t
              .widget<FilledButton>(find.byKey(const Key('updatesCheckButton')))
              .onPressed,
          isNull,
          reason: 'проверка поверх закачки перепутала бы состояние');

      await t.tap(find.byKey(const Key('updatesCancelButton')));
      h.downloadGate!.complete();
      await t.pumpAndSettle();
      expect(h.controller.phase, UpdatePhase.available);
      expect(h.installer.launches, isEmpty);
    });

    testWidgets('⚠️ живой VPN: «Установить» сначала спрашивает', (t) async {
      await offer();
      await h.controller.download();
      h.vpnActive = true;
      await show(t);
      await t.tap(find.byKey(const Key('updatesInstallButton')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('updateVpnConfirmOk')), findsOneWidget);

      await t.tap(find.byKey(const Key('updateVpnConfirmCancel')));
      await t.pumpAndSettle();
      expect(h.installer.launches, isEmpty,
          reason: 'без согласия VPN не рвём');

      await t.tap(find.byKey(const Key('updatesInstallButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('updateVpnConfirmOk')));
      await pumpSome(t);
      expect(h.installer.launches.single.forceQuit, isTrue);
    });

    testWidgets('установка ждёт отключения VPN — так и написано', (t) async {
      await offer();
      await h.controller.download();
      h.vpnActive = true;
      await h.controller.install();
      expect(h.controller.waitingForVpnOff, isTrue);
      await show(t);
      expect(statusText(t), ru().updatesWaitingVpn);
      expect(find.byKey(const Key('updatesInstallNowButton')), findsOneWidget);
    });

    testWidgets('отказ называет причину и даёт повторить', (t) async {
      final r = h.publish('1.14.1');
      // Подпись испорчена — отказ badSignature.
      h.routes[r.signatureUrl!] = 'bad'.codeUnits;
      h.checkResult = () => UpdateCheckResult.available(r);
      await h.controller.checkNow();
      await h.controller.download();
      expect(h.controller.phase, UpdatePhase.failed);
      await show(t);
      expect(statusText(t),
          ru().updatesStatusFailed(ru().updatesErrSignature));
      expect(find.byKey(const Key('updatesRetryButton')), findsOneWidget);
    });

    testWidgets('пропущенная версия видна как пропущенная', (t) async {
      await offer();
      await h.controller.skipVersion();
      await show(t);
      expect(statusText(t), ru().updatesSkippedNote('1.14.1'));
      expect(find.byKey(const Key('updatesDownloadButton')), findsNothing);
    });
  });

  group('«Только ссылка» — с причиной', () {
    final reasons = <InstallCapability, String Function(AppLocalizations)>{
      InstallCapability.portable: (l) => l.updatesPortableFallback,
      InstallCapability.notInstalled: (l) => l.updatesPortableFallback,
      InstallCapability.isolated: (l) => l.updatesLinkIsolated,
      InstallCapability.locationMismatch: (l) => l.updatesLinkLocation,
      InstallCapability.elevated: (l) => l.updatesLinkElevated,
      InstallCapability.unsupported: (l) => l.updatesLinkUnsupported,
    };
    for (final e in reasons.entries) {
      testWidgets('${e.key.name}: «Скачать» нет, причина и страница есть',
          (t) async {
        h.installer.capabilityResult = e.key;
        await offer();
        await show(t);
        expect(find.byKey(const Key('updatesDownloadButton')), findsNothing,
            reason: 'ставить самим нельзя — кнопка была бы обманкой');
        expect(find.byKey(const Key('updatesOpenPageButton')), findsOneWidget);
        expect(find.text(e.value(ru())), findsOneWidget);
      });
    }

    testWidgets('у релиза нет подписанного установщика', (t) async {
      await offer(selfUpdate: false);
      await show(t);
      expect(find.byKey(const Key('updatesDownloadButton')), findsNothing);
      expect(find.text(ru().updatesLinkNoSelfUpdate), findsOneWidget);
    });

    testWidgets('режим «только уведомлять» объясняет себя', (t) async {
      unawaited(h.settings.update(
          (s) => s.copyWith(appUpdateMode: AppUpdateMode.notifyOnly)));
      await offer();
      expect(h.controller.phase, UpdatePhase.linkOnly);
      await show(t);
      expect(find.text(ru().updatesLinkNotify), findsOneWidget);
      expect(find.byKey(const Key('updatesOpenPageButton')), findsOneWidget);
    });

    test('каждая причина и каждый отказ имеют свой текст', () {
      final l = ru();
      for (final r in LinkOnlyReason.values) {
        expect(linkOnlyReasonText(l, r), isNotEmpty, reason: r.name);
      }
      for (final k in UpdateErrorKind.values) {
        expect(updateErrorText(l, UpdateError(k)), isNotEmpty, reason: k.name);
      }
    });
  });

  group('Настройки и плашки', () {
    testWidgets('подменённый источник — плашка наверху', (t) async {
      await show(t);
      expect(find.byKey(const Key('updatesOverrideBanner')), findsNothing);
      h.overridden = true;
      await t.pumpWidget(Container());
      await show(t);
      expect(find.byKey(const Key('updatesOverrideBanner')), findsOneWidget);
    });

    testWidgets('⚠️ режим пишется в настройки', (t) async {
      if (!(Platform.isWindows || Platform.isAndroid)) return;
      await show(t);
      expect(h.settings.settings.appUpdateMode, AppUpdateMode.ask);
      await t.tap(find.byKey(const ValueKey('updatesMode-auto')));
      await t.pumpAndSettle();
      expect(h.settings.settings.appUpdateMode, AppUpdateMode.auto);
      await t.tap(find.byKey(const ValueKey('updatesMode-notifyOnly')));
      await t.pumpAndSettle();
      expect(h.settings.settings.appUpdateMode, AppUpdateMode.notifyOnly);
    });

    testWidgets('переключатели проверки и бета-канала пишутся в настройки',
        (t) async {
      await show(t);
      final wasCheck = h.settings.settings.appUpdateCheck;
      await t.tap(find.byKey(const Key('updatesAutoCheckSwitch')));
      await t.pumpAndSettle();
      expect(h.settings.settings.appUpdateCheck, !wasCheck);

      expect(h.settings.settings.betaChannel, isFalse);
      await t.tap(find.byKey(const Key('updatesBetaSwitch')));
      await t.pumpAndSettle();
      expect(h.settings.settings.betaChannel, isTrue);
    });
  });

  group('Прежние версии', () {
    testWidgets('⚠️ откат: подтверждение → закачка → установка с allowDowngrade',
        (t) async {
      if (!Platform.isWindows) return; // откат ставится только на Windows
      final old = h.publish('1.13.2', beta: true);
      await show(t, history: () async => [old]);
      await t.tap(find.byKey(const Key('updatesPreviousVersionsTile')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('updatesInstallOlder-1.13.2')));
      await t.pumpAndSettle();
      // Подтверждение отката.
      expect(find.text(ru().updatesDowngradeWarning), findsOneWidget);
      await t.tap(find.byKey(const Key('updatesRollbackConfirm')));
      await pumpSome(t);

      expect(h.installer.launches, hasLength(1),
          reason: 'бета из истории ставится и при выключенном бета-канале');
      expect(h.installer.launches.single.version, '1.13.2');
      expect(h.installer.launches.single.allowDowngrade, isTrue);
    });

    testWidgets('где ставить нельзя — только «Открыть»', (t) async {
      h.installer.capabilityResult = InstallCapability.portable;
      final old = h.publish('1.13.2');
      await show(t, history: () async => [old]);
      await t.tap(find.byKey(const Key('updatesPreviousVersionsTile')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('updatesInstallOlder-1.13.2')), findsNothing);
      expect(find.byKey(const Key('updatesOpenRelease-1.13.2')), findsOneWidget);
    });
  });

  group('Вёрстка', () {
    for (final locale in const [Locale('ru'), Locale('ar'), Locale('de')]) {
      testWidgets('телефон 360 dp (${locale.languageCode}) — без переполнений',
          (t) async {
        await offer();
        h.installer.capabilityResult = InstallCapability.portable;
        await show(t, size: const Size(360, 640), locale: locale);
        expect(t.takeException(), isNull);
        // Прокрутить до конца — нижние строки тоже обязаны уместиться.
        await t.drag(find.byType(ListView), const Offset(0, -2000));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
