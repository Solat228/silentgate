import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/probe_factory.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/subscription_switcher.dart';

/// Счётчик подписки в меню переключателя: он врал в трёх разных случаях, и все
/// три врали УБЕДИТЕЛЬНО — числа выглядели как законченный вердикт.
///
/// ⚠️ ЧТО ИМЕННО ЗДЕСЬ СТЕРЕЖЁТСЯ.
///
/// 1. **Во время прогона** счётчик показывал промежуточный итог как
///    окончательный. Первые секунды прогона это НОЛЬ рабочих (вердикты ещё не
///    пришли), а ноль нарисован красным — «101 · 0» рядом с названием подписки
///    человек читает как «подписка умерла». Теперь такое состояние отдельное:
///    вместо цифры многоточие, в подсказке — «проверка идёт».
/// 2. **После отмены** прогона картинка неотличима от законченного: у части
///    серверов вердикт есть, у остальных нет — «101 · 4». По результатам это не
///    определить (`notRun` стоит и у «не успели», и у «не проверяли»), поэтому
///    список недостигнутых ведёт сам [ProbeController.unfinishedKeys], а
///    счётчик метит такое число значком и отдельной подсказкой.
/// 3. **Кэш серверов в открытом меню**: ключом был `id` подписки, а он не
///    меняется никогда — обновление подписки, завершившееся при открытом меню,
///    счётчик не замечал.
/// 4. **Пункт «Пинг серверов всех подписок» во время замера скорости**
///    выглядел живым, а `_pingBatch` при `speedRunning` молча выходит первой
///    строкой: нажатие закрывало меню и не делало ничего.
///
/// Сети здесь нет нигде: серверы прогона — с полным JSON-конфигом (мимо TCP), а
/// харнесс подменён фейком, который порта не даёт. VPN не поднимается.
void main() {
  final l = AppLocalizationsRu();

  // ── Часть 1. Модель счёта ────────────────────────────────────────────────
  //
  // Здесь проверяется голая арифметика состояний — без меню и без прогона.

  group('SubscriptionPingCount: промежуточное и неполное — не вердикт', () {
    final srv = [
      _server('one', 'a1.example'),
      _server('two', 'a2.example'),
      _server('three', 'a3.example'),
    ];

    /// Все серверы подписки в прогоне — так выглядит массовый пинг (кнопка на
    /// главном берёт активную подписку целиком, пункт меню — все подписки).
    final wholeSubscription = {for (final s in srv) s.key};

    SubscriptionPingCount count(Map<int, PingResult> byIndex,
            {Set<String> runningKeys = const {},
            Set<String> unfinished = const {}}) =>
        SubscriptionPingCount.of(
          srv,
          (s) => byIndex[srv.indexWhere((x) => x.key == s.key)] ??
              PingResult.untested,
          runningKeys: runningKeys,
          unfinished: unfinished,
        );

    test('идёт прогон — числа рабочих нет вовсе, а не «0»', () {
      // Ровно первые секунды прогона: один сервер уже провалил проверку,
      // остальные ещё в очереди. Старый код отдавал working = 0 — красный ноль.
      final c = count({
        0: _res(PingVerification.failed),
        1: PingResult.testing,
        2: PingResult.testing,
      }, runningKeys: wholeSubscription);
      expect(c.state, SubscriptionCountState.running);
      expect(c.working, isNull,
          reason: 'промежуточный итог нельзя выдавать за окончательный');
      expect(c.total, 3);
    });

    test('сервер в фазе проверки канала — тоже «идёт»', () {
      final c = count({
        0: _res(PingVerification.passed),
        1: _res(PingVerification.pending),
        2: _res(PingVerification.passed),
      }, runningKeys: wholeSubscription);
      expect(c.state, SubscriptionCountState.running);
      expect(c.working, isNull);
    });

    test('перепроверка ОДНОЙ строки не прячет счётчик подписки', () {
      // Тап по плашке пинга в списке серверов — это `pingOne`, а он идёт через
      // тот же `_pingBatch` и поднимает тот же признак «прогон идёт». Пока
      // признаком служил голый флаг, одна перепроверяемая строка убирала число
      // рабочих у ВСЕЙ подписки — в стосерверной это выглядело как потеря
      // счётчика на ровном месте.
      final c = count({
        0: _res(PingVerification.passed),
        1: _res(PingVerification.failed),
        2: PingResult.testing,
      }, runningKeys: {srv[2].key});
      expect(c.state, SubscriptionCountState.ready,
          reason: 'ЗДЕСЬ БЫЛ БАГ: один сервер в проверке прятал весь счётчик');
      expect(c.working, 1,
          reason: 'про остальных известно — молчать о них незачем');
    });

    test('прогон идёт по ДРУГОЙ подписке — эту не трогаем', () {
      // Кнопка на главном экране пингует только активную подписку. Пометить
      // «идёт проверка» у всех четырёх — это новая ложь вместо старой.
      final c = count({
        0: _res(PingVerification.passed),
        1: _res(PingVerification.failed),
        2: _res(PingVerification.passed),
      }, runningKeys: {
        'vless://someone-else@x.example:443',
        'vless://someone-else@y.example:443',
      });
      expect(c.state, SubscriptionCountState.ready);
      expect(c.working, 2);
    });

    test('прогон оборвался — число помечено неполным', () {
      final c = count({
        0: _res(PingVerification.passed),
        1: _res(PingVerification.failed),
      }, unfinished: {srv[2].key});
      expect(c.state, SubscriptionCountState.partial,
          reason: 'отмена — это не результат');
      expect(c.working, 1, reason: 'что успели проверить — показываем');
    });

    test('оборвался прогон ЧУЖОЙ подписки — эта не помечена', () {
      final c = count({
        0: _res(PingVerification.passed),
        1: _res(PingVerification.failed),
        2: _res(PingVerification.passed),
      }, unfinished: {'vless://someone-else@x.example:443'});
      expect(c.state, SubscriptionCountState.ready);
      expect(c.working, 2);
    });

    test('законченный прогон — обычное состояние', () {
      final c = count({
        0: _res(PingVerification.passed),
        1: _res(PingVerification.failed),
        2: _res(PingVerification.passed),
      });
      expect(c.state, SubscriptionCountState.ready);
      expect(c.working, 2);
    });

    test('отмена до первого вердикта — числа нет, помечать нечего', () {
      final c = count(const {}, unfinished: {srv[0].key, srv[1].key});
      expect(c.working, isNull);
      expect(c.state, SubscriptionCountState.ready,
          reason: 'счётчик и так молчит о рабочих — значок был бы шумом');
    });
  });

  // ── Часть 2. Откуда берётся признак «прогон не дошёл» ────────────────────

  group('ProbeController помнит, до кого прогон не дошёл', () {
    late Directory tmp;

    setUp(() {
      // Пинг сохраняет результаты на диск — уводим корень в темп.
      tmp = Directory.systemTemp.createTempSync('sg_sub_counter_');
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('отменённый прогон отдаёт ключи непроверенных', () async {
      final a = _server('one', 'a1.example', full: true);
      final b = _server('two', 'a2.example', full: true);
      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);

      final run = ctrl.pingAll([a, b], const AppSettings());
      ctrl.cancel();
      await run;

      expect(ctrl.unfinishedKeys, {a.key, b.key},
          reason: 'без этого списка отмену не отличить от законченного прогона');
    });

    test('законченный прогон пометки не оставляет, и новый её снимает',
        () async {
      final a = _server('one', 'a1.example', full: true);
      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);

      final cancelled = ctrl.pingAll([a], const AppSettings());
      ctrl.cancel();
      await cancelled;
      expect(ctrl.unfinishedKeys, isNotEmpty);

      await ctrl.pingAll([a], const AppSettings());
      expect(ctrl.unfinishedKeys, isEmpty,
          reason: 'иначе клеймо старой отмены висело бы вечно');
    },
        skip: proxyProbeSupported
            ? null
            : 'фаза 2 (и её отметки «сделано») есть только там, где есть харнесс');

    test('новый прогон снимает пометку ТОЛЬКО со своих серверов', () async {
      // ⚠️ РАДИ ЭТОГО ТЕСТА ГРУППА И ДОПИСАНА. Ревьюер вернул в `_pingBatch`
      // прежнее `_unfinished = const {}` (стирание пометки целиком) — и 129
      // тестов трёх профильных файлов остались зелёными: везде повторный прогон
      // шёл по ТЕМ ЖЕ серверам, а на таком сценарии вычитание и обнуление
      // неотличимы. Отличить их может только прогон по ЧАСТИ прежнего списка —
      // ровно то, что делает человек, ткнув «перепроверить» в одну строку после
      // отменённого прогона на сотне серверов.
      final a = _server('one', 'a1.example', full: true);
      final b = _server('two', 'a2.example', full: true);
      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);

      final cancelled = ctrl.pingAll([a, b], const AppSettings());
      ctrl.cancel();
      await cancelled;
      expect(ctrl.unfinishedKeys, {a.key, b.key});

      // Второй прогон берёт ОДИН сервер из двух и доходит до конца.
      await ctrl.pingAll([a], const AppSettings());

      // Половина первая: со своего сервера пометка снята.
      expect(ctrl.unfinishedKeys, isNot(contains(a.key)),
          reason: 'этот сервер прогон взял в работу и проверил');
      // Половина вторая: чужого сервера прогон не касался.
      expect(ctrl.unfinishedKeys, contains(b.key),
          reason: 'ЗДЕСЬ БЫЛ БАГ: `_unfinished = const {}` стирал пометку '
              'целиком, и недосчитанное число снова выдавалось за вердикт');
      expect(ctrl.unfinishedKeys, {b.key});
    });

    test('пометка переживает перезапуск приложения', () async {
      // ⚠️ ПЕРСИСТ НЕ СТЕРЁГ НИКТО ВО ВСЁМ ДЕРЕВЕ. В памяти всё работало бы и
      // без записи на диск: уехал бы вызов `_persistUnfinished`, сменился бы
      // формат файла — и после перезапуска счётчик снова показывал бы
      // недосчитанное число как законченный вердикт, то есть ровно тот дефект,
      // ради которого пометка и заведена.
      final a = _server('one', 'a1.example', full: true);
      final b = _server('two', 'a2.example', full: true);
      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);

      final cancelled = ctrl.pingAll([a, b], const AppSettings());
      ctrl.cancel();
      await cancelled;
      expect(ctrl.unfinishedKeys, {a.key, b.key});

      // Так выглядит перезапуск приложения: контроллер новый, каталог данных
      // тот же (см. setUp), состояние берётся ТОЛЬКО с диска.
      final restarted = ProbeController(harnessFactory: _FakeHarness.new);
      await restarted.init();
      expect(restarted.unfinishedKeys, {a.key, b.key},
          reason: 'пометка обязана лежать в ping_unfinished.json, а не в памяти');
    });

    test('ключ в старом написании при чтении приводится к каноническому',
        () async {
      // Тот же перенос, что у результатов пинга: у gRPC имя сервиса приходит то
      // как `serviceName=`, то как `path=`, и ключ сервера зависел от формата
      // ответа панели. Живой сервер приходит из парсера УЖЕ канонизированным —
      // значит пометка, записанная в старом написании, повисла бы на ключе,
      // которого больше ни у кого нет, то есть просто исчезла бы.
      const legacy = 'vless://00000000-0000-0000-0000-000000000000'
          '@grpc.example:443?type=grpc&security=reality&encryption=none'
          '&sni=a.example.org&fp=chrome&pbk=KEY&sid=ab&serviceName=my-service'
          '#GRPC';
      final canonical = ShareLinkParser.canonicalKey(legacy);
      expect(canonical, isNot(legacy),
          reason: 'иначе тест ниже зелен по построению и ничего не стережёт');

      // Файл, оставшийся от прошлой версии приложения.
      final sep = Platform.pathSeparator;
      File('${tmp.path}${sep}ping_unfinished.json')
          .writeAsStringSync(jsonEncode([legacy]));

      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);
      await ctrl.init();
      expect(ctrl.unfinishedKeys, {canonical},
          reason: 'без KeyMigration.remapList на пути чтения пометка осиротела '
              'бы вместе со сменой формата подписки');
    });

    test('сервер исчез из подписок — пометка не остаётся навсегда', () async {
      // ⚠️ ФАЙЛ ТОЛЬКО РОС. Ключ снимает лишь прогон, взявший сервер в работу, а
      // сервер, пропавший из подписки, не возьмёт уже никто. Хуже размера —
      // воскрешение: вернётся узел с тем же ключом, и подписка пометится
      // неполной по прогону, которого в этой её жизни не было.
      final a = _server('one', 'a1.example', full: true);
      final b = _server('two', 'a2.example', full: true);
      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);

      final cancelled = ctrl.pingAll([a, b], const AppSettings());
      ctrl.cancel();
      await cancelled;
      expect(ctrl.unfinishedKeys, {a.key, b.key});

      // Панель убрала `b` из подписки: приложение знает только `a`.
      await ctrl.forgetUnknownServers([a.key]);
      expect(ctrl.unfinishedKeys, {a.key});

      // И чистка обязана дойти до диска — иначе файл всё равно растёт, а
      // воскрешение возвращается на первом же перезапуске.
      final restarted = ProbeController(harnessFactory: _FakeHarness.new);
      await restarted.init();
      expect(restarted.unfinishedKeys, {a.key},
          reason: 'чистка только в памяти ничего не чинит');
    });

    test('пустой список известных серверов не чистит ничего', () async {
      // «Список не собрался» и «серверов нет» здесь неразличимы, а цена ошибки —
      // молча стёртая пометка у всех подписок сразу.
      final a = _server('one', 'a1.example', full: true);
      final ctrl = ProbeController(harnessFactory: _FakeHarness.new);

      final cancelled = ctrl.pingAll([a], const AppSettings());
      ctrl.cancel();
      await cancelled;

      await ctrl.forgetUnknownServers(const []);
      expect(ctrl.unfinishedKeys, {a.key});
    });
  });

  // ── Часть 3. Меню ────────────────────────────────────────────────────────

  group('Счётчик и пункты меню', () {
    Directory? tmp;
    late AppState state;
    late _FakeProbe probe;
    late SettingsController settings;

    /// Две подписки на диске: активная A (2 сервера) и неактивная B (3).
    /// Кладём `subscriptions.json` до `init()` — единственный способ получить
    /// настоящую неактивную подписку без похода в сеть.
    Future<void> boot() async {
      tmp = Directory.systemTemp.createTempSync('sg_sub_counter_ui_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      File('${tmp!.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp!.path}${sep}subscriptions.json')
          .writeAsStringSync(jsonEncode({
        'activeId': _idA,
        'items': [
          {'id': _idA, 'url': _urlA, 'servers': [_a1, _a2]},
          {'id': _idB, 'url': _urlB, 'servers': [_b1, _b2, _b3]},
        ],
      }));
      state = AppState(engine: _FakeEngine());
      await state.init();
      probe = _FakeProbe();
      settings = SettingsController();
      await settings.init();
    }

    Widget app() => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
            ChangeNotifierProvider<ProbeController>.value(value: probe),
          ],
          child: const MaterialApp(
            locale: Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // Переключатель сверху слева: меню открывается ПОД ним, из середины
            // экрана нижние пункты уехали бы за край холста 800×600.
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SubscriptionSwitcher(title: 'Alpha'),
              ),
            ),
          ),
        );

    Finder badge(String id) => find.byKey(ValueKey('subCount_$id'));

    /// Качать кадры, ПОКА не наступит [ready], но не бесконечно.
    ///
    /// ⚠️ ВМЕСТО `pump(Duration)`. Фиксированные 350 мс — это надежда, что за
    /// них успеет и маршрут меню, и обработчик; под нагрузкой (параллельные
    /// прогоны, занятый диск) не успевало, и падало не там, где сломано.
    /// `pumpAndSettle` тут не годится по своей причине: в меню во время прогона
    /// крутится индикатор, а он анимируется бесконечно.
    Future<void> pumpUntil(
      WidgetTester tester,
      bool Function() ready, {
      String what = 'ожидаемое состояние',
      int maxFrames = 200,
      Duration step = const Duration(milliseconds: 20),
    }) async {
      for (var i = 0; i < maxFrames; i++) {
        if (ready()) return;
        await tester.pump(step);
      }
      expect(ready(), isTrue,
          reason: 'не дождались: $what '
              '(кадров $maxFrames по ${step.inMilliseconds} мс)');
    }

    /// Виджет найден И его центр лежит НА ЭКРАНЕ, то есть по нему можно нажать.
    ///
    /// ⚠️ «ВИДЖЕТ ПОЯВИЛСЯ» — ЕЩЁ НЕ «ПО НЕМУ МОЖНО НАЖАТЬ». `showMenu`
    /// разворачивает содержимое анимацией `Align(widthFactor: 0→1)`: пока
    /// фактор мал, левая часть висит в отрицательных координатах, и удар
    /// приходится мимо холста.
    bool onScreen(WidgetTester tester, Finder f) {
      final found = f.evaluate();
      if (found.length != 1) return false;
      final box = found.single.renderObject;
      if (box is! RenderBox || !box.hasSize) return false;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final surface = Offset.zero &
          (tester.view.physicalSize / tester.view.devicePixelRatio);
      return surface.contains(center);
    }

    /// Поднять интерфейс на ЗАВЕДОМО ПРОСТОРНОЙ поверхности.
    ///
    /// ⚠️ Размер задаётся ТОЛЬКО через `tester.view`: обёртка в `SizedBox`
    /// поверхность не расширяет — коробку зажимает та же 800×600. А на 800×600
    /// меню переключателя уже впритык, и подписи в нём растут при каждой правке
    /// текстов: тест бил бы по пункту, уехавшему за край, и падал так, будто
    /// сломана логика меню. Тот же приём, что в `ping_all_subscriptions_test`.
    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app());
      await tester.pump();
    }

    /// Открыть меню и дождаться, пока оно РАЗВЕРНЁТСЯ.
    ///
    /// [still] — ждать ещё и прекращения планирования кадров: пока маршрут
    /// анимируется, он накрыт `AbsorbPointer`, и нажатие не доходит до пункта,
    /// даже когда тот уже нарисован. Выключается там, где в меню крутится
    /// индикатор прогона: он планирует кадры бесконечно, и «покоя» не будет
    /// никогда (такому тесту нажимать всё равно не по чему — он только читает).
    Future<void> openMenu(WidgetTester tester, {bool still = true}) async {
      await tester.tap(find.byType(SubscriptionSwitcher));
      await pumpUntil(
          tester,
          () =>
              (!still || !tester.binding.hasScheduledFrame) &&
              onScreen(tester, badge(_idB)),
          what: 'развёрнутое меню переключателя подписок');
    }

    String tooltipOf(WidgetTester tester, String id) =>
        tester
            .widget<Tooltip>(
                find.descendant(of: badge(id), matching: find.byType(Tooltip)))
            .message ??
        '';

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
      tmp = null;
    });

    testWidgets('во время прогона — многоточие вместо цифры', (tester) async {
      await tester.runAsync(boot);
      final b = state.serversOfSubscription(_idB);
      // Картина первых секунд прогона: один вердикт уже есть, остальные в
      // очереди. Раньше отсюда получался красный ноль.
      probe.results[b[0].key] = _res(PingVerification.failed);
      probe.results[b[1].key] = PingResult.testing;
      probe.results[b[2].key] = PingResult.testing;
      probe.runningNow = true;
      // Массовый прогон: в партии вся подписка. Именно этим он и отличается от
      // тапа по одной плашке пинга, который прятать весь счётчик не должен.
      probe.runningNowKeys = {for (final s in b) s.key};

      await mount(tester);
      // `still: false` — в меню крутится индикатор идущего прогона, кадры
      // планируются бесконечно, и ждать «покоя» здесь означало бы упасть по
      // потолку кадров. Нажимать в этом тесте не по чему: он только читает.
      await openMenu(tester, still: false);

      expect(find.descendant(of: badge(_idB), matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: badge(_idB), matching: find.text('0')),
          findsNothing,
          reason: 'ЗДЕСЬ БЫЛ БАГ: недосчитанный ноль выдавался за вердикт');
      expect(
          find.descendant(
              of: badge(_idB), matching: find.byIcon(Icons.more_horiz)),
          findsOneWidget);
      expect(tooltipOf(tester, _idB), l.subSwitcherCountChecking(3));
    });

    testWidgets('после отмены число помечено значком и подсказкой',
        (tester) async {
      await tester.runAsync(boot);
      final b = state.serversOfSubscription(_idB);
      probe.results[b[0].key] = _res(PingVerification.passed);
      probe.results[b[1].key] = _res(PingVerification.failed);
      // До третьего прогон не дошёл — его и вернёт `unfinishedKeys`.
      probe.unfinishedNow = {b[2].key};

      await mount(tester);
      await openMenu(tester);

      expect(find.descendant(of: badge(_idB), matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: badge(_idB), matching: find.text('1')),
          findsOneWidget);
      expect(
          find.descendant(
              of: badge(_idB), matching: find.byIcon(Icons.error_outline)),
          findsOneWidget,
          reason: 'ЗДЕСЬ БЫЛ БАГ: отмена выглядела как законченный прогон');
      expect(tooltipOf(tester, _idB), l.subSwitcherCountPartial(3, 1));
    });

    testWidgets('законченный прогон — ни значка, ни многоточия', (tester) async {
      await tester.runAsync(boot);
      final b = state.serversOfSubscription(_idB);
      // Два рабочих из трёх: число рабочих нарочно НЕ равно общему, иначе
      // «нашлась цифра 3» ничего не доказывало бы — их было бы две.
      probe.results[b[0].key] = _res(PingVerification.passed);
      probe.results[b[1].key] = _res(PingVerification.passed);
      probe.results[b[2].key] = _res(PingVerification.failed);

      await mount(tester);
      await openMenu(tester);

      expect(find.descendant(of: badge(_idB), matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: badge(_idB), matching: find.text('2')),
          findsOneWidget);
      expect(
          find.descendant(
              of: badge(_idB), matching: find.byIcon(Icons.error_outline)),
          findsNothing);
      expect(
          find.descendant(
              of: badge(_idB), matching: find.byIcon(Icons.more_horiz)),
          findsNothing);
      expect(tooltipOf(tester, _idB), l.subSwitcherCountWorking(3, 2));
    });

    testWidgets('состав подписки изменился при ОТКРЫТОМ меню — счётчик следом',
        (tester) async {
      await tester.runAsync(boot);
      await mount(tester);
      await openMenu(tester);
      expect(find.descendant(of: badge(_idA), matching: find.text('2')),
          findsOneWidget);

      // Так же выглядит завершившееся в фоне обновление подписки: состав
      // профиля поменялся, меню при этом открыто.
      await tester.runAsync(() => state.removeServer(state.servers.first));
      // Ждём САМО ПОЯВЛЕНИЕ нового числа: меню перерисовывается по уведомлению
      // `AppState`, и срок этого ничем не задан.
      await pumpUntil(
          tester,
          () => find
              .descendant(of: badge(_idA), matching: find.text('1'))
              .evaluate()
              .isNotEmpty,
          what: 'пересчитанный счётчик подписки A');

      expect(find.descendant(of: badge(_idA), matching: find.text('1')),
          findsOneWidget,
          reason: 'ЗДЕСЬ БЫЛ БАГ: кэш по id подписки не сбрасывался никогда');
      expect(find.descendant(of: badge(_idA), matching: find.text('2')),
          findsNothing);
    });

    testWidgets('замер скорости выключает пинг и называет причину',
        (tester) async {
      await tester.runAsync(boot);
      probe.speedNow = true;
      await mount(tester);
      await openMenu(tester);

      expect(find.text(l.subSwitcherPingBusySpeed), findsOneWidget,
          reason: 'человек должен понимать, почему пункт погас');
      expect(find.text(l.subSwitcherPingAll), findsNothing);

      // Бьём по пункту только после того, как он оказался НА ЭКРАНЕ: иначе
      // «would not hit test» выглядел бы отказом кода, а не промахом теста.
      expect(onScreen(tester, find.text(l.subSwitcherPingBusySpeed)), isTrue);
      await tester.tap(find.text(l.subSwitcherPingBusySpeed));
      // Отсутствие вызова доказывается ожиданием, а не одним кадром: даём
      // обработчику столько же кадров, сколько ниже хватает рабочему пункту.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(probe.pinged, isNull,
          reason: 'ЗДЕСЬ БЫЛ БАГ: пункт нажимался и молча не делал ничего');

      // Контроль, чтобы проверка выше не оказалась пустой: как только замер
      // закончился, ровно тот же пункт снова работает.
      probe.speedNow = false;
      probe.bump();
      await pumpUntil(tester, () => onScreen(tester, find.text(l.subSwitcherPingAll)),
          what: 'вернувшийся пункт «Пинг серверов»');
      await tester.tap(find.text(l.subSwitcherPingAll));
      await pumpUntil(tester, () => probe.pinged != null,
          what: 'вызов ProbeController.pingAll');
      expect(probe.pinged, isNotNull);
    });

    testWidgets('открытие меню чистит пометку от исчезнувших серверов',
        (tester) async {
      // ⚠️ ЗДЕСЬ СТЕРЕЖЁТСЯ САМА СВЯЗКА, А НЕ ЧИСТКА. Сам разбор пометки
      // проверен выше настоящим `ProbeController`; сломаться же легче всего
      // проводу: пропадёт вызов из `SubscriptionSwitcher._open` — и
      // `ping_unfinished.json` снова начнёт расти без предела, а вернувшийся
      // сервер снова пометит подписку неполной. Из памяти это не видно ничем.
      await tester.runAsync(boot);
      await mount(tester);
      await openMenu(tester);

      expect(probe.forgotten, isNotNull,
          reason: 'меню обязано звать forgetUnknownServers при открытии');
      // Список — ВСЁ, что знает приложение: обе подписки целиком. Передай меньше
      // (скажем, только активную) — и чистка стёрла бы живые пометки.
      expect(probe.forgotten!.toSet(), {
        for (final link in [_a1, _a2, _b1, _b2, _b3])
          ShareLinkParser.canonicalKey(link),
      });
    });

  });

  // ── Часть 4. Счётчик подписки и объём прогона ────────────────────────────
  //
  // Пояснение к комментарию у счётчика в `subscription_switcher.dart`. Он
  // побывал неверным ДВАЖДЫ: сперва обещал совпадение чисел всегда, потом —
  // расхождение всегда. Правда посередине и зависит от пересечения подписок,
  // поэтому здесь стерегутся ОБЕ половины: одной мало — она оставляет вторую
  // без присмотра, и комментарий снова разойдётся с кодом.

  group('счётчик подписки и объём прогона', () {
    Directory? tmp;
    late AppState state;

    Future<void> boot(List<String> serversA, List<String> serversB) async {
      tmp = Directory.systemTemp.createTempSync('sg_sub_counter_sum_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      File('${tmp!.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp!.path}${sep}subscriptions.json')
          .writeAsStringSync(jsonEncode({
        'activeId': _idA,
        'items': [
          {'id': _idA, 'url': _urlA, 'servers': serversA},
          {'id': _idB, 'url': _urlB, 'servers': serversB},
        ],
      }));
      state = AppState(engine: _FakeEngine());
      await state.init();
    }

    int sumOfBadges() =>
        state.serversOfSubscription(_idA).length +
        state.serversOfSubscription(_idB).length;

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
      tmp = null;
    });

    test('подписки не пересекаются — сумма счётчиков РАВНА объёму прогона',
        () async {
      await boot(const [_a1, _a2], const [_b1, _b2, _b3]);
      expect(sumOfBadges(), 5);
      expect(state.allSubscriptionServers().length, 5,
          reason: 'без общих серверов расхождению взяться неоткуда');
    });

    test('один сервер в ДВУХ подписках — сумма счётчиков БОЛЬШЕ', () async {
      // a1 лежит и в A, и в B: в каждой подписке он считается своим, а на
      // прогон уходит один раз (`allSubscriptionServers` отсекает по ключу).
      await boot(const [_a1, _a2], const [_a1, _b1]);
      expect(sumOfBadges(), 4);
      expect(state.allSubscriptionServers().length, 3,
          reason: 'прогон отсекает повтор по ключу — сумма счётчиков больше');
    });
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

const _a1 = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
    '?type=tcp&security=none#Alpha-1';
const _a2 = 'vless://11111111-1111-1111-1111-111111111111@a2.example:443'
    '?type=tcp&security=none#Alpha-2';
const _b1 = 'vless://22222222-2222-2222-2222-222222222222@b1.example:443'
    '?type=tcp&security=none#Bravo-1';
const _b2 = 'vless://22222222-2222-2222-2222-222222222222@b2.example:443'
    '?type=tcp&security=none#Bravo-2';
const _b3 = 'vless://22222222-2222-2222-2222-222222222222@b3.example:443'
    '?type=tcp&security=none#Bravo-3';

const _urlA = 'https://panel.example/sub/aaaaaaaa';
const _urlB = 'https://panel.example/sub/bbbbbbbb';
final _idA = SubscriptionProfile.idFor(_urlA);
final _idB = SubscriptionProfile.idFor(_urlB);

/// Сервер для прогона. [full] — с полным JSON-конфигом: такие идут МИМО
/// TCP-фазы, поэтому тест не касается сети вообще.
///
/// ⚠️ ССЫЛКА — КАНОНИЧЕСКАЯ, как у живого сервера. Ключ сервера в приложении
/// всегда приходит из парсера уже приведённым, а сохранённое на диск проходит
/// через `KeyMigration` при чтении. Собери здесь ссылку «от руки» — и тест на
/// перезапуск покраснел бы на переносе ключа, а не на том, что проверяет.
VpnServer _server(String name, String host, {bool full = false}) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: host,
      port: 443,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink: ShareLinkParser.canonicalKey(
          'vless://11111111-2222-3333-4444-555555555555@$host:443#$name'),
      rawJsonOverride: full ? '{"outbounds":[]}' : null,
    );

/// Готовый результат пинга с нужным состоянием проверки канала.
PingResult _res(PingVerification v) =>
    PingResult(outcome: PingOutcome.ok, latencyMs: 42, verification: v);

/// Харнесс, который порта не даёт (как при не поднявшемся ядре кандидата) —
/// сети не касается вовсе.
class _FakeHarness implements ProbeHarness {
  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async =>
      _FakeHandle();

  @override
  bool get supportsProxyRequests => true;
}

class _FakeHandle implements HarnessHandle {
  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  @override
  int proxyPortFor(int index) => -1;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}

/// Подменённый контроллер: меню интересуют только ПРИЗНАКИ прогона, а сам
/// прогон проверяется выше настоящим [ProbeController].
class _FakeProbe extends ProbeController {
  bool runningNow = false;
  bool speedNow = false;
  Set<String> unfinishedNow = const {};

  /// Ключи ВСЕГО прогона, а не только тех, кто прямо сейчас в полёте:
  /// настоящий `runningKeys` отдаёт именно партию целиком (`_batchKeys`).
  /// Одного флага `running` мало — по нему подписка не отличит массовый прогон
  /// от перепроверки одной своей строки.
  Set<String> runningNowKeys = const {};
  final Map<String, PingResult> results = {};
  List<VpnServer>? pinged;

  /// С какими ключами меню позвало чистку пометки. `null` — не звало вовсе.
  List<String>? forgotten;

  @override
  Future<void> forgetUnknownServers(Iterable<String> knownKeys) async {
    forgotten = knownKeys.toList();
  }

  @override
  bool get running => runningNow;

  @override
  bool get speedRunning => speedNow;

  @override
  Set<String> get unfinishedKeys => unfinishedNow;

  @override
  Set<String> get runningKeys => runningNow ? runningNowKeys : const {};

  @override
  PingResult resultFor(VpnServer s) => results[s.key] ?? PingResult.untested;

  @override
  Future<void> pingAll(List<VpnServer> servers, AppSettings settings) async {
    pinged = servers;
  }

  void bump() => notifyListeners();
}

class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();

  @override
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
