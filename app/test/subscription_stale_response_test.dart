import 'dart:async';
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
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/subscription/subscription_service.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// Устаревший ответ подписки не должен перезаписывать активную.
///
/// ⚠️ СТЕРЕЖЁТСЯ РОВНО ЭТА СВЕРКА (`app/lib/state/app_state.dart`,
/// `importSource`):
///
/// ```dart
/// final startedActive = _activeId;
/// _loading = true;
/// notifyListeners();
/// try {
///   final result = await _subscription.fetch(url, deviceHeaders: ...);
///   ...
///   if (_activeId != startedActive) {
///     // Пользователь ушёл на другую подписку. Данные не выбрасываем — кладём
///     // в её профиль на диск, чтобы при возврате они уже были свежими.
///     await _updateProfileQuietly(url, result.info, result.servers);
///     AppLog.i('Ответ подписки пришёл после переключения на другую — ...');
///     return;
///   }
///   ... // применение к активному экрану/карточке
/// }
/// ```
///
/// `_subscription.fetch` идёт без собственного таймаута и может занять
/// десятки секунд; переключатель подписок всё это время остаётся нажимаемым.
/// Без сверки `_activeId != startedActive` ответ по подписке A, пришедший уже
/// после того, как пользователь переключился на B, молча подменил бы список
/// серверов, карточку и активную подписку обратно на A.
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

/// Панель, чей ответ придерживается до явного [respond] — ровно та гонка,
/// которую описывает комментарий фикса: запрос ушёл в сеть, ответа ещё нет.
class _StallingPanel extends SubscriptionService {
  final Completer<SubscriptionResult> _gate = Completer<SubscriptionResult>();
  int calls = 0;

  @override
  Future<SubscriptionResult> fetch(String url,
      {Map<String, String> deviceHeaders = const {}}) async {
    calls++;
    return _gate.future;
  }

  void respond(SubscriptionResult result) => _gate.complete(result);
}

/// Заглушка идентификатора устройства: настоящая на Windows лезет в реестр.
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
  const uuid = '00000000-0000-0000-0000-000000000000';

  String link({required String host, required String name}) =>
      'vless://$uuid@$host:443?type=tcp&security=reality&encryption=none'
      '&sni=a.example.org&fp=chrome&pbk=KEY&sid=ab'
      '#${Uri.encodeComponent(name)}';

  VpnServer parse(String l) {
    final s = ShareLinkParser.tryParse(l);
    expect(s, isNotNull, reason: 'ссылка теста должна разбираться: $l');
    return s!;
  }

  const urlA = 'https://panel.example/sub/token-a';
  const urlB = 'https://panel.example/sub/token-b';
  final idA = SubscriptionProfile.idFor(urlA);
  final idB = SubscriptionProfile.idFor(urlB);

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_stale_sub_');
    // ⚠️ ОБЯЗАТЕЛЬНО: без подмены корня тест полез бы в боевой
    // %APPDATA%\SilentGate владельца (память tests-must-not-touch-real-appdata).
    AppPaths.overrideRoot(tmp);
    setDeviceIdProviderForTests(_FakeDeviceId());
    final sep = Platform.pathSeparator;
    // Автообновление по таймеру завело бы таймер и полезло на version-эндпоинт.
    File('${tmp.path}${sep}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    // Две подписки на диске: A — активная, B — уже известная (переключение на
    // неё идёт по локальным данным, сети не требует).
    File('${tmp.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
      'activeId': idA,
      'items': [
        {
          'id': idA,
          'url': urlA,
          'servers': [link(host: 'a-old.example.com', name: 'A-старый')],
          'addedAt': '2026-08-01T00:00:00.000Z',
        },
        {
          'id': idB,
          'url': urlB,
          'servers': [link(host: 'b.example.com', name: 'B-сервер')],
          'addedAt': '2026-08-01T00:00:00.000Z',
        },
      ],
    }));
  });

  tearDown(() async {
    setDeviceIdProviderForTests(null);
    await AppLog.resetFileForTest();
    // Дать досчитать фоновым цепочкам (см. subscription_diff_test.dart) —
    // подмену каталога снимаем ПОСЛЕ них.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
      '⚠️ ОТВЕТ ПО УСТАРЕВШЕЙ ПОДПИСКЕ НЕ ЗАТИРАЕТ ТУ, НА КОТОРУЮ УСПЕЛ '
      'ПЕРЕКЛЮЧИТЬСЯ ПОЛЬЗОВАТЕЛЬ', () async {
    final panel = _StallingPanel();
    final state = AppState(engine: _FakeEngine(), subscription: panel);
    await state.init();
    expect(state.activeSubscriptionId, idA);
    await AppLog.resetFileForTest();

    // Обновление A уходит в сеть и зависает на фейковом гейте — ровно то окно,
    // за время которого владелец успевает переключиться на B.
    final updateFuture = state.importSource(urlA);
    // Дать синхронной части importSource (в т.ч. `startedActive = _activeId`)
    // выполниться до первого await внутри неё.
    await Future<void>.delayed(Duration.zero);
    expect(panel.calls, 1, reason: 'запрос обязан уже уйти в сеть');

    // Пользователь переключился на B, пока ответ A ещё в пути.
    await state.switchSubscription(idB);
    expect(state.activeSubscriptionId, idB);
    expect(state.servers.map((s) => s.remark), contains('B-сервер'));

    // Теперь приходит ответ по A — с составом, отличным от того, что на
    // экране B, иначе подмену было бы не отличить от совпадения.
    final staleServer =
        parse(link(host: 'a-new.example.com', name: 'A-устаревший-ответ'));
    panel.respond(SubscriptionResult(
      [staleServer],
      const SubscriptionInfo(title: 'Подписка A'),
    ));
    await updateFuture;

    // Экран обязан остаться на B — устаревший ответ A его не тронул.
    expect(state.activeSubscriptionId, idB,
        reason: 'ответ по подписке A пришёл после переключения на B и не '
            'должен был вернуть активную подписку обратно на A');
    expect(state.servers.map((s) => s.remark),
        isNot(contains('A-устаревший-ответ')),
        reason: 'список серверов на экране должен остаться списком B');
    expect(state.servers.map((s) => s.remark), contains('B-сервер'));

    // Данные A не потеряны — фикс кладёт их «тихо» в профиль A на диске
    // (`_updateProfileQuietly`), и они видны при возврате на неё.
    await state.switchSubscription(idA);
    expect(state.servers.map((s) => s.remark), contains('A-устаревший-ответ'),
        reason: 'ответ A не должен был просто выброситься — он ждёт в '
            'профиле до возврата на эту подписку');

    // И в журнал ушла строка, объясняющая, что произошло (а не тихая пропажа
    // ответа A, неотличимая от сетевой ошибки).
    final infos = AppLog.entries.map((e) => e.message).join('\n');
    expect(infos, contains('Ответ подписки пришёл после переключения'));
  });
}
