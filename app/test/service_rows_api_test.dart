import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/api_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// Три требования владельца от 18.08.2026, у которых один общий почерк: экран
/// показывает НЕ ТО, что есть на самом деле.
///
///  1. Четырнадцать проверок стояли двумя одинаковыми столбиками по бокам
///     кнопки Connect — «Telegram зелёный, ChatGPT красный, Instagram зелёный»
///     вперемешку читается как случайность, а не как диагноз «мессенджеры
///     живы, ИИ нет».
///  2. Абзац в 230 символов висел голой подсказкой над строкой списка серверов
///     и накрывал соседей (тот же дефект, что владелец прислал скриншотом по
///     раздельному туннелированию).
///  3. Экран API называл номера портов, ничего не говоря о том, что в режиме
///     системного прокси (умолчание на Windows) их не существует вовсе, — и
///     светил токеном, который является паролем ко всему каналу.
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

  // ───────────────────────────────────────────────────────────────────────────
  group('Группы сервисов покрывают каталог ровно один раз', () {
    test('каждая группа непуста', () {
      for (final e in ServiceChecks.groups.entries) {
        expect(e.value, isNotEmpty,
            reason: 'подпись «${e.key.name}» над пустым рядом занимала бы '
                'высоту у кнопки Connect и ничего не сообщала');
      }
      // И группа без сервисов не должна появиться сама собой: перечисление и
      // раскладка обязаны совпадать по составу.
      expect(ServiceChecks.groups.keys.toSet(), ServiceGroup.values.toSet());
    });

    test('объединение групп = весь каталог', () {
      final union = [
        for (final services in ServiceChecks.groups.values) ...services,
      ];
      // ⚠️ ПОСОСТАВНО, А НЕ ПОПОРЯДКУ: каталог задаёт порядок в подменю, группы
      // — порядок рядов, и это разные порядки по замыслу. Сойтись они обязаны
      // именно составом: сервис, забытый в группах, молча выпал бы из рядов
      // (в подменю он есть, галочку поставить можно, а кружка на главном нет),
      // лишний — нарисовался бы кружок, которого нельзя выбрать.
      expect(union.toSet(), ServiceChecks.catalog.toSet());
      expect(union.length, ServiceChecks.catalog.length,
          reason: 'дубль в группах дал бы два кружка одному сервису');
      expect(union.toSet(), ProbeService.values.toSet());
    });

    test('сервис не попадает в две группы', () {
      final seen = <ProbeService, ServiceGroup>{};
      for (final e in ServiceChecks.groups.entries) {
        for (final s in e.value) {
          expect(seen[s], isNull,
              reason: '${s.name} уже лежит в ${seen[s]?.name}: два ряда рисовали '
                  'бы один и тот же кружок, а тап по одному молча менял бы '
                  'второй');
          seen[s] = e.key;
        }
      }
      expect(seen.length, ServiceChecks.catalog.length);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Раскладка по рядам', () {
    test('пустые группы не возвращаются', () {
      final rows = ServiceChecks.grouped(const [ProbeService.claude]);
      expect(rows.length, 1);
      expect(rows.single.group, ServiceGroup.ai);
      expect(rows.single.services, [ProbeService.claude]);
    });

    test('порядок рядов — порядок групп, а не порядок выбора', () {
      final rows = ServiceChecks.grouped(const [
        ProbeService.github, // «Прочее» — последняя группа
        ProbeService.telegram, // «Мессенджеры» — первая
        ProbeService.youtube, // «Видео и музыка» — третья
      ]);
      expect(rows.map((r) => r.group).toList(),
          [ServiceGroup.messengers, ServiceGroup.media, ServiceGroup.other]);
    });

    test('порядок внутри ряда — объявленный, а не пришедший', () {
      // Набор приходит из настроек множеством, у множества порядка нет вовсе:
      // возьми мы его как есть, чипы перескакивали бы после каждой правки.
      final rows = ServiceChecks.grouped(const [
        ProbeService.discord,
        ProbeService.telegram,
      ]);
      expect(rows.single.services,
          [ProbeService.telegram, ProbeService.discord]);
    });

    test('пустой набор — рядов нет', () {
      expect(ServiceChecks.grouped(const []), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Ряды на экране', () {
    Widget host(List<ProbeService> services) => MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChangeNotifierProvider(
            create: (_) => ServiceCheckController(),
            child: Scaffold(
              body: Center(
                child: ServiceChecksRows(services: services, httpPort: 0),
              ),
            ),
          ),
        );

    testWidgets('каждый ряд отделён подписью и линиями', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1040, 900);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(const [
        ProbeService.telegram,
        ProbeService.chatgpt,
        ProbeService.claude,
      ]));
      await t.pump();

      // Ровно два ряда: мессенджеры и ИИ. Прежняя раскладка (две колонки)
      // разделителей не имела вовсе — этот тест на ней красный.
      expect(find.byKey(const ValueKey('serviceGroup:messengers')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('serviceGroup:ai')), findsOneWidget);
      expect(find.byKey(const ValueKey('serviceGroup:media')), findsNothing);
      expect(find.text(l.serviceGroupMessengers), findsOneWidget);
      expect(find.text(l.serviceGroupAi), findsOneWidget);
      // Разграничение именно ЛИНИЯМИ, а не отступом: у кнопки Connect пустой
      // промежуток между рядами на глаз неотличим от промежутка внутри ряда.
      expect(find.byType(Divider), findsNWidgets(4));
    });

    testWidgets('у каждой пары свой ключ по имени сервиса', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1040, 900);
      addTearDown(t.view.reset);
      await t.pumpWidget(
          host(const [ProbeService.telegram, ProbeService.whatsapp]));
      await t.pump();

      // Без ключей Flutter сопоставляет элементы позиционно, и при смене
      // состава вторая пара забирала состояние первой: оживал чужой значок.
      expect(find.byKey(const ValueKey('svc:telegram')), findsOneWidget);
      expect(find.byKey(const ValueKey('svc:whatsapp')), findsOneWidget);
    });

    testWidgets('проверок нет — нет и рядов, место не занимается', (t) async {
      await t.pumpWidget(host(const []));
      await t.pump();
      expect(find.byType(Divider), findsNothing);
      expect(t.getSize(find.byType(ServiceChecksRows)), Size.zero);
    });

    testWidgets('узкий экран: ряд переносится, а не уезжает за край', (t) async {
      // 360 dp — обычный телефон. Пять пар в одну строку туда не влезают.
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(360, 640);
      addTearDown(t.view.reset);
      await t.pumpWidget(host(ServiceChecks.catalog));
      await t.pump();

      expect(t.takeException(), isNull,
          reason: 'переполнение вёрстки на телефоне — это и есть «распёрло окно»');
      final w = t.getSize(find.byType(ServiceChecksRows)).width;
      expect(w, lessThanOrEqualTo(360));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('Памятка по API', () {
    late Directory tmp;
    late AppState state;
    late SettingsController settings;

    const link = 'vless://00000000-0000-0000-0000-000000000000@a.example:443'
        '?type=tcp&security=none#Alpha';

    Future<void> boot(
        {CaptureMode mode = CaptureMode.tun, String token = 'S3CRET-TOKEN'}) async {
      // ⚠️ Боевой каталог под тестами не отдаётся вовсе — объявляем свой.
      tmp = Directory.systemTemp.createTempSync('sg_api_memo_');
      AppPaths.overrideRoot(tmp);
      state = AppState(engine: _FakeEngine());
      await state.init();
      await state.importSource(link);
      settings = SettingsController();
      await settings.init();
      await settings.update((s) => s.copyWith(
            apiEnabled: true,
            apiToken: token,
            captureMode: mode,
            apiExitServerKeys: [state.servers.first.key],
          ));
    }

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget app() => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
          ],
          child: const MaterialApp(
            locale: Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ApiScreen(),
          ),
        );

    /// Большой холст: `ListView` строит только видимое, и на 800×600 памятка
    /// осталась бы непостроенной — проверки краснели бы по ложной причине.
    void bigSurface(WidgetTester t) {
      t.view.physicalSize = const Size(1200, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    testWidgets('называет настоящий адрес и настоящие порты выходов',
        (t) async {
      await t.runAsync(() => boot(mode: CaptureMode.tun));
      bigSurface(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      expect(find.text('http://127.0.0.1:${ApiPorts.control}'), findsOneWidget,
          reason: 'адрес берётся из `ApiPorts`, а не пишется в тексте руками');
      expect(find.text(l.apiCheatSheetPortDirect(ApiPorts.direct)),
          findsOneWidget);
      // Порт отмеченного сервера считается тем же способом, что и физически
      // (`ApiPorts.forServer`), — иначе памятка называла бы номер, на котором
      // никто не слушает.
      expect(
          find.text(l.apiCheatSheetPortServer(
              ApiPorts.firstServer, state.servers.first.displayName)),
          findsOneWidget);
      // Эндпоинты — строкой на каждый, ровно те, что разбирает
      // `LocalApiServer._route`.
      for (final path in const [
        'GET /v1/status',
        'GET /v1/servers',
        'GET /v1/exits',
        'GET /v1/traffic',
        'GET /v1/subscription',
        'POST /v1/connect',
        'POST /v1/disconnect',
        'POST /v1/ping',
      ]) {
        expect(find.text(path), findsOneWidget, reason: path);
      }
    });

    testWidgets('системный прокси: памятка говорит, что портов НЕТ',
        (t) async {
      await t.runAsync(() => boot(mode: CaptureMode.systemProxy));
      bigSurface(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      expect(find.text(l.apiCheatSheetPortsSystemProxy(ApiPorts.control)),
          findsOneWidget);
      // ⚠️ Главное: номеров портов выходов в этом режиме на экране быть не
      // должно вовсе. Названный порт, которого не существует, — это ровно тот
      // дефект, что уже случался в 1.4.0 с портом «Прямо».
      expect(find.text(l.apiCheatSheetPortDirect(ApiPorts.direct)), findsNothing);
      expect(
          find.text(l.apiCheatSheetPortServer(
              ApiPorts.firstServer, state.servers.first.displayName)),
          findsNothing);
    });

    testWidgets('пустой токен: памятка говорит, что канал не поднимается',
        (t) async {
      await t.runAsync(() => boot(mode: CaptureMode.tun, token: ''));
      bigSurface(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      expect(find.text(l.apiCheatSheetTokenOff), findsOneWidget);
      expect(find.text(l.apiCheatSheetPortDirect(ApiPorts.direct)), findsNothing);
    });

    testWidgets('токен не показывается, пока его не попросят', (t) async {
      const token = 'S3CRET-TOKEN';
      await t.runAsync(() => boot(token: token));
      bigSurface(t);
      await t.pumpWidget(app());
      await t.pumpAndSettle();

      // Экран API открывают ради портов и примера — и вместе с ними в кадр
      // попадал пароль ко ВСЕМУ каналу (он же пароль каждого порта выхода).
      expect(find.textContaining(token), findsNothing);
      expect(find.textContaining(l.apiTokenHidden), findsOneWidget);

      await t.tap(find.byKey(const Key('apiTokenReveal')));
      await t.pumpAndSettle();
      expect(find.text(token), findsOneWidget);

      // И обратно: показ живёт в состоянии экрана, а не в настройках.
      await t.tap(find.byKey(const Key('apiTokenReveal')));
      await t.pumpAndSettle();
      expect(find.textContaining(token), findsNothing);
    });
  });
}
