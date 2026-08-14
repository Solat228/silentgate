import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';
import 'package:silentgate/core/util/key_migration.dart';
import 'package:silentgate/data/panel_outbounds_store.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// Движок-пустышка: к сохранности файлов VPN отношения не имеет, а включать его
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

/// Подписки переживают беду с файлом.
///
/// ⚠️ САМАЯ ДОРОГАЯ НАХОДКА АУДИТА. `SubscriptionsStore.load()` глушил разбор и
/// отдавал ПУСТОЙ снимок; `AppState.init()` видел `_profiles.isEmpty` при
/// непустом `_subscriptionUrl` (он в ДРУГОМ файле и порчи первого не замечает),
/// принимал это за переход со старой одно-подписочной версии, создавал ОДИН
/// профиль и тут же СОХРАНЯЛ его поверх файла с четырьмя. В журнале оставалась
/// строка «Подписка перенесена в новый формат профилей». У владельца это четыре
/// подписки и 131 сервер — восстановление руками на вечер.
void main() {
  const legacyUrl = 'https://panel.example/sub/legacy-token';
  const remark = '🎬 Авто (YouTube)';

  late Directory tmp;

  String path(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  void seedRaw(String name, String content) =>
      File(path(name)).writeAsStringSync(content);

  void seedBytes(String name, List<int> bytes) =>
      File(path(name)).writeAsBytesSync(bytes);

  void seed(String name, Object data) => seedRaw(name, jsonEncode(data));

  /// Четыре подписки владельца.
  String fourSubs() => jsonEncode({
        'activeId': 'sub_1',
        'items': [
          for (var i = 1; i <= 4; i++)
            {
              'id': 'sub_$i',
              'url': 'https://panel.example/sub/token-$i',
              'servers': ['vless://uuid@node$i.example.com:443?type=tcp'],
            },
        ],
      });

  /// Профиль «Авто …» от панели: балансировщик + burstObservatory.
  /// Восстанавливается ПОСЛЕ ПЕРЕЗАПУСКА только из `panel_outbounds.json` —
  /// ссылку `panel://…` не разбирает ничто.
  Map<String, dynamic> profileCfg() => {
        'outbounds': [
          for (var i = 0; i < 2; i++)
            {
              'tag': i == 0 ? 'proxy' : 'proxy-$i',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': 'auto$i.example.com',
                    'port': 443,
                    'users': [
                      {'id': '11111111-1111-1111-1111-111111111111',
                        'encryption': 'none'}
                    ],
                  }
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'reality'},
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
        'burstObservatory': {
          'subjectSelector': ['proxy']
        },
        'remarks': remark,
      };

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_sub_recovery_');
    // ⚠️ ОБЯЗАТЕЛЬНО: без подмены корня тест полез бы в боевой
    // %APPDATA%\SilentGate владельца — так 14.08.2026 и переписали его
    // настоящий subscriptions.json.
    AppPaths.overrideRoot(tmp);
    KeyMigration.resetPanelKeys();
    // Сеть в тестах запрещена: обновление на старте и так заблокировано
    // (`AppState._underTest`), автообновление гасим явно.
    seed('silentgate_settings.json', {
      'autoUpdateEnabled': false,
      'updateSubscriptionOnStart': false,
    });
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Старое одно-подписочное состояние: URL подписки лежит в ДРУГОМ файле и о
  /// порче `subscriptions.json` ничего не знает. Именно оно включало миграцию.
  void seedLegacyState() => seed('silentgate_state.json', {
        'subscriptionUrl': legacyUrl,
        'servers': ['vless://uuid@legacy.example.com:443?type=tcp'],
        'selectedIndex': 0,
      });

  group('Нечитаемый файл подписок', () {
    test('⚠️ ГЛАВНОЕ: ОБРЕЗАННЫЙ ФАЙЛ НЕ ЗАМЕНЯЕТСЯ ОДНОЙ ПОДПИСКОЙ', () async {
      // Процесс убили посреди записи (на Android систему никто не спрашивает),
      // антивирус подержал файл, диск кончился — форма одна.
      final original = fourSubs().substring(0, 140);
      seedRaw('subscriptions.json', original);
      seedLegacyState();

      final state = AppState(engine: _FakeEngine());
      await state.init();

      final bad = File(path('subscriptions.json.bad'));
      expect(bad.existsSync(), isTrue,
          reason: 'улику обязаны отодвинуть, а не затереть');
      expect(bad.readAsStringSync(), original);

      final survivors = File(path('subscriptions.json'));
      expect(
          survivors.existsSync() ? survivors.readAsStringSync() : '',
          isNot(contains('legacy-token')),
          reason: 'миграция запустилась поверх непрочитанных данных — ровно '
              'так четыре подписки превращались в одну');
      expect(state.subscriptions, isEmpty,
          reason: 'честная пустота лучше выдуманной подписки: файл цел в .bad '
              'и восстанавливается руками');
      expect(state.subscriptionsReadOnly, isFalse,
          reason: 'улику отодвинули — писать снова можно, и запрещать запись '
              'на весь день не за что');
    });

    test('⚠️ BOM НЕ СТОИТ НИ ОДНОЙ ПОДПИСКИ (двойной — тот, что доезжает)',
        () async {
      // ⚠️ ЗДЕСЬ БЫЛ БЕЗЗУБЫЙ ТЕСТ, И ЭТО ВАЖНЕЕ САМОЙ ПРОВЕРКИ. Он писал файл
      // с ОДНИМ BOM и был зелёным при снятой защите: ведущий `EF BB BF` снимает
      // сам декодер UTF-8 внутри `readAsString`, до `jsonDecode` символ не
      // доезжает. Проверено запуском: на строке с U+FEFF `jsonDecode` бросает
      // FormatException, а `utf8.decode([0xEF,0xBB,0xBF,…])` отдаёт строку уже
      // без него.
      //
      // До разбора U+FEFF доезжает, когда BOM в файле НЕ ОДИН: декодер снимает
      // первый, второй остаётся символом в строке. Так выглядит файл, который
      // прочитали сырыми байтами и записали обратно средством, дописывающим
      // свой BOM, — а владелец правит эти файлы руками (штатная методика
      // живого теста в VM).
      //
      // ⚠️ Байты задаём числами: невидимый символ в исходнике глазами не
      // проверяется, на этом классе багов в проекте уже стояли.
      seedBytes('subscriptions.json',
          [0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, ...utf8.encode(fourSubs())]);
      seedLegacyState();

      final state = AppState(engine: _FakeEngine());
      await state.init();

      expect(state.subscriptions.length, 4,
          reason: 'BOM срезается, как и в SettingsStorage; снимите срез — здесь '
              'будет одна подписка из legacy-миграции');
      expect(File(path('subscriptions.json.bad')).existsSync(), isFalse,
          reason: 'файл читаем — отодвигать нечего');
      expect(File(path('subscriptions.json')).readAsStringSync(),
          contains('token-4'),
          reason: 'файл обязан остаться нетронутым');
      expect(state.subscriptionsReadOnly, isFalse);
    });

    test('файл занят целиком — тоже не «подписок нет»', () async {
      // Каталог с именем файла: прочитать нечем, отодвинуть нечем. Форма та же,
      // что у файла, который держит антивирус.
      Directory(path('subscriptions.json')).createSync();
      seedLegacyState();

      final state = AppState(engine: _FakeEngine());
      await state.init();

      expect(state.subscriptions, isEmpty);
      expect(Directory(path('subscriptions.json')).existsSync(), isTrue,
          reason: 'ничего не стёрли');
      // ⚠️ ЗАПРЕТ ЗАПИСИ ОБЯЗАН ВЫЙТИ НАРУЖУ. Снаружи он неотличим от исправной
      // работы: подписка добавляется, список перерисовывается, всё выглядит
      // сделанным — и пропадает при следующем запуске. Пока это только
      // состояние (`subscriptionsReadOnly`); плашку по нему рисует интерфейс,
      // и её ещё нет — см. отчёт по задаче.
      expect(state.subscriptionsReadOnly, isTrue,
          reason: 'молчаливый запрет записи — это потерянный день работы');
    });
  });

  group('Миграция со старой версии — на месте', () {
    test('файла нет: одна подписка переносится в новый формат', () async {
      // Страж обратной стороны: запрет перезаписи не имел права выключить саму
      // миграцию.
      seedLegacyState();

      final state = AppState(engine: _FakeEngine());
      await state.init();

      expect(state.subscriptions.length, 1);
      expect(state.subscriptions.single.url, legacyUrl);
      expect(File(path('subscriptions.json')).readAsStringSync(),
          contains('legacy-token'));
    });

    test('файл разобран и пуст — это читаемо, миграция допустима', () async {
      // «Разобран и пуст» отличается от «не прочитан»: здесь на диске нет
      // ничьих данных, терять нечего.
      seedRaw('subscriptions.json', '{"activeId":null,"items":[]}');
      seedLegacyState();

      final state = AppState(engine: _FakeEngine());
      await state.init();

      expect(state.subscriptions.length, 1);
      expect(File(path('subscriptions.json.bad')).existsSync(), isFalse);
    });
  });

  group('Удаление последней подписки', () {
    test('⚠️ ЗАКРЕПЛЁННЫЙ ПРОФИЛЬ «АВТО» ПЕРЕЖИВАЕТ ПЕРЕЗАПУСК', () async {
      // Диалог удаления обещает буквально: «Иначе они останутся в списке и
      // переживут удаление». Код при этом стирал panel_outbounds.json ЦЕЛИКОМ,
      // а профиль «Авто …» восстанавливается только оттуда — обещание держалось
      // ровно до перезакрытия приложения.
      final cfg = profileCfg();
      final key = XrayJsonSubscription.panelKeyOf(cfg);
      seed('panel_outbounds.json', {
        key: {'config': jsonEncode(cfg)},
        // Конфиг сервера удаляемой подписки: он-то уйти обязан.
        'vless://uuid@ghost.example.com:443?type=tcp': {'outbound': '{}'},
      });
      seed('pinned_servers.json', [key]);
      seed('subscriptions.json', {
        'activeId': 'sub_1',
        'items': [
          {
            'id': 'sub_1',
            'url': legacyUrl,
            'servers': ['vless://uuid@ghost.example.com:443?type=tcp'],
          }
        ],
      });

      final state = AppState(engine: _FakeEngine());
      await state.init();
      expect(state.servers.map((s) => s.key), contains(key),
          reason: 'профиль должен подняться до удаления');

      await state.deleteSubscription();

      final onDisk = File(path('panel_outbounds.json')).readAsStringSync();
      expect(onDisk, isNot(contains('ghost.example.com')),
          reason: 'конфиги удалённой подписки убирать по-прежнему нужно');

      // Перезапуск приложения — единственная честная проверка «пережил».
      KeyMigration.resetPanelKeys();
      final restarted = AppState(engine: _FakeEngine());
      await restarted.init();
      expect(restarted.servers.map((s) => s.key), contains(key),
          reason: 'закреплённый профиль исчезал молча и необратимо');
      expect(
          restarted.servers.firstWhere((s) => s.key == key).isPanelProfile,
          isTrue,
          reason: 'подняться обязан именно профиль с балансировщиком, а не '
              'пересобранный из полей ссылки сервер');
    });

    test('галочка «удалить и закреплённые» чистит конфиги полностью', () async {
      final cfg = profileCfg();
      final key = XrayJsonSubscription.panelKeyOf(cfg);
      seed('panel_outbounds.json', {
        key: {'config': jsonEncode(cfg)}
      });
      seed('pinned_servers.json', [key]);
      seed('subscriptions.json', {
        'activeId': 'sub_1',
        'items': [
          {'id': 'sub_1', 'url': legacyUrl, 'servers': <String>[]}
        ],
      });

      final state = AppState(engine: _FakeEngine());
      await state.init();
      await state.deleteSubscription(removePinned: true);

      expect(await PanelOutboundsStore().load(), isEmpty,
          reason: 'человек попросил убрать закреплённые — их конфигам тоже '
              'незачем оставаться');
    });
  });
}
