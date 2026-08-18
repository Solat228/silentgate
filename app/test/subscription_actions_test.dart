import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_info.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/subscription/subscription_service.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// ДЕЙСТВИЯ НАД ПОДПИСКОЙ ОТНОСЯТСЯ К ТОЙ, НА КОТОРОЙ НАЖАЛИ.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ ПОНАДОБИЛОСЬ. Меню действий раньше существовало только у
/// карточки, а карточка всегда показывает АКТИВНУЮ подписку — поэтому
/// `deleteSubscription`, `refreshSubscription` и копирование ссылки брали
/// активную молча, без всякого параметра. С появлением ПКМ-меню у строк
/// переключателя это стало ловушкой: человек жмёт «Удалить» на четвёртой
/// строке, а исчезает первая — та, что открыта. Ни один тест такого поймать не
/// мог, потому что указать другую подписку было НЕЧЕМ.
///
/// Тесты ниже поднимают настоящий `AppState` в ВРЕМЕННОМ каталоге данных:
/// боевой `%APPDATA%` тесты не трогают никогда (предохранитель в `AppPaths`).
/// В сеть никто не ходит — панель подменена.
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

/// Панель, которая запоминает, ЧЬЮ подписку у неё спросили, и отдаёт свой
/// список серверов на каждый адрес.
class _FakePanel extends SubscriptionService {
  _FakePanel({this.answers = const {}, this.fail = false});

  /// url → ссылки серверов, которые «прислала» панель.
  final Map<String, List<String>> answers;
  final bool fail;
  final List<String> urls = [];

  @override
  Future<SubscriptionResult> fetch(String url,
      {Map<String, String> deviceHeaders = const {}}) async {
    urls.add(url);
    if (fail) throw SubscriptionException('панель недоступна');
    final links = answers[url] ?? const <String>[];
    return SubscriptionResult(
      [for (final l in links) ShareLinkParser.tryParse(l)!],
      const SubscriptionInfo(title: 'ответ панели'),
    );
  }
}

/// Настоящий провайдер на Windows лезет в реестр — тесту это ни к чему.
class _FakeDeviceId implements DeviceIdProvider {
  @override
  Future<String> hwid() async => 'test-hwid';
  @override
  String osName() => 'Test';
  @override
  Future<String> osVersion() async => '1.0';
  @override
  Future<String> deviceModel() async => 'TestModel';
}

void main() {
  const urlA = 'https://panel.example/sub/token-a';
  const urlB = 'https://panel.example/sub/token-b';
  final idA = SubscriptionProfile.idFor(urlA);
  final idB = SubscriptionProfile.idFor(urlB);

  // Серверы: у каждой подписки свой, плюс один общий (он лежит в обеих сразу —
  // такой сервер осиротеть не может).
  const linkA = 'vless://11111111-1111-1111-1111-111111111111@a.example:443'
      '?type=tcp&security=none#A';
  const linkB = 'vless://22222222-2222-2222-2222-222222222222@b.example:443'
      '?type=tcp&security=none#B';
  const linkFresh = 'vless://44444444-4444-4444-4444-444444444444@fresh.example'
      ':443?type=tcp&security=none#FRESH';

  Directory? tmp;
  AppState? live;

  String path(String name) => '${tmp!.path}${Platform.pathSeparator}$name';

  void seed(String name, Object data) =>
      File(path(name)).writeAsStringSync(jsonEncode(data));

  /// Поднять состояние так, как оно поднимается после перезапуска.
  ///
  /// [withUrl] == false — состояние БЕЗ единой подписки, но с названием в
  /// карточке: так выглядит клиент, в который сервер добавили руками (ссылкой
  /// или своим JSON). Подписки за таким сервером нет, и открывать нечего.
  AppState boot({
    bool withUrl = true,
    List<String> pinned = const [],
    _FakePanel? panel,
  }) {
    tmp = Directory.systemTemp.createTempSync('sg_sub_actions_');
    AppPaths.overrideRoot(tmp!);
    // Автообновление по таймеру здесь только мешало бы: оно ходит на панель
    // само и оставляет за собой таймер, который переживает тест.
    seed('silentgate_settings.json', {
      'autoUpdateEnabled': false,
      'updateSubscriptionOnStart': false,
    });
    if (pinned.isNotEmpty) seed('pinned_servers.json', pinned);
    if (withUrl) {
      seed('silentgate_state.json', {
        'subscriptionUrl': urlA,
        'servers': [linkA],
        'selectedIndex': 0,
      });
      seed('subscriptions.json', {
        'activeId': idA,
        'items': [
          {'id': idA, 'url': urlA, 'servers': [linkA]},
          {'id': idB, 'url': urlB, 'servers': [linkB]},
        ],
      });
    } else {
      // Ни одной подписки: карточка держится на названии из состояния.
      seed('silentgate_state.json', {
        'subscriptionUrl': null,
        'servers': <String>[],
        'info': const SubscriptionInfo(title: 'Ручной сервер').toJson(),
      });
    }
    return live = AppState(
      engine: _FakeEngine(),
      subscription: panel ?? _FakePanel(),
    );
  }

  setUp(() => setDeviceIdProviderForTests(_FakeDeviceId()));

  tearDown(() {
    live?.dispose();
    live = null;
    setDeviceIdProviderForTests(null);
    AppPaths.resetForTests();
    try {
      tmp?.deleteSync(recursive: true);
    } catch (_) {}
    tmp = null;
  });

  group('Удаление указанной подписки', () {
    test('⚠️ ГЛАВНОЕ: удаляется ТА, что назвали, а не активная', () async {
      final state = boot();
      await state.init();
      expect(state.activeSubscriptionId, idA, reason: 'исходно активна A');

      await state.deleteSubscription(id: idB);

      expect(state.subscriptions.map((p) => p.id), [idA],
          reason: 'ЗДЕСЬ БЫЛА ПОДМЕНА: метод удалял активную подписку, чем бы '
              'ни была нажатая строка');
      expect(state.activeSubscriptionId, idA);
      expect(state.subscriptionUrl, urlA,
          reason: 'экран остаётся на своей подписке — её не трогали');
      expect(state.servers.map((s) => s.key),
          contains(ShareLinkParser.tryParse(linkA)!.key),
          reason: 'список серверов активной подписки не должен шелохнуться');
    });

    test('⚠️ закреплённые серверы ДРУГИХ подписок остаются', () async {
      final state = boot(pinned: [linkA, linkB]);
      await state.init();
      expect(state.pinnedCount, 2);

      // Человек согласился убрать закреплённые серверы удаляемой подписки.
      await state.deleteSubscription(id: idB, removePinned: true);

      final keys = state.servers.map((s) => s.key).toList();
      expect(keys, contains(ShareLinkParser.tryParse(linkA)!.key),
          reason: 'закрепление ЧУЖОЙ (активной) подписки не за что снимать');
      expect(state.pinnedCount, 1,
          reason: 'ушло ровно одно закрепление — осиротевшее');
      expect(keys, isNot(contains(ShareLinkParser.tryParse(linkB)!.key)),
          reason: 'сервер удалённой подписки осиротел и снят');
    });

    test('вопрос про закреплённые считает ТОЛЬКО осиротевшие', () async {
      final state = boot(pinned: [linkA, linkB]);
      await state.init();

      // Диалог показывал `pinnedCount` — общий счётчик всех закреплений, — и на
      // удалении одной подписки из двух предлагал убрать чужие (жалоба
      // владельца 18.08.2026). Удаление стало адресным, а вопрос — нет.
      expect(state.pinnedCount, 2);
      expect(state.pinnedAtRiskOf(idB), 1,
          reason: 'у подписки B закреплён ровно один сервер');
      expect(state.pinnedAtRiskOf(idA), 1);
    });

    test('последняя подписка: на кону весь список закреплённых', () async {
      final state = boot(pinned: [linkA, linkB]);
      await state.init();
      await state.deleteSubscription(id: idB);

      // Осталась одна подписка — уносить закрепления не у кого, и галочка
      // значит буквально то, что на ней написано: список пустеет целиком.
      // Асимметрия намеренная, см. `deleteSubscription`.
      expect(state.pinnedAtRiskOf(idA), state.pinnedCount);
    });

    test('подписки с таким id уже нет — активная цела', () async {
      final state = boot();
      await state.init();

      // Строку меню могли нажать по устаревшему списку.
      await state.deleteSubscription(id: 'sub_несуществующая');

      expect(state.subscriptions.length, 2, reason: 'удалять было нечего');
      expect(state.activeSubscriptionId, idA,
          reason: 'молчаливое удаление активной вместо ненайденной — худший '
              'из возможных ответов');
    });

    test('без id удаляется активная — прежнее поведение карточки', () async {
      final state = boot();
      await state.init();

      await state.deleteSubscription();

      expect(state.subscriptions.map((p) => p.id), [idB]);
      expect(state.activeSubscriptionId, idB,
          reason: 'активной становится оставшаяся');
    });
  });

  group('Обновление указанной подписки', () {
    test('⚠️ ГЛАВНОЕ: спрашивают адрес НАЗВАННОЙ подписки', () async {
      final panel = _FakePanel(answers: {urlB: [linkFresh]});
      final state = boot(panel: panel);
      await state.init();

      final ok = await state.refreshSubscription(id: idB);

      expect(ok, isTrue);
      expect(panel.urls, [urlB],
          reason: 'ЗДЕСЬ БЫЛА ПОДМЕНА: обновлялась активная подписка');
    });

    test('⚠️ соседняя подписка НЕ становится активной', () async {
      final panel = _FakePanel(answers: {urlB: [linkFresh]});
      final state = boot(panel: panel);
      await state.init();

      await state.refreshSubscription(id: idB);

      // Наивная реализация («позвать importSource с чужим адресом») делает
      // загруженную подписку активной и подменяет экран целиком: список
      // серверов, карточку, логотип. Человек просил обновить строку в меню, а
      // получил бы смену канала — при живом туннеле ещё и с плашкой
      // «переподключитесь».
      expect(state.activeSubscriptionId, idA);
      expect(state.subscriptionUrl, urlA);
      expect(state.servers.map((s) => s.key),
          contains(ShareLinkParser.tryParse(linkA)!.key));
      expect(state.servers.map((s) => s.key),
          isNot(contains(ShareLinkParser.tryParse(linkFresh)!.key)),
          reason: 'серверы соседней подписки не лезут в открытый список');
    });

    test('свежие серверы легли в профиль соседней подписки', () async {
      final panel = _FakePanel(answers: {urlB: [linkFresh]});
      final state = boot(panel: panel);
      await state.init();

      await state.refreshSubscription(id: idB);

      expect(state.serversOfSubscription(idB).map((s) => s.key),
          [ShareLinkParser.tryParse(linkFresh)!.key],
          reason: 'иначе обновление ничего не обновило — только сходило в сеть');
    });

    test('отказ панели не роняет ошибку на чужой экран', () async {
      final panel = _FakePanel(fail: true);
      final state = boot(panel: panel);
      await state.init();

      final ok = await state.refreshSubscription(id: idB);

      expect(ok, isFalse);
      expect(state.error, isNull,
          reason: 'красный баннер относится к тому, что человек видит, — '
              'к активной подписке');
    });

    test('обновление подписки, которой уже нет, ничего не делает', () async {
      final panel = _FakePanel();
      final state = boot(panel: panel);
      await state.init();

      final ok = await state.refreshSubscription(id: 'sub_несуществующая');

      expect(ok, isFalse);
      expect(panel.urls, isEmpty,
          reason: 'подменять активной нельзя: человек просил не эту');
    });
  });

  group('Адрес подписки', () {
    test('спрашивается у названной подписки, а не у активной', () async {
      final state = boot();
      await state.init();

      expect(state.subscriptionUrlOf(idA), urlA);
      expect(state.subscriptionUrlOf(idB), urlB,
          reason: 'ЗДЕСЬ БЫЛА ПОДМЕНА: копирование брало ссылку активной, и на '
              'чужой строке в буфер уходил чужой токен');
      expect(state.subscriptionUrlOf('sub_несуществующая'), isNull);
    });
  });

}
