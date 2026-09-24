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
