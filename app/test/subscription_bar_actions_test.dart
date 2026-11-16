import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_info.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/split_service_presets.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/state/support_chat_controller.dart';
import 'package:silentgate/ui/widgets/subscription_bar.dart';
import 'package:silentgate/ui/widgets/subscription_switcher.dart';
import 'package:silentgate/ui/widgets/support_chat_overlay.dart';
import 'package:silentgate/ui/widgets/telegram_icon.dart';

void main() {
  final l = AppLocalizationsRu();

  group('SupportEndpointTarget и URL-преобразования', () {
    test('очищает /sub/<id> и /silentgate/<id> от редиректов', () {
      final fromSub = SupportEndpointTarget.parse(
        'https://sub.silentgate.lol/sub/EXAMPLE_TOKEN_01',
      );
      expect(fromSub, isNotNull);
      expect(fromSub!.baseHostUrl, 'https://s.silentgate.lol');
      expect(fromSub.shortUuid, 'EXAMPLE_TOKEN_01');
      expect(fromSub.pageUrl, 'https://s.silentgate.lol/EXAMPLE_TOKEN_01');
      expect(
        fromSub.supportApiUrl,
        'https://s.silentgate.lol/EXAMPLE_TOKEN_01/support',
      );

      final fromDeepLinkRedirect = SupportEndpointTarget.parse(
        'https://s.silentgate.lol/silentgate/EXAMPLE_TOKEN_01',
      );
      expect(fromDeepLinkRedirect, isNotNull);
      expect(fromDeepLinkRedirect!.shortUuid, 'EXAMPLE_TOKEN_01');
      expect(
        SubscriptionActions.subscriptionPageUrl(
          'https://s.silentgate.lol/silentgate/EXAMPLE_TOKEN_01',
        ),
        'https://s.silentgate.lol/EXAMPLE_TOKEN_01',
      );
      expect(
        SubscriptionActions.supportWebUrl(
          'https://s.silentgate.lol/silentgate/EXAMPLE_TOKEN_01',
        ),
        'https://s.silentgate.lol/EXAMPLE_TOKEN_01#support-modal',
      );
    });

    test('telegramUrlFor использует ссылку из заголовка или дефолтного бота', () {
      const withHeader = SubscriptionInfo(
        supportUrl: 'https://t.me/custom_support_bot',
      );
      expect(
        SubscriptionActions.telegramUrlFor(
          info: withHeader,
          subscriptionUrl: 'https://sub.silentgate.lol/sub/abc12345',
        ),
        'https://t.me/custom_support_bot',
      );

      const withoutHeader = SubscriptionInfo();
      expect(
        SubscriptionActions.telegramUrlFor(
          info: withoutHeader,
          subscriptionUrl: 'https://sub.silentgate.lol/sub/abc12345',
        ),
        SubscriptionActions.defaultTelegramBotUrl,
      );
    });
  });

  group('Пресеты нейросетей (ИИ)', () {
    test('toggleAiAppsPreset и toggleAiSitesPreset переключают списки правил', () {
      const emptyApps = <AppRule>[];
      expect(SplitServicePresets.isAiAppsPresetActive(emptyApps), isFalse);
      final withApps = SplitServicePresets.toggleAiAppsPreset(emptyApps);
      expect(withApps.added, isTrue);
      expect(SplitServicePresets.isAiAppsPresetActive(withApps.apps), isTrue);
      expect(
        withApps.apps.any((a) => a.path.toLowerCase() == 'antigravity.exe'),
        isTrue,
      );
      expect(
        withApps.apps.any((a) => a.path.toLowerCase() == 'claude.exe'),
        isTrue,
      );
      final removedApps = SplitServicePresets.toggleAiAppsPreset(withApps.apps);
      expect(removedApps.added, isFalse);
      expect(
        SplitServicePresets.isAiAppsPresetActive(removedApps.apps),
        isFalse,
      );

      const emptySites = <SiteRule>[];
      expect(SplitServicePresets.isAiSitesPresetActive(emptySites), isFalse);
      final withSites = SplitServicePresets.toggleAiSitesPreset(emptySites);
      expect(withSites.added, isTrue);
      expect(SplitServicePresets.isAiSitesPresetActive(withSites.sites), isTrue);
      expect(
        withSites.sites.map((s) => s.domain),
        contains('claude.ai'),
      );
      expect(
        withSites.sites.map((s) => s.domain),
        contains('daily-cloudcode-pa.googleapis.com'),
      );
      final removedSites =
          SplitServicePresets.toggleAiSitesPreset(withSites.sites);
      expect(removedSites.added, isFalse);
      expect(
        SplitServicePresets.isAiSitesPresetActive(removedSites.sites),
        isFalse,
      );
    });
  });

  group('Кнопки внизу SubscriptionBar и встроенное окно поддержки', () {
    Directory? tmp;
    AppState? state;
    SettingsController? settingsCtrl;

    setUp(() async {
      SupportChatController.clearMemoryStoreForTests();
      SupportChatController.instance.resetForTest();
      tmp = Directory.systemTemp.createTempSync('sg_sub_actions_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      File('${tmp!.path}${sep}silentgate_settings.json').writeAsStringSync(
        jsonEncode({'autoUpdateEnabled': false, 'hidePanelAnnounce': false}),
      );
      File('${tmp!.path}${sep}subscriptions.json').writeAsStringSync(
        jsonEncode({
          'activeId': _id,
          'items': [
            {
              'id': _id,
              'url': _url,
              'servers': [_link],
              'info': {
                'title': 'SilentGate VPN',
                'uploadBytes': 1 << 30,
                'downloadBytes': 5 << 30,
                'totalBytes': 100 << 30,
                'expiresAt': '2099-01-01T00:00:00.000Z',
                'announce': 'Тестовое объявление в карточке подписки',
              },
            },
          ],
        }),
      );
      final sc = SettingsController();
      await sc.init();
      settingsCtrl = sc;
      final s = AppState(engine: _FakeEngine());
      await s.init();
      state = s;
    });

    tearDown(() async {
      SupportChatController.instance.resetForTest();
      SupportChatController.clearMemoryStoreForTests();
      state?.dispose();
      state = null;
      settingsCtrl?.dispose();
      settingsCtrl = null;
      await Future<void>.delayed(Duration.zero);
      AppPaths.resetForTests();
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'кнопки «Телеграм / Бот» и «Поддержка» расположены в самом низу под объявлением и содержат значок Telegram',
      (tester) async {
        tester.view.physicalSize = const Size(964, 761);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppState>.value(value: state!),
              ChangeNotifierProvider<SettingsController>.value(
                value: settingsCtrl!,
              ),
            ],
            child: const MaterialApp(
              locale: Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [SubscriptionBar(compact: true)],
                    ),
                    SupportChatOverlay(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final announceFinder =
            find.text('Тестовое объявление в карточке подписки');
        final tgBtnFinder = find.byKey(const Key('subBarTelegramButton'));
        final supBtnFinder = find.byKey(const Key('subBarSupportButton'));

        expect(announceFinder, findsOneWidget);
        expect(tgBtnFinder, findsOneWidget);
        expect(supBtnFinder, findsOneWidget);
        expect(find.byType(TelegramIcon), findsOneWidget);

        // Обе кнопки обязаны находиться НИЖЕ блока объявления:
        final announceBottom = tester.getBottomLeft(announceFinder).dy;
        final tgTop = tester.getTopLeft(tgBtnFinder).dy;
        final supTop = tester.getTopLeft(supBtnFinder).dy;
        expect(tgTop, greaterThan(announceBottom));
        expect(supTop, greaterThan(announceBottom));
      },
    );

    testWidgets(
      'клик «Поддержка» открывает внутреннее окно, текст сохраняется на диске, клик мимо сворачивает в значок со счётчиком',
      (tester) async {
        tester.view.physicalSize = const Size(980, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppState>.value(value: state!),
              ChangeNotifierProvider<SettingsController>.value(
                value: settingsCtrl!,
              ),
            ],
            child: const MaterialApp(
              locale: Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SizedBox.expand(
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [SubscriptionBar()],
                      ),
                      SupportChatOverlay(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Нажимаем кнопку «Поддержка» в карточке подписки
        await tester.tap(find.byKey(const Key('subBarSupportButton')));
        await tester.pump();

        expect(find.byKey(const Key('inAppSupportModalCard')), findsOneWidget);
        expect(SupportChatController.instance.isExpanded, isTrue);

        // Вводим имя и вопрос в форму
        await tester.enterText(
          find.byKey(const Key('supportNameInput')),
          'Алексей',
        );
        await tester.enterText(
          find.byKey(const Key('supportQuestionInput')),
          'Не открывается один сервер после переключения',
        );
        await tester.pump();

        expect(SupportChatController.instance.draftName, 'Алексей');
        expect(
          SupportChatController.instance.draftText,
          'Не открывается один сервер после переключения',
        );

        // Проверяем, что данные реально сброшены на диск в support_chat_state.json
        final diskFile = File(
          '${tmp!.path}${Platform.pathSeparator}support_chat_state.json',
        );
        expect(diskFile.existsSync(), isTrue);
        final savedJson =
            jsonDecode(diskFile.readAsStringSync()) as Map<String, dynamic>;
        expect(
          (savedJson['subs'] as Map)['EXAMPLE_TOKEN_01']['draftText'],
          'Не открывается один сервер после переключения',
        );

        // Кликаем мимо окна поддержки (в подложку) — окно должно СВЕРНУТЬСЯ, а не закрыться
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();

        expect(find.byKey(const Key('inAppSupportModalCard')), findsNothing);
        expect(SupportChatController.instance.isMinimized, isTrue);
        expect(
          find.byKey(const Key('supportFloatingBadgeButton')),
          findsOneWidget,
        );

        // Эмулируем приход 2 новых сообщений от оператора, пока окно свёрнуто
        SupportChatController.instance.injectTicketsForTest([
          const SupportTicketItem(
            id: 42,
            no: '42',
            status: 'open',
            messages: [
              SupportMessageItem(
                id: 101,
                dir: 'in',
                text: 'Не открывается один сервер после переключения',
              ),
              SupportMessageItem(
                id: 102,
                dir: 'out',
                text: 'Здравствуйте! Проверяем узел.',
              ),
              SupportMessageItem(
                id: 103,
                dir: 'out',
                text: 'Узел перезапущен, проверьте сейчас.',
              ),
            ],
          ),
        ]);
        await tester.pump();

        expect(SupportChatController.instance.unreadCount, 2);
        expect(find.byKey(const Key('supportUnreadBadgeText')), findsOneWidget);
        expect(find.byKey(const Key('subBarSupportUnreadBadge')), findsOneWidget);
        expect(find.text('2'), findsNWidgets(2));

        // Разворачиваем окно кликом по плавающему значку — счётчик непрочитанных гаснет,
        // а черновик остаётся на месте!
        await tester.tap(find.byKey(const Key('supportFloatingBadgeButton')));
        await tester.pump();

        expect(find.byKey(const Key('inAppSupportModalCard')), findsOneWidget);
        expect(SupportChatController.instance.unreadCount, 0);
        expect(
          SupportChatController.instance.draftText,
          'Не открывается один сервер после переключения',
        );
        expect(
          find.text('Узел перезапущен, проверьте сейчас.'),
          findsOneWidget,
        );
      },
    );

    test('бесшовная миграция ссылки подписки при сбросе токена инициатором', () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final oldUrl = 'http://127.0.0.1:${server.port}/sub/oldToken12345';
      final newUrl = 'http://127.0.0.1:${server.port}/sub/newToken99999';

      String? migratedFrom;
      String? migratedTo;

      server.listen((HttpRequest req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'migrated_sub_url': newUrl,
          'tickets': [],
        }));
        await req.response.close();
      });

      final ctrl = SupportChatController(
        onMigrateSubscriptionUrl: (from, to) async {
          migratedFrom = from;
          migratedTo = to;
          return true;
        },
      );
      addTearDown(ctrl.dispose);

      await ctrl.bindSubscriptionUrl(oldUrl);
      await ctrl.fetchTickets(silent: false);

      expect(migratedFrom, oldUrl);
      expect(migratedTo, newUrl);
      expect(ctrl.target?.shortUuid, 'newToken99999');
    });
  });

  test('меню «⋮» содержит пункты Телеграм, Страница подписки и Поддержка в нужном порядке', () {
    final items = SubscriptionActions.menuItems(
      l,
      hasUrl: true,
      hasTelegram: true,
    ).whereType<PopupMenuItem<String>>().map((e) => e.value).toList();

    final tgIdx = items.indexOf(SubscriptionActions.telegram);
    final siteIdx = items.indexOf(SubscriptionActions.site);
    final supIdx = items.indexOf(SubscriptionActions.support);

    expect(tgIdx, greaterThanOrEqualTo(0));
    expect(siteIdx, greaterThan(tgIdx));
    expect(supIdx, greaterThan(siteIdx));
  });
}

const _url = 'https://s.silentgate.lol/silentgate/EXAMPLE_TOKEN_01';
final _id = SubscriptionProfile.idFor(_url);
const _link = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
    '?type=tcp&security=none#Alpha-1';

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
  Future<void> connect(
    VpnServer server, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {}

  @override
  Future<void> connectBalancer(
    List<VpnServer> servers, {
    ConnectionOptions options = const ConnectionOptions(),
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
