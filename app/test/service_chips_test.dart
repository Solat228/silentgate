import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// Пять задач владельца по сервис-чипам (18.08.2026):
///  1. «было → стало» не появлялось у сервисов, добавленных после запуска;
///  2. пять новых сервисов (WhatsApp/Twitch/Spotify/Steam/GitHub) — 14 всего;
///  3. в подменю не видно, что выбрано, из-за ярких бренд-иконок;
///  4. кнопки «Все»/«Снять» в подменю;
///  5. пометка «сервис не попадает под правила VPN» по явному правилу.
void main() {
  final l = AppLocalizationsRu();

  // ⚠️ Сеть в тестах не нужна и вредна: правила «когда мерить» к погоде на
  // серверах YouTube отношения не имеют. Подменяем обе пробы во всём файле.
  late Map<ProbeService, int> probed;

  setUp(() {
    probed = {};
    ServiceCheckController.readinessDelay = Duration.zero;
    ServiceCheckController.readinessProbe = (port) async => true;
    ServiceCheckController.prober = (port, s) async {
      probed[s] = (probed[s] ?? 0) + 1;
      return const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 11);
    };
  });

  tearDown(() {
    ServiceCheckController.readinessAttempts = 6;
    ServiceCheckController.readinessDelay = const Duration(seconds: 2);
    ServiceCheckController.prober = ServiceChecker.check;
    ServiceCheckController.readinessProbe =
        ServiceCheckController.defaultReadinessProbe;
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Задача 1. Замер «до» для сервисов, добавленных после запуска.
  group('Догон замера «до»', () {
    test('стартовый прогон замера сервис, добавленный позже, НЕ получает',
        () async {
      // Это и есть жалоба владельца, зафиксированная как факт: `autoBaseline`
      // отрабатывает один раз за запуск и по тому набору, что был выбран в ту
      // секунду. Лечение — не в нём, поэтому поведение остаётся прежним.
      final c = ServiceCheckController();
      await c.autoBaseline(const [ProbeService.youtube]);
      await c.autoBaseline(
          const [ProbeService.youtube, ProbeService.steam]);
      expect(probed[ProbeService.steam], isNull,
          reason: 'стартовый прогон один за запуск — это его контракт');
      c.dispose();
    });

    test('ensureBaseline меряет ТОЛЬКО недостающих', () async {
      // ⚠️ Падает на старом поведении: метода не было вовсе, и добавленный
      // сервис оставался без замера «до» до перезапуска приложения — у него
      // рисовался один кружок вместо пары «было → стало».
      final c = ServiceCheckController();
      await c.autoBaseline(const [ProbeService.youtube]);
      expect(probed[ProbeService.youtube], 1);

      await c.ensureBaseline(
          const [ProbeService.youtube, ProbeService.steam]);
      expect(probed[ProbeService.steam], 1, reason: 'новый сервис — догнали');
      expect(probed[ProbeService.youtube], 1,
          reason: 'уже замеренный перепроверять нечего: каждое открытие '
              'подменю гоняло бы полтора десятка запросов заново');
      expect(c.baselineFor(ProbeService.steam).state, ServiceCheckState.ok);
      c.dispose();
    });

    test('пустой набор ничего не меряет и ничего не помнит', () async {
      final c = ServiceCheckController();
      await c.ensureBaseline(const []);
      expect(probed, isEmpty);
      expect(c.baselineWanted, isEmpty);
      c.dispose();
    });

    test('при живом туннеле замер ОТКЛАДЫВАЕТСЯ, а не идёт через VPN',
        () async {
      // ⚠️ Ключевое условие задачи: замер «до» идёт мимо VPN. На живом канале
      // проба ушла бы ЧЕРЕЗ него и легла в графу «без VPN» — сравнение стало бы
      // ложью, причём правдоподобной.
      final c = ServiceCheckController();
      c.setTunnelUp(true);
      await c.ensureBaseline(const [ProbeService.steam]);
      expect(probed[ProbeService.steam], isNull,
          reason: 'через туннель замер «до» снимать нельзя');
      expect(c.baselineWanted, contains(ProbeService.steam),
          reason: 'просьба обязана сохраниться, иначе замер потерян навсегда');

      // Пользователь выключил VPN — догоняем сами, без участия интерфейса.
      c.setTunnelUp(false);
      await Future<void>.delayed(Duration.zero);
      expect(probed[ProbeService.steam], 1);
      expect(c.baselineWanted, isEmpty);
      c.dispose();
    });

    test('признак живого канала от интерфейса тоже откладывает замер',
        () async {
      // Порт живого ядра колонка знает раньше, чем контроллеру сообщат
      // `setTunnelUp` (тот приходит из postFrame главного экрана). Достаточно
      // ОДНОГО признака живого канала, чтобы замер отложить.
      final c = ServiceCheckController();
      await c.ensureBaseline(const [ProbeService.github], vpnActive: true);
      expect(probed[ProbeService.github], isNull);
      expect(c.baselineWanted, contains(ProbeService.github));
      c.dispose();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Задача 2. Пять новых сервисов.
  group('Каталог из 14 сервисов', () {
    test('пятёрка добавлена и в перечисление, и в каталог подменю', () {
      // ⚠️ Падает на старом поведении: сервисов было девять.
      const added = [
        ProbeService.whatsapp,
        ProbeService.twitch,
        ProbeService.spotify,
        ProbeService.steam,
        ProbeService.github,
      ];
      for (final s in added) {
        expect(ServiceChecks.catalog, contains(s),
            reason: '${s.name} нет в каталоге — выбрать его негде');
        expect(s.label, isNotEmpty);
        expect(s.domain, contains('.'));
      }
      expect(ServiceChecks.catalog.length, 14);
      expect(ServiceChecks.catalog.toSet(), ProbeService.values.toSet(),
          reason: 'страж `connect_checks_test` требует того же — держим оба '
              'списка одним изменением');
    });

    test('⚠️ четырнадцать раскладываются по ПЯТИ смысловым рядам', () {
      // Раньше здесь стояла проверка «по семь в колонку»: набор делился
      // пополам вокруг кнопки Connect. Колонки удалены 19.08.2026 — при
      // четырнадцати сервисах столбцы по семь строк лезли за край экрана
      // телефона, а сама группировка по смыслу, ради которой набор и
      // расширяли, до интерфейса не доходила вовсе.
      final rows = ServiceChecks.grouped(ServiceChecks.catalog);
      expect(rows.length, ServiceGroup.values.length,
          reason: 'при полном наборе непустых групп ровно столько, сколько их '
              'объявлено — пустых среди них быть не может');
      expect(rows.expand((r) => r.services).toList(), hasLength(14));
    });

    test('у новых сервисов есть проба, и она проверяет СИГНАТУРУ ответа', () {
      // Заглушка провайдера — это 200 с HTML-страницей. Валидатор, смотрящий
      // на «2xx», принял бы её за работающий сервис.
      const stub = '<html><body>Доступ ограничен</body></html>';
      for (final s in const [
        ProbeService.twitch,
        ProbeService.spotify,
        ProbeService.steam,
        ProbeService.github,
      ]) {
        final ep = AutoConfigCatalog.endpointFor(s)!;
        expect(ep.url, startsWith('https://'),
            reason: 'TLS отсекает подмену ответа');
        expect(ep.validator(200, stub), isFalse,
            reason: '${s.name}: HTML-заглушка не должна проходить');
      }

      expect(
          AutoConfigCatalog.endpointFor(ProbeService.twitch)!
              .validator(200, 'User-agent: *\nDisallow: /'),
          isTrue);
      expect(
          AutoConfigCatalog.endpointFor(ProbeService.spotify)!
              .validator(200, '{"accesspoint":["ap-gew4.spotify.com:4070"]}'),
          isTrue);
      expect(
          AutoConfigCatalog.endpointFor(ProbeService.spotify)!
              .validator(200, '{"ap_list":["ap.spotify.com:4070"]}'),
          isTrue,
          reason: 'историческая форма ответа того же эндпоинта');
      expect(
          AutoConfigCatalog.endpointFor(ProbeService.steam)!
              .validator(200, '{"servertime":1755500000}'),
          isTrue);
      expect(
          AutoConfigCatalog.endpointFor(ProbeService.github)!
              .validator(200, '{"current_user_url":"https://api.github.com/user"}'),
          isTrue);
    });

    test('WhatsApp проверяется дозвоном до чат-сервера, а не сайтом', () {
      // Та же причина, что у Telegram: сайт живёт на обычном хостинге и
      // открывается тогда, когда мессенджер молчит.
      final ep = AutoConfigCatalog.endpointFor(ProbeService.whatsapp)!;
      expect(ep.url, startsWith('tcp://'));
      expect(ep.url, contains('whatsapp.net'));
      expect(ep.url, isNot(contains('web.whatsapp.com')));
      expect(ep.url.split(':').last, '443');
    });

    test('набор по умолчанию не изменился', () {
      expect(AppSettings.defaults.connectCheckServices, {
        ProbeService.youtube,
        ProbeService.chatgpt,
        ProbeService.telegram,
      });
    });

    test('новые сервисы переживают запись и чтение настроек', () {
      final s = AppSettings.defaults.copyWith(connectCheckServices: {
        ProbeService.steam,
        ProbeService.github,
      });
      final back = AppSettings.fromJson(s.toJson());
      expect(back.connectCheckServices,
          {ProbeService.steam, ProbeService.github});
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Задача 5. Пометка «сервис не попадает под правила VPN».
  group('Пометка «мимо VPN» по правилу раздельного туннелирования', () {
    SplitTunnelConfig cfg(List<SiteRule> sites,
            {SplitMode mode = SplitMode.onlySelected}) =>
        SplitTunnelConfig(mode: mode, sites: sites);

    test('без правил пометки нет', () {
      expect(ServiceChecks.bypassRuleFor(cfg(const []), ProbeService.github),
          isNull);
    });

    test('явное «Прямо» на домене сервиса — пометка есть', () {
      // ⚠️ Падает на старом поведении: сопоставления не было вовсе.
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('github.com', action: AppAction.direct)]),
          ProbeService.github);
      expect(r?.action, AppAction.direct);
    });

    test('«Блок» помечается отдельно', () {
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('twitch.tv', action: AppAction.block)]),
          ProbeService.twitch);
      expect(r?.action, AppAction.block);
    });

    test('правило суффиксное: родительский домен покрывает поддомен', () {
      // Правило «google.com → Прямо» уводит мимо VPN и gemini.google.com.
      // Сравнение по точному совпадению врало бы ровно здесь.
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('google.com', action: AppAction.direct)]),
          ProbeService.gemini);
      expect(r, isNotNull);
      expect(r!.domain, 'google.com');
    });

    test('более конкретное правило «Туннель» отменяет общее «Прямо»', () {
      // Пара правил, которую ядро разводит подъёмом конкретного поддомена выше
      // общего (`_addSitePriorityRules`). Пометка обязана считать так же,
      // иначе замок висел бы на сервисе, который идёт через VPN.
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [
            SiteRule('google.com', action: AppAction.direct),
            SiteRule('gemini.google.com', action: AppAction.tunnel),
          ]),
          ProbeService.gemini);
      expect(r, isNull);
    });

    test('чужой домен с похожим хвостом не считается совпадением', () {
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('notgithub.com', action: AppAction.direct)]),
          ProbeService.github);
      expect(r, isNull);
    });

    test('мишень пробы тоже считается доменом сервиса', () {
      // «googlevideo.com → Прямо» — обычный приём против замедления YouTube.
      // Проба идёт именно туда, значит и кружок «через VPN» через VPN не шёл.
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('googlevideo.com', action: AppAction.direct)]),
          ProbeService.youtube);
      expect(r, isNotNull);
    });

    test('правило с ЧУЖИМ портом сервис не помечает', () {
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [
            SiteRule('github.com', port: 8443, action: AppAction.direct)
          ]),
          ProbeService.github);
      expect(r, isNull,
          reason: 'правило меняет маршрут только своему порту, а проба '
              'идёт на 443');
      final same = ServiceChecks.bypassRuleFor(
          cfg(const [
            SiteRule('github.com', port: 443, action: AppAction.direct)
          ]),
          ProbeService.github);
      expect(same, isNotNull);
    });

    test('в режиме «Всё через VPN» пометок нет', () {
      // Пользовательские правила там не применяются — показывать замок
      // означало бы врать.
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('github.com', action: AppAction.direct)],
              mode: SplitMode.all),
          ProbeService.github);
      expect(r, isNull);
    });

    test('IP-мишень Telegram не ловится доменным правилом-обрывком', () {
      // Суффиксное сравнение на адресе даёт чепуху: «51» совпало бы с
      // «149.154.167.51».
      final r = ServiceChecks.bypassRuleFor(
          cfg(const [SiteRule('51', action: AppAction.direct)]),
          ProbeService.telegram);
      expect(r, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Экранная часть: подменю и колонки.
  group('Подменю и чипы на экране', () {
    late Directory tmp;
    late SettingsController settings;
    late ServiceCheckController checks;

    setUp(() {
      // ⚠️ Боевой каталог под тестами не отдаётся — объявляем свой.
      tmp = Directory.systemTemp.createTempSync('sg_service_chips_');
      AppPaths.overrideRoot(tmp);
      settings = SettingsController();
      checks = ServiceCheckController();
    });

    tearDown(() {
      settings.dispose();
      checks.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget host(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<ServiceCheckController>.value(value: checks),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Center(child: child)),
          ),
        );

    Future<void> openMenu(WidgetTester t) async {
      // ⚠️ Экран стенда по умолчанию 800×600, а в подменю теперь четырнадцать
      // строк: нижние сервисы уезжают за край, и тап по ним не попадает в
      // виджет (сам стенд об этом честно предупреждает). На настоящем экране
      // меню прокручивается — своей прокрутки мы внутрь не ставим (`showMenu`
      // оборачивает содержимое в `IntrinsicWidth`, и прокручиваемая область
      // внутри бросает исключение).
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1000, 1400);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(const ServiceChecksMenuButton()));
      await t.tap(find.byType(ServiceChecksMenuButton));
      await t.pumpAndSettle();
    }

    testWidgets('сервис, добавленный в настройках, догоняет замер «до»',
        (t) async {
      // ⚠️ ПАДАЕТ НА СТАРОМ ПОВЕДЕНИИ. Подписки на изменение набора не было ни
      // одной: `autoBaseline` звался единожды из `home_screen.initState`, флаг
      // `_baselineRan` нигде не сбрасывался. Владелец видел это как «пара точек
      // со стрелкой есть только у YouTube/ChatGPT/Telegram».
      await t.pumpWidget(host(const ServiceChecksMenuButton()));
      await t.pump(); // стартовый заказ замера по текущему набору
      expect(probed[ProbeService.youtube], 1);
      expect(probed[ProbeService.steam], isNull);

      // Пользователь добавляет Steam (в подменю или в настройках — источник не
      // важен, набор один).
      await t.runAsync(() => settings.update((c) => c.copyWith(
          connectCheckServices: {
            ...c.connectCheckServices,
            ProbeService.steam
          })));
      await t.pump();
      await t.pump();

      expect(probed[ProbeService.steam], 1,
          reason: 'у нового сервиса обязана появиться графа «без VPN»');
      expect(probed[ProbeService.youtube], 1,
          reason: 'остальные перепроверять незачем');
    });

    testWidgets('невыбранный сервис затемнён и перечёркнут', (t) async {
      // Жалоба владельца: «галочку просто не видно из-за значков приложений».
      // ⚠️ Падает на старом поведении: строки рисовались одинаково.
      await openMenu(t);
      Text label(ProbeService s) =>
          t.widget<Text>(find.text(s.label));

      // YouTube — в наборе по умолчанию, Steam — нет.
      expect(label(ProbeService.youtube).style?.decoration,
          isNot(TextDecoration.lineThrough));
      expect(label(ProbeService.steam).style?.decoration,
          TextDecoration.lineThrough);

      // Включили — перечёркивание снялось.
      // ⚠️ Сперва доскроллить: сервисов четырнадцать, список в подменю
      // прокручивается, и Steam лежит ниже границы окна. Без этого tap бьёт
      // мимо — ровно так тест и упал после добавления пятёрки.
      await t.ensureVisible(find.text(ProbeService.steam.label));
      await t.pumpAndSettle();
      await t.tap(find.text(ProbeService.steam.label));
      await t.pumpAndSettle();
      expect(label(ProbeService.steam).style?.decoration,
          isNot(TextDecoration.lineThrough));
    });

    testWidgets('«Все» и «Снять» правят набор целиком', (t) async {
      // ⚠️ Падает на старом поведении: кнопок в подменю не было.
      await openMenu(t);
      await t.tap(find.byKey(const Key('connectChecksMenuAll')));
      await t.pumpAndSettle();
      expect(settings.settings.connectCheckServices,
          ServiceChecks.catalog.toSet());
      expect(settings.settings.connectCheckServices.length, 14);

      await t.tap(find.byKey(const Key('connectChecksMenuNone')));
      await t.pumpAndSettle();
      expect(settings.settings.connectCheckServices, isEmpty);
      expect(ServiceChecks.selected(settings.settings), isEmpty,
          reason: 'снять все — законный способ выключить проверки');
    });

    testWidgets('при выключенных проверках «Все»/«Снять» недоступны',
        (t) async {
      await t.runAsync(
          () => settings.update((c) => c.copyWith(connectChecksEnabled: false)));
      await openMenu(t);
      expect(
          t
              .widget<TextButton>(find.byKey(const Key('connectChecksMenuAll')))
              .onPressed,
          isNull,
          reason: 'иначе непонятно, кто главнее: общий выключатель или набор');
    });

    testWidgets('замок появляется только у сервиса с явным правилом',
        (t) async {
      // ⚠️ Падает на старом поведении: пометки не существовало.
      await t.runAsync(() => settings.update((c) => c.copyWith(
              splitTunnel: const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            sites: [SiteRule('github.com', action: AppAction.direct)],
          ))));
      await t.pumpWidget(host(const ConnectCenterpiece(
        serverName: null,
        httpPort: 0,
        services: [ProbeService.github, ProbeService.steam],
        button: SizedBox(key: Key('btn'), width: 148, height: 148),
      )));
      await t.pumpAndSettle();

      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget,
          reason: 'ровно один сервис уведён мимо VPN правилом');
      expect(find.byIcon(Icons.block), findsNothing);
    });

    testWidgets('в режиме «Всё через VPN» замков нет', (t) async {
      await t.runAsync(() => settings.update((c) => c.copyWith(
              splitTunnel: const SplitTunnelConfig(
            mode: SplitMode.all,
            sites: [SiteRule('github.com', action: AppAction.direct)],
          ))));
      await t.pumpWidget(host(const ConnectCenterpiece(
        serverName: null,
        httpPort: 0,
        services: [ProbeService.github],
        button: SizedBox(key: Key('btn'), width: 148, height: 148),
      )));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
    });

    testWidgets('подменю открывается со всеми четырнадцатью сервисами',
        (t) async {
      await openMenu(t);
      expect(t.takeException(), isNull);
      expect(find.text(l.serviceChecksMenuTitle), findsOneWidget);
      for (final s in ServiceChecks.catalog) {
        expect(find.text(s.label), findsOneWidget,
            reason: '${s.label} нет в подменю — выбрать его нечем');
      }
    });
  });

  group('Провал замера «до» не становится окончательным', () {
    // ⚠️ НАЙДЕНО СКЕПТИКОМ 18.08.2026. Догон срабатывает по любому переходу в
    // «не подключено» — включая окно переподключения и kill switch, где трафик
    // заблокирован НАМЕРЕННО. Пробы там падают все, а прежний отбор («мерим
    // только тех, у кого записи нет») закреплял провал навсегда: запись есть —
    // значит больше не меряем. Сервис, добавленный при живом VPN, получал
    // вечный красный кружок вместо честного «не проверялось».

    test('⚠️ ГЛАВНОЕ: упавший замер перемеряется при следующей попытке', () async {
      final c = ServiceCheckController();
      var calls = 0;
      ServiceCheckController.prober = (port, s) async {
        calls++;
        // Первый заход — «нет сети» (окно переподключения), потом всё хорошо.
        return calls == 1
            ? const ServiceCheckOutcome(ServiceCheckState.fail)
            : const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 12);
      };
      addTearDown(() => ServiceCheckController.prober = ServiceChecker.check);

      await c.ensureBaseline([ProbeService.steam]);
      expect(c.baselineFor(ProbeService.steam)?.state, ServiceCheckState.fail);

      // Вторая попытка обязана состояться — раньше запись «провал» её отменяла.
      await c.ensureBaseline([ProbeService.steam]);
      expect(calls, 2,
          reason: 'ЗДЕСЬ ПРОВАЛ КЭШИРОВАЛСЯ НАВСЕГДА');
      expect(c.baselineFor(ProbeService.steam)?.state, ServiceCheckState.ok);
    });

    test('удачный замер второй раз не гоняется', () async {
      final c = ServiceCheckController();
      var calls = 0;
      ServiceCheckController.prober = (port, s) async {
        calls++;
        return const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 5);
      };
      addTearDown(() => ServiceCheckController.prober = ServiceChecker.check);

      await c.ensureBaseline([ProbeService.steam]);
      await c.ensureBaseline([ProbeService.steam]);
      expect(calls, 1, reason: 'иначе каждое отключение — лишние пробы наружу');
      expect(c.baselineWanted, isEmpty,
          reason: 'набор ждущих обязан сокращаться, иначе догон дёргается '
              'на КАЖДОМ отключении канала');
    });
  });
}
