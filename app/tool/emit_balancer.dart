// Печатает balancer-конфиг (все серверы + burstObservatory) для валидации ядром:
//   dart run tool/emit_balancer.dart > bal.json && xray run -test -c bal.json
import 'dart:io';

import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

void main() {
  const pbk = 'jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0';
  final links = [
    'vless://11111111-2222-3333-4444-555555555555@a.example.com:443'
        '?type=tcp&security=reality&pbk=$pbk&fp=chrome&sni=a.com&sid=6ba85179e30d4fc2'
        '&flow=xtls-rprx-vision&encryption=none#A',
    'vless://11111111-2222-3333-4444-555555555555@b.example.com:443'
        '?type=tcp&security=reality&pbk=$pbk&fp=chrome&sni=b.com&sid=6ba85179e30d4fc2'
        '&flow=xtls-rprx-vision&encryption=none#B',
  ];
  final servers =
      links.map(ShareLinkParser.tryParse).whereType<VpnServer>().toList();
  stdout.write(const XrayConfigBuilder().buildBalancerJson(servers));
}
