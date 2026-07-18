// Утилита разработчика: печатает Xray-конфиг для заданной share-ссылки.
// Используется для валидации генератора против настоящего ядра:
//   dart run tool/emit_config.dart "<share-link>" > sample.json
//   xray run -test -c sample.json
import 'dart:io';

import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

void main(List<String> args) {
  final link = args.isNotEmpty
      ? args[0]
      : 'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?type=tcp&security=tls&sni=example.com&fp=chrome&encryption=none#Sample';
  final server = ShareLinkParser.tryParse(link);
  if (server == null) {
    stderr.writeln('Не удалось распознать ссылку');
    exit(1);
  }
  stdout.write(const XrayConfigBuilder().buildJson(server));
}
