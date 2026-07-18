// Печатает конфиг sing-box в роли ПРОКСИ-ядра (hysteria2) для валидации:
//   dart run tool/emit_hysteria2.dart "hy2://..." ["hy2://..." ...]        → прокси-конфиг
//   dart run tool/emit_hysteria2.dart --harness "hy2://..." ["hy2://..."]  → конфиг пинг-харнесса
//   dart run tool/emit_hysteria2.dart --links links.txt                    → ссылки из файла
//
// Вариант с файлом нужен на Windows: в ссылке hysteria2 полно «&», и оболочка
// рвёт её на куски раньше, чем аргумент дойдёт до Dart.
//   ../engine/windows/bin/sing-box.exe check -c hy2.json
//
// Реального подключения не происходит: `check` только разбирает конфиг.
import 'dart:io';

import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/singbox/singbox_harness_config_builder.dart';
import 'package:silentgate/core/singbox/singbox_proxy_config_builder.dart';

void main(List<String> args) {
  final harness = args.contains('--harness');
  final fileIdx = args.indexOf('--links');
  final links = <String>[];
  if (fileIdx >= 0 && fileIdx + 1 < args.length) {
    links.addAll(File(args[fileIdx + 1])
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#')));
  } else {
    links.addAll(args.where((a) => !a.startsWith('--')));
  }
  if (links.isEmpty) {
    stderr.writeln('Нужна хотя бы одна ссылка hysteria2:// или hy2://');
    exit(2);
  }

  final servers = [
    for (final l in links)
      ShareLinkParser.tryParse(l) ??
          (throw ArgumentError('Не распознана ссылка: $l')),
  ];
  for (final s in servers) {
    if (s.protocol != 'hysteria2') {
      stderr.writeln('Это не hysteria2: ${s.protocol} (${s.displayName})');
      exit(2);
    }
  }

  if (harness) {
    const builder = SingboxHarnessConfigBuilder();
    stdout.write(builder.buildJson([
      for (final s in servers) HarnessEntry(key: s.key, server: s),
    ]));
    return;
  }
  stdout.write(const SingboxProxyConfigBuilder().buildJson(servers));
}
