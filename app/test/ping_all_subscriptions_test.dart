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
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/subscription_switcher.dart';

/// Пинг ВСЕХ подписок и счётчик у каждой (план 1.4.2, задача 7).
///
/// ⚠️ ЧТО ИМЕННО ЗДЕСЬ СТЕРЕЖЁТСЯ.
///
/// 1. Пункт «Пинг серверов» в меню переключателя раньше гонял `state.servers` —
///    то есть ровно то же, что кнопка на главном экране: серверы ОДНОЙ,
///    активной подписки. Владелец просил обратного: в меню — все подписки
///    (у него их четыре, 124 сервера), кнопка на главном остаётся прежней.
///    Мысленно вернув `state.servers`, первый тест краснеет: серверов будет 2
///    вместо 5.
/// 2. Серверы неактивных подписок существуют на диске ТОЛЬКО ссылками —
///    объекты `VpnServer` для них строит переключение подписки. Пинг «по
///    ссылкам» молча ушёл бы в пустоту, поэтому второй блок проверяет само
///    восстановление, и отдельно — что активная подписка при этом НЕ меняется
///    (человек просил пинг, а не смену канала).
/// 3. Счётчик «всего · рабочих» считает рабочим только
///    [PingVerification.passed]. Достижимость по TCP рабочим не делает — на
///    этой подмене уже горели зелёные плашки у серверов, через которые не
///    работало ничего. До проверки канала число рабочих не показывается
///    вовсе: ноль означал бы «проверили и ни один не работает».
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

/// Пинг наружу не уходит: нас интересует ТОЛЬКО список, который пункт меню
/// отдаёт на прогон.
class _SpyProbe extends ProbeController {
  List<VpnServer>? pinged;

  @override
  Future<void> pingAll(List<VpnServer> servers, AppSettings settings) async {
    pinged = servers;
  }
}

/// Готовый результат пинга с нужным состоянием проверки канала.
PingResult _res(PingVerification v) =>
    PingResult(outcome: PingOutcome.ok, latencyMs: 42, verification: v);

void main() {
  final l = AppLocalizationsRu();

  // Серверы нарочно разных подписок и с разными адресами: ключ сервера — это
  // его каноническая ссылка, и совпадение адресов склеило бы записи.
  const a1 = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
      '?type=tcp&security=none#Alpha-1';
  const a2 = 'vless://11111111-1111-1111-1111-111111111111@a2.example:443'
      '?type=tcp&security=none#Alpha-2';
  const b1 = 'vless://22222222-2222-2222-2222-222222222222@b1.example:443'
      '?type=tcp&security=none#Bravo-1';
  const b2 = 'vless://22222222-2222-2222-2222-222222222222@b2.example:443'
      '?type=tcp&security=none#Bravo-2';
  const b3 = 'vless://22222222-2222-2222-2222-222222222222@b3.example:443'
      '?type=tcp&security=none#Bravo-3';

  const urlA = 'https://panel.example/sub/aaaaaaaa';
  const urlB = 'https://panel.example/sub/bbbbbbbb';
  final idA = SubscriptionProfile.idFor(urlA);
  final idB = SubscriptionProfile.idFor(urlB);

  Directory? tmp;
  late AppState state;
  late _SpyProbe probe;
  late SettingsController settings;

  /// Две подписки на диске: активная A и НЕАКТИВНАЯ B.
  ///
  /// Кладём `subscriptions.json` до `init()` — это единственный способ получить
  /// здесь настоящую неактивную подписку: `importSource` ходит в сеть, а
  /// подделывать профили мимо `AppState` значило бы проверять не тот путь,
  /// которым подписки доходят до меню после перезапуска приложения.
  Future<void> boot({
    List<String> serversA = const [a1, a2],
    List<String> serversB = const [b1, b2, b3],
  }) async {
    tmp = Directory.systemTemp.createTempSync('sg_ping_all_');
    AppPaths.overrideRoot(tmp!);
    final sep = Platform.pathSeparator;
    // Автообновление подписки в тесте не нужно: оно завело бы таймеры и полезло
    // бы на version-эндпоинт панели.
    File('${tmp!.path}${sep}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp!.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
      'activeId': idA,
      'items': [
        {'id': idA, 'url': urlA, 'servers': serversA},
        {'id': idB, 'url': urlB, 'servers': serversB},
      ],
    }));
    state = AppState(engine: _FakeEngine());
    await state.init();
    probe = _SpyProbe();
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
          // Переключатель сверху слева: меню открывается ПОД ним, и из середины
          // экрана нижние пункты уехали бы за край тестового холста 800×600.
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SubscriptionSwitcher(title: 'Alpha'),
            ),
          ),
        ),
      );

  /// Открыть меню переключателя.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(SubscriptionSwitcher));
    // ⚠️ НЕ pumpAndSettle: во время прогона в меню крутится индикатор, а он
    // анимируется бесконечно — «дождаться покоя» здесь означает ждать вечно и
    // упасть по таймауту. Хватает ограниченного числа кадров: маршрут меню
    // открывается за один-два.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp?.deleteSync(recursive: true);
    } catch (_) {}
    tmp = null;
  });

  group('Пункт меню пингует ВСЕ подписки, а не активную', () {
    testWidgets('на прогон уходят серверы обеих подписок', (tester) async {
      await tester.runAsync(boot);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // На главном экране видна только активная подписка — именно её список и
      // уходил на пинг раньше.
      expect(state.servers.length, 2);

      await openMenu(tester);
      await tester.tap(find.text(l.subSwitcherPingAll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(probe.pinged, isNotNull, reason: 'пункт меню обязан запустить пинг');
      final keys = probe.pinged!.map((s) => s.key).toSet();
      expect(keys, {
        for (final link in [a1, a2, b1, b2, b3])
          ShareLinkParser.canonicalKey(link),
      });
      expect(probe.pinged!.length, 5,
          reason: 'все 5 серверов двух подписок, без повторов');
    });

    testWidgets('активная подписка и список на главном не меняются',
        (tester) async {
      await tester.runAsync(boot);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await openMenu(tester);
      await tester.tap(find.text(l.subSwitcherPingAll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Пинг — это не переключение подписки: канал, список и выбор сервера
      // обязаны остаться теми же (иначе при живом туннеле человек получил бы
      // ещё и плашку «переподключитесь»).
      expect(state.activeSubscriptionId, idA);
      expect(state.servers.length, 2);
      expect(state.servers.map((s) => s.key).toSet(),
          {ShareLinkParser.canonicalKey(a1), ShareLinkParser.canonicalKey(a2)});
    });
  });

  group('AppState: серверы неактивной подписки восстанавливаются из ссылок', () {
    test('serversOfSubscription поднимает профиль, который сейчас не активен',
        () async {
      await boot();
      final b = state.serversOfSubscription(idB);
      expect(b.map((s) => s.key).toList(), [
        ShareLinkParser.canonicalKey(b1),
        ShareLinkParser.canonicalKey(b2),
        ShareLinkParser.canonicalKey(b3),
      ]);
      // Само чтение чужого профиля переключением быть не должно.
      expect(state.activeSubscriptionId, idA);
      expect(state.servers.length, 2);
    });

    test('allSubscriptionServers не дублирует сервер из двух подписок',
        () async {
      // a1 лежит и в A, и в B — это законно: один сервер вполне живёт в двух
      // подписках. Пинговать его дважды значило бы удвоить прогон.
      await boot(serversA: const [a1, a2], serversB: const [a1, b1]);
      final all = state.allSubscriptionServers();
      expect(all.length, 3);
      expect(all.map((s) => s.key).toSet(), {
        ShareLinkParser.canonicalKey(a1),
        ShareLinkParser.canonicalKey(a2),
        ShareLinkParser.canonicalKey(b1),
      });
    });

    test('нет такой подписки — пустой список, а не исключение', () async {
      await boot();
      expect(state.serversOfSubscription('sub_ffff'), isEmpty);
    });
  });

  group('Счётчик «всего · рабочих»', () {
    final srv = [a1, b1, b2].map(ShareLinkParser.tryParse).cast<VpnServer>().toList();

    SubscriptionPingCount countWith(Map<int, PingVerification> byIndex) =>
        SubscriptionPingCount.of(srv, (s) {
          final i = srv.indexWhere((x) => x.key == s.key);
          final v = byIndex[i];
          return v == null ? PingResult.untested : _res(v);
        });

    test('до пинга показываем только общее число', () {
      final c = countWith(const {});
      expect(c.total, 3);
      expect(c.working, isNull,
          reason: 'ноль означал бы «проверили и ни один не работает»');
    });

    test('рабочим считается ТОЛЬКО прошедший проверку канала', () {
      // Достижимы (outcome == ok) все три, но проверку прошёл один. Считать по
      // достижимости — ровно та подмена, из-за которой зелёным горели серверы,
      // через которые не работало ничего.
      final c = countWith(const {
        0: PingVerification.passed,
        1: PingVerification.failed,
        2: PingVerification.notRun,
      });
      expect(c.total, 3);
      expect(c.working, 1);
    });

    test('проверка была и не прошёл никто — это ноль, а не «неизвестно»', () {
      final c = countWith(const {0: PingVerification.failed});
      expect(c.working, 0);
    });

    test('проверка ещё идёт — результата нет', () {
      final c = countWith(const {
        0: PingVerification.pending,
        1: PingVerification.pending,
      });
      expect(c.working, isNull);
    });
  });

  group('Счётчик в меню и пояснение по наведению', () {
    Finder badge(String id) => find.byKey(ValueKey('subCount_$id'));

    testWidgets('до пинга у подписки видно одно число, после — два',
        (tester) async {
      await tester.runAsync(boot);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openMenu(tester);

      // B — неактивная подписка, три сервера. Число обязано быть даже у неё:
      // её серверы в память не подняты, и без восстановления здесь стоял бы
      // ноль.
      expect(find.descendant(of: badge(idB), matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: badge(idB), matching: find.text('0')),
          findsNothing,
          reason: 'до проверки канала рабочих не показываем вовсе');
      expect(
          tester
              .widget<Tooltip>(
                  find.descendant(of: badge(idB), matching: find.byType(Tooltip)))
              .message,
          l.subSwitcherCountTotal(3));

      // Один сервер подписки B прошёл проверку канала.
      final b = state.serversOfSubscription(idB);
      probe.setResult(b.first, _res(PingVerification.passed));
      probe.setResult(b[1], _res(PingVerification.failed));
      await tester.pumpAndSettle();

      expect(find.descendant(of: badge(idB), matching: find.text('3')),
          findsOneWidget);
      expect(find.descendant(of: badge(idB), matching: find.text('1')),
          findsOneWidget);
      expect(
          tester
              .widget<Tooltip>(
                  find.descendant(of: badge(idB), matching: find.byType(Tooltip)))
              .message,
          l.subSwitcherCountWorking(3, 1),
          reason: 'владелец просил пояснение к цифрам по наведению');
    });
  });
}
