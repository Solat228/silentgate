import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// Порты API и СПОСОБ ЗАХВАТА.
///
/// С версии 1.18.7 порты выходов API поднимаются во ВСЕХ режимах захвата
/// (`tun`, `systemProxy`, `proxyOnly`): в `systemProxy` поднимается изолированный
/// маршрутизатор выходов `ExitRouter` на `127.0.0.1`, не затрагивающий WinINET.
/// `PortCheck` (`WindowsEngine.corePortsFor`) обязан проверять ровно те порты,
/// которые реально откроются сессией.
void main() {
  const ports = XrayPorts();
  const keys = ['vless://a', 'vless://b', 'vless://c'];

  AppSettings withMode(CaptureMode mode) => const AppSettings().copyWith(
        captureMode: mode,
        apiEnabled: true,
        apiToken: 'secret',
        apiExitServerKeys: keys,
      );

  group('Гейт «порты выходов существуют»', () {
    test('во всех трёх режимах захвата (системный прокси, TUN, Только прокси) порты есть', () {
      for (final m in CaptureMode.values) {
        expect(ApiPorts.exitPortsExistIn(m), isTrue, reason: 'режим $m');
        expect(ApiPorts.exitPortsActive(withMode(m)), isTrue, reason: 'режим $m');
      }
    });

    test('режим не отменяет условий безопасности: тумблер и токен управляющего API', () {
      for (final m in CaptureMode.values) {
        expect(
            ApiPorts.exitPortsActive(withMode(m).copyWith(apiEnabled: false)),
            isFalse);
        expect(
            ApiPorts.exitPortsActive(withMode(m).copyWith(apiToken: '')),
            isFalse);
      }
    });
  });

  group('Состав corePorts', () {
    test('порты ядра сессии и порты API проверяются во всех режимах захвата', () {
      for (final m in CaptureMode.values) {
        final got = WindowsEngine.corePortsFor(withMode(m), ports);
        expect(
            got,
            containsAll([
              ports.socks,
              ports.http,
              ports.api,
              10820,
              10821,
              10822,
              ApiPorts.auto,
              ApiPorts.direct,
            ]),
            reason: 'режим $m');
        expect(got.length, 3 + keys.length + 2, reason: 'режим $m');
      }
    });

    test('⚠️ порт «Прямо» и порт «Умный Автовыбор» проверяются и БЕЗ выбранных серверов', () {
      final got = WindowsEngine.corePortsFor(
          withMode(CaptureMode.proxyOnly).copyWith(apiExitServerKeys: const []),
          ports);
      expect(
          got, [ports.socks, ports.http, ports.api, ApiPorts.auto, ApiPorts.direct]);
    });

    test('отключённый порт Автовыбора убирает 10818 из проверки', () {
      final got = WindowsEngine.corePortsFor(
          withMode(CaptureMode.proxyOnly).copyWith(
            apiExitServerKeys: const [],
            apiAutoPortEnabled: false,
          ),
          ports);
      expect(got, [ports.socks, ports.http, ports.api, ApiPorts.direct]);
    });

    test('выключенный API не добавляет ничего', () {
      for (final m in CaptureMode.values) {
        final got = WindowsEngine.corePortsFor(
            withMode(m).copyWith(apiEnabled: false), ports);
        expect(got, [ports.socks, ports.http, ports.api], reason: 'режим $m');
      }
    });

    test('⚠️ активный сервер даёт ВТОРОЙ outbound к тому же узлу — конфиг '
        'выгружается для проверки настоящим ядром', () {
      const key = 'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:443#DE';
      final json = SingboxConfigBuilder(
        options: const TunOptions(serverIps: ['203.0.113.10']),
        exitOutbounds: [
          {
            'type': 'vless',
            'tag': exitTagFor(key),
            'server': '203.0.113.10',
            'server_port': 443,
            'uuid': '11111111-2222-3333-4444-555555555555',
          },
        ],
        apiExitServerKeys: const [key],
        apiToken: 'secret-token',
      ).buildJson(const SplitTunnelConfig());

      final dir = Directory('build/api-configs')..createSync(recursive: true);
      File('${dir.path}/sg_api_active_server_exit.json').writeAsStringSync(json);

      final cfg = jsonDecode(json) as Map<String, dynamic>;
      final tags = [
        for (final o in cfg['outbounds'] as List) (o as Map)['tag'],
      ];
      // Оба: основной канал и отдельный порт того же сервера.
      expect(tags, containsAll(<String>['proxy', exitTagFor(key)]));
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => i['tag'] == apiExitInboundTag(key)), isTrue);
      expect(ins.any((i) => i['tag'] == apiDirectInboundTag), isTrue);
    });

    test('сверх 250 серверов лишних портов не появляется и служебные не задеты', () {
      final many = [
        for (var i = 0; i < ApiPorts.maxServers + 10; i++)
          'vless://${i.toString().padLeft(3, '0')}'
      ];
      final got = WindowsEngine.corePortsFor(
          withMode(CaptureMode.tun).copyWith(apiExitServerKeys: many), ports);
      // 3 порта ядра + 250 серверных + Автовыбор (10818) + Прямо (10819).
      expect(got.length, 3 + ApiPorts.maxServers + 2);
      expect(got, isNot(contains(10855)));
      expect(got, isNot(contains(10870)));
      expect(got, isNot(contains(11401)));
    });
  });
}
