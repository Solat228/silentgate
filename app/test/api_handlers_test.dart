import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/net/api_secrets.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/api_handlers.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/split_tunnel_screen.dart' show splitRulesEditableIn;

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

/// Сервер на протоколе, которого sing-box в выходах не умеет (см.
/// `SingboxOutboundFactory.supports`): vmess разбирается парсером и живёт в
/// списке, но отдельным выходом не поднимается.
const _serverVmess = 'vmess://eyJ2IjogIjIiLCAicHMiOiAi0K/Qv9C+0L3QuNGPIiwgImFk'
    'ZCI6ICIxMjcuMC4wLjEiLCAicG9ydCI6ICIyMDAwMyIsICJpZCI6ICIxMTExMTExMS0yMjIy'
    'LTMzMzMtNDQ0NC01NTU1NTU1NTU1NTUiLCAiYWlkIjogIjAiLCAibmV0IjogInRjcCIsICJ0'
    'eXBlIjogIm5vbmUiLCAidGxzIjogIiJ9';

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
      // ⚠️ Гейт `ApiPorts.exitsActive`: без включённого API и токена ни один
      // инбаунд (ни серверный, ни «Прямо») физически не создаётся, и exits()
      // теперь честно отдаёт пустой список — см. группу «exits() и гейт …»
      // ниже. Здесь гейт открыт явно, чтобы проверить состав.
      await env.settings.update((s) => s.copyWith(
          apiEnabled: true,
          apiToken: 'secret',
          apiExitServerKeys: [a.key]));

      final servers = await env.handlers.servers();
      final exits = await env.handlers.exits();

      expect(servers, hasLength(1));
      expect(servers.single['key'], a.key);
      expect(servers.single['name'], 'Германия');
      // «Прямо» — всегда последней записью, даже без единого сервера-выхода.
      expect(exits.last['name'], 'Прямо');
      expect(exits.last['port'], ApiPorts.direct);
      expect(exits.any((e) => e['serverKey'] == a.key), isTrue);
    });

    group('exits() и гейт «канал реально поднят»', () {
      test('API выключен — exits() пуст, включая «Прямо»', () async {
        final env = await _Env.create();
        addTearDown(env.dispose);
        final a = await env.addServer(_serverA);
        // apiEnabled по умолчанию false, apiToken пуст — ни один инбаунд не
        // создаётся, и список не обязан рекламировать порт, которого нет.
        await env.settings
            .update((s) => s.copyWith(apiExitServerKeys: [a.key]));

        expect(await env.handlers.exits(), isEmpty);
      });

      test('API включён, но токен пуст — тоже пусто', () async {
        final env = await _Env.create();
        addTearDown(env.dispose);
        final a = await env.addServer(_serverA);
        await env.settings.update((s) =>
            s.copyWith(apiEnabled: true, apiExitServerKeys: [a.key]));

        expect(await env.handlers.exits(), isEmpty);
      });

      test('⚠️ сервер за пределами топ-40 не получает запись (port: null не '
          'отдаётся)', () async {
        final env = await _Env.create();
        addTearDown(env.dispose);
        final a = await env.addServer(_serverA);
        // 40 «чужих» ключей, сортирующихся ПЕРЕД ключом сервера `a` (UUID
        // начинается с "00000000" < "11111111" у _serverA) — реальных
        // серверов под них поднимать не нужно: `exits()` фильтрует состав по
        // `AppState.servers`, а `ApiPorts.forServer` считает индекс по ПОЛНОМУ
        // списку ключей настройки. Ключ `a` окажется 41-м — вне диапазона.
        final padding = [
          for (var i = 0; i < ApiPorts.maxServers; i++)
            'vless://00000000-0000-0000-0000-'
                '${i.toString().padLeft(12, '0')}@x.test:1#pad$i',
        ];
        await env.settings.update((s) => s.copyWith(
            apiEnabled: true,
            apiToken: 'secret',
            apiExitServerKeys: [...padding, a.key]));

        final exits = await env.handlers.exits();

        expect(exits.any((e) => e['serverKey'] == a.key), isFalse,
            reason: 'ключ вне диапазона — порта для него нет физически');
        expect(exits.any((e) => e['port'] == null), isFalse,
            reason: 'запись без порта собрала бы у клиента битый URL '
                'http://sg:токен@127.0.0.1:None');
        // «Прямо» от порядка серверов не зависит — она обязана остаться.
        expect(exits.last['name'], 'Прямо');
      });

      test('⚠️ сервер, из которого выход НЕ собирается, порта не получает',
          () async {
        // Находка финального ревью (6). `ExitOutbounds.build` пропускает
        // протоколы, которых не умеет `SingboxOutboundFactory` (и панельные
        // профили «Авто»): инбаунд для такого сервера не создаётся —
        // построитель проверяет живые теги. Публиковать его порт значило бы
        // назвать скрипту адрес, на который ядро заведомо не сядет.
        final env = await _Env.create();
        addTearDown(env.dispose);
        final ok = await env.addServer(_serverA);
        final bad = await env.addServer(_serverVmess);
        expect(bad.protocol, 'vmess', reason: 'vmess — то, чего sing-box '
            'в выходах не умеет; если он вдруг научится, тест обязан упасть');

        await env.settings.update((s) => s.copyWith(
            apiEnabled: true,
            apiToken: 'secret',
            apiExitServerKeys: [ok.key, bad.key]));

        final exits = await env.handlers.exits();
        expect(exits.any((e) => e['serverKey'] == ok.key), isTrue);
        expect(exits.any((e) => e['serverKey'] == bad.key), isFalse);
        // ⚠️ Номера портов от исключения НЕ съезжают: индекс считается по
        // полному списку ключей настройки, а не по отфильтрованному ответу.
        // Иначе снятие одной галочки увело бы чужой запрос в другую страну.
        expect(
            exits.firstWhere((e) => e['serverKey'] == ok.key)['port'],
            ApiPorts.forServer([ok.key, bad.key], ok.key));
        expect(exits.last['name'], 'Прямо');
      });
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

    test('⚠️ возвращается СРАЗУ, не дожидаясь прогона (находка 10)', () async {
      // Раньше здесь стоял `await probe.pingAll(...)`: ответ уходил только
      // после обеих фаз по всем серверам подписки. На сотне серверов это
      // минуты, а обёртка `tools/silentgate.py` ходит с `timeout=30` —
      // гарантированное падение по таймауту на вызове, который документирован
      // как мгновенный.
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);
      await env.addServer(_serverB);

      final sw = Stopwatch()..start();
      final r = await env.handlers.ping();
      sw.stop();

      expect(r.isOk, isTrue);
      // Порог с огромным запасом: одна только TCP-фаза на мёртвый адрес живёт
      // секундами. Смысл проверки — «не ждём прогона», а не микробенчмарк.
      expect(sw.elapsedMilliseconds, lessThan(1500),
          reason: 'ответ обязан уходить до завершения прогона');
      // И прогон при этом РЕАЛЬНО запущен — иначе «мгновенный ответ» получался
      // бы и от пустышки, ничего не делающей.
      expect(env.probe.running, isTrue);
      // Состояние отдаёт признак: без него скрипту неоткуда узнать, когда
      // забирать результаты из `GET /v1/servers`.
      expect((await env.handlers.status())['pinging'], isTrue);

      // Не оставляем прогон висеть в фоне после теста.
      env.probe.cancel();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('повторный вызов на идущем прогоне безопасен', () async {
      final env = await _Env.create();
      addTearDown(env.dispose);
      await env.addServer(_serverA);

      expect((await env.handlers.ping()).isOk, isTrue);
      // `ProbeController._pingBatch` выходит сразу при `_running` — второй
      // прогон не запускается и первому не мешает.
      expect((await env.handlers.ping()).isOk, isTrue);
      env.probe.cancel();
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

  /// ⚠️ НАХОДКА ФИНАЛЬНОГО РЕВЬЮ (7). Занятый управляющий порт был виден
  /// ТОЛЬКО в журнале: тумблер оставался включённым и выглядел рабочим, токен
  /// показан, кнопка «Скопировать пример» на месте — а скрипт получал отказ
  /// соединения и не мог понять почему. Спека требовала обратного: тумблер
  /// показывает ошибку с именем процесса-держателя.
  group('Занятый управляющий порт виден состоянию, а не только журналу', () {
    const busyPort = 18782;

    test('порт занят — apiPortConflict заполнен номером порта', () async {
      if (!Platform.isWindows) return;
      final env = await _Env.create();
      addTearDown(env.dispose);

      // Держим порт «чужой» программой (в тесте — просто другой сокет).
      final squatter =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, busyPort);
      addTearDown(() => squatter.close());

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: true, apiToken: 'tok'),
          env.probe, env.settings,
          port: busyPort);

      final conflict = env.state.apiPortConflict;
      expect(conflict, isNotNull,
          reason: 'отказ подъёма обязан быть виден интерфейсу');
      expect(conflict!.port, busyPort);
      // `holder` — best-effort (netstat + tasklist): на занятом порту этого
      // же процесса имя обычно определяется, но требовать его нельзя —
      // интерфейс умеет обе формулировки (`apiPortBusy` / `apiPortBusyUnknown`).
    });

    test('порт свободен — конфликта нет', () async {
      if (!Platform.isWindows) return;
      final env = await _Env.create();
      addTearDown(env.dispose);

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: true, apiToken: 'tok'),
          env.probe, env.settings,
          port: busyPort);
      expect(env.state.apiPortConflict, isNull);

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: false), env.probe, env.settings,
          port: busyPort);
    });

    test('⚠️ пустой токен — это НЕ ошибка порта', () async {
      if (!Platform.isWindows) return;
      final env = await _Env.create();
      addTearDown(env.dispose);
      // Держим порт: даже так «канал выключен» обязан остаться «выключен», а
      // не превратиться в красную плашку про занятый порт. Про пустой токен в
      // интерфейсе своя строка (`apiTokenUnset`), и пугать человека ошибкой
      // там, где он просто ещё не нажал «Обновить токен», нельзя.
      final squatter =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, busyPort);
      addTearDown(() => squatter.close());

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: true), env.probe, env.settings,
          port: busyPort);
      expect(env.state.apiPortConflict, isNull);
    });

    test('выключение API снимает прежнюю ошибку', () async {
      if (!Platform.isWindows) return;
      final env = await _Env.create();
      addTearDown(env.dispose);
      final squatter =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, busyPort);
      addTearDown(() => squatter.close());

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: true, apiToken: 'tok'),
          env.probe, env.settings,
          port: busyPort);
      expect(env.state.apiPortConflict, isNotNull);

      await env.state.applyApiSettings(
          const AppSettings(apiEnabled: false), env.probe, env.settings,
          port: busyPort);
      expect(env.state.apiPortConflict, isNull,
          reason: 'у выключенного тумблера ошибка — мусор на экране');
    });
  });

  /// ⚠️ НАХОДКА ФИНАЛЬНОГО РЕВЬЮ (8). Тумблер «Применять правила раздельного
  /// туннелирования» виден ТОЛЬКО в «Только прокси», а список «Блок», которым
  /// он оперирует, редактируется на экране раздельного туннелирования — где в
  /// этом режиме всё было серым под `IgnorePointer`.
  group('Редактирование правил и способ захвата', () {
    test('«Только прокси» — экран правил редактируем', () {
      expect(splitRulesEditableIn(CaptureMode.proxyOnly), isTrue,
          reason: 'иначе тумблер «Применять правила» ведёт в заблокированный '
              'экран и завести правило «Блок» негде');
    });

    test('TUN — редактируем, системный прокси — нет', () {
      expect(splitRulesEditableIn(CaptureMode.tun), isTrue);
      // Там правила не действуют вовсе: приложения сами решают, ходить ли
      // через прокси, и принудить их нечем.
      expect(splitRulesEditableIn(CaptureMode.systemProxy), isFalse);
    });
  });
}
