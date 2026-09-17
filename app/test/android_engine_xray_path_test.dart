import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/engine/android/android_engine.dart';
import 'package:silentgate/engine/vpn_engine.dart';

// ⚠️ КАКОЕ ЯДРО ПРЕДСТАВЛЯЕТСЯ СЕРВЕРУ REALITY — ЭТО НЕ ДЕТАЛЬ РЕАЛИЗАЦИИ.
//
// Xray на ноде отбрасывает в fallback клиента, назвавшегося версией ниже
// `minClientVer` (умолчание после апгрейда нод — 26.3.27), и делает это
// МОЛЧА: ни строки в журнале с обеих сторон, туннель «поднят», трафика нет.
// sing-box представляется хардкодом 1.8.1 и режется всегда. До этой правки
// обычный VLESS/Trojan/SS на Android шёл прямо через sing-box (libxray
// поднимался только для панельных «Авто» и правок из JSON) — и держался
// исключительно на чужой настройке `minClientVer: 0.0.0` на нодах.
//
// Решение владельца: всё, что Xray-ядро, идёт через libxray и SOCKS-мост в
// sing-box — как на Windows. hysteria2 (Xray её не умеет) остаётся на sing-box.
//
// Проверяется на НАСТОЯЩЕМ `startSession` и по тому, что реально уезжает
// нативному сервису: `xray_config` в аргументах `start` — единственный
// признак, по которому Kotlin поднимает libxray (`SilentGateVpnService.
// startTunnelLocked` → `startXray`). Проверять одну булеву переменную внутри
// движка было бы недостаточно: она могла бы быть верной, а конфиг — пустым.

/// Сторож канала, который никуда не ходит: настоящая проба била бы в сеть.
class _QuietHealth extends TunnelHealth {
  _QuietHealth() : super(proxyPort: 1, interval: const Duration(hours: 1));

  @override
  Future<bool> probeOnce() async => true;
}

/// Настоящий Android-движок с одной подменой — пробой сторожа.
class _QuietHealthEngine extends AndroidEngine {
  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) =>
      _QuietHealth();
}

// Адреса — TEST-NET (RFC 5737), литеральные: резолв в тесте не ходит в сеть.
const _vless = VpnServer(
  protocol: 'vless',
  remark: 'reality',
  address: '203.0.113.5',
  port: 443,
  id: '11111111-2222-3333-4444-555555555555',
  flow: 'xtls-rprx-vision',
  network: 'tcp',
  security: 'reality',
  sni: 'www.google.com',
  fingerprint: 'chrome',
  publicKey: 'jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0',
  shortId: '0123abcd',
  rawLink: 'vless://11111111-2222-3333-4444-555555555555@203.0.113.5:443',
);

const _trojan = VpnServer(
  protocol: 'trojan',
  remark: 'trojan',
  address: '203.0.113.6',
  port: 443,
  id: 'secret',
  network: 'tcp',
  security: 'tls',
  sni: 'example.com',
  rawLink: 'trojan://secret@203.0.113.6:443',
);

const _hysteria2 = VpnServer(
  protocol: 'hysteria2',
  remark: 'hy2',
  address: '203.0.113.8',
  port: 443,
  id: 'secret',
  network: 'quic',
  security: 'tls',
  sni: 'example.com',
  rawLink: 'hysteria2://secret@203.0.113.8:443',
);

/// Панельный профиль «Авто»: balancer + burstObservatory, два узла.
const _panelConfig = '{"inbounds":[{"tag":"socks","protocol":"socks",'
    '"port":10808,"settings":{"auth":"noauth","udp":true}}],'
    '"outbounds":['
    '{"tag":"node-a","protocol":"vless","settings":{"vnext":[{"address":'
    '"203.0.113.21","port":443,"users":[{"id":"11111111-2222-3333-4444-'
    '555555555555","encryption":"none"}]}]}},'
    '{"tag":"node-b","protocol":"vless","settings":{"vnext":[{"address":'
    '"203.0.113.22","port":443,"users":[{"id":"11111111-2222-3333-4444-'
    '555555555555","encryption":"none"}]}]}},'
    '{"tag":"direct","protocol":"freedom"}],'
    '"routing":{"balancers":[{"tag":"auto","selector":["node-"],'
    '"strategy":{"type":"leastPing"}}],"rules":[{"type":"field",'
    '"network":"tcp,udp","balancerTag":"auto"}]},'
    '"burstObservatory":{"subjectSelector":["node-"],"pingConfig":'
    '{"destination":"https://www.gstatic.com/generate_204","interval":"5m",'
    '"sampling":3,"timeout":"5s"}}}';

const _panel = VpnServer(
  protocol: 'vless',
  remark: 'Авто (YouTube)',
  address: '203.0.113.21',
  port: 443,
  id: '11111111-2222-3333-4444-555555555555',
  rawLink: 'panel://auto-youtube',
  rawPanelConfig: _panelConfig,
);

/// Правка из JSON-редактора поверх обычного сервера — с приметным тегом.
const _override = '{"inbounds":[{"tag":"socks","protocol":"socks",'
    '"port":10808,"settings":{"auth":"noauth","udp":true}}],'
    '"outbounds":[{"tag":"user-override","protocol":"freedom"}]}';

const _edited = VpnServer(
  protocol: 'vless',
  remark: 'override',
  address: '203.0.113.5',
  port: 443,
  id: '11111111-2222-3333-4444-555555555555',
  rawLink: 'vless://11111111-2222-3333-4444-555555555555@203.0.113.5:443',
  rawJsonOverride: _override,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpnChannel = MethodChannel('lol.silentgate/vpn');
  const eventsChannel = MethodChannel('lol.silentgate/vpn_events');
  const deviceChannel = MethodChannel('lol.silentgate/device');

  late Directory tmp;
  late _QuietHealthEngine engine;
  // Аргументы КАЖДОЙ команды `start` — ровно то, что получает нативный сервис.
  final started = <Map<Object?, Object?>>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_android_xray_path_');
    AppPaths.overrideRoot(tmp);
    started.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(vpnChannel, (call) async {
      switch (call.method) {
        case 'isRunning':
          // Сервис «поднял туннель» сразу — иначе startSession ждёт 25 с.
          return started.isNotEmpty;
        case 'start':
          started.add(call.arguments as Map<Object?, Object?>);
          return null;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(eventsChannel, (call) async => null);
    messenger.setMockMethodCallHandler(deviceChannel,
        (call) async => call.method == 'directDns' ? '192.168.1.1' : null);
    engine = _QuietHealthEngine();
  });

  tearDown(() async {
    await engine.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger
      ..setMockMethodCallHandler(vpnChannel, null)
      ..setMockMethodCallHandler(eventsChannel, null)
      ..setMockMethodCallHandler(deviceChannel, null);
    // Журнал пишется фоновой цепочкой — дать ей закончиться ДО возврата
    // каталога данных к боевому.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Подключиться штатным путём (кнопка → `connect` → `startSession`) и
  /// вернуть аргументы единственной команды `start`.
  Future<Map<Object?, Object?>> connectAndCapture(VpnServer server) async {
    await engine.connect(server, options: const ConnectionOptions());
    expect(engine.status.isConnected, isTrue,
        reason: 'предпосылка: подъём дошёл до «Подключено», а не упал раньше');
    expect(started, hasLength(1),
        reason: 'предпосылка: нативному сервису ушла ровно одна команда start');
    return started.single;
  }

  Map<String, dynamic> tunOf(Map<Object?, Object?> args) =>
      jsonDecode(args['config'] as String) as Map<String, dynamic>;

  Map<String, dynamic>? xrayOf(Map<Object?, Object?> args) {
    final raw = args['xray_config'] as String?;
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Map<String, dynamic> proxyOutboundOf(Map<String, dynamic> tun) =>
      (tun['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((o) => o['tag'] == 'proxy');

  group('Android: обычные серверы Xray-ядра идут через libxray', () {
    for (final server in [_vless, _trojan]) {
      test('${server.protocol}: libxray поднимается, туннель ходит в его SOCKS',
          () async {
        final args = await connectAndCapture(server);

        // Страж на ВЫЗОВ: конфиг Xray реально собран и уехал сервису.
        final xray = xrayOf(args);
        expect(xray, isNotNull,
            reason: 'без `xray_config` Kotlin libxray не поднимает вовсе — '
                'сервер REALITY увидит sing-box 1.8.1 и молча отправит его в '
                'fallback, как только с нод снимут `minClientVer: 0.0.0`');
        final outbounds =
            (xray!['outbounds'] as List).cast<Map<String, dynamic>>();
        final toServer = outbounds.firstWhere(
            (o) => o['protocol'] == server.protocol,
            orElse: () => const {});
        expect(toServer, isNotEmpty,
            reason: 'в конфиге Xray нет outbound-а к самому серверу');
        expect(jsonEncode(toServer), contains(server.address));

        // Локальный SOCKS Xray закрыт паролем (настройка включена по
        // умолчанию) и слушает порт моста.
        final inbounds =
            (xray['inbounds'] as List).cast<Map<String, dynamic>>();
        final socks = inbounds.firstWhere((i) => i['protocol'] == 'socks');
        expect(socks['port'], 10808);
        expect((socks['settings'] as Map)['auth'], 'password',
            reason: 'loopback на Android между приложениями не изолирован');

        // Туннель sing-box НЕ несёт outbound сервера сам — только мост.
        final proxy = proxyOutboundOf(tunOf(args));
        expect(proxy['type'], 'socks',
            reason: 'outbound сервера встроен прямо в sing-box — значит '
                'REALITY-рукопожатие делает sing-box, а не Xray');
        expect(proxy['server'], '127.0.0.1');
        expect(proxy['server_port'], 10808);
        expect(proxy['username'], isNotEmpty,
            reason: 'мост без пароля — трафик встанет на 407');
      });
    }

    test('hysteria2: остаётся на sing-box, libxray не поднимается', () async {
      final args = await connectAndCapture(_hysteria2);
      expect(xrayOf(args), isNull,
          reason: 'Xray протокола hysteria2 не знает и не стартовал бы; '
              'сервис попытался бы поднять его и снял туннель целиком');
      final proxy = proxyOutboundOf(tunOf(args));
      expect(proxy['type'], 'hysteria2');
      expect(proxy['server'], _hysteria2.address);
    });

    test('панельный профиль «Авто»: по-прежнему целиком через Xray', () async {
      final args = await connectAndCapture(_panel);
      final xray = xrayOf(args);
      expect(xray, isNotNull);
      expect((xray!['routing'] as Map)['balancers'], isNotEmpty,
          reason: 'балансировщик панели потерян — автовыбор свёлся к одному '
              'узлу');
      expect(xray['burstObservatory'], isNotNull);
      expect(proxyOutboundOf(tunOf(args))['type'], 'socks');
    });

    test('правка из JSON-редактора: по-прежнему целиком через Xray', () async {
      final args = await connectAndCapture(_edited);
      final xray = xrayOf(args);
      expect(xray, isNotNull);
      expect(jsonEncode(xray), contains('user-override'),
          reason: 'правка пользователя выброшена, вместо неё собранный из '
              'полей конфиг');
      expect(proxyOutboundOf(tunOf(args))['type'], 'socks');
    });
  });
}
