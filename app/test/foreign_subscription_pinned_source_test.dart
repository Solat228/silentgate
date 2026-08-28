import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// ЗНАЧОК «ЧУЖАЯ ПОДПИСКА» У ЗАКРЕПЛЁННОГО СЕРВЕРА НЕ ДОЛЖЕН ГАСНУТЬ ПРИ
/// СОВПАДЕНИИ ССЫЛКИ С АКТИВНОЙ ПОДПИСКОЙ.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА: выбрана подписка «Rush»; у закреплённого «Германия 1.4»
/// подпись «Silentgate VPN» есть, у «USA 1.5» — нет, хотя оба сервера реально
/// закреплялись из «Silentgate VPN».
///
/// Причина: происхождение пина не хранилось, а вычислялось заново по
/// `_ownerByLink`, который при совпадении ссылок отдаёт приоритет АКТИВНОЙ
/// подписке. Ссылка «USA 1.5» была ещё и в «Rush» — стоило её сделать активной,
/// как эвристика тут же объявляла сервер «своим». Починка — хранить источник
/// на момент закрепления и не пересчитывать его при каждом переключении.
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
  late Directory tmp;

  // Ссылка «USA 1.5» — намеренно ОДНА И ТА ЖЕ в обеих подписках (ровно так
  // панель и породила дефект: два тарифа отдают часть узлов с одних и тех же
  // адресов). Ссылка «Германия 1.4» лежит только в «Silentgate VPN».
  //
  // ⚠️ ФРАГМЕНТ ЗАРАНЕЕ ЗАКОДИРОВАН `Uri.encodeComponent`, А НЕ ВЗЯТ БУКВАЛЬНО.
  // `ShareLinkParser.tryParse` перекодирует имя при разборе (ту же кодировку
  // использует `buildShareLink`), и `rawLink` разобранного сервера — это уже
  // ПЕРЕКОДИРОВАННАЯ строка. Запиши тут кириллицу или пробел как есть — ключ
  // разобранного сервера разойдётся со строкой, что лежит в `serverLinks`
  // профиля, и `_ownerByLink` (он строится ИМЕННО по `serverLinks`) не найдёт
  // сервер вовсе — тест ловил бы не дефект, а рассинхрон своей же фикстуры.
  final linkGermany =
      'vless://11111111-1111-1111-1111-111111111111@de.example:443'
      '?type=tcp&security=none&encryption=none#${Uri.encodeComponent('Германия 1.4')}';
  final linkUsa = 'vless://22222222-2222-2222-2222-222222222222@us.example:443'
      '?type=tcp&security=none&encryption=none#${Uri.encodeComponent('USA 1.5')}';

  const idSilentgate = 'sub-silentgate';
  const idRush = 'sub-rush';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_foreign_pin_');
    AppPaths.overrideRoot(tmp);
    setDeviceIdProviderForTests(_FakeDeviceId());
    File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp.path}${Platform.pathSeparator}subscriptions.json')
        .writeAsStringSync(jsonEncode({
      // Активная — «Silentgate VPN»: именно с её экрана пользователь и
      // закрепляет оба сервера в сценарии жалобы.
      'activeId': idSilentgate,
      'items': [
        {
          'id': idSilentgate,
          'url': 'https://panel.example/silentgate',
          'title': 'Silentgate VPN',
          'servers': [linkGermany, linkUsa],
          'addedAt': '2026-08-01T00:00:00.000Z',
        },
        {
          'id': idRush,
          'url': 'https://panel.example/rush',
          'title': 'Rush',
          'servers': [linkUsa],
          'addedAt': '2026-08-02T00:00:00.000Z',
        },
      ],
    }));
  });

  tearDown(() async {
    setDeviceIdProviderForTests(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppState> boot() async {
    final state = AppState(engine: _FakeEngine());
    await state.init();
    return state;
  }

  VpnServer byRemark(AppState state, String remark) =>
      state.servers.firstWhere((s) => s.remark == remark);

  test(
      '⚠️ ГЛАВНОЕ: пин из подписки A остаётся чужим при активной B, даже если '
      'ссылка есть и в B', () async {
    final state = await boot();

    // Закрепляем оба сервера, пока активна «Silentgate VPN» — ровно как в
    // жалобе владельца.
    await state.togglePin(byRemark(state, 'Германия 1.4'));
    await state.togglePin(byRemark(state, 'USA 1.5'));

    // Переключаемся на «Rush» — она тоже содержит ссылку «USA 1.5».
    await state.switchSubscription(idRush);

    final germany = byRemark(state, 'Германия 1.4');
    final usa = byRemark(state, 'USA 1.5');

    final foreignGermany = state.foreignSubscriptionOf(germany);
    final foreignUsa = state.foreignSubscriptionOf(usa);

    expect(foreignGermany?.id, idSilentgate,
        reason: 'этот сервер и раньше показывал значок правильно');
    expect(foreignUsa?.id, idSilentgate,
        reason: 'ЗДЕСЬ БЫЛ ДЕФЕКТ: значок гас, потому что та же ссылка '
            'нашлась в активной сейчас подписке Rush');
  });

  test('сервер активной подписки (не закреплённый) чужим не считается',
      () async {
    final state = await boot();
    // Не закрепляем ничего — USA 1.5 обычный сервер активной «Silentgate VPN».
    final usa = byRemark(state, 'USA 1.5');
    expect(state.foreignSubscriptionOf(usa), isNull);
  });

  test(
      'после возврата на исходную подписку закреплённый сервер снова свой',
      () async {
    final state = await boot();
    await state.togglePin(byRemark(state, 'USA 1.5'));
    await state.switchSubscription(idRush);
    await state.switchSubscription(idSilentgate);

    final usa = byRemark(state, 'USA 1.5');
    expect(state.foreignSubscriptionOf(usa), isNull,
        reason: 'источник совпал с активной — свой, как и раньше');
  });

  test('пин, переживший перезапуск (источник читается с диска), тоже чужой',
      () async {
    final first = await boot();
    await first.togglePin(byRemark(first, 'USA 1.5'));
    await first.switchSubscription(idRush);

    // «Перезапуск приложения»: поднимаем AppState заново — источник пина
    // обязан прочитаться из pinned_servers.json, а не потеряться.
    final second = await boot();
    final usa = byRemark(second, 'USA 1.5');
    expect(second.foreignSubscriptionOf(usa)?.id, idSilentgate);
  });

  test('пин с ПУСТЫМ сохранённым источником ведёт себя как раньше (эвристика)',
      () async {
    // Симулируем СТАРЫЙ формат pinned_servers.json (просто список ссылок) —
    // источника там нет и взяться неоткуда.
    File('${tmp.path}${Platform.pathSeparator}pinned_servers.json')
        .writeAsStringSync(jsonEncode([linkUsa]));

    final state = await boot();
    // Активная подписка — «Silentgate VPN», и линк в ней тоже есть: эвристика
    // `_ownerByLink` отдаёt её (приоритет активной), значит сервер «свой».
    final usa = byRemark(state, 'USA 1.5');
    expect(state.foreignSubscriptionOf(usa), isNull);

    await state.switchSubscription(idRush);
    // Теперь активна «Rush», и ссылка есть только там (эвристика не знает про
    // «Silentgate VPN» — источник пуст, старое поведение).
    final usaAfter = byRemark(state, 'USA 1.5');
    expect(state.foreignSubscriptionOf(usaAfter), isNull,
        reason: 'без сохранённого источника это прежняя эвристика: ссылка '
            'есть у активной — сервер свой');
  });
}
