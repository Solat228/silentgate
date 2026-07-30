import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// ВРЕМЕННЫЙ эмиттер конфигов для статической проверки ядрами. Удалить.
void main() {
  final out = Directory('build/leakcheck')..createSync(recursive: true);

  void emit(String name, Map<String, dynamic> cfg) {
    File('${out.path}/$name.json')
        .writeAsStringSync(const JsonEncoderIndent().convert(cfg));
  }

  const sites = [
    SiteRule('example.org', action: AppAction.direct),
    SiteRule('example.net', action: AppAction.tunnel),
    SiteRule('ads.example', action: AppAction.block),
  ];
  const apps = [
    AppRule(r'C:\Chrome\chrome.exe', byName: true, action: AppAction.tunnel),
  ];

  test('emit', () {
    // 1. Обычный: IPv6 выключен + QUIC-блок + DoH-блок.
    emit(
        'no_ipv6_quic_doh',
        SingboxConfigBuilder(
          options: const TunOptions(
            serverIps: ['203.0.113.10'],
            ipv6: false,
            blockQuic: true,
            blockEncryptedDns: true,
            directDnsUpstream: '192.168.1.1',
          ),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    // 2. IPv6-резолвер «Прямо» (что будет, если у адаптера только IPv6 DNS).
    emit(
        'ipv6_dns_upstream',
        SingboxConfigBuilder(
          options: const TunOptions(
            serverIps: ['203.0.113.10'],
            directDnsUpstream: 'fe80:0:0:0:0:0:0:1',
          ),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    // 3. Android-вариант (платформенный TUN, всё в одном ядре).
    emit(
        'android_platform',
        SingboxConfigBuilder(
          probePort: 10809,
          proxyOutbound: const {
            'type': 'socks',
            'server': '203.0.113.10',
            'server_port': 1080,
            'version': '5',
          },
          options: const TunOptions(
            platformTun: true,
            serverIps: ['203.0.113.10'],
            ipv6: false,
            blockQuic: true,
            directDnsUpstream: '192.168.1.1',
          ),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected,
            apps: [AppRule('com.android.chrome', action: AppAction.tunnel)],
            sites: sites)));

    // 4. Заглушка kill switch.
    emit(
        'blackhole',
        SingboxConfigBuilder(
          options: const TunOptions(serverIps: ['203.0.113.10'])
              .asBlackhole(),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));

    // 5. Дефолт из настроек «как у пользователя».
    emit(
        'defaults',
        SingboxConfigBuilder(
          options: TunOptions.fromSettings(const AppSettings(),
              serverIps: const ['203.0.113.10'],
              directDnsUpstream: '192.168.1.1'),
        ).buildMap(const SplitTunnelConfig(
            mode: SplitMode.onlySelected, apps: apps, sites: sites)));
    expect(true, isTrue);
  });
}

class JsonEncoderIndent {
  const JsonEncoderIndent();
  String convert(Object? o) =>
      const JsonEncoderImpl().convert(o);
}

class JsonEncoderImpl {
  const JsonEncoderImpl();
  String convert(Object? o) => _enc.convert(o);
  static const _enc = JsonEncoderX();
}

class JsonEncoderX {
  const JsonEncoderX();
  String convert(Object? o) => jsonEncodeIndent(o);
}

String jsonEncodeIndent(Object? o) =>
    const JsonEncoderReal().convert(o);
