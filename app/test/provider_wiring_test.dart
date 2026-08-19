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
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';
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

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sg_provider_wiring_');
    AppPaths.overrideRoot(dir);
    engine = _SpyEngine();
    state = _SpyAppState(engine: engine);
    await state.init();
    settings = SettingsController();
    await settings.init();
    probe = ProbeController();
  });

  tearDown(() async {
    AppPaths.resetForTests();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

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
  });
}
