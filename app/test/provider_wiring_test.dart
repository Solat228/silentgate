import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/update_installer_fake.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/app_update_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/provider_wiring.dart';
import 'package:silentgate/state/settings_controller.dart';

/// Страж дефекта «провайдер-связка ради побочного эффекта, которую никто не
/// читает» — ровно то, что нашла соседняя задача в `main.dart`
/// (`shadeLayoutLinkProvider`/`apiSettingsLinkProvider`, `state/provider_wiring.dart`).
///
/// `ProxyProvider`/`ProxyProvider2` по умолчанию строят значение ЛЕНИВО:
/// `create`/`update` вызываются только когда их тип читает `context.watch`/
/// `context.read` где-то в дереве. `ShadeLayoutLink` и `ApiSettingsLink`
/// существуют ИСКЛЮЧИТЕЛЬНО ради побочного эффекта конструктора/`update` —
/// их тип не читает ничто, и без `lazy: false` они не строились бы никогда,
/// хотя код выглядел бы совершенно рабочим (компилятор и `flutter analyze`
/// это не ловят).
///
/// ⚠️ Тест собирает РОВНО ТЕ ФУНКЦИИ (`shadeLayoutLinkProvider`,
/// `apiSettingsLinkProvider`), что уходят в боевой `runApp` из `main.dart` —
/// НЕ свою параллельную копию их конструкции. Если кто-то уберёт
/// `lazy: false` в `state/provider_wiring.dart`, тест покраснеет: он и
/// `main.dart` читают один и тот же код.
///
/// Прочитать эффект самих связок напрямую нельзя — конкретный тип создаваемого
/// значения (`ShadeLayoutLink`/`ApiSettingsLink`) снаружи файла не нужен и не
/// экспортируется намеренно (сама и есть суть дефекта: единственная причина
/// его существования — сработавший побочный эффект, а не то, что кто-то
/// прочитал бы значение). Наблюдаем СЛЕДСТВИЯ через публичный API:
///  - `ShadeLayoutLink` кладёт колбэк в `AppState.onCompactToggledInShade`,
///    которое проксируется в движок — подменяем движок фейком и проверяем,
///    что колбэк туда дошёл;
///  - `ApiSettingsLink.applyIfChanged` вызывает `AppState.applyApiSettings` —
///    считаем вызовы в тестовом подклассе `AppState`.
///
/// ⚠️ Настройки по умолчанию (`apiEnabled: false`) и так не подняли бы
/// реальный сокет (см. `AppState.applyApiSettings`), но подклассовая версия
/// НЕ зовёт `super` вовсе — тест не должен зависеть от чужих дефолтов и не
/// имеет права поднять настоящий API-сервер, тронуть боевой `%APPDATA%`
/// (изолируем `AppPaths.overrideRoot`, как `test/api_handlers_test.dart`)
/// или сходить в сеть.
class _SpyEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

  void Function(bool compact)? capturedShadeHandler;

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) =>
      capturedShadeHandler = handler;

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

class _SpyAppState extends AppState {
  _SpyAppState({required VpnEngine engine}) : super(engine: engine);

  int applyApiSettingsCalls = 0;

  @override
  Future<void> applyApiSettings(
      AppSettings s, ProbeController probe, SettingsController settings,
      {int port = ApiPorts.control}) async {
    applyApiSettingsCalls++;
    // Намеренно НЕ зовём super: реальный сервер тесту не нужен ни при каких
    // настройках (см. комментарий класса выше).
  }
}

void main() {
  late Directory dir;
  late _SpyEngine engine;
  late _SpyAppState state;
  late SettingsController settings;
  late ProbeController probe;

  // Самообновление — на подменных зависимостях: ни сети, ни установщика.
  late FakeUpdateInstaller installer;
  late AppUpdateController updateController;
  late Completer<void> checked;
  var updateCreateCalls = 0;
  var checkerCalls = 0;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sg_provider_wiring_');
    AppPaths.overrideRoot(dir);
    engine = _SpyEngine();
    state = _SpyAppState(engine: engine);
    await state.init();
    // ⚠️ БЕЗ init(): загрузку настроек каждый тест самообновления делает
    // сам и в нужный ему момент — запуск контроллера привязан именно к ней.
    settings = SettingsController();
    probe = ProbeController();
    installer = FakeUpdateInstaller(
        staging: Directory('${dir.path}${Platform.pathSeparator}updates'));
    checked = Completer<void>();
    updateCreateCalls = 0;
    checkerCalls = 0;
    updateController = AppUpdateController(
      settings: () => settings.settings,
      updateSettings: settings.update,
      installer: installer,
      checker: ({required bool beta}) async {
        checkerCalls++;
        if (!checked.isCompleted) checked.complete();
        return const UpdateCheckResult.upToDate();
      },
      overridden: true,
    );
  });

  tearDown(() async {
    AppPaths.resetForTests();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Дождаться [done], чередуя настоящее время и такты виджет-теста.
  ///
  /// ⚠️ Зачем чередовать. Продолжение `whenLoaded.then(startup)` повешено
  /// внутри `pumpWidget`, то есть в зоне подменных часов: его микрозадачи
  /// выполняются только на такте (`pump`). А сам старт читает и чистит
  /// каталог закачек настоящим вводом-выводом, который движется только в
  /// `runAsync`. Одного из двух не хватает — ожидание висит до таймаута.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'не дождались за 200 тактов');
  }

  Widget buildTree() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          // Связка №1 — та же функция, что в main.dart.
          shadeLayoutLinkProvider(),
          ChangeNotifierProvider<ProbeController>.value(value: probe),
          // Связка №2 — та же функция, что в main.dart. Требует ProbeController
          // выше в дереве (applyIfChanged читает его через context.read).
          apiSettingsLinkProvider(),
          // Связка №3 — та же функция, что в main.dart.
          unfinishedPruneLinkProvider(),
          // Самообновление — та же функция, что в main.dart; контроллер
          // подменён (create — параметр ради стража), сама функция — нет.
          appUpdateProvider(create: (_) {
            updateCreateCalls++;
            return updateController;
          }),
        ],
        child: const SizedBox.shrink(),
      );

  group('Провайдер-связки строятся БЕЗ единого чтения их типа', () {
    testWidgets(
        'shadeLayoutLinkProvider: колбэк дошёл до движка после одной сборки '
        'дерева, хотя тип ShadeLayoutLink никто не читает', (tester) async {
      expect(engine.capturedShadeHandler, isNull,
          reason: 'до сборки дерева колбэка ещё нет — это база для сравнения');

      await tester.pumpWidget(buildTree());

      expect(engine.capturedShadeHandler, isNotNull,
          reason: 'ProxyProvider2<AppState, SettingsController, '
              'ShadeLayoutLink> обязан построиться с lazy:false — иначе '
              'update() не позовётся никогда, и кнопка "Свернуть" на '
              'уведомлении Android откатывается на следующем такте счётчиков');
    });

    testWidgets(
        'apiSettingsLinkProvider: AppState.applyApiSettings вызван после '
        'одной сборки дерева, хотя тип ApiSettingsLink никто не читает',
        (tester) async {
      expect(state.applyApiSettingsCalls, 0,
          reason: 'до сборки дерева вызовов ещё нет — это база для сравнения');

      await tester.pumpWidget(buildTree());

      expect(state.applyApiSettingsCalls, greaterThan(0),
          reason: 'ProxyProvider<SettingsController, ApiSettingsLink> '
              'обязан построиться с lazy:false — иначе update() не '
              'позовётся никогда, и локальный API-сервер (порт 10870) не '
              'поднимется ни при каких настройках');
    });

    testWidgets(
        'unfinishedPruneLinkProvider: поставщик списка серверов дошёл до '
        'контроллера проб, хотя тип UnfinishedPruneLink никто не читает',
        (tester) async {
      // ⚠️ РАДИ ЧЕГО ЭТА СВЯЗКА ВООБЩЕ ПОЯВИЛАСЬ. Чистку пометки «прогон сюда
      // не дошёл» звало открытие меню переключателя подписок — а он рисуется
      // ТОЛЬКО при двух и более подписках. У владельца ОДНОЙ подписки, то есть
      // у большинства, `ping_unfinished.json` не чистился никогда: рос без
      // предела, и вернувшийся с прежним ключом сервер помечал подписку
      // неполной по прогону, которого в этой её жизни не было.
      expect(probe.knownServerKeys, isNull,
          reason: 'до сборки дерева поставщика ещё нет — база для сравнения');

      await tester.pumpWidget(buildTree());

      expect(probe.knownServerKeys, isNotNull,
          reason: 'ProxyProvider2<AppState, ProbeController, '
              'UnfinishedPruneLink> обязан построиться с lazy:false — иначе '
              'update() не позовётся никогда, и пометки не почистит ничто');
      // И обратная сторона связки: состояние обязано УМЕТЬ сообщить о смене
      // состава, иначе чистка случится ровно один раз за запуск.
      expect(state.onServersChanged, isNotNull,
          reason: 'без этого хука смена состава серверов проходит незамеченной');
    });

    testWidgets(
        'обе связки срабатывают ОДНОВРЕМЕННО на реальном дереве main.dart '
        '(shadeLayoutLinkProvider + apiSettingsLinkProvider вместе)',
        (tester) async {
      await tester.pumpWidget(buildTree());
      await tester.pump();

      expect(engine.capturedShadeHandler, isNotNull);
      expect(state.applyApiSettingsCalls, greaterThan(0));
    });

    testWidgets(
        'appUpdateProvider: контроллер создан после одной сборки дерева, '
        'хотя тип AppUpdateController никто не читает', (tester) async {
      expect(updateCreateCalls, 0,
          reason: 'до сборки дерева контроллера ещё нет — база для сравнения');

      await tester.pumpWidget(buildTree());
      await tester.pump();

      expect(updateCreateCalls, 1,
          reason: 'ChangeNotifierProvider<AppUpdateController> обязан быть '
              'с lazy:false — иначе контроллер появится только при первом '
              'чтении его типа, и «проверять при запуске» станет «проверять, '
              'когда откроют экран настроек»');
      expect(settings.loaded, isFalse);
      expect(updateController.started, isFalse,
          reason: 'запуск привязан к загрузке настроек, а не к create: '
              'в момент сборки дерева настройки ещё умолчания');
      expect(checkerCalls, 0);
    });

    testWidgets(
        '⚠️ appUpdateProvider: правка настроек ДО загрузки startup НЕ '
        'запускает — только SettingsController.whenLoaded', (tester) async {
      await tester.pumpWidget(buildTree());

      // Прежняя связка (волна 2) стартовала по ПЕРВОМУ уведомлению — а его
      // шлёт и правка, случившаяся раньше init(). Тогда проверка шла по
      // умолчаниям, хотя человек мог автопроверку выключить.
      await tester.runAsync(() => settings.update((s) => s));
      await tester.pump();
      expect(updateController.started, isFalse,
          reason: 'уведомление без загрузки — не повод стартовать');
      expect(checkerCalls, 0);

      await tester.runAsync(settings.init);
      await pumpUntil(tester, () => checked.isCompleted);

      expect(settings.loaded, isTrue);
      expect(updateController.started, isTrue);
      expect(checkerCalls, 1, reason: 'проверка при запуске — ровно одна');
      expect(installer.reconcileCalls, hasLength(1),
          reason: 'итог прошлой установки разбирается при старте');

      // Повторные уведомления настроек ничего не запускают заново.
      await tester.runAsync(() => settings.update((s) => s));
      expect(checkerCalls, 1);
    });

    testWidgets(
        'appUpdateProvider: настройки загружены РАНЬШЕ сборки дерева — '
        'startup всё равно случается (признак, а не событие)', (tester) async {
      await tester.runAsync(settings.init);
      expect(settings.loaded, isTrue);

      await tester.pumpWidget(buildTree());
      await pumpUntil(tester, () => checked.isCompleted);

      expect(updateController.started, isTrue,
          reason: 'слушатель «первого уведомления» здесь не сработал бы '
              'никогда: уведомление ушло до того, как его повесили');
      expect(checkerCalls, 1);
    });

    test('main.dart кладёт appUpdateProvider в тот же список провайдеров',
        () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src, contains('appUpdateProvider('),
          reason: 'страж выше проверяет функцию из provider_wiring.dart; '
              'без этой строки в main.dart она в приложение не попадает');
    });
  });
}
