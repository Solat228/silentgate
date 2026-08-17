import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// Пункт 5 владельца: «добавь пункт для выбора приложений на главном экране,
/// которые проверяются при запуске VPN соединения, с галочкой полного
/// отключения. Сама настройка спрятана под подменю».
///
/// До этого набор был ЗАШИТ константой `ServiceChecks.services`: шесть чипов у
/// кнопки Connect, шесть проб при каждом подъёме туннеля — независимо от того,
/// нужны ли человеку Discord и Instagram и хочет ли он вообще, чтобы при
/// подключении что-то куда-то ходило.
void main() {
  final l = AppLocalizationsRu();

  // ───────────────────────────────────────────────────────────────────────────
  group('Состав ряда — из настроек, а не из константы', () {
    test('выключенная галочка = не проверять НИЧЕГО', () {
      final s = AppSettings.defaults.copyWith(
        connectChecksEnabled: false,
        // Набор при этом сохранён: выключение — не стирание выбора, иначе
        // включив проверки обратно, человек начинал бы с чистого листа.
        connectCheckServices: {ProbeService.youtube, ProbeService.telegram},
      );
      expect(ServiceChecks.selected(s), isEmpty);
    });

    test('пустой набор при включённой галочке — тоже пусто', () {
      final s = AppSettings.defaults.copyWith(connectCheckServices: {});
      expect(ServiceChecks.selected(s), isEmpty,
          reason: 'снять все галочки — законный способ выключить проверки');
    });

    test('берётся ровно выбранное, а не зашитая шестёрка', () {
      final s = AppSettings.defaults
          .copyWith(connectCheckServices: {ProbeService.claude});
      expect(ServiceChecks.selected(s), [ProbeService.claude]);
      expect(ServiceChecks.selected(s), isNot(ServiceChecks.services),
          reason: 'ровно эта подмена константы на настройку и есть задача');
    });

    test('порядок — каталога, а не множества', () {
      // У `Set` порядок — порядок ВСТАВКИ. Если брать его как есть, чипы
      // перескакивали бы с места на место после каждой правки набора: снял
      // галочку с YouTube, вернул — и он уехал в конец.
      final s = AppSettings.defaults.copyWith(
          connectCheckServices: {ProbeService.google, ProbeService.youtube});
      expect(ServiceChecks.selected(s),
          [ProbeService.youtube, ProbeService.google]);
    });

    test('каталог подменю покрывает ВСЕ сервисы', () {
      // Список в `catalog` явный (ради порядка показа), поэтому новый
      // `ProbeService` легко забыть — и он станет невыбираемым: настройка его
      // хранить умеет, а показать негде.
      expect(ServiceChecks.catalog.toSet(), ProbeService.values.toSet());
      expect(ServiceChecks.catalog.length, ProbeService.values.length,
          reason: 'дубль в каталоге нарисовал бы две галочки одному сервису');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Раскладка по колонкам', () {
    test('шесть — поровну, как было', () {
      final c = ServiceChecks.columns(ServiceChecks.services);
      expect(c.left.length, 3);
      expect(c.right.length, 3);
    });

    test('нечётное уходит влево', () {
      final c = ServiceChecks.columns(const [
        ProbeService.youtube,
        ProbeService.chatgpt,
        ProbeService.telegram,
      ]);
      expect(c.left, [ProbeService.youtube, ProbeService.chatgpt]);
      expect(c.right, [ProbeService.telegram]);
    });

    test('пусто — пусты обе', () {
      final c = ServiceChecks.columns(const []);
      expect(c.left, isEmpty);
      expect(c.right, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Автопрогон при подключении', () {
    late Map<ProbeService, int> probed;
    late int readinessProbes;
    late ServiceCheckController ctrl;

    setUp(() {
      probed = {};
      readinessProbes = 0;
      ctrl = ServiceCheckController();
      // Ожидание готовности канала к правилу «когда прогонять» отношения не
      // имеет, а сети в тесте быть не должно: обе пробы подменены.
      ServiceCheckController.readinessDelay = Duration.zero;
      ServiceCheckController.readinessProbe = (port) async {
        readinessProbes++;
        return true;
      };
      ServiceCheckController.prober = (port, s) async {
        probed[s] = (probed[s] ?? 0) + 1;
        return const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 7);
      };
    });

    tearDown(() {
      ServiceCheckController.readinessAttempts = 6;
      ServiceCheckController.readinessDelay = const Duration(seconds: 2);
      ServiceCheckController.prober = ServiceChecker.check;
      ServiceCheckController.readinessProbe =
          ServiceCheckController.defaultReadinessProbe;
      ctrl.dispose();
    });

    int total() => probed.values.fold(0, (a, b) => a + b);

    test('выключенные проверки не гоняют ни одной пробы', () async {
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, const []);
      expect(total(), 0);
    });

    test('выключенные проверки не ходят в сеть ВООБЩЕ', () async {
      // ⚠️ Падает на старом поведении. `services.isEmpty` в страже не было —
      // был только комментарий, утверждавший, что есть. Пустой список доходил
      // до ожидания готовности канала и слал до шести запросов на
      // gstatic.com ЧЕРЕЗ ТУННЕЛЬ, а `Future.wait([])` ниже отрабатывал
      // вхолостую. Снаружи это ровно то, чего человек просил не делать,
      // снимая галочку «проверять при подключении»: проб сервисов не видно,
      // а трафик идёт.
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, const []);
      expect(readinessProbes, 0,
          reason: '«не проверять» означает «не ходить в сеть», а не '
              '«сходить и промолчать о результате»');
    });

    test('пустой набор НЕ съедает единственный автопрогон подъёма', () async {
      // ⚠️ Падает на старом поведении: `autoCheckAll` помечал подъём
      // отработанным ДО того, как смотрел на список, и `Future.wait([])`
      // отрабатывал вхолостую. Человек, включивший проверки при уже поднятом
      // туннеле, не получал ничего до переподключения.
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, const []);
      await ctrl.autoCheckAll(10809, const [ProbeService.youtube]);
      expect(total(), 1,
          reason: 'галочку вернули на живом канале — проверка обязана пойти');
    });

    test('один автопрогон на эпоху — правило цело', () async {
      ctrl.setTunnelUp(true);
      const set = [ProbeService.youtube, ProbeService.telegram];
      await ctrl.autoCheckAll(10809, set);
      final after = total();
      expect(after, 2);
      // Главный экран зовёт это на КАЖДОЙ перерисовке (счётчики тикают раз в
      // секунду) — повтор обязан быть отброшен.
      for (var i = 0; i < 5; i++) {
        ctrl.setTunnelUp(true);
        await ctrl.autoCheckAll(10809, set);
      }
      expect(total(), after);

      // Новый подъём — новый прогон, и уже по НОВОМУ составу.
      ctrl.setTunnelUp(false);
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, const [ProbeService.claude]);
      expect(probed[ProbeService.claude], 1);
      expect(total(), after + 1);
    });

    test('замер «до» пустым набором не помечается сделанным', () async {
      // Иначе выключенные на старте проверки лишали бы сравнения весь запуск:
      // включив их через минуту, человек получил бы одинокий кружок «через
      // VPN» без «до».
      await ctrl.autoBaseline(const []);
      await ctrl.autoBaseline(const [ProbeService.youtube]);
      expect(probed[ProbeService.youtube], 1);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Ряд чипов на главном', () {
    Widget host(Widget child) => MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChangeNotifierProvider(
            create: (_) => ServiceCheckController(),
            child: Scaffold(body: Center(child: child)),
          ),
        );

    Future<void> pump(WidgetTester t, List<ProbeService> services) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1040, 900);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(ConnectCenterpiece(
        serverName: null,
        httpPort: 0,
        services: services,
        button: const SizedBox(key: Key('btn'), width: 148, height: 148),
      )));
      await t.pump();
    }

    testWidgets('проверки выключены — ряд не занимает места вовсе', (t) async {
      await pump(t, const []);
      expect(find.byType(ServiceChecksColumn), findsNothing,
          reason: 'владелец просил «галочку полного отключения», а колонка с '
              'нулём чипов всё равно ела бы ширину у кнопки');
      // Кнопка при этом на месте и по центру.
      expect(find.byKey(const Key('btn')), findsOneWidget);
    });

    testWidgets('состав чипов = состав настройки', (t) async {
      await pump(t, const [ProbeService.claude, ProbeService.x]);
      final columns = t
          .widgetList<ServiceChecksColumn>(find.byType(ServiceChecksColumn))
          .toList();
      expect(columns.length, 2);
      expect([...columns[0].services, ...columns[1].services],
          [ProbeService.claude, ProbeService.x],
          reason: 'раньше здесь стояла зашитая шестёрка при любых настройках');
    });

    testWidgets('единственный сервис — одна колонка, а не две', (t) async {
      await pump(t, const [ProbeService.telegram]);
      expect(find.byType(ServiceChecksColumn), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Подменю у ряда проверок', () {
    late Directory tmp;
    late SettingsController settings;

    setUp(() {
      // ⚠️ Боевой каталог под тестами не отдаётся — объявляем свой.
      tmp = Directory.systemTemp.createTempSync('sg_connect_checks_');
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

    Widget host() => ChangeNotifierProvider<SettingsController>.value(
          value: settings,
          child: const MaterialApp(
            locale: Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
                body: Center(child: ServiceChecksMenuButton())),
          ),
        );

    Future<void> open(WidgetTester t) async {
      await t.pumpWidget(host());
      await t.tap(find.byType(ServiceChecksMenuButton));
      await t.pumpAndSettle();
    }

    testWidgets('открывается без исключений', (t) async {
      await open(t);
      expect(t.takeException(), isNull);
      expect(find.text(l.serviceChecksMenuTitle), findsOneWidget);
      for (final s in ServiceChecks.catalog) {
        expect(find.text(s.label), findsOneWidget,
            reason: '${s.label} нет в подменю — выбрать его нечем');
      }
    });

    testWidgets('ширина содержимого меню — ТУГАЯ', (t) async {
      await open(t);
      // ⚠️ Проверка СТРУКТУРНАЯ, и это осознанно.
      //
      // `showMenu` оборачивает содержимое в `IntrinsicWidth`, а тот спрашивает
      // у потомков внутренние размеры — прокручиваемая область на такой вопрос
      // бросает исключение. Сегодня внутри меню голая `Column`, поэтому и
      // диапазонное ограничение отрисовалось бы без единой жалобы: измерить
      // дефект нечем, пока его нет. Он появится ровно в тот день, когда список
      // сервисов подрастёт и кто-нибудь завернёт его в `ListView` — а чинить
      // его тогда придётся по красному экрану в debug (в release проверки
      // вырезаны, то есть до пользователя дефект и не доедет, зато доедет до
      // чужого `flutter run`).
      //
      // Поэтому стережём не симптом, а само средство: тугую ширину. Подмена её
      // на `ConstrainedBox(minWidth/maxWidth)` роняет этот тест — короткое
      // замыкание в `RenderConstrainedBox` работает только на ТУГИХ
      // ограничениях.
      final tight = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width != null && w.width! >= 200);
      expect(tight, findsOneWidget,
          reason: 'содержимое меню обязано иметь заданную ширину');
      expect(t.getSize(tight).width, 280,
          reason: '280 — штатный потолок ширины меню (_kMenuMaxWidth)');
    });

    testWidgets('галочка сервиса меняет настройку немедленно', (t) async {
      expect(settings.settings.connectCheckServices,
          isNot(contains(ProbeService.instagram)));
      await open(t);
      await t.tap(find.text(ProbeService.instagram.label));
      await t.pumpAndSettle();

      expect(settings.settings.connectCheckServices,
          contains(ProbeService.instagram),
          reason: 'кнопки «Сохранить» в меню нет — правка применяется сразу');
      expect(ServiceChecks.selected(settings.settings),
          contains(ProbeService.instagram),
          reason: 'а значит и ряд чипов на главном обязан её показать');
      // Меню осталось открытым: набор правят несколькими галочками подряд.
      expect(find.text(l.serviceChecksMenuTitle), findsOneWidget);

      // Повторное нажатие снимает.
      await t.tap(find.text(ProbeService.instagram.label));
      await t.pumpAndSettle();
      expect(settings.settings.connectCheckServices,
          isNot(contains(ProbeService.instagram)));
    });

    testWidgets('«не проверять при подключении» выключает проверки целиком',
        (t) async {
      await open(t);
      await t.tap(find.text(l.serviceChecksMenuOff));
      await t.pumpAndSettle();

      expect(settings.settings.connectChecksEnabled, isFalse);
      expect(ServiceChecks.selected(settings.settings), isEmpty,
          reason: 'ни чипов, ни автопрогона при подключении');
      // Набор сервисов при этом цел — включение вернёт прежний выбор.
      expect(settings.settings.connectCheckServices,
          AppSettings.defaults.connectCheckServices);

      // И вернуть проверки можно ровно отсюда же: на главном ряда больше нет.
      await t.tap(find.text(l.serviceChecksMenuOff));
      await t.pumpAndSettle();
      expect(settings.settings.connectChecksEnabled, isTrue);
    });

    testWidgets('при выключенных проверках галочки сервисов недоступны',
        (t) async {
      // ⚠️ `runAsync`: `update` дописывает настройки на ДИСК, а обычное `await`
      // внутри `testWidgets` живёт в поддельном времени и настоящего ввода-
      // вывода не дожидается — тест просто висел бы до таймаута.
      await t.runAsync(
          () => settings.update((c) => c.copyWith(connectChecksEnabled: false)));
      await open(t);
      final boxes = t
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      // Последняя галочка — «не проверять», она обязана остаться живой.
      expect(boxes.last.onChanged, isNotNull);
      expect(boxes.take(ServiceChecks.catalog.length).every((c) => c.onChanged == null),
          isTrue,
          reason: 'иначе непонятно, кто главнее: общий выключатель или галочка '
              'отдельного сервиса');
    });
  });
}
