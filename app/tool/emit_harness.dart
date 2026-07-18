// Печатает harness-конфиг (несколько кандидатов, включая fragment) для валидации ядром:
//   dart run tool/emit_harness.dart "<share-link>" > harness.json
//   xray run -test -c harness.json
import 'dart:io';

import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';

void main(List<String> args) {
  final link = args.isNotEmpty
      ? args[0]
      : 'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?type=tcp&security=reality&pbk=jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0'
          '&fp=chrome&sni=www.microsoft.com&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision'
          '&encryption=none#Sample';
  final server = ShareLinkParser.tryParse(link);
  if (server == null) {
    stderr.writeln('Не удалось распознать ссылку');
    exit(1);
  }
  const builder = HarnessConfigBuilder();
  stdout.write(builder.buildJson([
    HarnessEntry(key: 'plain', server: server),
    HarnessEntry(key: 'frag', server: server, variant: const OutboundVariant(fragment: true)),
  ]));
}
