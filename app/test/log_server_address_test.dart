import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// Барьер «адрес сервера в журнале» — СО СТОРОНЫ ПРИЛОЖЕНИЯ.
///
/// ⚠️ ЧТО ИМЕННО ЗДЕСЬ СТЕРЕЖЁТСЯ И ПОЧЕМУ ОДНОГО `log_secrets_test` МАЛО.
/// Там проверяется сам барьер: реестру дали адрес — строка ушла с меткой.
/// Но барьер, который никто не наполняет, чист по всем своим тестам и не
/// маскирует НИЧЕГО в работающем приложении — ровно так же, как связки
/// провайдеров без `lazy: false` были «написаны» и не звались никогда.
/// Поэтому здесь поднимается настоящий `AppState` на настоящем файле
/// подписки, и в журнал пишется ровно та строка, которую пишет `engine_base`.
///
/// ⚠️ Проверять надо ИМЕННО безымянный сервер: `VpnServer.displayName` при
/// пустом имени вырождается в «адрес:порт» — это и есть утечка, а у сервера с
/// названием её глазами не видно.
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

void main() {
  // Сервер БЕЗ имени (`#…` в ссылке нет) — тот самый случай, когда displayName
  // отдаёт адрес. И сервер неактивной подписки: его объекты живут только на
  // диске ссылками, а в журнал он попадает наравне с остальными.
  const noName = 'vless://11111111-1111-1111-1111-111111111111'
      '@ru1.example.net:443?type=tcp&security=none';
  const named = 'vless://11111111-1111-1111-1111-111111111111'
      '@de2.example.net:8443?type=tcp&security=none#Germany-2';
  const other = 'vless://22222222-2222-2222-2222-222222222222'
      '@nl3.example.net:443?type=tcp&security=none';

  const urlA = 'https://panel.example/sub/aaaaaaaa';
  const urlB = 'https://panel.example/sub/bbbbbbbb';
  final idA = SubscriptionProfile.idFor(urlA);
  final idB = SubscriptionProfile.idFor(urlB);

  Directory? tmp;
  AppState? state;

  Future<AppState> boot() async {
    tmp = Directory.systemTemp.createTempSync('sg_log_addr_');
    AppPaths.overrideRoot(tmp!);
    final sep = Platform.pathSeparator;
    // Автообновление подписки завело бы таймер и полезло на version-эндпоинт.
    File('${tmp!.path}${sep}silentgate_settings.json')
        .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
    File('${tmp!.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
      'activeId': idA,
      'items': [
        {
          'id': idA,
          'url': urlA,
          'servers': [noName, named]
        },
        {
          'id': idB,
          'url': urlB,
          'servers': [other]
        },
      ],
    }));
    final st = AppState(engine: _FakeEngine());
    await st.init();
    return state = st;
  }

  tearDown(() async {
    // ⚠️ СНАЧАЛА гасим состояние (у него подписки на потоки, наблюдатель сети
    // и таймеры) и даём догореть фоновым записям, и только ПОТОМ снимаем
    // подмену каталога. Обратный порядок — то, как 14.08.2026 тестом переписали
    // боевой `subscriptions.json` владельца: незавершённая цепочка резолвила
    // путь заново и получала настоящий %APPDATA%.
    state?.dispose();
    state = null;
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    SensitiveAddresses.forgetAllForTest();
    await AppLog.resetFileForTest();
    AppPaths.resetForTests();
    try {
      tmp?.deleteSync(recursive: true);
    } catch (_) {}
    tmp = null;
  });

  test('адрес безымянного сервера подписки не доходит до журнала', () async {
    final st = await boot();
    final server = st.servers.firstWhere((s) => s.remark.isEmpty);
    expect(server.displayName, 'ru1.example.net:443',
        reason: 'иначе тест проверяет не тот случай');

    // Дословно строка `engine_base._fallbackTo` — одно из девяти мест, где
    // displayName уходит в журнал.
    AppLog.w('Переключаюсь на запасной сервер: ${server.displayName}');
    final line = AppLog.entries.last.message;

    expect(line, isNot(contains('ru1.example.net')),
        reason: 'app.log целиком вкладывается в отчёт поддержки');
    expect(line, contains('адрес №'),
        reason: 'узел должен оставаться узнаваемым между строками');
    expect(line, contains(':443'), reason: 'порт не секрет и нужен для разбора');
  });

  test('своё имя сервера в журнале остаётся — по нему и разбирают', () async {
    final st = await boot();
    final server = st.servers.firstWhere((s) => s.remark == 'Germany-2');
    AppLog.w('Переключаюсь на запасной сервер: ${server.displayName}');
    expect(AppLog.entries.last.message, contains('Germany-2'));
  });

  test('локальные адреса ядра и TUN журнал не теряет', () async {
    await boot();
    // ⚠️ Половина задачи именно в этом: вырезать все адреса подряд значило бы
    // вылечить утечку ценой разбора, ради которого журнал и существует.
    AppLog.i('Порт 127.0.0.1:10808 занят процессом happ.exe');
    expect(AppLog.entries.last.message, contains('127.0.0.1:10808'));
    AppLog.i('TUN поднят: 172.19.0.1, DNS 1.1.1.1');
    expect(AppLog.entries.last.message, contains('172.19.0.1'));
    expect(AppLog.entries.last.message, contains('1.1.1.1'));
  });

  test('сервер НЕАКТИВНОЙ подписки тоже в реестре — его пингуют из меню',
      () async {
    final st = await boot();
    // До обращения к чужому профилю его серверов в памяти нет вовсе.
    expect(st.servers.any((s) => s.address == 'nl3.example.net'), isFalse);

    // Пункт «Пинг серверов» поднимает серверы всех подписок — и они идут в
    // журнал (`Скорость «…»`, `Автонастройка: …`).
    st.allSubscriptionServers();
    AppLog.w('Скорость «nl3.example.net:443»: харнесс не дал порт');
    expect(AppLog.entries.last.message, isNot(contains('nl3.example.net')));
  });

  test('реестр наполняется, но наружу себя не отдаёт', () async {
    await boot();
    // Адреса двух серверов активной подписки. Список самих адресов у реестра
    // спросить нечем — есть только счётчик, и это намеренно: барьер, который
    // можно прочитать через отчёт или API, был бы ещё одним местом утечки.
    expect(SensitiveAddresses.count, 2);
  });
}
