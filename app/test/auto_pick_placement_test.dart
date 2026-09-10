import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/servers_screen.dart';
import 'package:silentgate/ui/widgets/auto_pick_button.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';
import 'package:silentgate/ui/widgets/site_favicon.dart';

/// КНОПКА ПОДБОРА ЖИВЁТ НАД СПИСКОМ СЕРВЕРОВ — ГДЕ БЫ СПИСОК НИ РИСОВАЛСЯ.
///
/// Правило владельца (10.09.2026): «с переносом выбора автосервера ближе к
/// серверам, где-нибудь сверху». Список рисуется в двух местах — правая панель
/// широкого окна и отдельный экран на узком, — и кнопка обязана быть в обоих;
/// внизу главного экрана она остаётся ЗАПАСНОЙ и только там, где списка с этого
/// экрана не видно.
///
/// ⚠️ ЧЕГО НЕ ХВАТАЛО РАНЬШЕ. Пока `_ConnectPane`/`_ServerPane` были
/// приватными, проверить раскладку панели было нечем: стражи поднимали
/// публичный `ConnectCenterpiece`, а переполнялась панель — ровно поэтому
/// жалоба «низ обрезан» дожила до владельца. Теперь поднимается [HomeBody],
/// то есть то самое место, где кнопка либо есть, либо её нет.
void main() {
  late Directory tmp;

  /// Три сервера: число видно в поясняющей строке кнопки.
  const linkA = 'vless://11111111-2222-3333-4444-555555555555'
      '@a.example.com:443?encryption=none#Germany';
  const linkB = 'vless://11111111-2222-3333-4444-555555555555'
      '@b.example.com:443?encryption=none#Netherlands';
  const linkC = 'vless://11111111-2222-3333-4444-555555555555'
      '@c.example.com:443?encryption=none#USA';

  late Future<ServiceCheckOutcome> Function(int, ProbeService) savedProber;

  setUp(() {
    // ⚠️ ПРОБЫ СЕРВИСОВ — ЗАГЛУШКОЙ. Блок проверок сам заводит замер «до» при
    // первом же кадре, а это НАСТОЯЩИЕ сокеты: тест висел на них и падал
    // «A Timer is still pending». Сети в стражах вёрстки быть не должно.
    savedProber = ServiceCheckController.prober;
    ServiceCheckController.prober = (port, s) async =>
        const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 42);
    // ⚠️ Боевой `%APPDATA%` тестам недоступен (`AppPaths`), и это не формальность:
    // тест уже переписывал владельцу subscriptions.json.
    tmp = Directory.systemTemp.createTempSync('sg_auto_pick_');
    AppPaths.overrideRoot(tmp);
    File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp.path}${Platform.pathSeparator}subscriptions.json')
        .writeAsStringSync(jsonEncode({
      'activeId': 'sub-test',
      'items': [
        {
          'id': 'sub-test',
          'url': 'https://panel.example/sub',
          'title': 'Test',
          'servers': [linkA, linkB, linkC],
          'addedAt': '2026-09-01T00:00:00.000Z',
        },
      ],
    }));
  });

  tearDown(() async {
    ServiceCheckController.prober = savedProber;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Настройки владельца: проверок четырнадцать — самый тесный случай, ради
  /// которого низ экрана и сжимали.
  const fourteen = AppSettings(
      connectCheckServices: {...ServiceChecks.catalog},
      serviceChecksLayout: ServiceChecksLayout.sides);

  /// ⚠️ ЧЕРЕЗ `runAsync`, И БЕЗ ЭТОГО ТЕСТ ПРОСТО ВИСНЕТ. Тело `testWidgets`
  /// живёт в поддельном времени: таймеры двигает `pump`, а настоящие
  /// файловые операции (`AppState.init` читает четыре файла с диска) в нём не
  /// завершаются НИКОГДА — не падают, а именно висят. Диагноз выглядит как
  /// «тест зациклился», хотя зациклиться там нечему.
  Future<AppState> boot(WidgetTester t) async {
    final state = AppState(engine: _FakeEngine());
    await t.runAsync(() => state.init());
    return state;
  }

  Widget host(Widget child, AppState state, {double textScale = 1.0}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ProbeController>.value(
              value: ProbeController()),
          ChangeNotifierProvider<SettingsController>.value(
              value: SettingsController()),
          ChangeNotifierProvider<AutoConfigController>.value(
              value: AutoConfigController()),
          ChangeNotifierProvider<ServiceCheckController>.value(
              value: ServiceCheckController()),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Поднять тело главного экрана на окне [size].
  Future<AppState> pumpHome(
    WidgetTester t, {
    required Size size,
    AppSettings settings = fourteen,
    double textScale = 1.0,
    VpnStatus status = const VpnStatus.disconnected(),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final state = await boot(t);
    await t.pumpWidget(host(
      HomeBody(
        status: status,
        settings: settings,
        onOpen: (_) {},
      ),
      state,
      textScale: textScale,
    ));
    await t.pump();
    return state;
  }

  group('⚠️ кнопка стоит над списком, а не в двух местах сразу', () {
    testWidgets('широкое окно: кнопка в правой панели и НЕ внизу', (t) async {
      await pumpHome(t, size: const Size(1024, 781));
      expect(t.takeException(), isNull);

      expect(find.byType(ServerPane), findsOneWidget,
          reason: 'на широком окне список серверов рисуется справа');
      expect(
          find.descendant(
              of: find.byType(ServerPane),
              matching: find.byType(AutoPickServerButton)),
          findsOneWidget,
          reason: 'кнопки подбора нет над списком серверов');
      expect(
          find.descendant(
              of: find.byType(ConnectPane),
              matching: find.byType(AutoPickServerButton)),
          findsNothing,
          reason: 'на широком окне запасная кнопка внизу не нужна: список '
              'виден справа, и это был бы второй такой же вход рядом с первым');
      expect(find.byType(AutoPickServerButton), findsOneWidget,
          reason: 'кнопка обязана быть ровно одна на экране');
      // Поясняющая строка называет ЧИСЛО серверов: их три.
      expect(
          find.descendant(
              of: find.byType(AutoPickServerButton),
              matching: find.textContaining('3')),
          findsOneWidget,
          reason: 'кнопка над списком обязана объяснять, что она сделает и '
              'скольких серверов это касается');
    });

    testWidgets('⚠️ плашка сервера осталась на оси кнопки Connect', (t) async {
      // Значок «Информация о сервере» встал в ЛЕВЫЙ край полосы плашки. Без
      // симметричной распорки справа плашка съехала бы с оси кнопки на
      // половину ширины хвоста — 30 px, заметно глазом.
      await pumpHome(t, size: const Size(1024, 781));
      final label = t.getRect(find.byType(ActiveServerLabel));
      final button = t.getRect(find.byType(ConnectButton));
      expect(label.center.dx, closeTo(button.center.dx, 1.0),
          reason: 'плашка уехала от оси кнопки на '
              '${(label.center.dx - button.center.dx).abs().toStringAsFixed(1)}'
              ' px');
    });

    testWidgets('узкое окно: кнопка внизу, правой панели нет вовсе', (t) async {
      await pumpHome(t, size: const Size(500, 800));
      expect(t.takeException(), isNull);

      expect(find.byType(ServerPane), findsNothing,
          reason: 'на узком окне список уезжает на отдельный экран');
      expect(
          find.descendant(
              of: find.byType(ConnectPane),
              matching: find.byType(AutoPickServerButton)),
          findsOneWidget,
          reason: 'списка с этого экрана не видно — запасная кнопка внизу '
              'остаётся единственным входом в подбор');
      // ⚠️ ОБЕ КНОПКИ В ОДНОЙ СТРОКЕ `Wrap`, а не столбиком: ради этих 48 px
      // низ и сжимали. Именно `Wrap`, а не `Row`, — на узком окне с крупным
      // шрифтом две подписи в строку не влезают, и `Row` дал бы переполнение
      // вместо переноса.
      final wrap = find.ancestor(
          of: find.byType(AutoPickServerButton), matching: find.byType(Wrap));
      expect(wrap, findsOneWidget,
          reason: 'кнопка подбора встала не в общую строку');
      expect(
          find.descendant(of: wrap, matching: find.byType(OutlinedButton)),
          findsOneWidget,
          reason: '«Подобрать настройки» пропала из общей строки');
    });

    testWidgets('экран списка серверов: кнопка над списком', (t) async {
      t.view.physicalSize = const Size(500, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final state = await boot(t);
      await t.pumpWidget(host(const ServersScreen(), state));
      await t.pump();
      expect(t.takeException(), isNull);

      expect(find.byType(AutoPickServerButton), findsOneWidget);
      // Именно НАД списком: ниже поля поиска и выше первой строки.
      final btn = t.getRect(find.byType(AutoPickServerButton));
      final list = t.getRect(find.byType(ListView));
      expect(btn.bottom, lessThanOrEqualTo(list.top + 0.5),
          reason: 'кнопка оказалась внутри списка — прокрутка унесёт её');
    });

    test('⚠️ страж от расхождения копий: все три места — один виджет', () {
      // Разъехавшиеся копии одной кнопки в этом проекте уже давали
      // расхождение поведения (гейт пинга закрывал две точки входа из
      // четырёх). Свой `FilledButton` с тем же ярлыком где-то ещё означал бы
      // ровно это.
      String code(String path) => File(path)
          .readAsLinesSync()
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join(String.fromCharCode(10));

      final home = code('lib/ui/home_screen.dart');
      final servers = code('lib/ui/servers_screen.dart');
      final widget = code('lib/ui/widgets/auto_pick_button.dart');

      // Три места вызова: панель, экран списка, низ главного.
      expect('AutoPickServerButton('.allMatches(home).length, 2,
          reason: 'главный экран зовёт кнопку не из двух мест');
      expect(servers, contains('AutoPickServerButton('));
      // Ярлык кнопки читает ТОЛЬКО сам виджет. Появление `homeAutoBest` в
      // кнопке где-то ещё — это и есть вторая копия.
      expect(widget, contains('l.homeAutoBest'));
      for (final f in [home, servers]) {
        expect(f.contains('label: Text(l.homeAutoBest)'), isFalse,
            reason: 'кнопка подбора собрана второй раз своими руками');
      }
      // И действие тоже одно: подключение «Авто» зовётся из виджета.
      expect(widget, contains('connectAuto'));
      expect(home.contains('state.connectAuto('), isFalse,
          reason: 'главный экран подключает «Авто» в обход общей кнопки');
    });
  });

  group('⚠️ «Информация о сервере» не потеряна и держится сервера', () {
    /// Подключённый туннель: имя сессии в плашке появляется только при
    /// `isConnected`. Ключ поднятого узла у поддельного движка пуст, поэтому
    /// плашка называет сессию «Авто» — для геометрии это то же самое.
    const live = VpnStatus(VpnConnectionState.connected);

    testWidgets('доступна с главного экрана значком у плашки', (t) async {
      // Регресс-страж: кнопку убрали снизу, и потерять её целиком было бы
      // легко — второй вход в этот экран только в контекстном меню строки
      // списка, где его никто не находит.
      await pumpHome(t, size: const Size(1024, 781), status: live);
      final info = find.byType(ServerInfoButton);
      expect(info, findsOneWidget);
      expect(
          find.descendant(
              of: info, matching: find.byIcon(ServerInfoButton.icon)),
          findsOneWidget,
          reason: 'сервер выбран — кнопка обязана быть нажимаемой');

      // ⚠️ ДВА ОДИНАКОВЫХ «i» НА ОДНОЙ ПОЛОСЕ — ЭТО РЕБУС, А НЕ ОФОРМЛЕНИЕ.
      // У плашки — вход на целый экран (внешний адрес, страна, провайдер,
      // скорость), у правого края — всплывающее пояснение про проверки
      // сервисов. Подписей на полосе нет; пока глифы совпадали, назначение
      // каждого выяснялось только нажатием.
      expect(ServerInfoButton.icon, isNot(Icons.info_outline),
          reason: 'значок сервера снова стал неотличим от подсказки рядом');
      final banner0 = find.byType(ActiveServerBanner);
      expect(
          find.descendant(
              of: banner0, matching: find.byIcon(Icons.info_outline)),
          findsOneWidget,
          reason: '«i» на полосе обязано быть ровно одно — у подсказки');

      // ⚠️ И У ОБЕИХ КНОПОК ОБЯЗАНА БЫТЬ ПОДСКАЗКА ПРИ НАВЕДЕНИИ, причём
      // РАЗНАЯ: по ней и понятно, куда ведёт каждая.
      final tips = t
          .widgetList<Tooltip>(
              find.descendant(of: banner0, matching: find.byType(Tooltip)))
          .map((w) => w.message)
          .whereType<String>()
          .toSet();
      expect(tips.length, greaterThanOrEqualTo(2),
          reason: 'на полосе меньше двух РАЗНЫХ подсказок — значит какая-то '
              'кнопка молчит либо повторяет соседнюю');

      // ⚠️ ГЕОМЕТРИЯ, А НЕ «ЛЕЖИТ В ТОМ ЖЕ РОДИТЕЛЕ». Владелец прислал снимок:
      // значок висел сам по себе у левого края полосы, плашка — по центру,
      // связи между ними глазом не видно. Значит проверять надо расстояние.
      final banner = t.getRect(banner0);
      final icon = t.getRect(
          find.descendant(of: info, matching: find.byType(IconButton)));
      final label = t.getRect(find.byType(ActiveServerLabel));
      final gap = label.left - icon.right;
      expect(gap, greaterThanOrEqualTo(0), reason: 'значок наехал на плашку');
      expect(gap, lessThanOrEqualTo(10),
          reason: 'значок оторвался от плашки на ${gap.toStringAsFixed(1)} px '
              '— это и есть жалоба владельца');
      expect(icon.top, greaterThanOrEqualTo(banner.top - 0.5));
      expect(icon.bottom, lessThanOrEqualTo(banner.bottom + 0.5),
          reason: 'кнопка вылезла из полосы плашки — та поднялась бы, и весь '
              'выигрыш от переезда ушёл бы обратно');

      // ⚠️ ЦЕНТРИРУЕТСЯ ГРУППА ЦЕЛИКОМ. Плашка одна на оси кнопки, а значок
      // сбоку — это перекошенная пара, и перекос виден глазом.
      final connect = t.getRect(find.byType(ConnectButton));
      final group = icon.expandToInclude(label);
      expect(group.center.dx, closeTo(connect.center.dx, 1.5),
          reason: 'группа «значок + плашка» уехала с оси кнопки Connect на '
              '${(group.center.dx - connect.center.dx).abs().toStringAsFixed(1)}'
              ' px');

      // ⚠️ И полосы под статусом больше нет: её 48 px и есть предмет правки.
      expect(
          find.descendant(
              of: find.byType(ConnectPane),
              matching: find.widgetWithIcon(TextButton, Icons.info_outline)),
          findsNothing,
          reason: 'строка «Информация о сервере» вернулась под статус');
    });

    testWidgets('⚠️ VPN выключен — значка нет, а полоса на месте', (t) async {
      // Требование владельца 10.09.2026: «если VPN выключен, то и информация
      // о сервере должна пропасть, так как VPN сервер не выбран». Это решение
      // об интерфейсе: сам экран работает и без туннеля (меряет харнессом), и
      // открыть его по-прежнему можно из контекстного меню строки списка.
      await pumpHome(t, size: const Size(1024, 781), status: live);
      final bannerOn = t.getRect(find.byType(ActiveServerBanner));
      final connectOn = t.getRect(find.byType(ConnectButton));

      await pumpHome(t, size: const Size(1024, 781));
      expect(find.byType(ServerInfoButton), findsNothing,
          reason: 'значок пережил отключение VPN — владелец просил обратного');
      expect(find.byIcon(ServerInfoButton.icon), findsNothing,
          reason: 'значок остался на экране где-то ещё');

      // Полоса и кнопка Connect не двигаются: иначе весь блок дёргался бы на
      // каждом подключении.
      final bannerOff = t.getRect(find.byType(ActiveServerBanner));
      expect(bannerOff.height, closeTo(bannerOn.height, 0.5),
          reason: 'полоса просела с ${bannerOn.height} до ${bannerOff.height}');
      expect(t.getRect(find.byType(ConnectButton)).center.dy,
          closeTo(connectOn.center.dy, 0.5),
          reason: 'кнопка Connect прыгает при подключении');

      // Хвост полосы — про ПРОВЕРКИ, а не про сервер: он виден всегда, иначе
      // выключенные проверки будет неоткуда включить обратно.
      expect(
          find.descendant(
              of: find.byType(ActiveServerBanner),
              matching: find.byIcon(Icons.info_outline)),
          findsOneWidget,
          reason: 'подсказка проверок пропала вместе с сервером');
      expect(find.byType(ServiceChecksMenuButton), findsOneWidget,
          reason: 'подменю проверок пропало вместе с сервером');
    });
  });

  group('⚠️ резерв под потолком равен тому, что реально ниже него', () {
    testWidgets('замер по настоящей вёрстке панели', (t) async {
      // ⚠️ ЗАМЕР, А НЕ АРИФМЕТИКА НА ГЛАЗ. Прежний резерв (214) был неверным и
      // «работал» только потому, что блок никогда не дорастал до потолка.
      // Здесь считается ровно то, что лежит ниже `ConstrainedBox`: от нижней
      // кромки блока до нижней кромки счётчиков трафика, минус распорка
      // `Spacer` между ними (её высота — свободный остаток, а не резерв).
      t.view.physicalSize = const Size(980, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final state = await boot(t);
      await t.pumpWidget(host(
        const SizedBox(
          // Высота с запасом: замеряются МИНИМАЛЬНЫЕ высоты того, что лежит
          // ниже потолка, и свободный остаток из формулы вычитается отдельно.
          width: 535,
          height: 820,
          child: ConnectPane(
            status: VpnStatus.disconnected(),
            settings: AppSettings(),
            onOpen: _noop,
          ),
        ),
        state,
      ));
      await t.pump();
      expect(t.takeException(), isNull);

      final centerpiece = t.getRect(find.byType(ConnectCenterpiece));
      final traffic = t.getRect(find.byType(TrafficRow));
      final spacers = find.descendant(
          of: find.byType(ConnectPane), matching: find.byType(Spacer));
      expect(spacers, findsNWidgets(2),
          reason: 'распорок стало не две — формула замера больше не верна');
      // Нижняя распорка — та, что между блоком и счётчиками.
      final slack = t.getSize(spacers.last).height;
      final measured = traffic.bottom - centerpiece.bottom - slack;

      expect(measured, closeTo(kChecksReserveBelow, 1.0),
          reason: 'ниже потолка лежит $measured px, а резерв обещает '
              '$kChecksReserveBelow — низ панели уедет за край ровно на '
              'разницу');
    });
  });

  group('⚠️ замер: значок сервиса после сжатия низа', () {
    // Окна из снимков в VM: минимальное 980×800 (панель 535) и рабочее
    // 1040×820 (панель 595). До сжатия низа значок был 18,8 px.
    // Замеренные значения: до сжатия низа значок был 18,8 px.
    const measured = <(Size, double)>[
      (Size(980, 800), 28.0),
      (Size(1040, 820), 32.5),
    ];
    for (final (w, expected) in measured) {
      testWidgets('окно ${w.width.toInt()}×${w.height.toInt()}', (t) async {
        await pumpHome(t, size: w);
        expect(t.takeException(), isNull);
        final pane = t.getRect(find.byType(ConnectCenterpiece));
        final icon = t.getRect(find.byType(SiteFavicon).first);
        // ignore: avoid_print
        print('ICON>>> окно=${w.width.toInt()}×${w.height.toInt()} '
            'ширина блока=${pane.width.toStringAsFixed(1)} '
            'высота блока=${pane.height.toStringAsFixed(1)} '
            'значок=${icon.width.toStringAsFixed(1)}');
        expect(icon.width, greaterThan(18.8),
            reason: 'значок не вырос — сжатие низа не дошло до блока проверок');
        expect(icon.width, closeTo(expected, 0.6),
            reason: 'размер значка разошёлся с замером в отчёте — либо низ '
                'снова растёт, либо изменилась раскладка блока');
      });
    }

    testWidgets('⚠️ на 980 рост упирается в ШИРИНУ', (t) async {
      // Важно для будущих правок низа: на этой ширине дальше сжимать низ ради
      // значков бессмысленно — лишняя высота им уже не достаётся.
      await pumpHome(t, size: const Size(980, 800));
      final tight = t.getRect(find.byType(SiteFavicon).first).width;
      await pumpHome(t, size: const Size(980, 1100));
      final tall = t.getRect(find.byType(SiteFavicon).first).width;
      // ignore: avoid_print
      print('ICON-TALL>>> 980×800=$tight 980×1100=$tall');
      expect(tall, closeTo(tight, 0.5),
          reason: 'значок вырос от высоты — значит потолок по ширине ещё не '
              'достигнут, и вывод «дальше сжимать низ бесполезно» неверен');
    });

    testWidgets('⚠️ а на 1024×781 высота ЕЩЁ ограничивает рост', (t) async {
      // ⚠️ ПРЕЖНИЙ ВЫВОД БЫЛ НЕВЕРЕН, И ОШИБКА БЫЛА В ЗАМЕРЕ, А НЕ В КОДЕ.
      // «31,3 px, упирается ШИРИНА» снято с ФИКСИРОВАННОЙ коробки 595×438
      // (тест «замер на панелях 535 и 595 из брифа» ниже) — то есть с высоты,
      // которой на настоящем окне 1024×781 у панели нет. На нём значок ещё
      // растёт от высоты, и 31,3 достигается только начиная примерно с
      // 1024×900. Вывод «дальше сжимать низ бесполезно» верен для 980, но не
      // для 1024: там ещё есть что выигрывать.
      await pumpHome(t, size: const Size(1024, 781));
      final short = t.getRect(find.byType(SiteFavicon).first).width;
      await pumpHome(t, size: const Size(1024, 900));
      final tall = t.getRect(find.byType(SiteFavicon).first).width;
      // ignore: avoid_print
      print('ICON-1024>>> 781=$short 900=$tall');
      expect(short, lessThan(tall),
          reason: 'на 1024×781 значок уже достиг потолка по ширине — значит '
              'вернулся вывод, который замер опроверг');
      expect(short, closeTo(30.96, 0.15));
      expect(tall, closeTo(31.30, 0.15));
    });

    testWidgets('замер на панелях 535 и 595 из брифа', (t) async {
      // Владелец называл ширины панели 535 и 595; на самом деле панель шире
      // (551 и 611: окно минус список 380, разделитель и отступы 2×24).
      // Меряем и то, и другое — чтобы числа в отчёте нельзя было спутать.
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final state = await boot(t);
      for (final box in const [Size(535, 383), Size(595, 438)]) {
        await t.pumpWidget(host(
          SizedBox(
            width: box.width,
            height: box.height,
            child: const ConnectCenterpiece(
              serverName: 'DE-1',
              httpPort: 10809,
              services: ServiceChecks.catalog,
              layout: ServiceChecksLayout.sides,
              button: SizedBox(width: 148, height: 148),
            ),
          ),
          state,
        ));
        await t.pump();
        final icon = t.getRect(find.byType(SiteFavicon).first).width;
        // ignore: avoid_print
        print('ICON-BRIEF>>> панель=${box.width.toInt()} '
            'значок=${icon.toStringAsFixed(1)}');
        // 26,8 на 535 и 31,3 на 595.
        //
        // ⚠️ ЭТО ЧИСЛА С ФИКСИРОВАННОЙ КОРОБКИ, А НЕ С НАСТОЯЩЕГО ОКНА, и
        // путать их дорого: коробка 595×438 даёт блоку столько высоты, сколько
        // на окне 1024×781 у панели НЕТ. На настоящем окне той же ширины
        // значок 30,96 (тест «а на 1024×781 высота ЕЩЁ ограничивает рост»), и
        // 31,3 набирается только к 1024×900. Отсюда и неверный вывод «упирается
        // ШИРИНА»: он верен для 980, но не для 1024.
        expect(icon, closeTo(box.width == 535 ? 26.8 : 31.3, 0.6));
      }
    });
  });

  group('⚠️ переполнения нет в тесном окне', () {
    for (final size in const [Size(964, 761), Size(1024, 781), Size(980, 800)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}', (t) async {
        await pumpHome(t, size: size);
        expect(t.takeException(), isNull,
            reason: 'низ панели снова уехал за край окна');
      });
    }

    for (final size in const [Size(964, 761), Size(1024, 781)]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} при шрифте ×1,3',
          (t) async {
        // Крупный системный шрифт растит ровно то, что лежит НИЖЕ потолка
        // (статус, подписи кнопок, счётчики). Потолок обязан отступить на
        // столько же — иначе правка ради тесного окна ломается на первом же
        // человеке с плохим зрением.
        await pumpHome(t, size: size, textScale: 1.3);
        expect(t.takeException(), isNull,
            reason: 'при шрифте ×1,3 низ панели переполнился');
      });
    }
  });

  /// ⚠️ ПЛАШКА KILL SWITCH И СТРОКА ОШИБКИ ЛЕЖАТ НИЖЕ ПОТОЛКА.
  ///
  /// Это ровно тот случай, ради которого низ и сжимали: у владельца включены
  /// все четырнадцать сервисов. Он подключается, связь рвётся, kill switch
  /// держит трафик — и появляется красная плашка, которую и добавляли, чтобы
  /// человек не выключил VPN с перепугу. Если вёрстка ломается именно в этот
  /// момент, добавленное объяснение делает хуже, чем его отсутствие.
  ///
  /// Обе врезки стоят НИЖЕ `ConstrainedBox` и в резерв не входили вовсе, а
  /// блок проверок теперь честно съедает выданный ему потолок целиком.
  group('⚠️ плашка блокировки и строка ошибки входят в резерв', () {
    /// Короткое сообщение — в одну строку.
    const short = 'Трафик заблокирован защитой';

    /// ⚠️ ДЛИННОЕ — РОВНО В ДВЕ СТРОКИ, И ЭТО ПРОВЕРЯЕТСЯ ОТДЕЛЬНО (тест
    /// «длинное сообщение и правда переносится»). Шрифт в `flutter_test`
    /// моноширинный и много шире настоящего (знак = кегль), поэтому «длинное»
    /// здесь короче, чем выглядело бы в жизни: считать длину в знаках по
    /// экранному шрифту нельзя.
    const long = 'Трафик заблокирован защитой, связь разорвана';

    /// Все четыре сочетания: только блокировка, только ошибка, обе сразу и
    /// длинный текст в две строки.
    const cases = <(String, VpnStatus)>[
      (
        'только блокировка',
        VpnStatus(VpnConnectionState.connected,
            message: short, blocking: true)
      ),
      (
        'только ошибка',
        VpnStatus(VpnConnectionState.error, message: short)
      ),
      (
        'блокировка и ошибка сразу',
        VpnStatus(VpnConnectionState.error, message: short, blocking: true)
      ),
      (
        'длинное сообщение в две строки',
        VpnStatus(VpnConnectionState.error, message: long, blocking: true)
      ),
    ];

    for (final size in const [
      Size(964, 761),
      Size(980, 800),
      Size(1024, 781)
    ]) {
      for (final scale in const [1.0, 1.3]) {
        for (final (name, status) in cases) {
          testWidgets(
              '${size.width.toInt()}×${size.height.toInt()} '
              '×${scale.toStringAsFixed(1)}: $name', (t) async {
            await pumpHome(t, size: size, textScale: scale, status: status);
            expect(t.takeException(), isNull,
                reason: 'панель переполнилась: врезки под потолком не попали '
                    'в резерв');
          });
        }
      }
    }

    testWidgets('длинное сообщение и правда переносится на вторую строку',
        (t) async {
      // Иначе случай «в две строки» из матрицы выше — самообман: одну строку
      // укладывает любая формула, ошибаются на второй.
      await pumpHome(t,
          size: const Size(964, 761),
          status: const VpnStatus(VpnConnectionState.connected,
              message: long, blocking: true));
      final tall = t.getSize(find.byType(KillSwitchNotice)).height;
      await pumpHome(t,
          size: const Size(964, 761),
          status: const VpnStatus(VpnConnectionState.connected,
              message: short, blocking: true));
      final one = t.getSize(find.byType(KillSwitchNotice)).height;
      expect(tall, greaterThan(one),
          reason: 'длинное сообщение уложилось в одну строку — случай «в две '
              'строки» ничего не проверяет');
    });

    testWidgets('⚠️ резерв под врезки замерен, а не прикинут', (t) async {
      // Числа в комментариях к `blockingNoticeHeight`/`errorLineHeight`
      // обязаны совпадать с тем, что реально занимают эти два блока. Иначе
      // потолок отступает не на столько, на сколько нужно, и разница уезжает
      // за край окна — то есть ровно та беда, которую и чиним.
      await pumpHome(t,
          size: const Size(1024, 781),
          status: const VpnStatus(VpnConnectionState.error,
              message: short, blocking: true));
      expect(t.takeException(), isNull);

      // Обе врезки занимают всю ширину, доступную колонке панели, — от неё и
      // считается перенос текста.
      final notice = t.getRect(find.byType(KillSwitchNotice));
      final error = t.getRect(find.byType(ConnectErrorLine));
      final paneWidth = notice.width;
      final ctx = t.element(find.byType(KillSwitchNotice));
      final style = DefaultTextStyle.of(ctx).style;
      final scaler = MediaQuery.textScalerOf(ctx);

      expect(
          blockingNoticeHeight(
              paneWidth: paneWidth, style: style, scaler: scaler, text: short),
          closeTo(notice.height, 1.0),
          reason: 'расчёт плашки разошёлся с её настоящей высотой '
              '(${notice.height} px)');
      expect(
          errorLineHeight(
              paneWidth: paneWidth, style: style, scaler: scaler, text: short),
          closeTo(error.height, 1.0),
          reason: 'расчёт строки ошибки разошёлся с её настоящей высотой '
              '(${error.height} px)');

      // ⚠️ И ТО ЖЕ НА ДЛИННОМ ТЕКСТЕ. Одна строка укладывается в расчёт у
      // любой формулы; ошибаются на второй.
      expect(
          blockingNoticeHeight(
              paneWidth: paneWidth, style: style, scaler: scaler, text: long),
          greaterThan(blockingNoticeHeight(
              paneWidth: paneWidth, style: style, scaler: scaler, text: short)),
          reason: 'длинное сообщение переносится на вторую строку, а расчёт '
              'этого не заметил');
    });
  });
}

void _noop(Widget _) {}

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
