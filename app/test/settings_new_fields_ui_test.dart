import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/data/settings_storage.dart';
import 'package:silentgate/engine/probe_factory.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';
import 'package:silentgate/ui/widgets/speed_traffic_note.dart';

/// ⚠️ ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ: ПОЛЯ БЫЛИ, А КРУТИТЬ ИХ БЫЛО НЕЧЕМ.
///
/// В батче появились `speedTopN`, `autoConfigConcurrency`,
/// `connectChecksEnabled`, `connectCheckServices` и тройка `seamless*`: они
/// сериализуются, движок их читает — а в настройках не показывался ни один.
/// Тот же почерк уже стоил пользователям маршрутов (`myRulesOverridePanel`:
/// умолчание `true`, менять нечем, реврайт панельных правил включён у всех
/// навсегда). Поэтому тест проверяет не «виджет нарисовался», а «нажатие
/// ДОЕХАЛО до настроек».
///
/// На прежнем коде падает весь файл целиком: ни одного из этих контролов в
/// `settings_screen.dart` не существовало — ни ключей, ни разделов.
void main() {
  final l = AppLocalizationsRu();

  late Directory tmp;
  late SettingsController settings;

  setUp(() {
    // ⚠️ Боевой каталог под тестами не отдаётся (`AppPaths`), и правильно:
    // тест уже переписывал владельцу `subscriptions.json`. Свой каталог —
    // единственный законный путь.
    tmp = Directory.systemTemp.createTempSync('sg_settings_new_fields_');
    AppPaths.overrideRoot(tmp);
    settings = SettingsController();
  });

  tearDown(() {
    settings.dispose();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Задать значение ДО отрисовки.
  ///
  /// ⚠️ БЕЗ `await`. `SettingsController.update` пишет настройки на диск, а
  /// настоящий дисковый ввод-вывод под FakeAsync (`testWidgets`) не
  /// завершается — ожидание такого будущего вешает тест. Само значение
  /// меняется СИНХРОННО: тело `update` до первого `await` уже отработало,
  /// подписчики уведомлены. Запись на диск проверяется отдельной группой
  /// обычными `test`.
  void preset(AppSettings Function(AppSettings) mutate) {
    unawaited(settings.update(mutate));
  }

  /// Экран настроек, но только нужные разделы.
  ///
  /// ⚠️ Секции берутся у НАСТОЯЩЕГО [buildSettingsSections] — иначе тест
  /// проверял бы свою копию раскладки, а не ту, что видит пользователь.
  /// Отфильтрованы они лишь затем, чтобы не строить «О программе» с версией
  /// ядра и HWID: там платформенные каналы, которых в тесте нет.
  Widget host(Set<String> ids) =>
      ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(builder: (context) {
              final c = context.watch<SettingsController>();
              final all = buildSettingsSections(context, c.settings, c);
              return SettingsBody(
                sections: all.where((s) => ids.contains(s.id)).toList(),
                collapsed: const {},
                onToggleSection: (_) {},
              );
            }),
          ),
        ),
      );

  /// Окно ВЫСОКОЕ, но УЖЕ порога бокового меню.
  ///
  /// ⚠️ Шире 900 — и заголовок раздела появляется дважды (в меню слева и над
  /// содержимым), после чего `findsOneWidget` падает на верном коде.
  void setWindow(WidgetTester t) {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(880, 2400);
    addTearDown(t.view.reset);
  }

  Future<void> pump(WidgetTester t, Set<String> ids) async {
    setWindow(t);
    await t.pumpWidget(host(ids));
    await t.pump();
  }

  // ───────────────────────────────────────────────────────────────────────────
  group('Бесшовность — три переключателя со своей ценой', () {
    const ids = {SettingsSectionIds.seamless};

    testWidgets('раздел есть в раскладке настроек', (t) async {
      await pump(t, ids);
      expect(find.text(l.settingsSectionSeamless), findsOneWidget,
          reason: 'до правки поля были, а раздела не было вовсе');
      expect(find.text(l.settingsSeamlessNote), findsOneWidget,
          reason:
              'вводная строка про обрыв соединений обязана быть ДО тумблеров');
    });

    testWidgets('каждый тумблер доезжает до настроек', (t) async {
      await pump(t, ids);
      // Умолчание у всех трёх — true, поэтому нажатие выключает.
      expect(settings.settings.seamlessServerSwitch, isTrue);
      expect(settings.settings.seamlessNetworkChange, isTrue);
      expect(settings.settings.seamlessKeepTun, isTrue);

      await t.tap(find.byKey(const Key('seamlessServerSwitch')));
      await t.pump();
      expect(settings.settings.seamlessServerSwitch, isFalse);
      expect(settings.settings.seamlessNetworkChange, isTrue,
          reason: 'переключатели независимы: один тумблер — одно поле');

      await t.tap(find.byKey(const Key('seamlessNetworkChange')));
      await t.pump();
      expect(settings.settings.seamlessNetworkChange, isFalse);

      await t.tap(find.byKey(const Key('seamlessKeepTun')));
      await t.pump();
      expect(settings.settings.seamlessKeepTun, isFalse);

      // Обратный ход — иначе «доезжает» доказано только в одну сторону.
      await t.tap(find.byKey(const Key('seamlessKeepTun')));
      await t.pump();
      expect(settings.settings.seamlessKeepTun, isTrue);
    });

    test('⚠️ подписи не обещают, что соединения переживут смену сервера', () {
      // Живое TCP смену внешнего IP не переживает — это физика. Обещание
      // «звонок продолжится» вскрылось бы на первом же звонке.
      final texts = [
        l.settingsSeamlessNote,
        l.settingsSeamlessServerTitle,
        l.settingsSeamlessServerSub,
        l.settingsSeamlessNetworkSub,
      ].join(' ').toLowerCase();
      for (final promise in ['не оборв', 'не разорв', 'сохраняются соединения']) {
        expect(texts.contains(promise), isFalse,
            reason: 'обещание «$promise» здесь невыполнимо');
      }
      expect(l.settingsSeamlessNote.toLowerCase(), contains('оборв'),
          reason: 'про обрыв соединений надо сказать прямо, а не умолчать');
    });

    test('⚠️ «держать адаптер» прямо назван НЕ kill switch', () {
      // Название читается как защита от утечки, а защиты тут нет: трафик мимо
      // VPN не блокируется, удерживается только адаптер.
      expect(
          l.settingsSeamlessKeepTunSub.toLowerCase(), contains('kill switch'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Проверка сервисов при подключении', () {
    const ids = {SettingsSectionIds.checks};

    testWidgets('галочка доезжает до настроек и прячет набор', (t) async {
      await pump(t, ids);
      expect(settings.settings.connectChecksEnabled, isTrue);
      expect(find.byKey(const Key('connectCheck-youtube')), findsOneWidget);

      await t.tap(find.byKey(const Key('connectChecksEnabled')));
      await t.pump();
      expect(settings.settings.connectChecksEnabled, isFalse);
      expect(find.byKey(const Key('connectCheck-youtube')), findsNothing,
          reason: 'выбирать, ЧТО проверять, когда не проверяется ничего, — '
              'работа впустую');
      // ⚠️ Выключение НЕ стирает выбор: иначе, включив проверки обратно,
      // человек начинал бы с чистого листа.
      expect(settings.settings.connectCheckServices, isNotEmpty);
    });

    testWidgets('чип добавляет и убирает сервис', (t) async {
      await pump(t, ids);
      expect(settings.settings.connectCheckServices,
          contains(ProbeService.youtube));

      await t.tap(find.byKey(const Key('connectCheck-youtube')));
      await t.pump();
      expect(settings.settings.connectCheckServices,
          isNot(contains(ProbeService.youtube)));

      await t.tap(find.byKey(const Key('connectCheck-youtube')));
      await t.pump();
      expect(settings.settings.connectCheckServices,
          contains(ProbeService.youtube));
    });

    testWidgets('«Выбрать все» и «Снять все»', (t) async {
      await pump(t, ids);
      await t.tap(find.byKey(const Key('connectChecksAll')));
      await t.pump();
      expect(
          settings.settings.connectCheckServices, ServiceChecks.catalog.toSet());

      await t.tap(find.byKey(const Key('connectChecksNone')));
      await t.pump();
      expect(settings.settings.connectCheckServices, isEmpty);
      // Пустой набор при включённой галочке — законное состояние, но молча оно
      // выглядит как поломка: «проверка включена, а чипов нет».
      expect(find.text(l.settingsConnectChecksEmpty), findsOneWidget);
    });

    testWidgets('⚠️ список чипов — тот же каталог, что под кнопкой Connect',
        (t) async {
      // Возьми настройки `ProbeService.values`, и сервис, забытый в каталоге,
      // выбирался бы здесь, но не появлялся на главном — настройка, которая
      // молча ничего не делает. Плюс порядок: человек ищет Telegram там, где
      // видел его у кнопки Connect.
      await pump(t, ids);
      final shown = t
          .widgetList<FilterChip>(find.byType(FilterChip))
          .map((c) => (c.key! as ValueKey<String>).value)
          .toList();
      expect(shown,
          ServiceChecks.catalog.map((s) => 'connectCheck-${s.name}').toList());
    });

    testWidgets('⚠️ набор НЕ общий с автонастройкой', (t) async {
      // Автонастройка ИЩЕТ рабочий сервер и готова перебирать долго, а эти
      // чипы отвечают на вопрос «работает ли прямо сейчас». Свести их в одну
      // настройку значило бы навязать один выбор двум разным задачам.
      await pump(t, ids);
      final autoBefore = settings.settings.autoConfigServices;
      expect(autoBefore, isNotEmpty);

      await t.tap(find.byKey(const Key('connectChecksNone')));
      await t.pump();
      expect(settings.settings.connectCheckServices, isEmpty);
      expect(settings.settings.autoConfigServices, autoBefore,
          reason: 'снятие чипов проверки не должно трогать автонастройку');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('⚠️ раздел автонастройки — только там, где прогон вообще идёт',
      (t) async {
    // Гейт по `autoConfigSupported` (харнесс умеет пропускать запросы через
    // кандидата только на Windows), а не по платформе «на глазок»: ручки
    // прогона, который на Android не начнётся никогда, — та же обманка, за
    // которую оттуда уже убирали права и тумблеры URL-схем.
    await pump(t, {SettingsSectionIds.autotune});
    expect(find.text(l.settingsSectionAutotune),
        autoConfigSupported ? findsOneWidget : findsNothing);
  });

  group('Автонастройка: сколько мерить и сколько разом', () {
    const ids = {SettingsSectionIds.autotune};

    testWidgets('поле «сколько серверов» видно только при включённом замере',
        (t) async {
      await pump(t, ids);
      expect(settings.settings.speedInAutoSelect, isFalse,
          reason: 'умолчание — выключено: замер тратит трафик подписки');
      expect(find.byKey(const Key('speedTopN-value')), findsNothing);
      expect(find.byKey(const Key('speedTrafficNote')), findsNothing);

      preset((s) => s.copyWith(speedInAutoSelect: true));
      await t.pump();
      expect(find.byKey(const Key('speedTopN-value')), findsOneWidget);
      expect(find.byKey(const Key('speedTrafficNote')), findsOneWidget);
    });

    testWidgets('⚠️ включение галочки ПРЕДУПРЕЖДАЕТ и называет число мегабайт',
        (t) async {
      await pump(t, ids);
      await t.tap(find.byKey(const Key('speedInAutoSelect')));
      await t.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget,
          reason: 'молчаливое включение списывало бы трафик подписки '
              'незаметно для владельца');
      final mb = settings.settings.speedTestTrafficMb;
      expect(mb, 55,
          reason: 'умолчания: 10 серверов + свой канал по 5 МБ = 55 МБ');
      // Число берётся ТОЛЬКО из `speedTestTrafficMb` — единственного места,
      // где оно считается; своя арифметика в диалоге разошлась бы с полем.
      final note = t.widget<SpeedTrafficNote>(
          find.descendant(of: dialog, matching: find.byType(SpeedTrafficNote)));
      expect(note.text, contains('$mb'));
      expect(find.descendant(of: dialog, matching: find.textContaining('$mb')),
          findsWidgets,
          reason: 'число обязано быть видно, а не подразумеваться');

      // Отказ оставляет настройку выключенной — в этом и смысл вопроса.
      await t.tap(find.text(l.commonCancel));
      await t.pumpAndSettle();
      expect(settings.settings.speedInAutoSelect, isFalse);
    });

    testWidgets('согласие включает замер', (t) async {
      await pump(t, ids);
      await t.tap(find.byKey(const Key('speedInAutoSelect')));
      await t.pumpAndSettle();
      await t.tap(find.text(l.settingsSpeedWarnEnable));
      await t.pumpAndSettle();
      expect(settings.settings.speedInAutoSelect, isTrue);
    });

    testWidgets('выключение спрашивать не должно', (t) async {
      preset((s) => s.copyWith(speedInAutoSelect: true));
      await pump(t, ids);
      await t.tap(find.byKey(const Key('speedInAutoSelect')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'вопрос про трафик у отказа от трафика — бессмыслица');
      expect(settings.settings.speedInAutoSelect, isFalse);
    });

    testWidgets(
        'шаги «сколько серверов» доезжают до настроек, число в подписи '
        'пересчитывается', (t) async {
      preset((s) => s.copyWith(speedInAutoSelect: true));
      await pump(t, ids);
      expect(settings.settings.effectiveSpeedTopN, AppSettings.speedTopNMax);

      await t.tap(find.byKey(const Key('speedTopN-minus')));
      await t.pump();
      expect(settings.settings.speedTopN, AppSettings.speedTopNMax - 1);
      expect(settings.settings.speedTestTrafficMb, 50,
          reason: '9 серверов + свой канал по 5 МБ');

      final note =
          t.widget<SpeedTrafficNote>(find.byKey(const Key('speedTrafficNote')));
      expect(note.text, contains('${settings.settings.speedTestTrafficMb}'),
          reason: 'подпись обязана пересчитаться вместе с числом серверов');

      await t.tap(find.byKey(const Key('speedTopN-plus')));
      await t.pump();
      expect(settings.settings.speedTopN, AppSettings.speedTopNMax);
    });

    testWidgets('⚠️ за границы 1..10 выйти нечем', (t) async {
      preset((s) => s.copyWith(speedInAutoSelect: true));
      await pump(t, ids);
      // Потолок: кнопка «плюс» неактивна — иначе человек набрал бы 50, увидел
      // своё число на экране и получил молча зажатое при прогоне.
      expect(
          t.widget<IconButton>(find.byKey(const Key('speedTopN-plus'))).onPressed,
          isNull);

      for (var i = 0; i < AppSettings.speedTopNMax + 3; i++) {
        final minus =
            t.widget<IconButton>(find.byKey(const Key('speedTopN-minus')));
        if (minus.onPressed == null) break;
        await t.tap(find.byKey(const Key('speedTopN-minus')));
        await t.pump();
      }
      expect(settings.settings.speedTopN, 1);
      expect(
          t
              .widget<IconButton>(find.byKey(const Key('speedTopN-minus')))
              .onPressed,
          isNull,
          reason: 'на нижней границе «минус» обязан гаснуть');
    });

    testWidgets('одновременность доезжает до настроек и зажата 1..5', (t) async {
      await pump(t, ids);
      expect(settings.settings.effectiveAutoConfigConcurrency, 3);

      await t.tap(find.byKey(const Key('autoConfigConcurrency-minus')));
      await t.pump();
      expect(settings.settings.autoConfigConcurrency, 2);

      for (var i = 0; i < AppSettings.autoConfigConcurrencyMax + 3; i++) {
        final plus = t.widget<IconButton>(
            find.byKey(const Key('autoConfigConcurrency-plus')));
        if (plus.onPressed == null) break;
        await t.tap(find.byKey(const Key('autoConfigConcurrency-plus')));
        await t.pump();
      }
      expect(settings.settings.autoConfigConcurrency,
          AppSettings.autoConfigConcurrencyMax);
      expect(
          t
              .widget<IconButton>(
                  find.byKey(const Key('autoConfigConcurrency-plus')))
              .onPressed,
          isNull);
    });

    test('⚠️ подпись одновременности называет путь отката', () {
      // Распараллеливание поднимает несколько ядер сразу; если замеры
      // «поплыли», человеку нужно знать, куда возвращаться, а не гадать.
      expect(l.settingsConcurrencySub, contains('1'));
      expect(l.settingsConcurrencySub.toLowerCase(), contains('очеред'));
    });
  }, skip: autoConfigSupported ? false : 'автонастройка только на Windows');

  // ───────────────────────────────────────────────────────────────────────────
  // Настройки правятся в памяти контроллера, а на диск уходят отдельной
  // записью. Класс багов «поле пишется, но не читается» уже стоил владельцу
  // молча сброшенного `tunnelDnsForAll`, поэтому шесть новых полей проверяются
  // сквозь настоящий файл: обычный `test`, а не `testWidgets`, — там нет
  // FakeAsync, и дисковый ввод-вывод честно доходит до конца.
  group('Новые поля переживают запись и чтение', () {
    test('шесть полей возвращаются с диска теми же', () async {
      final storage = SettingsStorage();
      await storage.save(AppSettings.defaults.copyWith(
        speedInAutoSelect: true,
        speedTopN: 4,
        autoConfigConcurrency: 5,
        connectChecksEnabled: false,
        connectCheckServices: {ProbeService.claude, ProbeService.google},
        seamlessServerSwitch: false,
        seamlessNetworkChange: false,
        seamlessKeepTun: false,
      ));
      final back = await storage.load();
      expect(back.speedTopN, 4);
      expect(back.autoConfigConcurrency, 5);
      expect(back.connectChecksEnabled, isFalse);
      expect(
          back.connectCheckServices, {ProbeService.claude, ProbeService.google});
      expect(back.seamlessServerSwitch, isFalse);
      expect(back.seamlessNetworkChange, isFalse);
      expect(back.seamlessKeepTun, isFalse);
      // Расход считается из ЭФФЕКТИВНОГО числа серверов: 4 + свой канал.
      expect(back.speedTestTrafficMb, 25);
    });
  });
}
