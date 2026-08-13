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
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/widgets/subscription_switcher.dart';

/// Пометка истёкших подписок в меню переключателя (просьба владельца:
/// «помечай истёкшие подписки по дате истечения то что она истекла»).
///
/// ⚠️ ЧТО ИМЕННО ЗДЕСЬ СТЕРЕЖЁТСЯ.
///
/// 1. **Ноль и пусто — это «бессрочно», а НЕ «истекла».** Панель кодирует
///    бессрочность нулём (`expire=0`), а профиль старой версии метаданных не
///    хранил вовсе. Пометить такие истёкшими значило бы перечеркнуть все
///    бессрочные подписки — эта ловушка в проекте уже срабатывала (фикс 0.4.0
///    «expire=0 → бессрочно»).
/// 2. **Сравнивается момент времени, а не календарный день.** Подписка,
///    истекающая сегодня вечером, ещё работает. Мысленно заменив сравнение на
///    усечение до даты, тест «сегодня, но позже текущего времени» краснеет.
/// 3. **Дата неактивной подписки берётся из профиля на диске.** В состоянии
///    приложения живёт карточка ТОЛЬКО активной подписки, а помечать надо все
///    четыре. Профиль без метаданных не помечается (миграция: «дата
///    неизвестна» ≠ «истекла»).
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

void main() {
  final l = AppLocalizationsRu();

  group('Что считается истёкшим', () {
    // Момент «сейчас» задан явно: тест не должен зависеть от того, в какую
    // секунду его запустили.
    final now = DateTime(2026, 8, 13, 14, 30);

    test('дата в прошлом — истекла', () {
      final info =
          SubscriptionInfo(expiresAt: now.subtract(const Duration(days: 1)));
      expect(info.isExpiredAt(now), isTrue);
    });

    test('дата в будущем — не истекла', () {
      final info = SubscriptionInfo(expiresAt: now.add(const Duration(days: 1)));
      expect(info.isExpiredAt(now), isFalse);
    });

    test('даты нет — бессрочно, а не истекла', () {
      expect(const SubscriptionInfo().isExpiredAt(now), isFalse);
      expect(SubscriptionInfo.empty.isExpiredAt(now), isFalse);
    });

    test('сегодня, но ПОЗЖЕ текущего времени — ещё работает', () {
      // Ловушка усечения до календарного дня: подписка «до сегодня 23:59»
      // действует весь день, а не «истекла с самого утра».
      final info = SubscriptionInfo(expiresAt: DateTime(2026, 8, 13, 23, 59));
      expect(info.isExpiredAt(now), isFalse);
    });

    test('сегодня, но РАНЬШЕ текущего времени — уже истекла', () {
      // Обратная половина той же ловушки: реализация, которая для «сегодня»
      // всегда отвечает «ещё работает», обязана здесь покраснеть.
      final info = SubscriptionInfo(expiresAt: DateTime(2026, 8, 13, 9, 0));
      expect(info.isExpiredAt(now), isTrue);
    });

    test('expire=0 от панели — бессрочно, а не 1970 год', () {
      final info = SubscriptionInfo.fromHeaders(const {
        'subscription-userinfo': 'upload=0; download=0; total=0; expire=0',
      });
      expect(info.expiresAt, isNull);
      expect(info.isExpiredAt(now), isFalse,
          reason: 'ноль у панели означает «без срока» (фикс 0.4.0)');
    });

    test('UTC на диске и локальное «сейчас» сравниваются по МОМЕНТУ', () {
      // Дата хранится в UTC, а живём мы в локальной зоне. Сравнение обязано
      // идти по абсолютному времени: реализация, которая сопоставляет
      // календарные поля, в любом поясе кроме UTC ответит неверно.
      final soon = SubscriptionInfo(
          expiresAt: now.toUtc().add(const Duration(minutes: 1)));
      final gone = SubscriptionInfo(
          expiresAt: now.toUtc().subtract(const Duration(minutes: 1)));
      expect(soon.isExpiredAt(now), isFalse);
      expect(gone.isExpiredAt(now), isTrue);
    });
  });

  group('Дата подписки переживает перезапуск', () {
    final now = DateTime(2026, 8, 13, 14, 30);
    const url = 'https://panel.example/sub/aaaaaaaa';

    SubscriptionProfile roundTrip(SubscriptionProfile p) =>
        SubscriptionProfile.fromJson(
            jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);

    test('профиль сохраняет момент истечения без потерь', () {
      // Дата неактивной подписки берётся ТОЛЬКО отсюда: в состоянии живёт
      // карточка одной активной. Перестань `toJson` писать `info` — и все
      // остальные подписки перестанут помечаться, молча.
      final exp = DateTime(2026, 3, 4, 15, 30);
      final p = SubscriptionProfile(
          id: SubscriptionProfile.idFor(url),
          url: url,
          info: SubscriptionInfo(title: 'Alpha', expiresAt: exp));
      final back = roundTrip(p);
      expect(back.info.expiresAt, isNotNull);
      expect(back.info.expiresAt!.isAtSameMomentAs(exp), isTrue,
          reason: 'момент обязан совпасть до секунды, а не «до даты»');
      expect(back.isExpiredAt(now), isTrue);
    });

    test('будущая дата после перезапуска остаётся будущей', () {
      final p = SubscriptionProfile(
          id: SubscriptionProfile.idFor(url),
          url: url,
          info: SubscriptionInfo(expiresAt: now.add(const Duration(hours: 5))));
      expect(roundTrip(p).isExpiredAt(now), isFalse);
    });

    test('старый профиль без метаданных НЕ помечается истёкшим', () {
      // Так выглядит запись, сделанная версией, которая `info` ещё не писала.
      final old = SubscriptionProfile.fromJson({
        'id': 'sub_old',
        'url': url,
        'servers': <String>[],
      });
      expect(old.info.expiresAt, isNull);
      expect(old.isExpiredAt(now), isFalse,
          reason: '«дата неизвестна» — это не «подписка истекла»');
    });
  });

  group('Меню переключателя помечает истёкшие подписки', () {
    const urlA = 'https://panel.example/sub/aaaaaaaa';
    const urlB = 'https://panel.example/sub/bbbbbbbb';
    const urlC = 'https://panel.example/sub/cccccccc';
    final idA = SubscriptionProfile.idFor(urlA);
    final idB = SubscriptionProfile.idFor(urlB);
    final idC = SubscriptionProfile.idFor(urlC);

    // Фиксированная дата в прошлом: она останется прошлым, когда бы тест ни
    // запустили. Будущая, наоборот, считается от «сейчас».
    final expiredAt = DateTime(2026, 3, 4, 15, 30);
    final aliveUntil = DateTime.now().add(const Duration(days: 30));

    const a1 = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
        '?type=tcp&security=none#Alpha-1';
    const b1 = 'vless://22222222-2222-2222-2222-222222222222@b1.example:443'
        '?type=tcp&security=none#Bravo-1';
    const c1 = 'vless://33333333-3333-3333-3333-333333333333@c1.example:443'
        '?type=tcp&security=none#Charlie-1';

    Directory? tmp;
    late AppState state;
    late ProbeController probe;
    late SettingsController settings;

    /// Три подписки на диске: активная A (действует), B (истекла) и C — запись
    /// СТАРОГО формата, вообще без метаданных.
    ///
    /// Кладём `subscriptions.json` до `init()`: это единственный способ
    /// получить здесь настоящие неактивные подписки — `importSource` ходит в
    /// сеть, а собирать профили мимо `AppState` значило бы проверять не тот
    /// путь, которым подписки доходят до меню после перезапуска.
    Future<void> boot() async {
      tmp = Directory.systemTemp.createTempSync('sg_expired_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      File('${tmp!.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp!.path}${sep}subscriptions.json')
          .writeAsStringSync(jsonEncode({
        'activeId': idA,
        'items': [
          {
            'id': idA,
            'url': urlA,
            'servers': [a1],
            'info': {
              'title': 'Alpha',
              // На диск дата ложится в UTC — ровно так её пишет
              // `SubscriptionInfo.toJson`.
              'expiresAt': aliveUntil.toUtc().toIso8601String(),
            },
          },
          {
            'id': idB,
            'url': urlB,
            'servers': [b1],
            'info': {
              'title': 'Bravo',
              'expiresAt': expiredAt.toUtc().toIso8601String(),
            },
          },
          // C — профиль без `info`: старая версия клиента метаданных не писала.
          {'id': idC, 'url': urlC, 'servers': [c1]},
        ],
      }));
      state = AppState(engine: _FakeEngine());
      await state.init();
      probe = ProbeController();
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
            // экрана нижние строки уехали бы за край тестового холста.
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SubscriptionSwitcher(title: 'Alpha'),
              ),
            ),
          ),
        );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byType(SubscriptionSwitcher));
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

    Finder mark(String id) => find.byKey(ValueKey('subExpired_$id'));

    testWidgets('помечена только истёкшая — не действующая и не «без даты»',
        (tester) async {
      await tester.runAsync(boot);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openMenu(tester);

      expect(mark(idB), findsOneWidget,
          reason: 'подписка с датой в прошлом обязана быть помечена');
      expect(mark(idA), findsNothing,
          reason: 'действующая подписка пометки не получает');
      expect(mark(idC), findsNothing,
          reason: 'профиль без даты — это «неизвестно», а не «истекла»');

      // Подпись словами, а не только значок: значок в одиночку читается как
      // что угодно.
      expect(find.text(l.subSwitcherExpired), findsOneWidget);
      // Строка помечена, но не спрятана: истёкшую подписку всё ещё видно и
      // можно выбрать, чтобы обновить.
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('по наведению видно дату истечения', (tester) async {
      await tester.runAsync(boot);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openMenu(tester);

      final tip = tester.widget<Tooltip>(
          find.descendant(of: mark(idB), matching: find.byType(Tooltip)));
      expect(tip.message, l.subSwitcherExpiredOn('04.03.2026'),
          reason: 'дата показывается в локальной зоне, а не в UTC как на диске');
    });
  });
}
