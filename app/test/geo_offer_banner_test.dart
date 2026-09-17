import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/geo/geo_bases.dart';
import 'package:silentgate/core/geo/geo_bases_controller.dart' show GeoAction;
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/ui/home_screen.dart';

/// СТРАЖ НА `geoOfferReason` И `GeoOfferBanner` (`app/lib/state/app_state.dart`
/// + `app/lib/ui/home_screen.dart`) — из BACKLOG.md, раздел отложенных тестов
/// вёрстки: плашка не была покрыта вовсе, ни как чистое решение, ни как
/// собранный виджет.
///
/// Две части ниже проверяют РАЗНОЕ:
/// * `geoOfferReason` — чистая функция, и это НАСТОЯЩЕЕ решение «показывать
///   или нет» (см. её собственный комментарий в app_state.dart). `GeoOfferBanner`
///   лишь красит то, что она вернула.
/// * `GeoOfferBanner` — что виджет ДЕЙСТВИТЕЛЬНО вызывает эту функцию с
///   настоящими `AppState`/`GeoBasesController`, а не со своей копией условия,
///   и что кнопка «больше не предлагать» доезжает до `AppState.dismissGeoOffer`.
void main() {
  group('geoOfferReason — чистое решение «предложить или промолчать»', () {
    test('файлов нет, правила есть → предлагаем скачать', () {
      expect(
          geoOfferReason(
              filesAction: GeoAction.download,
              rulesInUse: true,
              verdict: null,
              dismissed: null),
          EngineNoticeKind.geoAssetsMissing);
    });

    test('файлов нет, правил в конфигах НЕТ, ядро не жаловалось → молчим', () {
      // ⚠️ ГЕЙТ ПРОТИВ НАДОЕДАНИЯ. Без вердикта ядра и без ссылок на geoip/
      // geosite в конфигах предлагать скачать 25 МБ — значит платить трафиком
      // за то, что ничего не изменит.
      expect(
          geoOfferReason(
              filesAction: GeoAction.download,
              rulesInUse: false,
              verdict: null,
              dismissed: null),
          isNull);
    });

    test('файлов нет, правил не видно, но ЯДРО уже пожаловалось → предлагаем',
        () {
      // Жалоба ядра сильнее нашего разбора конфигов: профиль мог прийти как
      // rawJsonOverride в формате, который наш анализ не разобрал.
      expect(
          geoOfferReason(
              filesAction: GeoAction.download,
              rulesInUse: false,
              verdict: EngineNoticeKind.geoAssetsMissing,
              dismissed: null),
          EngineNoticeKind.geoAssetsMissing);
    });

    for (final action in [
      GeoAction.check,
      GeoAction.update,
      GeoAction.upToDate
    ]) {
      test('файлы на месте ($action), вердикт «непригодны» → предлагаем '
          'перекачать', () {
        expect(
            geoOfferReason(
                filesAction: action,
                rulesInUse: true,
                verdict: EngineNoticeKind.geoAssetsUnusable,
                dismissed: null),
            EngineNoticeKind.geoAssetsUnusable);
      });
    }

    test('файлы на месте, вердикта нет → молчим', () {
      expect(
          geoOfferReason(
              filesAction: GeoAction.check,
              rulesInUse: true,
              verdict: null,
              dismissed: null),
          isNull);
    });

    test('⚠️ файлы на месте, СТАРЫЙ вердикт «файлов нет» → молчим', () {
      // Вердикт мог остаться от прошлого подключения; человек мог скачать
      // базы сразу после него — предлагать скачивание снова означало бы
      // спорить с фактом на диске, который важнее прошлого вердикта.
      expect(
          geoOfferReason(
              filesAction: GeoAction.check,
              rulesInUse: true,
              verdict: EngineNoticeKind.geoAssetsMissing,
              dismissed: null),
          isNull);
    });

    test('отказ по ТОМУ ЖЕ поводу — молчим', () {
      expect(
          geoOfferReason(
              filesAction: GeoAction.download,
              rulesInUse: true,
              verdict: null,
              dismissed: EngineNoticeKind.geoAssetsMissing),
          isNull);
    });

    test('⚠️ отказ по ДРУГОМУ поводу не гасит новый', () {
      // Два повода запоминаются раздельно (см. комментарий к
      // `AppState._geoOfferDismissed`): отказ от «скачать» не должен глушить
      // «перекачать», когда ядро сообщает о поломке уже скачанных файлов.
      expect(
          geoOfferReason(
              filesAction: GeoAction.check,
              rulesInUse: true,
              verdict: EngineNoticeKind.geoAssetsUnusable,
              dismissed: EngineNoticeKind.geoAssetsMissing),
          EngineNoticeKind.geoAssetsUnusable);
      expect(
          geoOfferReason(
              filesAction: GeoAction.download,
              rulesInUse: true,
              verdict: null,
              dismissed: EngineNoticeKind.geoAssetsUnusable),
          EngineNoticeKind.geoAssetsMissing);
    });
  });

  group('GeoOfferBanner — собранный виджет', () {
    late Directory tmp;

    const link = 'vless://11111111-2222-3333-4444-555555555555'
        '@a.example.com:443?encryption=none#Alpha';

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_geo_offer_');
      AppPaths.overrideRoot(tmp);
      GeoBases.overrideDir(
          Directory('${tmp.path}${Platform.pathSeparator}geo'));
    });

    tearDown(() {
      GeoBases.resetForTests();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    void writeDisk({String? dismissed}) {
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
            'servers': [link],
            'addedAt': '2026-09-01T00:00:00.000Z',
          },
        ],
      }));
      if (dismissed != null) {
        File('${tmp.path}${Platform.pathSeparator}silentgate_state.json')
            .writeAsStringSync(jsonEncode({'geoOfferDismissed': dismissed}));
      }
    }

    Future<AppState> boot(WidgetTester t, {required _FakeEngine engine}) async {
      final state = AppState(engine: engine);
      await t.runAsync(() => state.init());
      return state;
    }

    Widget host(AppState state) => ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            locale: Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: GeoOfferBanner()),
          ),
        );

    /// ⚠️ ПОЧЕМУ ВЕРДИКТ ЯДРА, А НЕ «ФАЙЛОВ НЕТ». `GeoOfferBanner` держит
    /// СВОЙ `GeoBasesController` внутри `State` (не принимает его снаружи), и
    /// его `refresh()` запускается `unawaited` прямо в `build()` — а значит
    /// СТАРТУЕТ под фальшивым временем `testWidgets`, где настоящий дисковый
    /// ввод-вывод, по опыту всего проекта (см. `boot()` в других тестах), не
    /// завершается вовсе. Дождаться в тесте состояния «файлов нет» от НЕГО
    /// нечем. Путь через вердикт ядра (`EngineNotice.geoAssetsUnusable`)
    /// свободен от этого: `geoOfferReason` для ветки «непригодны» проверку
    /// файлов на диске не спрашивает вовсе (см. её собственный код) — она и
    /// проверяется здесь по-настоящему, без гонки с диском.
    Future<AppState> pumpUnusable(WidgetTester t,
        {String? dismissed}) async {
      writeDisk(dismissed: dismissed);
      final engine = _FakeEngine();
      final state = await boot(t, engine: engine);
      addTearDown(engine.dispose);
      await t.pumpWidget(host(state));
      await t.pump();
      expect(find.byType(Card), findsNothing,
          reason: 'до вердикта ядра плашке взяться неоткуда');

      engine.emitNotice(const EngineNotice(
          EngineNoticeKind.geoAssetsUnusable, 'ядро не открыло гео-базы'));
      // ⚠️ ДВА `pump()`, А НЕ ОДИН. Первый доносит событие потока до
      // `AppState` (микрозадача `StreamController.add`), второй — уже
      // перерисовывает `GeoOfferBanner` по изменившемуся `AppState`. Одного
      // кадра не хватает: виджет остаётся с прежним (пустым) выводом.
      await t.pump();
      await t.pump();
      return state;
    }

    testWidgets('⚠️ без гео-правил и вердикта — плашки нет', (t) async {
      writeDisk();
      final engine = _FakeEngine();
      final state = await boot(t, engine: engine);
      addTearDown(engine.dispose);
      await t.pumpWidget(host(state));
      await t.pump();

      expect(t.takeException(), isNull);
      expect(state.geoRulesInUse, isFalse);
      expect(state.geoVerdict, isNull);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets(
        'вердикт «базы непригодны» — плашка появляется и зовёт «Обновить»',
        (t) async {
      final l = AppLocalizationsRu();
      final state = await pumpUnusable(t);
      expect(t.takeException(), isNull);
      expect(state.geoVerdict, EngineNoticeKind.geoAssetsUnusable);

      expect(find.byType(Card), findsOneWidget,
          reason: 'вердикт ядра обязан проявиться плашкой на главном — '
              'до этого он оседал только в журнале');
      expect(find.byKey(const ValueKey('geoOfferAct')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('geoOfferAct')),
              matching: find.text(l.geoUpdate)),
          findsOneWidget,
          reason: 'базы УЖЕ скачаны и не открылись — кнопка обязана звать '
              '«Обновить» (перекачать), а не «Скачать» — предлагать «скачать» '
              'тому, у кого файлы уже есть, было бы бессмысленным советом');
    });

    testWidgets('нажатие «больше не предлагать» прячет плашку и запоминает '
        'повод', (t) async {
      final state = await pumpUnusable(t);
      expect(find.byType(Card), findsOneWidget);
      expect(state.geoOfferDismissedFor, isNull);

      await t.tap(find.byKey(const ValueKey('geoOfferDismiss')));
      await t.pump();

      expect(find.byType(Card), findsNothing,
          reason: 'нажатие на «не предлагать» обязано убрать плашку сразу, '
              'не дожидаясь следующего запуска');
      expect(state.geoOfferDismissedFor, EngineNoticeKind.geoAssetsUnusable,
          reason: 'повод запоминается КОНКРЕТНЫЙ, а не флагом «закрыто»');
    });

    testWidgets(
        '⚠️ отказ пережил перезапуск — тот же вердикт плашку не поднимает',
        (t) async {
      final state = await pumpUnusable(t,
          dismissed: EngineNoticeKind.geoAssetsUnusable.name);
      expect(t.takeException(), isNull);
      expect(state.geoVerdict, EngineNoticeKind.geoAssetsUnusable,
          reason: 'вердикт пришёл СНОВА — молчит именно отказ, а не '
              'отсутствие повода');
      expect(state.geoOfferDismissedFor, EngineNoticeKind.geoAssetsUnusable);
      expect(find.byType(Card), findsNothing);
    });
  });
}

class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final _noticeCtrl = StreamController<EngineNotice>.broadcast();

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => _noticeCtrl.stream;

  void emitNotice(EngineNotice n) => _noticeCtrl.add(n);

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
    await _noticeCtrl.close();
  }
}
