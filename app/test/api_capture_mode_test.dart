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
/// ⚠️ ПОЧЕМУ ЭТОТ ФАЙЛ ПОЯВИЛСЯ ТОЛЬКО НА ФИНАЛЬНОМ РЕВЬЮ. На
/// `WindowsEngine.startSession` не было ни одного теста — там живой процесс
/// ядра, реальные сокеты и права администратора. Из-за этого дефект дожил до
/// конца: `PortCheck` проверял порты 10820…10859 и 10819 по гейту «API включён
/// и токен непуст», БЕЗ учёта режима захвата, — а в режиме системного прокси
/// (умолчание на Windows!) этих инбаундов не создаётся вовсе. Сторонняя
/// программа на любом из этих портов давала «Конфликт портов» и ПОЛНЫЙ отказ
/// подключения на ровном месте.
///
/// Список портов — чистая функция настроек, поэтому проверяется без единого
/// сокета (`WindowsEngine.corePortsFor`).
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
    test('системный прокси — портов выходов НЕТ', () {
      expect(ApiPorts.exitPortsExistIn(CaptureMode.systemProxy), isFalse);
      expect(ApiPorts.exitPortsActive(withMode(CaptureMode.systemProxy)),
          isFalse);
    });

    test('TUN и «Только прокси» — есть', () {
      expect(ApiPorts.exitPortsExistIn(CaptureMode.tun), isTrue);
      expect(ApiPorts.exitPortsExistIn(CaptureMode.proxyOnly), isTrue);
      expect(ApiPorts.exitPortsActive(withMode(CaptureMode.tun)), isTrue);
      expect(ApiPorts.exitPortsActive(withMode(CaptureMode.proxyOnly)), isTrue);
    });

    test('режим не отменяет прежних условий: тумблер и токен', () {
      // Гейт обязан быть СТРОЖЕ прежнего, а не другим.
      expect(
          ApiPorts.exitPortsActive(
              withMode(CaptureMode.tun).copyWith(apiEnabled: false)),
          isFalse);
      expect(
          ApiPorts.exitPortsActive(
              withMode(CaptureMode.tun).copyWith(apiToken: '')),
          isFalse);
    });
  });

  group('Состав corePorts', () {
    test('порты ядра сессии проверяются ВСЕГДА, при любом режиме', () {
      for (final m in CaptureMode.values) {
        final got = WindowsEngine.corePortsFor(withMode(m), ports);
        expect(got, containsAll([ports.socks, ports.http, ports.api]),
            reason: 'режим $m');
      }
    });

    test('⚠️ системный прокси: портов API в проверке НЕТ ни одного', () {
      final got =
          WindowsEngine.corePortsFor(withMode(CaptureMode.systemProxy), ports);
      expect(got, [ports.socks, ports.http, ports.api]);
      // Именно этот порт в сценарии находки держала сторонняя программа.
      expect(got, isNot(contains(10821)));
      // И порт «Прямо» тоже: он живёт в тех же двух конфигах.
      expect(got, isNot(contains(ApiPorts.direct)));
    });

    test('TUN: порты серверов и «Прямо» проверяются', () {
      final got = WindowsEngine.corePortsFor(withMode(CaptureMode.tun), ports);
      expect(got, containsAll([10820, 10821, 10822, ApiPorts.direct]));
      expect(got.length, 3 + keys.length + 1);
    });

    test('«Только прокси»: то же самое', () {
      final got =
          WindowsEngine.corePortsFor(withMode(CaptureMode.proxyOnly), ports);
      expect(got, containsAll([10820, 10821, 10822, ApiPorts.direct]));
    });

    test('⚠️ порт «Прямо» проверяется и БЕЗ выбранных серверов', () {
      // Отложенная мелочь прошлого раунда: он не зависит от
      // `apiExitServerKeys` — единственное условие — открытый гейт. Пропусти мы
      // его в проверке, занятый 10819 всплыл бы только падением ядра.
      final got = WindowsEngine.corePortsFor(
          withMode(CaptureMode.proxyOnly).copyWith(apiExitServerKeys: const []),
          ports);
      expect(got, [ports.socks, ports.http, ports.api, ApiPorts.direct]);
    });

    test('выключенный API не добавляет ничего', () {
      final got = WindowsEngine.corePortsFor(
          withMode(CaptureMode.tun).copyWith(apiEnabled: false), ports);
      expect(got, [ports.socks, ports.http, ports.api]);
    });

    test('⚠️ активный сервер даёт ВТОРОЙ outbound к тому же узлу — конфиг '
        'выгружается для проверки настоящим ядром', () {
      // Находка 5 меняет ВХОД построителя, а не сам построитель: сервер,
      // выбранный на главном, теперь приходит и как `proxy`, и как выход
      // `exit-…`. Конфиг с двумя outbound-ами на один узел ядро обязано
      // принять — проверяется командой
      // `engine/windows/bin/sing-box.exe check -c build/api-configs/…`.
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

    test('сверх сорока серверов лишних портов не появляется', () {
      final many = [
        for (var i = 0; i < 45; i++) 'vless://${i.toString().padLeft(3, '0')}'
      ];
      final got = WindowsEngine.corePortsFor(
          withMode(CaptureMode.tun).copyWith(apiExitServerKeys: many), ports);
      // 3 порта ядра + 40 серверных + «Прямо».
      expect(got.length, 3 + ApiPorts.maxServers + 1);
      expect(got, isNot(contains(10860)));
    });
  });
}
