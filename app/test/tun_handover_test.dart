import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// СМЕНА ТУННЕЛЯ: ЧТО ДЕЛАЕТСЯ РАНЬШЕ — ПОДГОТОВКА ИЛИ СНЯТИЕ СТАРОГО.
///
/// ⚠️ Первое (kill switch). Между попытками восстановления захват НАМЕРЕННО не
/// снимается: туннель стоит, ядра нет, соединения падают — приложения получают
/// ошибку вместо утечки мимо VPN. Начало каждой попытки, однако, первым же
/// делом снимало этот туннель и только ПОТОМ шло резолвить серверы, опрашивать
/// DNS адаптера (до 2 с на адрес), искать IPv6 и поднимать запасной форвардер.
/// Всё это время — а на сломанной сети, то есть ровно когда идут попытки, это
/// десятки секунд — трафик машины шёл напрямую под реальным IP, притом что на
/// экране стояло «Переподключение… трафик заблокирован».
///
/// ⚠️ Второе (поколения). `isStale` отвечает «поколение сменилось» и не говорит,
/// ПОЧЕМУ: отменой или новым запуском. Устаревший запуск, вернувшийся из
/// `_tunRouter.start` (автоподбор стека идёт до двух минут), снимал туннель
/// БЕЗУСЛОВНО — то есть туннель уже НОВОЙ сессии, а флаг `_tunActive` при этом
/// обнулял, так что штатная уборка его больше не находила.
///
/// Ни то, ни другое не проверить через `startSession` (живое ядро, реальные
/// сокеты, права администратора), поэтому подъём туннеля вынесен в `raiseTun`,
/// а роутер и определение DNS подменяются.

/// TUN-роутер, который ничего не поднимает, но помнит порядок обращений.
class _FakeTunRouter implements TunRouter {
  _FakeTunRouter(this.log);

  final List<String> log;
  int starts = 0;
  int stops = 0;
  bool up = false;

  /// Опции ПОСЛЕДНЕГО подъёма — то, что реально уехало бы ядру.
  TunOptions? lastOptions;

  /// Позволяет «зависнуть» внутри подъёма — как настоящий автоподбор.
  Future<void> Function(int call)? onStart;

  @override
  Future<void> start(SplitTunnelConfig split,
      {required int xraySocksPort,
      required TunOptions options,
      void Function(String message)? onProgress,
      bool Function()? abort,
      List<Map<String, dynamic>> exitOutbounds = const [],
      String xraySocksUser = '',
      String xraySocksPassword = '',
      List<String> apiExitServerKeys = const [],
      List<String> apiOnlyExitKeys = const [],
      String apiToken = ''}) async {
    starts++;
    lastOptions = options;
    log.add('start');
    await onStart?.call(starts);
    up = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    log.add('stop');
    up = false;
  }
}

void main() {
  late Directory tmp;
  late List<String> log;
  late _FakeTunRouter router;
  late WindowsEngine engine;

  final servers = [
    const VpnServer(
      protocol: 'vless',
      remark: 'a',
      // Адрес литеральный: резолв не должен ходить в сеть.
      address: '203.0.113.10',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@203.0.113.10:443#a',
    ),
  ];

  final options = ConnectionOptions(
    settings: AppSettings.defaults.copyWith(
      captureMode: CaptureMode.tun,
      // Сторож зависания и запасной DNS-форвардер к порядку отношения не имеют,
      // а таймер и сокет прогону только мешают.
      tunWatchdogSeconds: 0,
      tunnelDnsForAll: false,
      splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
    ),
  );

  setUp(() {
    // Изолированный каталог данных: резолв читает кэш адресов с диска, и в
    // боевой %APPDATA%\SilentGate тесту лезть нельзя.
    tmp = Directory.systemTemp.createTempSync('sg_tun_handover_');
    AppPaths.overrideRoot(tmp);
    log = [];
    router = _FakeTunRouter(log);
    // ⚠️ recoverSystemProxy: false — маркер «прокси ставили мы» лежит в
    // системном %TEMP% мимо AppPaths, и без этого тест снял бы системный прокси
    // у РАБОТАЮЩЕГО приложения владельца.
    engine = WindowsEngine(tunRouter: router, recoverSystemProxy: false);
    // Подменяем ровно два внешних шага определения резолвера: список адресов у
    // адаптеров (Windows API) и UDP-пробу «отвечает ли он» (до 2 с на адрес).
    // Разбор — включая память о прошлом рабочем резолвере — остаётся настоящим.
    engine.adapterDnsForTest = () {
      log.add('dns');
      return const ['192.168.1.1'];
    };
    engine.dnsReachableForTest = (_) async => true;
  });

  tearDown(() async {
    await engine.dispose();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('kill switch: старый туннель снимается ТОЛЬКО после подготовки',
      () async {
    // Первый подъём: снимать нечего.
    expect(
        await engine.raiseTun(
            options: options,
            servers: servers,
            apiKeys: const [],
            aborted: () => false,
            gen: 1),
        isTrue);
    expect(engine.tunActive, isTrue);
    expect(log, ['dns', 'start']);

    log.clear();
    // Повторная попытка при kill switch: туннель прошлой попытки ещё стоит и
    // держит трафик — снимать его до готовности нового значит открыть канал.
    expect(
        await engine.raiseTun(
            options: options,
            servers: servers,
            apiKeys: const [],
            aborted: () => false,
            gen: 2),
        isTrue);

    expect(log, ['dns', 'stop', 'start'],
        reason: 'между stop и start машина остаётся без захвата — и всё, что '
            'стоит РАНЬШЕ stop, это окно удлиняет');
  });

  test('устаревший запуск не снимает туннель НОВОЙ сессии', () async {
    final reached = Completer<void>();
    final gate = Completer<void>();
    router.onStart = (call) async {
      if (call != 1) return;
      reached.complete();
      await gate.future; // как автоподбор стека: до двух минут
    };

    var staleFirst = false;
    final first = engine.raiseTun(
        options: options,
        servers: servers,
        apiKeys: const [],
        aborted: () => staleFirst,
        gen: 1);
    await reached.future;

    // Пользователь нажал «Отключить», а следом «Подключить»: пошёл новый
    // запуск, он поднял свой туннель и теперь им владеет.
    staleFirst = true;
    expect(
        await engine.raiseTun(
            options: options,
            servers: servers,
            apiKeys: const [],
            aborted: () => false,
            gen: 2),
        isTrue);
    expect(router.up, isTrue);

    // И только теперь первый запуск возвращается из подъёма и видит, что устарел.
    gate.complete();
    expect(await first, isFalse);

    expect(router.up, isTrue,
        reason: 'устаревший запуск снял туннель, поднятый НОВОЙ сессией');
    expect(engine.tunActive, isTrue,
        reason: 'флаг обнулён чужим запуском — этот туннель больше не снимет '
            'даже штатная уборка');
  });
}
