import 'dart:async';
import 'dart:io';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/util/country_flag.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';
import 'package:silentgate/ui/widgets/flag_cell.dart';
import 'package:silentgate/ui/widgets/flag_text.dart';
import 'package:silentgate/ui/widgets/server_tile.dart';

/// Флаг-эмодзи (пара regional-indicator) в тексте от панели (notice-сервер,
/// объявление подписки) на Windows рисуется двумя буквами — глифов флага там
/// нет. `buildFlagSpans`/`FlagUtil.splitFlagPairs` заменяют ровно пары на
/// картинку `CountryFlag`, остальной текст (и прочие эмодзи) не трогают.
/// `NoticeText` добавляет обрезку длинного текста ([kNoticeTextCap]) с
/// разворотом по тапу.
void main() {
  group('FlagUtil.splitFlagPairs — разбор на текст и флаг-пары', () {
    test('пара regional-indicator → часть-флаг', () {
      final parts = FlagUtil.splitFlagPairs('Hello 🇳🇱 World');
      expect(parts.map((p) => p.flagCode ?? p.text), ['Hello ', 'NL', ' World']);
      expect(parts[1].flagCode, 'NL');
      expect(parts[1].text, isNull);
    });

    test('непарный индикатор — остаётся простым текстом', () {
      // Одна половина флага без соседа: рисовать нечего, откусывать нельзя.
      final lone = String.fromCharCode(0x1F1F3); // regional indicator 'N'
      final parts = FlagUtil.splitFlagPairs('x${lone}y');
      expect(parts, hasLength(1));
      expect(parts.single.flagCode, isNull);
      expect(parts.single.text, 'x${lone}y');
    });

    test('другие эмодзи не трогаются', () {
      final parts = FlagUtil.splitFlagPairs('🎉 🇳🇱 🔥');
      expect(parts.map((p) => p.flagCode ?? p.text), ['🎉 ', 'NL', ' 🔥']);
    });

    test('несколько пар подряд разбираются каждая своя', () {
      // Мост «вход · выход»: два флага без разделителя между ними.
      final parts = FlagUtil.splitFlagPairs('🇳🇱🇨🇿 Bridge');
      expect(parts.map((p) => p.flagCode ?? p.text), ['NL', 'CZ', ' Bridge']);
    });
  });

  group('FlagUtil.truncateRunes — обрезка по рунам, без слома пары', () {
    test('201 символ → ровно 200, без флагов рвать нечего', () {
      final text = List.generate(201, (i) => 'a').join();
      final cut = FlagUtil.truncateRunes(text, 200);
      expect(cut.runes.length, 200);
      expect(cut, text.substring(0, 200));
    });

    test('текст короче потолка не трогается', () {
      const text = 'коротко';
      expect(FlagUtil.truncateRunes(text, 200), text);
    });

    test('⚠️ граница ровно между половинками пары — обрезаются ОБЕ', () {
      // 199 обычных символов + флаг-пара (2 руны) = 201 руна. Потолок 200
      // разрезал бы пару РОВНО пополам (первая половина входит, вторая — нет).
      final prefix = List.generate(199, (i) => 'a').join();
      final text = '$prefix🇳🇱';
      expect(text.runes.length, 201);
      final cut = FlagUtil.truncateRunes(text, 200);
      // Ни первой, ни второй половины индикатора в результате быть не должно —
      // иначе висячая буква вместо текста или флага.
      expect(cut, prefix);
      expect(cut.runes.length, 199);
    });

    test('граница МЕЖДУ двумя разными парами — резать можно', () {
      // (I0 I1)(I2 I3): резка после первой пары не трогает вторую.
      const text = '🇳🇱🇨🇿'; // NL + CZ, 4 руны
      final cut = FlagUtil.truncateRunes(text, 2);
      expect(cut.runes.length, 2);
      expect(FlagUtil.splitFlagPairs(cut).single.flagCode, 'NL');
    });
  });

  group('NoticeText — виджет', () {
    Widget host(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('короткий текст с флагом — рисуется CountryFlag, текст не обрезан',
        (tester) async {
      await tester.pumpWidget(host(const NoticeText('🇳🇱 Ваша подписка истекла')));
      await tester.pump();
      expect(find.byType(CountryFlag), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('длинный текст обрезается до kNoticeTextCap и тап разворачивает',
        (tester) async {
      final full = 'a' * (kNoticeTextCap + 50);
      await tester.pumpWidget(host(NoticeText(full)));
      await tester.pump();

      // До тапа — обрезанный текст с многоточием, полного текста на экране нет.
      final collapsed = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.textSpan?.toPlainText() ?? '')
          .firstWhere((s) => s.contains('a'));
      expect(collapsed.endsWith('…'), isTrue);
      expect(collapsed.length, lessThan(full.length));

      await tester.tap(find.byType(NoticeText));
      await tester.pump();

      final expanded = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.textSpan?.toPlainText() ?? '')
          .firstWhere((s) => s.contains('a'));
      expect(expanded, full, reason: 'тап обязан показать текст целиком');
    });
  });

  group('Notice-плитка сервера: копирование берёт ОРИГИНАЛЬНЫЙ текст', () {
    late Directory tmp;
    late AppState state;
    late ProbeController probe;
    late SettingsController settings;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_notice_copy_');
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

    testWidgets(
        '⚠️ обрезанный/офлаженный показ не влияет на буфер обмена — там полный remark',
        (tester) async {
      // Длиннее kNoticeTextCap и с флагом — ровно то, что на экране показано бы
      // урезанным и с картинкой вместо эмодзи-пары.
      final longNotice = '🇷🇺 ${'Оплатите подписку, чтобы продолжить пользоваться. ' * 5}';
      expect(longNotice.runes.length, greaterThan(kNoticeTextCap));
      final notice = VpnServer(
        protocol: 'vless',
        remark: longNotice,
        address: '0.0.0.0',
        port: 1,
        id: '00000000-0000-0000-0000-000000000000',
        rawLink: 'vless://notice',
      );
      expect(notice.isNotice, isTrue);

      final copied = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

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
          home: Scaffold(
            body: ListView(children: [
              ServerTile(server: notice, selected: false, onTap: () {}),
            ]),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      expect(copied, [longNotice.trim()],
          reason: 'в буфере обязан быть ОРИГИНАЛЬНЫЙ текст, а не обрезанный '
              'показ и не текст с картинками вместо флагов');
    });
  });

  /// Решение владельца 25.09.2026: «ВЕЗДЕ, где в тексте есть флаг, — картинка,
  /// НИГДЕ — буквы». Дополнительное правило: из текста вырезаются только те
  /// флаги, что уже нарисованы иконкой рядом (первые два, см. [FlagCell]) —
  /// третий и далее остаётся в тексте картинкой.
  group('Имя с тремя флагами: буквы стран нигде не видны', () {
    late Directory tmp;
    late AppState state;
    late ProbeController probe;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_flag_tile_');
      AppPaths.overrideRoot(tmp);
      state = AppState(engine: _FakeEngine());
      probe = ProbeController();
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget host(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<ProbeController>.value(value: probe),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: child),
          ),
        );

    testWidgets(
        'плитка сервера: ни одной буквы кода страны, третий флаг — картинкой',
        (tester) async {
      final server = VpnServer(
        protocol: 'vless',
        remark: '🇺🇸🇩🇪🇫🇷 Test',
        address: 'example.com',
        port: 443,
        id: '11111111-2222-3333-4444-555555555555',
        rawLink: 'vless://11111111-2222-3333-4444-555555555555'
            '@example.com:443?encryption=none#test',
      );

      await tester.pumpWidget(
          host(ServerTile(server: server, selected: false, onTap: () {})));
      await tester.pump();

      // Ни «US», ни «DE» голыми буквами на экране — их место заняли картинки
      // (в ячейке FlagCell) или они вырезаны из текста (третий флаг — FR —
      // остался в тексте картинкой через FlagText).
      expect(find.textContaining('US'), findsNothing,
          reason: 'код страны буквами — Windows такой эмодзи-пары не рисует');
      expect(find.textContaining('DE'), findsNothing,
          reason: 'код страны буквами — Windows такой эмодзи-пары не рисует');

      // FlagCell рядом с именем показывает ПЕРВЫЕ два флага — US/DE.
      final cellFlags = find.descendant(
          of: find.byType(FlagCell), matching: find.byType(CountryFlag));
      expect(cellFlags, findsNWidgets(2),
          reason: 'ячейка рисует ровно первые два флага (мост вход · выход)');

      // Третий флаг (FR) не нарисован иконкой — он остался в тексте и обязан
      // достаться FlagText картинкой, а не буквами и не как обычный текст.
      final textFlags = find.descendant(
          of: find.byType(FlagText), matching: find.byType(CountryFlag));
      expect(textFlags, findsOneWidget,
          reason: 'третий флаг (FR) не влез в иконку — должен остаться '
              'картинкой в тексте');

      // И сам текст без первых двух флагов — «Test» цело.
      expect(find.textContaining('Test'), findsWidgets);
    });
  });

  group('Флаг в тосте рисуется картинкой', () {
    Widget host(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        );

    // ⚠️ `_MessageToasts._host`/`_items` — статика, общая на все тесты файла.
    // Прошлый тест (копирование из notice-плитки) мог оставить в них
    // `OverlayEntry` от УЖЕ УНИЧТОЖЕННОГО дерева прошлого теста: новый вызов
    // `AppToast.show` увидел бы `_host != null` и тихо ничего не нарисовал
    // бы в дереве ЭТОГО теста. Гасим стопку перед стартом.
    setUp(() => AppToast.dismiss());

    testWidgets('AppToast с флагом в сообщении показывает CountryFlag',
        (tester) async {
      await tester.pumpWidget(host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => AppToast.show(context, '🇳🇱 Сервер недоступен',
              kind: ToastKind.error),
          child: const Text('go'),
        );
      })));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      // Второй кадр: инлайн-виджет флага (WidgetSpan) внутри Text.rich
      // довешивается к дереву элементов на следующем кадре после первого
      // построения оверлея.
      await tester.pump();

      expect(find.byType(CountryFlag), findsWidgets,
          reason: 'флаг в тексте тоста обязан рисоваться картинкой, а не '
              'буквами NL');
      expect(find.textContaining('NL'), findsNothing);
    });
  });

  group('Заголовок подписки рисуется картинкой', () {
    testWidgets('FlagText с названием подписки показывает CountryFlag',
        (tester) async {
      // Сам заголовок карточки подписки собирается внутри `SubscriptionBar`,
      // который тянет `AppState`/сеть — здесь проверяем ровно то звено,
      // которое подставлено на месте заголовка (`import_screen.dart`,
      // `subscription_switcher.dart`): `FlagText(info.title)`.
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: FlagText('🇩🇪 Моя подписка'),
        ),
      ));
      await tester.pump();

      expect(find.byType(CountryFlag), findsOneWidget,
          reason: 'название подписки с флагом обязано показать картинку');
      expect(find.textContaining('DE'), findsNothing);
      expect(find.textContaining('Моя подписка'), findsWidgets);
    });
  });
}

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
