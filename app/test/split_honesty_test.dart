import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/data/settings_storage.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_en.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/split_tunnel_screen.dart';

/// Обещания интерфейса против того, что делает код.
///
/// ⚠️ ЖАЛОБА, ИЗ КОТОРОЙ ВЫРОС ЭТОТ ФАЙЛ (19.08.2026): «kill switch включён, а
/// меня выбивает под реальным IP». Настройки у владельца были выставлены верно,
/// врал интерфейс — сразу в трёх местах:
///
///  1. Подпись «Не выходить под реальным IP» гласила «Даже при рабочем VPN весь
///     „прямой“ трафик идёт через VPN». На деле настройка переписывает ТОЛЬКО
///     явные правила «Прямо» и панельный `direct`. База маршрута
///     (`SingboxConfigBuilder`: `finalOutbound = onlySelected ? 'direct' :
///     'proxy'`) не меняется вовсе.
///  2. Про то, что в режиме «Только отмеченные» ВСЁ НЕОТМЕЧЕННОЕ идёт под
///     настоящим адресом, не было сказано нигде — ни на экране правил, ни в
///     настройках.
///  3. Kill switch в режиме системного прокси не берёт прав администратора и
///     блокировкой не является: он лишь оставляет прокси прописанным.
///
/// Ни один из трёх дефектов не поймал бы тест на маршрутизацию: конфиг ядра
/// собирался ПРАВИЛЬНО. Поэтому проверяем условия показа оговорок и сами
/// ключи текстов, а не вёрстку.

/// Настройки в памяти вместо файла.
///
/// ⚠️ НЕ РАДИ СКОРОСТИ. `SettingsController.update` ждёт запись на диск, а
/// внутри `testWidgets` время поддельное: настоящий ввод-вывод там не
/// завершается никогда, и тест висел ровно 10 минут до таймаута — при
/// совершенно исправном коде экрана.
class _MemorySettingsStorage extends SettingsStorage {
  AppSettings _saved = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => _saved;

  @override
  Future<void> save(AppSettings settings) async {
    _saved = settings;
  }
}

void main() {
  // ── 1. Чистая функция: когда оговорка нужна ────────────────────────────────

  group('splitHonestyWarnings: условие, а не вёрстка', () {
    AppSettings cfg({
      SplitMode mode = SplitMode.onlySelected,
      CaptureMode capture = CaptureMode.tun,
      bool killSwitch = false,
      List<SiteRule> sites = const [],
    }) =>
        AppSettings.defaults.copyWith(
          captureMode: capture,
          killSwitch: killSwitch,
          splitTunnel: SplitTunnelConfig(mode: mode, sites: sites),
        );

    test('«Только отмеченные» в TUN — говорим про реальный IP', () {
      expect(splitHonestyWarnings(cfg()),
          contains(SplitHonesty.realIpByDefault));
    });

    test('в остальных режимах оговорки нет — база уходит в туннель', () {
      for (final m in [SplitMode.all, SplitMode.exceptSelected]) {
        expect(splitHonestyWarnings(cfg(mode: m)),
            isNot(contains(SplitHonesty.realIpByDefault)),
            reason: 'в режиме $m неотмеченный трафик и так идёт через VPN');
      }
    });

    test('в системном прокси база маршрута ни при чём — молчим', () {
      // Правила раздельного туннелирования там не применяются вовсе, и об этом
      // экран говорит своей плашкой. Дублировать её оговоркой про базу значило
      // бы назвать причиной то, что причиной не является.
      expect(
          splitHonestyWarnings(cfg(capture: CaptureMode.systemProxy)),
          isNot(contains(SplitHonesty.realIpByDefault)));
    });

    test('сайты + kill switch: он работает по программам, не по доменам', () {
      final s = cfg(
        killSwitch: true,
        sites: const [SiteRule('example.com', action: AppAction.tunnel)],
      );
      expect(splitHonestyWarnings(s),
          contains(SplitHonesty.killSwitchIsPerApp));
    });

    test('без правил по сайтам про сайты не говорим', () {
      expect(splitHonestyWarnings(cfg(killSwitch: true)),
          isNot(contains(SplitHonesty.killSwitchIsPerApp)));
    });

    test('без kill switch про его границы не говорим', () {
      final s = cfg(sites: const [SiteRule('example.com')]);
      expect(splitHonestyWarnings(s),
          isNot(contains(SplitHonesty.killSwitchIsPerApp)));
    });

    test('kill switch в системном прокси помечен слабым', () {
      final s = cfg(capture: CaptureMode.systemProxy, killSwitch: true);
      expect(splitHonestyWarnings(s),
          contains(SplitHonesty.killSwitchWeakInSystemProxy));
    });

    test('в TUN kill switch слабым не считается', () {
      expect(splitHonestyWarnings(cfg(killSwitch: true)),
          isNot(contains(SplitHonesty.killSwitchWeakInSystemProxy)));
    });

    test('выключенный kill switch не даёт оговорки о системном прокси', () {
      expect(splitHonestyWarnings(cfg(capture: CaptureMode.systemProxy)),
          isNot(contains(SplitHonesty.killSwitchWeakInSystemProxy)));
    });
  });

  // ── 2. Плашка на экране правил ─────────────────────────────────────────────

  group('Плашка видна ровно там, где цена режима реальна', () {
    late Directory tmp;
    late SettingsController controller;

    setUp(() {
      // ⚠️ Боевой %APPDATA%\SilentGate не трогаем ДВАЖДЫ: хранилище подменено
      // на память, и корень данных всё равно уведён во временный каталог —
      // если что-то в цепочке всё-таки полезет на диск, оно полезет туда.
      tmp = Directory.systemTemp.createTempSync('sg_honesty_');
      AppPaths.overrideRoot(tmp);
      controller = SettingsController(storage: _MemorySettingsStorage());
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: SplitHonestyBanner()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> setMode(SplitMode mode) => controller.update((s) => s.copyWith(
        captureMode: CaptureMode.tun,
        splitTunnel: s.splitTunnel.copyWith(mode: mode)));

    testWidgets('появляется при «Только отмеченные» и исчезает в других режимах',
        (tester) async {
      await setMode(SplitMode.onlySelected);
      await pump(tester);
      expect(find.byKey(const Key('splitHonesty')), findsOneWidget,
          reason: 'цена режима нигде не названа — ровно то, на чём '
              'напоролся владелец');

      await setMode(SplitMode.all);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('splitHonesty')), findsNothing);

      await setMode(SplitMode.exceptSelected);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('splitHonesty')), findsNothing);
    });

    testWidgets('строка про «Не выходить под реальным IP» — только когда он включён',
        (tester) async {
      await setMode(SplitMode.onlySelected);
      await pump(tester);
      expect(find.byKey(const Key('splitHonesty-noRealIp')), findsNothing);

      await controller.update((s) => s.copyWith(noRealIp: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('splitHonesty-noRealIp')), findsOneWidget,
          reason: 'галочка выглядит как «теперь точно ничего не утечёт»');
    });

    testWidgets('строка про kill switch — только при живых правилах по сайтам',
        (tester) async {
      await setMode(SplitMode.onlySelected);
      await controller.update((s) => s.copyWith(killSwitch: true));
      await pump(tester);
      expect(find.byKey(const Key('splitHonesty-killSwitch')), findsNothing);

      await controller.update((s) => s.copyWith(
          splitTunnel: s.splitTunnel.copyWith(
              sites: const [SiteRule('example.com', action: AppAction.tunnel)])));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('splitHonesty-killSwitch')), findsOneWidget);
    });

    testWidgets('кнопка рядом с оговоркой переводит в «Все — через VPN»',
        (tester) async {
      await setMode(SplitMode.onlySelected);
      await pump(tester);
      await tester.tap(find.byKey(const Key('splitHonesty-toAll')));
      await tester.pumpAndSettle();
      expect(controller.settings.splitTunnel.mode, SplitMode.all);
      // И плашка уходит сама: цены больше нет.
      expect(find.byKey(const Key('splitHonesty')), findsNothing);
    });
  });

  // ── 3. Тексты не обещают того, чего код не делает ──────────────────────────

  group('Ключи текстов', () {
    final ru = AppLocalizationsRu();
    final en = AppLocalizationsEn();

    test('подпись noRealIp говорит про ПРАВИЛА, а не про весь трафик', () {
      // Прежний текст: «Даже при рабочем VPN весь „прямой“ трафик идёт через
      // VPN». Слово «весь» и было обещанием, которого код не выполняет.
      expect(ru.noRealIpSubRulesOnly, contains('только'));
      expect(ru.noRealIpSubRulesOnly, contains('Прямо'));
      expect(ru.noRealIpSubRulesOnly.toLowerCase(), isNot(contains('весь')));
      expect(en.noRealIpSubRulesOnly.toLowerCase(), contains('only'));
    });

    test('подсказка noRealIp прямо называет, чего настройка НЕ делает', () {
      expect(ru.infoNoRealIp, contains('НЕ делает'));
      expect(ru.infoNoRealIp, contains('базу маршрута'));
      expect(en.infoNoRealIp.toLowerCase(), contains('does not'));
    });

    test('оговорка про «Только отмеченные» называет реальный IP', () {
      for (final s in [
        ru.noRealIpOnlySelectedNote,
        ru.splitOnlySelectedWarnTitle,
      ]) {
        expect(s.toLowerCase(), contains('реальн'));
      }
      expect(ru.splitOnlySelectedWarnBody, contains('напрямую'));
      expect(en.splitOnlySelectedWarnTitle.toLowerCase(), contains('real ip'));
    });

    test('подпись kill switch в системном прокси не называет себя блокировкой',
        () {
      expect(ru.killSwitchSubProxyNoAdmin, contains('не блокировка'));
      expect(ru.killSwitchSubProxyNoAdmin, contains('администратор'));
      expect(ru.killSwitchSubProxyNoAdmin, contains('TUN'));
      expect(ru.killSwitchOfferTun, contains('TUN'));
      expect(en.killSwitchSubProxyNoAdmin.toLowerCase(), contains('not a real block'));
    });

    test('про сайты сказано, что kill switch работает по программам', () {
      expect(ru.splitKillSwitchIsPerApp, contains('по программам'));
      expect(ru.splitKillSwitchIsPerApp, contains('сайт'));
      expect(en.splitKillSwitchIsPerApp.toLowerCase(), contains('per program'));
    });
  });

  // ── 4. Экраны действительно взяли честные подписи ──────────────────────────
  //
  // ⚠️ ПОЧЕМУ ПРОВЕРЯЕМ ИСХОДНИК. Ключ, оставшийся в ARB, ничего не ломает и
  // никем не проверяется: старый текст продолжал бы жить на экране, а все
  // проверки выше остались бы зелёными. Ровно так уже случалось с
  // комментариями, утверждавшими не то, что делает код.

  group('Экраны больше не берут прежние подписи', () {
    String read(String path) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path не найден');
      return f.readAsStringSync();
    }

    test('настройки: прежние noRealIpSub и killSwitchSubProxy не используются',
        () {
      final src = read('lib/ui/settings_screen.dart');
      expect(RegExp(r'l\.noRealIpSub\b').hasMatch(src), isFalse,
          reason: 'подпись обещала «весь прямой трафик через VPN»');
      expect(RegExp(r'l\.killSwitchSubProxy\b').hasMatch(src), isFalse,
          reason: 'подпись молчала о том, что прав администратора не берут');
      expect(src, contains('l.noRealIpSubRulesOnly'));
      expect(src, contains('l.killSwitchSubProxyNoAdmin'));
      // Предложение перейти на TUN — не «где-нибудь», а рядом с тумблером.
      expect(src, contains('l.killSwitchOfferTun'));
    });

    test('экран правил показывает плашку под выбором режима', () {
      final src = read('lib/ui/split_tunnel_screen.dart');
      final banner = src.indexOf('SplitHonestyBanner()');
      final radios = src.indexOf('RadioListTile<SplitMode>');
      final diagram = src.indexOf('RouteDiagram(split: st)');
      expect(banner, greaterThan(radios),
          reason: 'оговорка обязана стоять там, где режим выбирают');
      expect(banner, lessThan(diagram));
    });
  });
}
