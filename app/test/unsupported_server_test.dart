import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/singbox/exit_outbounds.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_error.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/probe_controller.dart';

/// СЕРВЕР, КОТОРЫЙ КЛИЕНТ НЕ УМЕЕТ ПОДНЯТЬ, БОЛЬШЕ НЕ ВЫБРАСЫВАЕТСЯ.
///
/// ⚠️ Решение владельца 25.09.2026: скрытый сервер человек читает как «подписка
/// потеряна». Раньше `_fromHysteria` (`xray_json_subscription.dart`) на
/// finalmask.udp с gecko/неизвестной маской возвращал `null`, и узел исчезал
/// молча. Теперь он остаётся в списке (`VpnServer.isUnsupported`), но не
/// годится НИ ДЛЯ ЧЕГО: ни подключиться, ни попасть в пинг/автонастройку/
/// «Авто»/отдельный выход. Тест проверяет каждую из этих точек по отдельности —
/// одна забытая точка означает тихий отказ на живой подписке.
void main() {
  // Адрес — TEST-NET (RFC 5737), пароль выдуманный: никуда не ходит.
  Map<String, dynamic> hy2Node({required Map<String, dynamic> udpMask}) => {
        'remarks': 'Unsupported Hy2',
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'hysteria',
            'settings': {
              'address': '203.0.113.20',
              'port': 443,
              'version': 2,
            },
            'streamSettings': {
              'network': 'hysteria',
              'hysteriaSettings': {'version': 2, 'auth': 'fake-auth'},
              'security': 'tls',
              'tlsSettings': {'serverName': '203.0.113.20'},
              'finalmask': {
                'udp': [udpMask],
              },
            },
          },
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
      };

  VpnServer geckoServer() {
    final cfg = hy2Node(udpMask: {
      'type': 'salamander',
      'settings': {'password': 'x', 'packetSize': '1200-1500'},
    });
    return XrayJsonSubscription.parse('[${jsonEncode(cfg)}]').single;
  }

  const supportedLink = 'vless://11111111-2222-3333-4444-555555555555'
      '@203.0.113.30:443?type=tcp&security=none#Support';

  group('VpnServer.isUnsupported', () {
    test('парсер помечает, а не выбрасывает', () {
      final s = geckoServer();
      expect(s.isUnsupported, isTrue);
      expect(s.unsupportedReason, 'hy2_mask:gecko');
    });

    test('обычный сервер не помечен', () {
      final s = ShareLinkParser.tryParse(supportedLink)!;
      expect(s.isUnsupported, isFalse);
    });
  });

  group('exitServerRejection / canBeExitServer', () {
    test('неподдерживаемый сервер не годится в отдельный выход', () {
      final s = geckoServer();
      expect(canBeExitServer(s), isFalse);
      expect(exitServerRejection(s), contains('не поддерживается'));
    });
  });

  group('ProbeController: пинг/скорость пропускают неподдерживаемый сервер', () {
    test('pingAll на одном неподдерживаемом сервере не запускает прогон', () async {
      final probe = ProbeController();
      final s = geckoServer();
      await probe.pingAll([s], AppSettings.defaults);
      expect(probe.running, isFalse,
          reason: '_pingBatch должен получить пустой список и выйти сразу');
      expect(probe.resultFor(s), PingResult.untested);
    });

    test('pingOne на неподдерживаемом сервере — no-op', () async {
      final probe = ProbeController();
      final s = geckoServer();
      await probe.pingOne(s, AppSettings.defaults);
      expect(probe.running, isFalse);
      expect(probe.resultFor(s), PingResult.untested);
    });

    test('measureSpeedOne на неподдерживаемом сервере — no-op', () async {
      final probe = ProbeController();
      final s = geckoServer();
      await probe.measureSpeedOne(s, AppSettings.defaults);
      expect(probe.speedFor(s), isNull);
    });
  });

  group('AppState: подключение отказывает', () {
    late Directory tmp;
    late AppState app;
    late _RecordingEngine engine;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('sg_unsupported_');
      AppPaths.overrideRoot(tmp);
      engine = _RecordingEngine();
      app = AppState(engine: engine);
      await app.init();
    });

    tearDown(() {
      app.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('selectServer отказывается выбрать неподдерживаемый сервер', () async {
      await app.importSource(supportedLink);
      final supportedIdx = app.selectedIndex;
      expect(app.selectedServer!.isUnsupported, isFalse);

      final unsupportedLink = geckoServer().buildShareLink();
      await app.importSource(unsupportedLink);
      // importSource ставит выбор напрямую (обходя `selectServer`) — это
      // законный путь, страхует его `toggleConnection` ниже. Здесь же
      // проверяем именно `selectServer`.
      final unsupportedIdx = app.selectedIndex;
      expect(app.selectedServer!.isUnsupported, isTrue);

      app.selectServer(supportedIdx);
      expect(app.selectedIndex, supportedIdx);

      app.selectServer(unsupportedIdx);
      // Отказ: индекс НЕ должен переехать на неподдерживаемый сервер.
      expect(app.selectedIndex, supportedIdx);
      expect(app.errorCode, AppErrorCode.serverUnsupported);
    });

    test('toggleConnection отказывается подключать выбранный неподдерживаемый сервер',
        () async {
      final unsupportedLink = geckoServer().buildShareLink();
      await app.importSource(unsupportedLink);
      expect(app.selectedServer!.isUnsupported, isTrue);

      await app.toggleConnection(AppSettings.defaults);

      expect(app.errorCode, AppErrorCode.serverUnsupported);
      expect(engine.connectCalls, 0,
          reason: 'движок не должен был увидеть неподдерживаемый сервер');
    });

    test('connectAuto отказывает, когда ВСЕ серверы неподдерживаемые', () async {
      final unsupportedLink = geckoServer().buildShareLink();
      await app.importSource(unsupportedLink);

      await app.connectAuto(AppSettings.defaults);

      expect(app.errorCode, AppErrorCode.serverUnsupported);
      expect(engine.connectBalancerCalls, 0);
    });

    test('connectAuto не передаёт неподдерживаемый сервер в балансировщик',
        () async {
      await app.importSource(supportedLink);
      final unsupportedLink = geckoServer().buildShareLink();
      await app.importSource(unsupportedLink);

      await app.connectAuto(AppSettings.defaults);

      expect(engine.connectBalancerCalls, 1);
      expect(engine.lastBalancerServers!.any((s) => s.isUnsupported), isFalse,
          reason: 'балансировщик не должен строить outbound без маски, '
              'которую сервер ждёт');
    });
  });

  group('Восстановление после перезапуска', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('sg_unsupported_restart_'));
    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('метка неподдерживаемости переживает перезапуск приложения', () async {
      AppPaths.overrideRoot(tmp);
      final first = AppState(engine: _RecordingEngine());
      await first.init();
      final unsupportedLink = geckoServer().buildShareLink();
      await first.importSource(unsupportedLink);
      expect(first.selectedServer!.isUnsupported, isTrue);
      first.dispose();

      // Новый процесс — тот же каталог данных, ссылка на диске несёт
      // `unsupported=hy2_mask:gecko` (см. VpnServer.buildShareLink).
      final second = AppState(engine: _RecordingEngine());
      await second.init();
      final restored =
          second.servers.where((s) => s.key.contains('203.0.113.20'));
      expect(restored, isNotEmpty);
      expect(restored.first.isUnsupported, isTrue);
      expect(restored.first.unsupportedReason, 'hy2_mask:gecko');
      second.dispose();
    });
  });
}

/// Движок-пустышка, который ЗАПОМИНАЕТ, что ему передали — тест проверяет не
/// только отказ AppState, но и что запрещённый сервер физически не доехал до
/// точки, которая строит конфиг ядра.
class _RecordingEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  int connectCalls = 0;
  int connectBalancerCalls = 0;
  List<VpnServer>? lastBalancerServers;

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
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    connectCalls++;
  }

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {
    connectBalancerCalls++;
    lastBalancerServers = servers;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
