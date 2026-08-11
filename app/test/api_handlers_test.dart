import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/api_secrets.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/api_handlers.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';

/// Что API НЕ отдаёт наружу.
///
/// ⚠️ ЭТО НЕ ПЕРЕСТРАХОВКА. Креды локального прокси лежат в глобальных
/// статиках процесса, а последний сегмент URL подписки у Remnawave — это
/// секрет. «Отдать состояние» без явного чёрного списка означало бы отдать
/// ключ от туннеля и от подписки одним GET-запросом.
///
/// ⚠️ РАУНД РЕВЬЮ 1 переписал ⅔ этого файла. Две находки:
///  1. Барьер (`assertNoSecrets`) раньше вызывался ТОЛЬКО из теста — реальный
///     `LocalApiServer` ничего не проверял. Барьер и его тест на границе
///     транспорта теперь в `core/net/api_secrets.dart` +
///     `test/api_server_auth_test.dart` — этот файл проверяет ВТОРОЙ,
///     независимый рубеж: что обработчики САМИ не кладут секрет в поля ответа.
///  2. Тест «ни один эндпоинт не отдаёт секретов» гонял `_FakeHandlers` —
///     хардкоженную структуру, а не настоящий `AppStateApiHandlers`. Теперь
///     ниже — реальный `AppState` с фейковым (но управляемым) движком, как в
///     `test/diag_multi_sub_test.dart`, и вызываются НАСТОЯЩИЕ методы.
class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = const VpnStatus.disconnected();

  String? lastConnectedKey;
  int connectCalls = 0;
  int balancerCalls = 0;
  int disconnectCalls = 0;

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
  VpnStatus get status => _status;

  void _emit(VpnStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    connectCalls++;
    lastConnectedKey = server.key;
    _emit(const VpnStatus(VpnConnectionState.connected));
  }

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    balancerCalls++;
    lastConnectedKey = null;
    _emit(const VpnStatus(VpnConnectionState.connected));
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    lastConnectedKey = null;
    _emit(const VpnStatus.disconnected());
  }

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}

/// Окружение теста: изолированный корень данных (`AppPaths.overrideRoot` —
/// тот же приём, что в `test/app_paths_test.dart`) + настоящий `AppState` +
/// настоящий `AppStateApiHandlers`. Ни сети, ни VPN: серверы добавляются
/// одиночными share-ссылками (`AppState.importSource` их не тянет из сети —
/// см. её же комментарий про «Одиночная share-ссылка — без сети»), а движок —
/// управляемый фейк выше.
class _Env {
  _Env._(this.dir, this.state, this.engine, this.probe, this.settings,
      this.handlers);

  final Directory dir;
  final AppState state;
  final _FakeEngine engine;
  final ProbeController probe;
  final SettingsController settings;
  final AppStateApiHandlers handlers;

  static Future<_Env> create() async {
    final dir = Directory.systemTemp.createTempSync('sg_api_handlers_');
    AppPaths.overrideRoot(dir);
    final engine = _FakeEngine();
    final state = AppState(engine: engine);
    await state.init();
    final probe = ProbeController();
    final settings = SettingsController();
    await settings.init();
    final handlers = AppStateApiHandlers(state, probe, settings);
    return _Env._(dir, state, engine, probe, settings, handlers);
  }

  /// Добавить сервер БЕЗ СЕТИ и вернуть его.
  Future<VpnServer> addServer(String link) async {
    await state.importSource(link);
    return state.servers.firstWhere((s) => s.key == link.trim());
  }

  void dispose() {
    AppPaths.resetForTests();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

const _serverA =
    'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:20001#Германия';
const _serverB =
    'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:20002#США';

void main() {
  group('Чёрный список секретов', () {
    test('чёрный список полей соблюдается', () {
      // Список ведётся ЗДЕСЬ и в apiSecretMarkers — двух копий быть не должно.
      expect(apiSecretMarkers, containsAll(<String>[
        'apiToken',
        'localProxyPassword',
        'localProxyUser',
        'subscriptionUrl',
        'rawJsonOverride',
        'rawPanelConfig',
      ]));
    });

    test('проверка ответа ловит запрещённое поле', () {
      final dirty = jsonEncode({'localProxyPassword': 'hunter2'});
      expect(() => assertNoSecrets(dirty), throwsA(isA<StateError>()));
    });

    test('чистый ответ проходит', () {
      final clean = jsonEncode({'state': 'connected', 'server': 'Германия'});
      expect(() => assertNoSecrets(clean), returnsNormally);
    });
  });

  group('⚠️ Настоящие обработчики, не макет (раунд ревью 1, находка 2)', () {
    test('ни один ЧТЕНИЕ-эндпоинт настоящего AppStateApiHandlers не отдаёт '
        'секретов', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);
      // Реальный секрет в реальных настройках — если бы барьер был фикцией,
      // он ушёл бы прямо в `exits()`/`status()`.
      await env.settings.update((s) => s.copyWith(
          apiEnabled: true,
          apiToken: 'real-token-should-never-leak',
          apiExitServerKeys: [_serverA]));

      // Перебор СПИСКОМ методов интерфейса — вызывает НАСТОЯЩИЙ
      // AppStateApiHandlers, а не переписанную руками структуру.
      final h = env.handlers;
      final bodies = <String>[
        jsonEncode(await h.status()),
        jsonEncode({'servers': await h.servers()}),
        jsonEncode({'exits': await h.exits()}),
        jsonEncode(await h.traffic()),
        jsonEncode(await h.subscription()),
      ];
      for (final b in bodies) {
        expect(() => assertNoSecrets(b), returnsNormally);
      }
    });

    test('servers()/exits() отдают реальный состав из AppState.servers',
        () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      final a = await env.addServer(_serverA);
      await env.settings
          .update((s) => s.copyWith(apiExitServerKeys: [a.key]));

      final servers = await env.handlers.servers();
      final exits = await env.handlers.exits();

      expect(servers, hasLength(1));
      expect(servers.single['key'], a.key);
      expect(servers.single['name'], 'Германия');
      // «Прямо» — всегда последней записью, даже без единого сервера-выхода.
      expect(exits.last['name'], 'Прямо');
      expect(exits.any((e) => e['serverKey'] == a.key), isTrue);
    });
  });

  group('connect() — переключатель не гасит живой канал (находка 3)', () {
    test('подключение при выключенном VPN — обычный коннект', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      final a = await env.addServer(_serverA);

      final r = await env.handlers.connect(serverKey: a.key);
      await pumpEventQueue();

      expect(r.isOk, isTrue);
      expect(env.engine.connectCalls, 1);
      expect(env.engine.disconnectCalls, 0);
      expect(env.engine.lastConnectedKey, a.key);
      expect(env.state.status.isConnected, isTrue);
    });

    test(
        '⚠️ подключение при УЖЕ поднятом канале — меняет сервер, а не '
        'отключает', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      final a = await env.addServer(_serverA);
      final b = await env.addServer(_serverB);

      await env.handlers.connect(serverKey: a.key);
      await pumpEventQueue();
      expect(env.state.status.isConnected, isTrue);
      expect(env.engine.lastConnectedKey, a.key);

      final second = await env.handlers.connect(serverKey: b.key);
      await pumpEventQueue();

      expect(second.isOk, isTrue);
      // Раньше здесь падало: toggleConnection на живом канале ОТКЛЮЧАЛ, и
      // ответ всё равно был {"ok": true} — молчаливое выключение вместо смены.
      expect(env.state.status.isConnected, isTrue,
          reason:
              'канал обязан остаться живым — сервер сменился, а не выключился');
      expect(env.engine.lastConnectedKey, b.key);
      expect(env.engine.disconnectCalls, 1,
          reason: 'старый сеанс реально гасится ПЕРЕД подъёмом нового');
      expect(env.engine.connectCalls, 2);
    });

    test('неизвестный ключ — server_not_found, движок не трогается',
        () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);

      final r =
          await env.handlers.connect(serverKey: 'vless://none@x.test:1#Y');

      expect(r.isOk, isFalse);
      expect(r.code, 'server_not_found');
      expect(env.engine.connectCalls, 0);
    });

    test('неоднозначное имя — ambiguous_name, движок не трогается', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(
          'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:20003#Дубль');
      await env.addServer(
          'vless://22222222-2222-3333-4444-555555555555@127.0.0.1:20004#Дубль');

      final r = await env.handlers.connect(name: 'Дубль');

      expect(r.isOk, isFalse);
      expect(r.code, 'ambiguous_name');
      expect(env.engine.connectCalls, 0);
    });

    test('неизвестное имя — server_not_found', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);

      final r = await env.handlers.connect(name: 'Такого сервера нет');

      expect(r.isOk, isFalse);
      expect(r.code, 'server_not_found');
    });

    test('ни server, ни name, ни auto — server_required', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);

      final r = await env.handlers.connect();

      expect(r.isOk, isFalse);
      expect(r.code, 'server_required');
    });

    test('⚠️ auto:true на уже живом канале — тоже смена, а не отключение',
        () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);

      await env.handlers.connect(auto: true);
      await pumpEventQueue();
      expect(env.engine.balancerCalls, 1);
      expect(env.state.status.isConnected, isTrue);

      final second = await env.handlers.connect(auto: true);
      await pumpEventQueue();

      expect(second.isOk, isTrue);
      expect(env.state.status.isConnected, isTrue,
          reason: 'повторный auto-коннект на живом канале не отключает VPN');
      expect(env.engine.balancerCalls, 2);
      expect(env.engine.disconnectCalls, 1);
    });

    test('auto:true при выключенном VPN — обычный автоконнект, без лишнего '
        'disconnect', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);

      final r = await env.handlers.connect(auto: true);
      await pumpEventQueue();

      expect(r.isOk, isTrue);
      expect(env.engine.balancerCalls, 1);
      expect(env.engine.disconnectCalls, 0);
      expect(env.state.status.isConnected, isTrue);
    });
  });

  group('disconnect()', () {
    test('гасит живой канал', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      final a = await env.addServer(_serverA);
      await env.handlers.connect(serverKey: a.key);
      await pumpEventQueue();
      expect(env.state.status.isConnected, isTrue);

      final r = await env.handlers.disconnect();
      await pumpEventQueue();

      expect(r.isOk, isTrue);
      expect(env.state.status.isConnected, isFalse);
      expect(env.engine.disconnectCalls, 1);
    });

    test('на уже выключенном — не падает, отвечает ok', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);

      final r = await env.handlers.disconnect();

      expect(r.isOk, isTrue);
    });
  });

  group('ping()', () {
    test('не падает и не виснет на закрытом порту localhost', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA); // 127.0.0.1:20001 — никто не слушает

      final r = await env.handlers.ping();

      expect(r.isOk, isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('AppState.applyApiSettings — гонка поколений (раунд ревью 1, '
      'находка 5)', () {
    // Не штатный порт (10870) — не спорит с живым приложением на машине.
    const testPort = 18781;

    Future<int> statusCode(String token) async {
      final c = HttpClient();
      final r = await c.openUrl(
          'GET', Uri.parse('http://127.0.0.1:$testPort/v1/status'));
      r.headers.set('Authorization', 'Bearer $token');
      final resp = await r.close();
      await resp.drain<void>();
      return resp.statusCode;
    }

    test(
        '⚠️ две ПАРАЛЛЕЛЬНЫЕ правки не теряют ссылку на сервер — порт '
        'реально освобождается после выключения', () async {
      // applyApiSettings — гейт «только Windows» (см. её же комментарий);
      // на других платформах вызов всегда no-op, и порт бы не поднялся вовсе.
      if (!Platform.isWindows) return;
      final env = await _Env.create();
      addTearDown(env.dispose);

      const s1 = AppSettings(apiEnabled: true, apiToken: 'token-a');
      const s2 = AppSettings(apiEnabled: true, apiToken: 'token-b');

      // ⚠️ НЕ awaitим по одному — параллельный запуск воспроизводит саму
      // гонку: до фикса `await _api?.stop()` внутри одного вызова мог
      // затереть `_api`, поднятый ДРУГИМ, ещё не закончившимся вызовом, и
      // владельца свежего `HttpServer` терялась ссылка — сокет оставался
      // слушать порт, а `stop()` его больше никогда не находил.
      await Future.wait([
        env.state
            .applyApiSettings(s1, env.probe, env.settings, port: testPort),
        env.state
            .applyApiSettings(s2, env.probe, env.settings, port: testPort),
      ]);

      // Победил ПОСЛЕДНИЙ по порядку вызов — «последняя правка выигрывает»,
      // такое же поведение, будто вызовы шли строго по очереди.
      expect(await statusCode('token-b'), 200);
      expect(await statusCode('token-a'), 401);

      // ⚠️ ГЛАВНАЯ ПРОВЕРКА: выключаем через ТОТ ЖЕ канал управления и
      // требуем порт РЕАЛЬНО свободным — если бы сервер от s1 (или его
      // сирота) продолжал слушать порт независимо от `_api`, `stop()`
      // окончательного сервера не нашёл бы его, и следующий bind ниже упал бы.
      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: false), env.probe, env.settings,
          port: testPort);
      final probe =
          await HttpServer.bind(InternetAddress.loopbackIPv4, testPort);
      await probe.close(force: true);
    });

    test('последовательные вызовы — тоже без утечки порта', () async {
      if (!Platform.isWindows) return;
      final env = await _Env.create();
      addTearDown(env.dispose);

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: true, apiToken: 'first'),
          env.probe, env.settings,
          port: testPort);
      expect(await statusCode('first'), 200);

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: true, apiToken: 'second'),
          env.probe, env.settings,
          port: testPort);
      expect(await statusCode('second'), 200);
      expect(await statusCode('first'), 401);

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: false), env.probe, env.settings,
          port: testPort);
      final probe =
          await HttpServer.bind(InternetAddress.loopbackIPv4, testPort);
      await probe.close(force: true);
    });
  });
}
