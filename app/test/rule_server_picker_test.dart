import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/app.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/split_tunnel_screen.dart';
import 'package:silentgate/ui/widgets/info_tooltip.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Выбор сервера для правила раздельного туннелирования и подсказка у плашки
/// сервера — две жалобы владельца от 18.08.2026.
///
/// ⚠️ ЧТО ИМЕННО БЫЛО СЛОМАНО.
///
/// 1. Плашка сервера в строке правила показывала абзац в 230 символов ОБЫЧНОЙ
///    всплывающей подсказкой. Подсказка Flutter по умолчанию не ограничена ни
///    по ширине, ни по отступам и рисуется ПОД плашкой (`preferBelow` = true) —
///    на скриншоте владельца она накрыла следующее правило списка. Плюс на
///    тач-экране наведения нет вовсе, то есть на телефоне текст был недоступен.
///
/// 2. Сервер для правила выбирался `DropdownButtonFormField`-ом с голым
///    `Text(displayName)`: ни флага, ни пинга, ни скорости, ни пометки, что
///    сервер отдельным выходом не поднимается. Владелец: «в выборе сервера,
///    через что пойдёт трафик, отображай инфу о сервере как на главной».
///
/// Сети и VPN тест не касается: движок фиктивный, результаты пинга в контроллер
/// не кладутся вовсе — проверяется состав интерфейса.
void main() {
  late Directory tmp;
  late AppState state;
  late ProbeController probe;
  late SettingsController settings;

  // Обычный сервер: годится и на отдельный выход.
  const de = VpnServer(
    protocol: 'vless',
    remark: 'DE Германия',
    address: 'de.example',
    port: 443,
    id: '00000000-0000-0000-0000-000000000001',
    rawLink: 'vless://00000000-0000-0000-0000-000000000001@de.example:443'
        '?type=tcp&security=none#DE',
  );
  const nl = VpnServer(
    protocol: 'vless',
    remark: 'NL Нидерланды',
    address: 'nl.example',
    port: 443,
    id: '00000000-0000-0000-0000-000000000002',
    rawLink: 'vless://00000000-0000-0000-0000-000000000002@nl.example:443'
        '?type=tcp&security=none#NL',
  );

  // Панельный профиль «Авто»: sing-box вторым выходом его не поднимет —
  // `canBeExitServer` отвечает `false`.
  const auto = VpnServer(
    protocol: 'vless',
    remark: '🎬 Авто (YouTube)',
    address: 'auto.example',
    port: 443,
    id: '00000000-0000-0000-0000-000000000003',
    rawLink: 'panel://Авто?sub=aa',
    rawPanelConfig: '{"outbounds":[{"protocol":"vless","tag":"proxy"}]}',
  );

  // Заглушка истёкшей подписки: `0.0.0.0:1` с текстом вместо имени.
  const notice = VpnServer(
    protocol: 'vless',
    remark: 'Ваша подписка истекла!',
    address: '0.0.0.0',
    port: 1,
    id: '00000000-0000-0000-0000-000000000004',
    rawLink: 'vless://00000000-0000-0000-0000-000000000004@0.0.0.0:1#notice',
  );

  setUp(() {
    // ⚠️ Боевой %APPDATA%\SilentGate не трогаем: AppState пишет туда пины и
    // результаты пинга.
    tmp = Directory.systemTemp.createTempSync('sg_rule_picker_');
    AppPaths.overrideRoot(tmp);
    state = AppState(engine: _FakeEngine());
    probe = ProbeController();
    settings = SettingsController();
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 1000, double height = 900}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<ProbeController>.value(value: probe),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // ── 1. Подсказка не расползается на всю ширину ─────────────────────────────

  group('Подсказки ограничены темой', () {
    test('обе темы задают потолок ширины и отступ от краёв', () {
      for (final b in Brightness.values) {
        final t = buildAppTheme(b).tooltipTheme;
        final c = t.constraints;
        expect(c, isNotNull,
            reason: 'без constraints подсказка тянется на всю ширину окна');
        // Потолок должен быть конечным и заметно меньше окна (минимум
        // 980 dp по TrayWindow.minimumSize).
        expect(c!.maxWidth, lessThanOrEqualTo(360));
        expect(c.maxWidth.isFinite, isTrue);
        // Минимальную высоту у подсказки отбирать нельзя: задав constraints,
        // мы отменяем платформенное умолчание Flutter целиком.
        expect(c.minHeight, greaterThanOrEqualTo(24));
        expect(t.margin, isNotNull,
            reason: 'без margin подсказка прилипает к краю окна');
        expect(t.margin, isNot(EdgeInsets.zero));
      }
    });
  });

  group('Плашка сервера в строке правила', () {
    testWidgets('у непригодного сервера абзац уехал в «!», в подсказке — имя',
        (tester) async {
      await pump(
        tester,
        // Ширину задаём коробкой: плашка меряет доступное место
        // (LayoutBuilder) и в тесной строке показывает один флаг.
        const SizedBox(
          width: 300,
          child: ServerBadge(
            servers: [auto],
            serverKey: 'panel://Авто?sub=aa',
            action: AppAction.tunnel,
          ),
        ),
      );

      // «!» с диалогом — вместо абзаца в подсказке.
      expect(find.byType(InfoTooltip), findsOneWidget);

      final tips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      // Подсказка самой плашки: только имя сервера, без объяснения на абзац.
      final badgeTip =
          tips.firstWhere((t) => t.message == '🎬 Авто (YouTube)');
      expect(badgeTip.message!.length, lessThan(60),
          reason: 'в подсказке плашки не должно быть абзаца');
      expect(badgeTip.message, isNot(contains('sing-box')));
    });

    testWidgets('у обычного сервера «!» нет — объяснять нечего',
        (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 300,
          child: ServerBadge(
            servers: const [de],
            serverKey: de.key,
            action: AppAction.tunnel,
          ),
        ),
      );
      expect(find.byType(InfoTooltip), findsNothing);
    });
  });

  // ── 2. Пикер сервера для правила ───────────────────────────────────────────

  group('Строка сервера умеет режим «только выбор»', () {
    testWidgets('showActions: false убирает кнопку правки и контекст-меню',
        (tester) async {
      await pump(
        tester,
        ListView(children: [
          ServerTile(
              server: de, selected: false, onTap: () {}, showActions: false),
        ]),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // Правая кнопка мыши больше не открывает меню: пункт «Удалить сервер»
      // в диалоге выбора — чужое действие.
      final gd = tester.widget<GestureDetector>(find
          .descendant(
              of: find.byType(ServerTile), matching: find.byType(GestureDetector))
          .first);
      expect(gd.onSecondaryTapDown, isNull);
      await tester.tap(find.byType(ListTile), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Удалить сервер'), findsNothing);
    });

    testWidgets('unavailableNote гасит строку и даёт «!»', (tester) async {
      await pump(
        tester,
        ListView(children: [
          ServerTile(
            server: de,
            selected: false,
            onTap: () {},
            showActions: false,
            unavailableNote: 'нельзя',
          ),
        ]),
      );
      expect(find.byType(InfoTooltip), findsOneWidget);
      final dimmed = tester
          .widgetList<Opacity>(find.descendant(
              of: find.byType(ServerTile), matching: find.byType(Opacity)))
          .where((o) => o.opacity < 1);
      expect(dimmed, isNotEmpty,
          reason: 'непригодный сервер обязан выглядеть непригодным');
    });

    testWidgets('без пометки строка не гаснет', (tester) async {
      await pump(
        tester,
        ListView(children: [
          ServerTile(server: de, selected: false, onTap: () {}),
        ]),
      );
      final dimmed = tester
          .widgetList<Opacity>(find.descendant(
              of: find.byType(ServerTile), matching: find.byType(Opacity)))
          .where((o) => o.opacity < 1);
      expect(dimmed, isEmpty);
    });
  });

  group('Пикер сервера для правила', () {
    /// Открывает поле и сам пикер, возвращает то, что поле отдало наружу.
    Future<List<String?>> openPicker(
      WidgetTester tester, {
      List<VpnServer> servers = const [de, nl, auto, notice],
      String? serverKey,
      VpnServer? current,
    }) async {
      final got = <String?>[];
      await pump(
        tester,
        Builder(
          builder: (_) => RuleServerField(
            servers: servers,
            currentServer: current,
            serverKey: serverKey,
            onChanged: got.add,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      return got;
    }

    testWidgets('показывает строки серверов, как на главном экране',
        (tester) async {
      await openPicker(tester);
      expect(find.byType(RuleServerPickerDialog), findsOneWidget);
      // Именно ServerTile, а не собственная упрощённая строка: только он берёт
      // пинг и скорость из тех же провайдеров, что главный экран.
      expect(find.byType(ServerTile), findsWidgets);
    });

    testWidgets('заглушки подписки в список не попадают', (tester) async {
      await openPicker(tester);
      final keys = tester
          .widgetList<ServerTile>(find.byType(ServerTile))
          .map((t) => t.server.key)
          .toSet();
      expect(keys, contains(de.key));
      expect(keys, contains(nl.key));
      expect(keys, isNot(contains(notice.key)),
          reason: 'выход из «0.0.0.0:1» ведёт в никуда');
    });

    testWidgets('непригодный сервер помечен, пригодный — нет', (tester) async {
      await openPicker(tester);
      final tiles = {
        for (final t in tester.widgetList<ServerTile>(find.byType(ServerTile)))
          t.server.key: t
      };
      expect(tiles[auto.key]!.unavailableNote, isNotNull,
          reason: 'панельный профиль «Авто» вторым выходом не поднимается');
      expect(tiles[de.key]!.unavailableNote, isNull);
      // Меню строки в пикере отключено у всех: оно уводит с диалога и умеет
      // удалять сервер.
      expect(tiles.values.every((t) => !t.showActions), isTrue);
    });

    testWidgets('строка «Как основной» есть и отдаёт null', (tester) async {
      final got = await openPicker(tester, serverKey: de.key, current: nl);
      // Подпись с именем текущего сервера — чтобы было видно, куда пойдёт
      // трафик «как у всех».
      expect(find.textContaining('Как основной'), findsOneWidget);
      await tester.tap(find.textContaining('Как основной'));
      await tester.pumpAndSettle();
      expect(got, [null]);
    });

    testWidgets('выбор сервера доезжает до правила', (tester) async {
      final got = await openPicker(tester);
      final tile = find.byWidgetPredicate(
          (w) => w is ServerTile && w.server.key == nl.key);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(got, [nl.key]);
      expect(find.byType(RuleServerPickerDialog), findsNothing);
    });

    testWidgets('отмена НЕ стирает уже выбранный сервер', (tester) async {
      // ⚠️ Страж обёртки [RuleServerChoice]: отдавай пикер голый `String?`,
      // закрытие крестиком было бы неотличимо от выбора «как основной» — и
      // правило молча уехало бы в общий туннель.
      final got = await openPicker(tester, serverKey: de.key);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(got, isEmpty);
    });

    testWidgets('поиск отбирает серверы по имени', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'нидерланды');
      await tester.pumpAndSettle();
      final keys = tester
          .widgetList<ServerTile>(find.byType(ServerTile))
          .map((t) => t.server.key)
          .toSet();
      expect(keys, {nl.key});
    });
  });

  group('Поле «Через сервер»', () {
    testWidgets('выбранный сервер показан строкой сервера', (tester) async {
      await pump(
        tester,
        RuleServerField(
          servers: const [de, nl],
          currentServer: null,
          serverKey: de.key,
          onChanged: (_) {},
        ),
      );
      // Раньше здесь был голый Text(displayName) внутри Dropdown.
      final tiles =
          tester.widgetList<ServerTile>(find.byType(ServerTile)).toList();
      expect(tiles.length, 1);
      expect(tiles.single.server.key, de.key);
      expect(tiles.single.showActions, isFalse);
    });

    testWidgets('пропавший сервер назван прямо, а не «как основной»',
        (tester) async {
      await pump(
        tester,
        RuleServerField(
          servers: const [de],
          currentServer: de,
          serverKey: 'vless://исчез@nowhere:443#gone',
          onChanged: (_) {},
        ),
      );
      expect(find.byIcon(Icons.link_off), findsOneWidget);
      expect(find.textContaining('Как основной'), findsNothing);
    });
  });
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
