// Собрать встроенный набор гео-баз (`app/assets/geo/*.dat`) из полных файлов.
//
// Запуск из каталога app:
//   dart run tool/build_geo_mini.dart <полный geoip.dat> <полный geosite.dat>
//
// Полные файлы брать из того же источника, что и приложение:
// https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release
// и сверять с лежащими рядом `*.sha256sum` до запуска. Состав набора —
// `GeoBundledSet` в lib/core/geo/geo_bundled_set.dart.
import 'dart:io';

import 'package:silentgate/core/geo/geo_bundled_set.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Использование: dart run tool/build_geo_mini.dart '
        '<geoip.dat> <geosite.dat>');
    exit(64);
  }
  final outDir = Directory('assets/geo');
  await outDir.create(recursive: true);
  final jobs = {
    'geoip.dat': (args[0], GeoBundledSet.ip),
    'geosite.dat': (args[1], GeoBundledSet.site),
  };
  for (final e in jobs.entries) {
    final (src, names) = e.value;
    final full = await File(src).readAsBytes();
    final mini = extractGeoCategories(full, names);
    final out = File('${outDir.path}/${e.key}');
    await out.writeAsBytes(mini, flush: true);
    stdout.writeln('${e.key}: ${full.length} -> ${mini.length} байт '
        '(${names.join(', ')})');
  }
}
