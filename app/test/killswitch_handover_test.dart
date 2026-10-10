import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/engine/windows/tun/kill_switch_plan_file.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// ПЕРЕСОЗДАНИЕ ТУННЕЛЯ ПРИ KILL SWITCH — БЕЗ СНЯТИЯ БЛОКИРОВКИ.
///
/// ⚠️ Обычное пересоздание — stop-файл, помощник снимает фильтры WFP и
/// выходит, пауза 600 мс, новый помощник поднимает их заново. Всё это время у
/// машины нет ни туннеля, ни блокировки. Когда блокировку держит прежний
/// туннель и её же просит новый, живой помощник перезапускает ядро сам
/// (`TunHandoverCapable.handover`), не отпуская фильтров.
///
/// Здесь проверяется решение движка: когда передачу просить, что делать при
/// отказе и что план блокировки лежит на диске ДО просьбы — помощник прочтёт
/// его сразу, как увидит её.

class _HandoverRouter implements TunRouter, TunHandoverCapable {
  _HandoverRouter(this.log);

  final List<String> log;

  /// Что ответит помощник на просьбу о перезапуске.
  bool handoverResult = true;

  /// План блокировки, лежавший на диске в момент просьбы.
  Map<String, dynamic>? planAtHandover;

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
    log.add('start');
  }

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<bool> handover(SplitTunnelConfig split,
      {required int xraySocksPort,
      required TunOptions options,
      bool Function()? abort,
      List<Map<String, dynamic>> exitOutbounds = const [],
      String xraySocksUser = '',
      String xraySocksPassword = '',
      List<String> apiExitServerKeys = const [],
      List<String> apiOnlyExitKeys = const [],
      String apiToken = ''}) async {
    log.add('handover');
    final f = File(KillSwitchPlanFile.pathFor(await AppPaths.supportDir()));
    planAtHandover = f.existsSync()
        ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
        : null;
    return handoverResult;
  }
}

void main() {
  late Directory tmp;
  late List<String> log;
  late _HandoverRouter router;
  late WindowsEngine engine;

  final servers = [
    const VpnServer(
      protocol: 'vless',
      remark: 'a',
      address: '203.0.113.10',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@203.0.113.10:443#a',
    ),
  ];

  ConnectionOptions opts({required bool killSwitch, bool seamless = false}) =>
      ConnectionOptions(
        settings: AppSettings.defaults.copyWith(
          captureMode: CaptureMode.tun,
          autoReconnect: true,
          killSwitch: killSwitch,
          seamlessServerSwitch: seamless,
          tunWatchdogSeconds: 0,
          tunnelDnsForAll: false,
          splitTunnel: const SplitTunnelConfig(mode: SplitMode.all),
        ),
      );

  Future<bool> raise(ConnectionOptions o, int gen) => engine.raiseTun(
      options: o,
      servers: servers,
      apiKeys: const [],
      aborted: () => false,
      gen: gen);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_ks_handover_');
    AppPaths.overrideRoot(tmp);
    log = [];
    router = _HandoverRouter(log);
    engine = WindowsEngine(tunRouter: router, recoverSystemProxy: false);
    engine.adapterDnsForTest = () => const ['192.168.1.1'];
    engine.dnsReachableForTest = (_) async => true;
  });

  tearDown(() async {
    await engine.dispose();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('kill switch → kill switch: туннель пересоздаёт живой помощник, '
      'stop не зовётся', () async {
    expect(await raise(opts(killSwitch: true), 1), isTrue);
    expect(log, ['start']);
    log.clear();

    expect(await raise(opts(killSwitch: true), 2), isTrue);
    expect(log, ['handover'],
        reason: 'stop снял бы фильтры WFP — ровно то окно, ради которого '
            'передача и написана');
    expect(engine.tunActive, isTrue);
  });

  test('план блокировки лежит на диске ДО просьбы о перезапуске', () async {
    await raise(opts(killSwitch: true), 1);
    // Портим файл: если движок не перепишет его перед просьбой, помощник
    // прочтёт вчерашний план.
    File(KillSwitchPlanFile.pathFor(await AppPaths.supportDir()))
        .writeAsStringSync('{}');

    await raise(opts(killSwitch: true), 2);
    expect(router.planAtHandover, isNotNull);
    expect(router.planAtHandover!['enabled'], isTrue);
    expect(router.planAtHandover!['serverIps'], contains('203.0.113.10'));
  });

  test('помощник отказал — обычный путь stop → start', () async {
    await raise(opts(killSwitch: true), 1);
    log.clear();
    router.handoverResult = false;

    expect(await raise(opts(killSwitch: true), 2), isTrue);
    expect(log, ['handover', 'stop', 'start']);
  });

  test('без kill switch передачи нет: снимать нечего', () async {
    await raise(opts(killSwitch: false), 1);
    log.clear();
    expect(await raise(opts(killSwitch: false), 2), isTrue);
    expect(log, ['stop', 'start']);
  });

  test('kill switch только что включили — старый помощник блокировки не '
      'держит, нужен новый', () async {
    await raise(opts(killSwitch: false), 1);
    log.clear();
    expect(await raise(opts(killSwitch: true), 2), isTrue);
    expect(log, ['stop', 'start'],
        reason: 'помощник без блокировки отказал бы в перезапуске — просить '
            'его незачем');
  });

  test('kill switch выключили — передачи нет, помощник снимет фильтры',
      () async {
    await raise(opts(killSwitch: true), 1);
    log.clear();
    expect(await raise(opts(killSwitch: false), 2), isTrue);
    expect(log, ['stop', 'start']);
  });

  test('бесшовность: тот же конфиг, но kill switch включён — туннель НЕ '
      'переиспользуется', () async {
    engine.tunAliveForTest = () async => true;
    await raise(opts(killSwitch: false, seamless: true), 1);
    log.clear();

    await raise(opts(killSwitch: true, seamless: true), 2);
    expect(log, contains('start'),
        reason: 'помощник читает состав блокировки только на старте: '
            'переиспользование оставило бы его без kill switch');
  });

  test('бесшовность: ни конфиг, ни блокировка не менялись — переиспользуем',
      () async {
    engine.tunAliveForTest = () async => true;
    await raise(opts(killSwitch: true, seamless: true), 1);
    log.clear();

    await raise(opts(killSwitch: true, seamless: true), 2);
    expect(log, isEmpty);
  });

  group('порты живого туннеля', () {
    // ⚠️ Найдено живьём в VM: смена сервера и автопереподключение по
    // включению kill switch падали «Порт 10820 ещё занят нашим ядром» — его
    // держит туннельный sing-box, а снимается он позже проверки портов.
    test('живой туннель держит свои порты при любом исходе', () async {
      await raise(opts(killSwitch: true), 1);
      expect(engine.tunnelHoldsItsPorts, isTrue);
    });

    test('и без kill switch', () async {
      await raise(opts(killSwitch: false), 1);
      expect(engine.tunnelHoldsItsPorts, isTrue);
    });

    test('туннеля нет — порты проверяются', () {
      expect(engine.tunnelHoldsItsPorts, isFalse);
    });
  });

  group('killSwitchPlanSignature', () {
    final base = AppSettings.defaults.copyWith(
        captureMode: CaptureMode.tun, autoReconnect: true, killSwitch: true);

    test('различает включённую и выключенную блокировку', () {
      expect(
          WindowsEngine.killSwitchPlanSignature(base, const ['203.0.113.1']),
          isNot(WindowsEngine.killSwitchPlanSignature(
              base.copyWith(killSwitch: false), const ['203.0.113.1'])));
    });

    test('порядок и повторы адресов не важны', () {
      expect(
          WindowsEngine.killSwitchPlanSignature(
              base, const ['203.0.113.2', '203.0.113.1', '203.0.113.2']),
          WindowsEngine.killSwitchPlanSignature(
              base, const ['203.0.113.1', '203.0.113.2']));
    });

    test('новый адрес сервера меняет подпись', () {
      expect(
          WindowsEngine.killSwitchPlanSignature(base, const ['203.0.113.1']),
          isNot(WindowsEngine.killSwitchPlanSignature(
              base, const ['203.0.113.1', '203.0.113.5'])));
    });
  });
}
