// Печатает harness-конфиг для сервера с полным JSON-override (#8.2) — валидация ядром:
//   dart run tool/emit_override_harness.dart path/to/config.json > override_harness.json
//   xray run -test -c override_harness.json
import 'dart:io';

import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Укажите путь к JSON-конфигу');
    exit(1);
  }
  final raw = File(args[0]).readAsStringSync();
  // Любой валидный сервер как «носитель» override — важен только rawJsonOverride.
  final base = ShareLinkParser.tryParse(
    'vless://11111111-2222-3333-4444-555555555555@example.com:443'
    '?type=tcp&security=reality&pbk=K&sni=a.com&sid=ab&encryption=none#OV',
  )!;
  final server = base.copyWith(rawJsonOverride: raw);
  const builder = HarnessConfigBuilder();
  stdout.write(builder.buildJson([HarnessEntry(key: 'ov', server: server)]));
}
