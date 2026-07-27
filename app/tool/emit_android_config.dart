import 'dart:io';

import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_outbound_factory.dart';

/// Печатает конфиг, который отдаёт ядру Android-движок.
///
/// Нужен, чтобы проверять его НАСТОЯЩИМ ядром той же версии, не имея под рукой
/// телефона:
///
/// ```
/// dart run tool/emit_android_config.dart [vless|trojan|ss|hysteria2] > android.json
/// sing-box check -c android.json
/// ```
///
/// Собирает ровно то же, что `AndroidEngine.startSession`: TUN-инбаунд из
/// настроек плюс прокси-outbound сервера (на Android ядро одно, промежуточного
/// SOCKS нет).
void main(List<String> args) {
  final kind = args.isEmpty ? 'vless' : args.first;
  final server = _fixture(kind);
  if (server == null) {
    stderr.writeln('Неизвестный вид сервера: $kind');
    exit(1);
  }

  const settings = AppSettings();
  stdout.write(
    SingboxConfigBuilder(
      options:
          TunOptions.fromSettings(settings, serverIps: const ['93.184.216.34']),
      proxyOutbound: SingboxOutboundFactory.build(server),
    ).buildJson(settings.splitTunnel),
  );
}

VpnServer? _fixture(String kind) {
  switch (kind) {
    case 'vless':
      return const VpnServer(
        protocol: 'vless',
        remark: 'reality',
        address: 'example.com',
        port: 443,
        id: '11111111-2222-3333-4444-555555555555',
        flow: 'xtls-rprx-vision',
        network: 'tcp',
        security: 'reality',
        sni: 'www.google.com',
        fingerprint: 'chrome',
        publicKey: 'Ab1cD2eF3gH4iJ5kL6mN7oP8qR9sT0uVwXyZ012345678',
        shortId: '0123abcd',
        rawLink: 'vless://fixture',
      );
    case 'ws':
      return const VpnServer(
        protocol: 'vless',
        remark: 'ws-tls',
        address: 'example.com',
        port: 443,
        id: '11111111-2222-3333-4444-555555555555',
        network: 'ws',
        security: 'tls',
        sni: 'example.com',
        host: 'example.com',
        path: '/ws',
        rawLink: 'vless://fixture-ws',
      );
    case 'trojan':
      return const VpnServer(
        protocol: 'trojan',
        remark: 'trojan',
        address: 'example.com',
        port: 443,
        id: 'secret',
        network: 'tcp',
        security: 'tls',
        sni: 'example.com',
        rawLink: 'trojan://fixture',
      );
    case 'hysteria2':
      return const VpnServer(
        protocol: 'hysteria2',
        remark: 'hy2',
        address: 'example.com',
        port: 443,
        id: 'secret',
        network: 'quic',
        security: 'tls',
        sni: 'example.com',
        rawLink: 'hysteria2://fixture',
      );
    default:
      return null;
  }
}
