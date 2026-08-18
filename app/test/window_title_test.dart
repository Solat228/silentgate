import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/app_info.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/tray_window.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/servers_screen.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';
import 'package:silentgate/ui/widgets/sel_text.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Две просьбы владельца, попавшие в один файл, потому что обе про окно:
/// версия в заголовке окна (и в подсказке значка в трее) и Ctrl+C, копирующий
/// ключ выбранного сервера.
///
/// ⚠️ ЗАЧЕМ ЗДЕСЬ СТОРОЖ НА ЕДИНСТВЕННОСТЬ ЗАГОЛОВКА. Заголовок ставится один
/// раз — параметрами окна при старте. Стоит кому-то позвать `setTitle` ещё
/// где-нибудь (например «обновить заголовок при показе окна»), и версия
/// пропадёт после первого же сворачивания в трей: снаружи это выглядит как
/// «иногда версии нет», и ловить такое глазами бесполезно.
///
/// ⚠️ ЗАЧЕМ ПРОВЕРЯТЬ Ctrl+C НА НАСТОЯЩЕМ ЭКРАНЕ. Опасность горячей клавиши не
/// в самом копировании, а в том, что она отбирает Ctrl+C у ПОЛЕЙ ВВОДА:
/// обработчик экрана стоит ближе к полю, чем штатные текстовые сокращения
/// приложения, и отвечает первым. Проверить это на выдуманной раскладке
/// нельзя — нужен реальный экран с реальным полем поиска.
void main() {
  // ── 1. Версия в заголовке окна и в подсказке трея ──────────────────────────

  group('Версия в заголовке окна', () {
    test('заголовок окна — имя И версия', () {
      // До правки здесь стоял литерал 'SilentGate': версию приложения было
      // видно только в «О программе».
      expect(TrayWindow.windowOptions.title, TrayWindow.nameWithVersion);
      expect(TrayWindow.windowOptions.title, contains(AppInfo.version));
      expect(TrayWindow.windowOptions.title, contains(AppInfo.name));
    });

    test('имя берётся из AppInfo, а не литералом', () {
      // Бренд может смениться — тогда правка должна быть ровно в одном месте.
      expect(TrayWindow.nameWithVersion, '${AppInfo.name} ${AppInfo.version}');
    });

    test('подсказка трея тоже показывает версию', () {
      // У свёрнутого в трей приложения заголовок окна не виден вовсе, и
      // подсказка — единственное оставшееся место.
      expect(TrayWindow.composeTooltip(), contains(AppInfo.version));
      final tip = TrayWindow.composeTooltip(
          server: 'Germany #3', speed: TrayWindow.speedLine(_stats));
      expect(tip.split('\n').first, contains(AppInfo.version));
      // И предел Windows на 127 символов от этого не поехал.
      expect(tip.length, lessThanOrEqualTo(TrayWindow.tooltipLimit));
    });

    test('длинное имя сервера всё ещё режется, а не выталкивает скорость', () {
      // Имя с версией на шесть символов длиннее — проверяем, что запас на
      // обрезание считается от него, а не от прежнего.
      final speed = TrayWindow.speedLine(_stats);
      for (var n = 0; n < 220; n++) {
        final tip = TrayWindow.composeTooltip(server: 'x' * n, speed: speed);
        expect(tip.length, lessThanOrEqualTo(TrayWindow.tooltipLimit),
            reason: 'длина имени $n');
        expect(tip.split('\n').last, speed,
            reason: 'скорость нужна целиком — режем имя');
      }
    });

    test('заголовок ставится РОВНО в одном месте', () {
      // Сторож против «обновим заголовок при показе окна»: второй установщик
      // заголовка — это потерянная версия после сворачивания в трей.
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.readAsStringSync().contains('setTitle(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'заголовок задаётся только через TrayWindow.windowOptions');
    });
  });

  // ── 2. Ctrl+C копирует ключ выбранного сервера ─────────────────────────────

  group('Ctrl+C: ключ выбранного сервера', () {
    const urlA = 'https://panel.example/sub/aaaaaaaa';
    const s1 = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
        '?type=tcp&security=none#Alpha-1';
    const s2 = 'vless://11111111-1111-1111-1111-111111111111@a2.example:443'
        '?type=tcp&security=none#Beta-2';

    late Directory tmp;
    late AppState state;
    late ProbeController probe;
    late SettingsController settings;

    setUp(() {
      // Выбор сервера и результаты пинга пишутся на диск — свой каталог
      // обязателен, боевой %APPDATA% тесты не трогают.
      tmp = Directory.systemTemp.createTempSync('sg_ctrl_c_');
      AppPaths.overrideRoot(tmp);
      AppToast.dismiss();
    });

    tearDown(() async {
      AppToast.dismiss();
      // Дать досчитать фоновым записям, прежде чем снимать подмену каталога.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Подписка с двумя серверами кладётся на диск ДО `init()` — тем же путём,
    /// каким она приезжает после перезапуска приложения.
    Future<void> boot() async {
      final sep = Platform.pathSeparator;
      File('${tmp.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
        'activeId': SubscriptionProfile.idFor(urlA),
        'items': [
          {
            'id': SubscriptionProfile.idFor(urlA),
            'url': urlA,
            'servers': [s1, s2],
            'addedAt': '2026-08-01T00:00:00.000Z',
          },
        ],
      }));
      state = AppState(engine: _FakeEngine());
      await state.init();
      probe = ProbeController();
      settings = SettingsController();
      await settings.init();
    }

    /// Что уехало в буфер обмена. Настоящий канал в тесте недоступен, поэтому
    /// слушаем его сами — иначе «скопировалось» пришлось бы принимать на веру.
    List<String> watchClipboard(WidgetTester tester) {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      return copied;
    }

    Future<void> pressCtrlC(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> mountServers(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ServersScreen(),
        ),
      ));
      await tester.pump();
    }

    test('предпосылка: тест идёт на платформе с клавиатурой', () {
      // На Android клавиша не вешается вовсе, и проверять там было бы нечего.
      expect(CopyServerKeyShortcut.hasKeyboard, isTrue);
    });

    testWidgets('копируется ВЫБРАННЫЙ в списке сервер', (tester) async {
      await tester.runAsync(boot);
      final copied = watchClipboard(tester);
      await mountServers(tester);

      // Выбираем ВТОРОЙ: с первым (он же выбран по умолчанию) тест не отличил
      // бы «скопировали выбранный» от «скопировали первый попавшийся».
      await tester.runAsync(() async => state.selectServer(1));
      await tester.pump();

      await pressCtrlC(tester);

      expect(copied, hasLength(1), reason: 'Ctrl+C не сработал вовсе');
      // ⚠️ ЧТО именно кладём в буфер, решает общая с меню строки функция —
      // спрашиваем её же, а не переписываем ожидание руками.
      expect(copied.single, serverClipboardPayload(state.servers[1]));
      expect(copied.single, contains('Beta-2'));
    });

    testWidgets('в поле поиска Ctrl+C копирует ТЕКСТ, а не сервер',
        (tester) async {
      // ⚠️ ГЛАВНАЯ ЛОВУШКА ВСЕЙ ЗАТЕИ. Обработчик экрана стоит ближе к полю,
      // чем штатные текстовые сокращения приложения, и без явного отказа
      // забирал бы Ctrl+C себе: в буфер вместо выделенного текста уезжал бы
      // ключ сервера. Поле поиска здесь настоящее, экранное.
      await tester.runAsync(boot);
      final copied = watchClipboard(tester);
      await mountServers(tester);

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump();
      // Выделяем набранное штатным сокращением — это тоже проверка того, что
      // сокращения поля живы.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      await pressCtrlC(tester);

      expect(copied, hasLength(1),
          reason: 'штатное копирование текста должно было сработать ровно раз');
      expect(copied.single, 'Alpha');
      expect(copied.single, isNot(contains('vless://')),
          reason: 'копирование в поле ввода отбирать нельзя');
    });

    /// Стенд, считающий Ctrl+C, ДОШЕДШИЙ выше обёртки.
    ///
    /// Иначе «не сработало» и «съело клавишу молча» неотличимы: в обоих
    /// случаях в буфер ничего не уходит, а разница между ними — рабочее и
    /// сломанное копирование у того, кто стоит выше по дереву.
    Future<int> pressAbove(WidgetTester tester, AppState st,
        {required void Function() onCopy}) async {
      var reachedAbove = 0;
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppState>.value(value: st)],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Focus(
            // Считаем только НАЖАТИЕ: отпускание клавиши сокращение не
            // забирает никогда, и в счётчике оно было бы шумом.
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyC) {
                reachedAbove++;
              }
              return KeyEventResult.ignored;
            },
            child: CopyServerKeyShortcut(
              onCopy: (_, __) => onCopy(),
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      ));
      await tester.pump();
      await pressCtrlC(tester);
      return reachedAbove;
    }

    testWidgets('в выделяемом тексте (SelText) клавиша тоже не отбирается',
        (tester) async {
      // ⚠️ SelText — это SelectableText, внутри у него тот же EditableText,
      // что и у поля ввода. Отдельная проверка нужна потому, что признак
      // «фокус в тексте» ищется ОДНОЙ проверкой на оба случая: держись она
      // только на TextField, из выделяемого текста перестали бы копироваться
      // адреса, пути и ключи — а их вручную не перенабрать, ради этого
      // SelText и заводили. Сервер здесь ВЫБРАН, то есть сокращение готово
      // сработать, и промолчать его заставляет ровно фокус.
      await tester.runAsync(boot);
      final copied = watchClipboard(tester);
      var calls = 0;
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppState>.value(value: state)],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CopyServerKeyShortcut(
            onCopy: (_, __) => calls++,
            child: const Scaffold(body: Center(child: SelText('10.0.0.1'))),
          ),
        ),
      ));
      await tester.pump();
      expect(state.selectedServer, isNotNull, reason: 'предпосылка теста');

      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      await pressCtrlC(tester);

      expect(calls, 0, reason: 'копирование выделенного отбирать нельзя');
      expect(copied, hasLength(1));
      expect(copied.single, '10.0.0.1');
    });

    testWidgets('нечего копировать — клавиша уходит выше, а не пропадает',
        (tester) async {
      // Сервер не выбран (список пуст): действие обязано быть ВЫКЛЮЧЕНО, а не
      // «вызваться и ничего не сделать». Выключенное отдаёт
      // `KeyEventResult.ignored`, и Ctrl+C достаётся тому, кто его ждёт выше;
      // вызванное и пустое — съедает клавишу молча.
      final empty = AppState(engine: _FakeEngine());
      var calls = 0;
      expect(empty.selectedServer, isNull, reason: 'предпосылка теста');

      final above = await pressAbove(tester, empty, onCopy: () => calls++);

      expect(calls, 0);
      expect(above, greaterThan(0),
          reason: 'выключенное действие обязано пропустить клавишу выше');
    });

    testWidgets('есть что копировать — клавиша дальше не идёт', (tester) async {
      // Обратная половина: сработавшее копирование обязано остановить событие,
      // иначе тот же Ctrl+C отработает ВТОРОЙ раз выше по дереву.
      await tester.runAsync(boot);
      var calls = 0;
      expect(state.selectedServer, isNotNull, reason: 'предпосылка теста');

      final above = await pressAbove(tester, state, onCopy: () => calls++);

      expect(calls, 1);
      expect(above, 0, reason: 'сработавшее сокращение событие не пропускает');
    });

    testWidgets('оба экрана со списком серверов слушают клавишу',
        (tester) async {
      // Функционально проверен экран серверов (выше). Главный экран поднять
      // тестом нельзя: его `initState` уходит в проверку помех и в проверку
      // обновлений — то есть в систему и в сеть. Поэтому здесь — сторож на то,
      // что обёртка с него не пропала.
      for (final path in [
        'lib/ui/home_screen.dart',
        'lib/ui/servers_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('return CopyServerKeyShortcut('),
            reason: '$path перестал слушать Ctrl+C');
      }
    });
  });
}

const _stats = TrafficStats(
  uplinkBytes: 3 * 1024 * 1024 * 1024,
  downlinkBytes: 7 * 1024 * 1024 * 1024,
  uplinkSpeed: 300 * 1024,
  downlinkSpeed: 1536 * 1024,
);

/// Движок-пустышка: ни одного реального действия, VPN не поднимается.
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
