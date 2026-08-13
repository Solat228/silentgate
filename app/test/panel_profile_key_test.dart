import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/server_override.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';
import 'package:silentgate/core/util/key_migration.dart';
import 'package:silentgate/data/panel_outbounds_store.dart';
import 'package:silentgate/data/results_store.dart';
import 'package:silentgate/data/server_overrides_store.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// Движок-пустышка: ключи серверов к VPN отношения не имеют, а включать его
/// в тестах запрещено правилами проекта.
class _FakeEngine extends VpnEngine {
  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

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
  Future<void> dispose() async {}
}

/// Ключ профиля «Авто …» от панели.
///
/// ⚠️ ЧЕМ БОЛЕЛО. Ключ состоял из ОДНОГО имени профиля (`panel://Авто (YouTube)`),
/// а панель называет профили одинаково во всех подписках. У человека с
/// четырьмя подписками профиль второй и профиль первой оказывались одним
/// сервером: результат пинга, ручная правка и сохранённый конфиг писались друг
/// поверх друга, пинг профиля B мог уйти конфигом A, и зелёная плашка висела на
/// профиле, который никто не проверял.
void main() {
  const uuidA = '11111111-1111-1111-1111-111111111111';
  const uuidB = '22222222-2222-2222-2222-222222222222';
  const remark = '🎬 Авто (YouTube)';

  /// Профиль-автовыбор: балансировщик + burstObservatory + несколько узлов
  /// одной подписки (учётные данные у Remnawave общие на все узлы).
  Map<String, dynamic> profileCfg({
    String uuid = uuidA,
    String name = remark,
    List<String> hosts = const ['a.example.com', 'b.example.com'],
  }) =>
      {
        'outbounds': [
          for (var i = 0; i < hosts.length; i++)
            {
              'tag': i == 0 ? 'proxy' : 'proxy-$i',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': hosts[i],
                    'port': 443,
                    'users': [
                      {'id': uuid, 'encryption': 'none'}
                    ],
                  }
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'reality',
                'realitySettings': {
                  'serverName': 'st.example.com',
                  'publicKey': 'KEY',
                  'shortId': 'ab',
                },
              },
            },
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
        'routing': {
          'rules': [
            {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'}
          ],
          'balancers': [
            {
              'tag': 'auto',
              'selector': ['proxy'],
              'strategy': {'type': 'leastPing'},
            }
          ],
        },
        'burstObservatory': {
          'subjectSelector': ['proxy']
        },
        'remarks': name,
      };

  String body(Map<String, dynamic> cfg) => jsonEncode([cfg]);

  setUp(() {
    // Псевдонимы — статика на весь процесс: без сброса тесты подсказывали бы
    // ответы друг другу.
    KeyMigration.resetPanelKeys();
  });

  group('Ключ различает подписки', () {
    test('⚠️ профили с ОДИНАКОВЫМ именем из разных подписок не делят ключ', () {
      final a = XrayJsonSubscription.parse(body(profileCfg(uuid: uuidA))).single;
      final b = XrayJsonSubscription.parse(body(profileCfg(uuid: uuidB))).single;

      expect(a.isPanelProfile, isTrue, reason: 'профиль не распознан');
      expect(b.isPanelProfile, isTrue);
      expect(a.remark, b.remark, reason: 'имена панель даёт одинаковые');
      expect(a.key, isNot(b.key),
          reason: 'до 1.4.2 ключ был один на обе подписки — данные затирались');
    });

    test('состав узлов сменился, а подписка та же — ключ прежний', () {
      // Панель тасует состав профиля при каждом обновлении подписки. Ключ,
      // зависящий от состава, «уезжал» бы вместе с ним — ровно та беда, из-за
      // которой его когда-то и свели к одному имени.
      final before = XrayJsonSubscription.parse(body(profileCfg())).single;
      final after = XrayJsonSubscription.parse(body(profileCfg(
        hosts: const ['c.example.com', 'a.example.com', 'd.example.com'],
      ))).single;
      expect(after.key, before.key);
    });

    test('в ключе нет самих учётных данных', () {
      final s = XrayJsonSubscription.parse(body(profileCfg())).single;
      // Ключ уезжает в правила раздельного туннелирования, ответы локального
      // API и отчёты поддержки — паролю подписки там не место.
      expect(s.key, isNot(contains(uuidA)));
      expect(s.key, startsWith('panel://'));
    });

    test('подписки различаются и по паролю (trojan), не только по uuid', () {
      Map<String, dynamic> trojan(String password) => {
            'outbounds': [
              for (final host in ['a.example.com', 'b.example.com'])
                {
                  'tag': 'proxy',
                  'protocol': 'trojan',
                  'settings': {
                    'servers': [
                      {'address': host, 'port': 443, 'password': password}
                    ],
                  },
                  'streamSettings': {'network': 'tcp', 'security': 'tls'},
                },
              {'tag': 'direct', 'protocol': 'freedom'},
            ],
            'remarks': remark,
          };
      final a = XrayJsonSubscription.parse(body(trojan('secret-a'))).single;
      final b = XrayJsonSubscription.parse(body(trojan('secret-b'))).single;
      expect(a.isPanelProfile, isTrue);
      expect(a.key, isNot(b.key));
    });

    test('обычный сервер ключ не меняет — это по-прежнему share-ссылка', () {
      final single = XrayJsonSubscription.parse(body({
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'x.example.com',
                  'port': 443,
                  'users': [
                    {'id': uuidA, 'encryption': 'none'}
                  ],
                }
              ],
            },
            'streamSettings': {'network': 'tcp', 'security': 'none'},
          },
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
        'remarks': '🇵🇱 Польша 1.2',
      })).single;
      expect(single.isPanelProfile, isFalse);
      expect(single.key, startsWith('vless://'));
    });
  });

  // ── Отпечаток подписки: смешанный профиль ───────────────────────────────────

  group('Отпечаток не «дышит» вместе с составом профиля', () {
    /// Профиль автовыбора собирает узлы РАЗНЫХ протоколов, а учётное значение у
    /// них лежит по-разному: у vless это uuid, у trojan — пароль. То есть в
    /// одном профиле живут два разных секрета, и их количества панель меняет от
    /// обновления к обновлению.
    ///
    /// ⚠️ ИМЕННО TROJAN, А НЕ HYSTERIA2, ХОТЯ РАЗБОР ПОНИМАЕТ ОБА. Профиль
    /// панели всегда поднимается Xray (`VpnServer.core`), а Xray hysteria2 не
    /// умеет — hy2-узел внутри профиля приложение просто не запустило бы, и
    /// проверять отпечаток на конфигурации, которой в продукте быть не может,
    /// значило бы охранять несуществующее. Vless и trojan Xray умеет оба.
    Map<String, dynamic> mixedCfg({
      required int vless,
      required int trojan,
      String uuid = uuidA,
      String trojanPass = 'zz-trojan-secret-a',
    }) =>
        {
          'outbounds': [
            for (var i = 0; i < vless; i++)
              {
                'tag': i == 0 ? 'proxy' : 'proxy-$i',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {
                      'address': 'v$i.example.com',
                      'port': 443,
                      'users': [
                        {'id': uuid, 'encryption': 'none'}
                      ],
                    }
                  ],
                },
                'streamSettings': {'network': 'tcp', 'security': 'reality'},
              },
            for (var i = 0; i < trojan; i++)
              {
                'tag': 'trojan-$i',
                'protocol': 'trojan',
                'settings': {
                  'servers': [
                    {
                      'address': 't$i.example.com',
                      'port': 443,
                      'password': trojanPass,
                    }
                  ],
                },
                'streamSettings': {
                  'network': 'tcp',
                  'security': 'tls',
                  'tlsSettings': {'serverName': 'st.example.com'},
                },
              },
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
          'routing': {
            'balancers': [
              {
                'tag': 'auto',
                'selector': ['proxy'],
              }
            ],
          },
          'remarks': remark,
        };

    test('⚠️ ГЛАВНОЕ: пропорции vless/trojan поменялись — ключ ТОТ ЖЕ', () {
      // Так выглядел дефект: отпечаток брался как САМОЕ ЧАСТОЕ учётное значение
      // профиля. Панель прислала trojan-узлов больше, чем vless, — победило
      // другое значение, ключ профиля сменился целиком, и пин, правка, конфиг и
      // пинг осиротели ровно так же, как до 1.4.2. Ключ, который «дышит», — та
      // самая болезнь, которую этот ключ лечит.
      final before =
          XrayJsonSubscription.parse(body(mixedCfg(vless: 3, trojan: 1))).single;
      final after =
          XrayJsonSubscription.parse(body(mixedCfg(vless: 1, trojan: 3))).single;
      expect(before.isPanelProfile, isTrue, reason: 'профиль не распознан');
      expect(after.key, before.key);
    });

    test('порядок outbound-ов на отпечаток не влияет', () {
      final a = XrayJsonSubscription.panelScope(mixedCfg(vless: 2, trojan: 2));
      final b = XrayJsonSubscription.panelScope({
        ...mixedCfg(vless: 2, trojan: 2),
        'outbounds': (mixedCfg(vless: 2, trojan: 2)['outbounds'] as List)
            .reversed
            .toList(),
      });
      expect(a, b);
      expect(a, isNotEmpty);
    });

    test('чужая подписка со смешанным профилем всё равно отличается', () {
      // Устойчивость не должна была превратиться в «один ключ на всех».
      final a =
          XrayJsonSubscription.parse(body(mixedCfg(vless: 2, trojan: 2))).single;
      final b = XrayJsonSubscription.parse(body(mixedCfg(
        vless: 2,
        trojan: 2,
        uuid: uuidB,
        trojanPass: 'zz-trojan-secret-b',
      ))).single;
      expect(a.key, isNot(b.key));
    });
  });

  group('Восстановление с диска', () {
    test('⚠️ конфиг с диска даёт ТОТ ЖЕ ключ, что и разбор подписки', () {
      // Разойдись эти два пути — после перезапуска профиль искал бы свои пинги
      // и правки по другому ключу, то есть не находил бы их никогда.
      final fresh = XrayJsonSubscription.parse(body(profileCfg())).single;
      final restored =
          XrayJsonSubscription.fromPanelConfig(fresh.rawPanelConfig!)!;
      expect(restored.key, fresh.key);
    });
  });

  group('Миграция: старый ключ не осиротел', () {
    test('запись по ключу из одного имени доезжает на новый ключ', () {
      final s = XrayJsonSubscription.parse(body(profileCfg())).single;
      final legacy = XrayJsonSubscription.panelKey(remark);
      expect(KeyMigration.panelAliasOf(legacy), s.key,
          reason: 'разбор профиля обязан объявить старое написание псевдонимом');

      final stored = {
        legacy: {'outcome': 'ok', 'latencyMs': 42}
      };
      // Так вело себя хранилище до правки: по новому ключу пусто.
      expect(stored[s.key], isNull);

      final out = KeyMigration.remapMap<dynamic>(stored);
      expect(out[s.key], stored[legacy]);
      expect(out[legacy], isNull,
          reason: 'ПЕРЕНОС, А НЕ КОПИЯ: пока старая запись оставалась рядом, '
              'она копировалась в новую при каждой загрузке и снятую правку '
              'было нечем снять');
    });

    test('настоящая запись по новому ключу сильнее старой общей', () {
      final s = XrayJsonSubscription.parse(body(profileCfg())).single;
      final legacy = XrayJsonSubscription.panelKey(remark);
      final out = KeyMigration.remapMap<dynamic>({
        legacy: {'latencyMs': 42},
        s.key: {'latencyMs': 7},
      });
      // Старая запись общая на все подписки, чью проверку она показывает —
      // неизвестно; перебивать ею измерение конкретной подписки нельзя.
      expect((out[s.key] as Map)['latencyMs'], 7);
      expect(out[legacy], isNull, reason: 'и здесь старая запись уходит');
    });

    test('пин по старому ключу переезжает вместе с конфигом', () {
      // Пины и конфиги профилей обязаны переезжать ОДНОВРЕМЕННО: конфиг
      // переносит `remapMap`, пин — `remapList`. Отстань список — остался бы
      // пин, указывающий в пустоту, и профиль исчез бы из списка серверов.
      final s = XrayJsonSubscription.parse(body(profileCfg())).single;
      final legacy = XrayJsonSubscription.panelKey(remark);
      expect(KeyMigration.remapList([legacy]), [s.key]);
    });

    test('снимок panel_outbounds.json объявляет псевдонимы без разбора подписки',
        () {
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      final found = XrayJsonSubscription.registerLegacyPanelKeys({
        legacy: {'config': jsonEncode(cfg)},
        'vless://someone@a.example.com:443': {'outbound': '{}'},
      });
      expect(found, 1);
      expect(KeyMigration.panelAliasOf(legacy),
          XrayJsonSubscription.panelKeyOf(cfg));
    });

    test('повторный прогон миграции ничего не меняет', () {
      XrayJsonSubscription.parse(body(profileCfg()));
      final once = KeyMigration.remapMap<dynamic>({
        XrayJsonSubscription.panelKey(remark): {'latencyMs': 42}
      });
      expect(KeyMigration.remapMap<dynamic>(once), once,
          reason: 'миграция зовётся при каждой загрузке');
    });
  });

  // ── Хранилища на диске ──────────────────────────────────────────────────────

  group('Хранилища: перенос при чтении', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_panel_key_');
      // ⚠️ ОБЯЗАТЕЛЬНО: без подмены корня тест полез бы в боевой
      // %APPDATA%\SilentGate владельца.
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    void seed(String file, Object data) {
      File('${tmp.path}${Platform.pathSeparator}$file')
          .writeAsStringSync(jsonEncode(data));
    }

    test('⚠️ чтение конфигов панели САМО заводит псевдоним', () async {
      // Раньше псевдонимы наполнялись из `ResultsStore`, читавшего ЧУЖОЙ файл, —
      // и только если в результатах пинга попадался старый ключ и чтение
      // успевало раньше `AppState.init()`. У того, кто профиль не пинговал,
      // конфиг не переезжал вовсе.
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      seed('panel_outbounds.json', {
        legacy: {'config': jsonEncode(cfg)}
      });

      final loaded = await PanelOutboundsStore().load();
      final key = XrayJsonSubscription.panelKeyOf(cfg);
      expect(loaded.keys, [key]);
      expect(KeyMigration.panelAliasOf(legacy), key);
    });

    test('сохранённый пинг профиля находится по новому ключу', () async {
      // ⚠️ ПОРЯДОК ЗДЕСЬ ЗАДАН ЯВНО, а не подразумевается: псевдоним заводит
      // чтение конфигов панели, и `AppState.init()` делает его ПЕРВЫМ. Прочитай
      // результаты пинга раньше (`ProbeController` живёт отдельно) — запись
      // осталась бы по старому ключу до следующей загрузки; данные при этом
      // целы, теряется только показ.
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      seed('panel_outbounds.json', {
        legacy: {'config': jsonEncode(cfg)}
      });
      seed('ping_results.json', {
        legacy: {
          'outcome': 'ok',
          'latencyMs': 42,
          'measuredAt': '2026-08-01T10:00:00.000Z',
        }
      });

      await PanelOutboundsStore().load();
      final loaded = await ResultsStore.ping.load() as Map;
      final key = XrayJsonSubscription.panelKeyOf(cfg);
      expect(loaded[key], isNotNull,
          reason: 'иначе профиль после обновления показал бы «не проверен»');
      expect((loaded[key] as Map)['latencyMs'], 42);
      expect(loaded[legacy], isNull, reason: 'перенос, а не копия');
    });

    test('⚠️ СНЯТАЯ ПРАВКА НЕ ВОСКРЕСАЕТ ПОСЛЕ ПЕРЕЗАПУСКА', () async {
      // Пока миграция ДУБЛИРОВАЛА запись (старый ключ → новый) и никогда не
      // убирала старую, ручную правку JSON у профиля «Авто», заведённую до
      // 1.4.2, нельзя было снять НАСОВСЕМ: `clearOverride` убирает только
      // канонический ключ, сохранение возвращало на диск старый, а следующая
      // загрузка копировала его обратно в новый.
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      seed('panel_outbounds.json', {
        legacy: {'config': jsonEncode(cfg)}
      });
      seed('server_overrides.json', {
        legacy: {'rawJson': '{"outbounds":[]}'}
      });

      await PanelOutboundsStore().load(); // как в AppState.init() — первым
      final store = ServerOverridesStore();
      final key = XrayJsonSubscription.panelKeyOf(cfg);
      final loaded = <String, ServerOverride>{...await store.load()};
      expect(loaded[key], isNotNull, reason: 'правка обязана доехать');

      // Ровно то, что делает AppState.clearOverride: убрать по ключу ЖИВОГО
      // сервера (он канонический) и сохранить карту целиком.
      loaded.remove(key);
      await store.save(loaded);

      await PanelOutboundsStore().load(); // перезапуск
      expect(await store.load(), isEmpty,
          reason: 'снятая правка вернулась — снять её было бы нечем');
    });
  });

  // ── Страж уровня приложения ────────────────────────────────────────────────

  group('⚠️ СТРАЖ: пин по НОВОМУ ключу, конфиг по СТАРОМУ', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_panel_boot_');
      AppPaths.overrideRoot(tmp);
      File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({
        // Сеть в тестах запрещена: обновление на старте под тестами и так
        // заблокировано (`AppState._underTest`), автообновление гасим явно.
        'autoUpdateEnabled': false,
        'updateSubscriptionOnStart': false,
      }));
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    void seed(String file, Object data) {
      File('${tmp.path}${Platform.pathSeparator}$file')
          .writeAsStringSync(jsonEncode(data));
    }

    /// Сценарий из жизни, без единой экзотики: человек обновился с 1.4.1,
    /// закреплённый профиль восстановился и получил НОВЫЙ ключ, человек
    /// закрепил/открепил любой другой сервер — и `pinned_servers.json`
    /// переписался уже новым ключом. `panel_outbounds.json` при этом остался со
    /// старым: его переписывает только обновление подписки.
    test('профиль остаётся живым после перезапуска', () async {
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      final canonical = XrayJsonSubscription.panelKeyOf(cfg);
      seed('panel_outbounds.json', {
        legacy: {'config': jsonEncode(cfg)}
      });
      seed('pinned_servers.json', [canonical]);

      final state = AppState(engine: _FakeEngine());
      await state.init();

      expect(state.servers.map((s) => s.key), contains(canonical),
          reason: 'профиль «Авто» пропал из списка молча и необратимо: '
              'следующее сохранение вычистило бы его окончательно');
      final profile = state.servers.firstWhere((s) => s.key == canonical);
      expect(profile.isPanelProfile, isTrue,
          reason: 'должен подняться именно профиль с балансировщиком');
      expect(profile.remark, remark);
    });

    /// ⚠️ ПОРЯДОК ЧТЕНИЯ В `init()` — ЧАСТЬ ЛЕЧЕНИЯ, А НЕ ОФОРМЛЕНИЕ.
    /// Псевдоним заводит чтение конфигов панели; читайся правки серверов раньше
    /// (а до этой правки читались именно они, при комментарии, обещавшем
    /// обратное) — правка профиля осталась бы по старому ключу, а сервер уже
    /// живёт под новым, и своей же правки он не видит.
    test('ручная правка профиля доезжает до живого сервера', () async {
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      final canonical = XrayJsonSubscription.panelKeyOf(cfg);
      seed('panel_outbounds.json', {
        legacy: {'config': jsonEncode(cfg)}
      });
      seed('pinned_servers.json', [canonical]);
      seed('server_overrides.json', {
        legacy: {'rawJson': '{"outbounds":[]}'}
      });

      final state = AppState(engine: _FakeEngine());
      await state.init();

      final profile = state.servers.firstWhere((s) => s.key == canonical);
      expect(state.overrideFor(profile)?.rawJson, '{"outbounds":[]}',
          reason: 'правку вводил человек — молча отвязаться она не имеет права');
    });

    /// Обратная сторона переноса: `subscriptions.json` ключи НЕ канонизирует,
    /// и там старое написание остаётся. Конфиг к этому моменту уже переехал —
    /// без запроса псевдонима профиль исчез бы из списка подписки.
    test('ссылка подписки осталась старой — профиль всё равно поднимается',
        () async {
      final cfg = profileCfg();
      final legacy = XrayJsonSubscription.panelKey(remark);
      final canonical = XrayJsonSubscription.panelKeyOf(cfg);
      seed('panel_outbounds.json', {
        legacy: {'config': jsonEncode(cfg)}
      });
      seed('subscriptions.json', {
        'activeId': 'sub-1',
        'items': [
          {
            'id': 'sub-1',
            'url': 'https://panel.example/sub/token',
            'servers': [legacy],
          }
        ],
      });

      final state = AppState(engine: _FakeEngine());
      await state.init();

      expect(state.servers.map((s) => s.key), contains(canonical));
    });
  });
}
