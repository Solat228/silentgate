import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silentgate/core/geo/geo_bases.dart';
import 'package:silentgate/core/geo/geo_bases_controller.dart';
import 'package:silentgate/core/geo/geo_bundled_set.dart';
import 'package:silentgate/core/geo/geo_dat.dart';
import 'package:silentgate/core/geo/geo_usage.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/xray/geodata_fallback.dart';
import 'package:silentgate/state/app_state.dart';

/// Встроенный набор гео-баз и закачка полных по Wi-Fi (решение владельца
/// 14.10.2026: «Россия + реклама», около 5 МБ; полные — сами по Wi-Fi; на
/// мобильной сети — плашка один раз).
///
/// ⚠️ ГЛАВНОЕ, ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ: ссылка на категорию, которой в наборе
/// нет (`geoip:de`), обязана вычищаться — Xray на такую ссылку отвергает
/// конфиг ЦЕЛИКОМ, и VPN не поднялся бы вовсе. И обратное: ссылки на
/// категории набора обязаны ОСТАТЬСЯ — ради них набор и едет в приложении.

/// Запись `.dat`: `entry = 1 { name = 1; payload = 2 }`. Полезная нагрузка
/// раздувает файл выше килобайта — меньше [GeoBases.healthOf] считает обрывком.
List<int> _entry(String name, {int payload = 600}) {
  final body = <int>[
    0x0a, name.length, ...ascii.encode(name),
    0x12, ..._varint(payload), ...List.filled(payload, 0x41),
  ];
  return [0x0a, ..._varint(body.length), ...body];
}

List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

Uint8List _dat(List<String> names) =>
    Uint8List.fromList([for (final n in names) ..._entry(n)]);

Uint8List _miniFor(GeoBase b) => _dat([
      for (final n in GeoBundledSet.namesForFile(b.fileName)) n.toUpperCase()
    ]);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_geo_bundled_');
    AppPaths.overrideRoot(tmp);
    GeoBases.overrideDir(Directory('${tmp.path}${Platform.pathSeparator}geo'));
  });

  tearDown(() {
    GeoBases.resetForTests();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> write(GeoBase b, List<int> bytes) async {
    final f = await GeoBases.fileOf(b);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  group('extractGeoCategories — вырезка набора из полного файла', () {
    test('берёт ровно нужные записи, байт в байт и в исходном порядке', () {
      final full = _dat(['RU', 'DE', 'PRIVATE', 'CN']);
      final mini = extractGeoCategories(full, ['private', 'ru']);
      expect(mini, [..._entry('RU'), ..._entry('PRIVATE')]);
    });

    test('⚠️ нет обещанной категории — отказ, а не тихий урезанный набор', () {
      expect(() => extractGeoCategories(_dat(['RU']), ['ru', 'telegram']),
          throwsFormatException);
    });

    test('не гео-база — отказ', () {
      expect(
          () => extractGeoCategories(
              Uint8List.fromList(utf8.encode('<html>502</html>')), ['ru']),
          throwsFormatException);
    });
  });

  group('GeoBundledSet.looksBundled', () {
    test('только категории набора — набор', () {
      expect(GeoBundledSet.looksBundled({'RU', 'PRIVATE'}, 'geoip.dat'),
          isTrue);
    });
    test('лишняя категория — полная база', () {
      expect(GeoBundledSet.looksBundled({'RU', 'DE'}, 'geoip.dat'), isFalse);
    });
    test('пусто — не набор', () {
      expect(GeoBundledSet.looksBundled({}, 'geosite.dat'), isFalse);
    });
    test('категории сайта не путаются с категориями адресов', () {
      expect(GeoBundledSet.looksBundled({'YANDEX'}, 'geoip.dat'), isFalse);
      expect(GeoBundledSet.looksBundled({'YANDEX'}, 'geosite.dat'), isTrue);
    });
  });

  group('⚠️ страж поставки: assets/geo — ровно набор, не больше и не меньше',
      () {
    for (final b in GeoBase.values) {
      test(b.fileName, () async {
        final f = File('assets/geo/${b.fileName}');
        expect(f.existsSync(), isTrue,
            reason: 'набор собирается tool/build_geo_mini.dart');
        final scan = await GeoDat.scan(f);
        expect(scan.readable, isTrue);
        expect(
            scan.names,
            {
              for (final n in GeoBundledSet.namesForFile(b.fileName))
                n.toUpperCase()
            },
            reason: 'состав файла разошёлся с GeoBundledSet');
        // Иначе [GeoBases.isBundledFile] не узнает набор по размеру.
        expect(f.lengthSync(), lessThan(8 * 1024 * 1024));
        expect(await GeoBases.isBundledFile(f, b), isTrue);
      });
    }
  });

  group('seedBundled — набор кладётся только туда, где рабочего файла нет', () {
    test('пустой каталог: оба файла положены, статус — «готово, набор»',
        () async {
      final asked = <String>[];
      final n = await GeoBases.seedBundled(load: (p) async {
        asked.add(p);
        return _miniFor(
            GeoBase.values.firstWhere((b) => p.endsWith(b.fileName)));
      });
      expect(n, 2);
      expect(asked, [
        for (final b in GeoBase.values) GeoBundledSet.assetPath(b.fileName)
      ]);
      final st = await GeoBases.status();
      expect(st.ready, isTrue);
      expect(st.bundled, isTrue);
      // Временных файлов не осталось.
      final left = (await GeoBases.dir())
          .listSync()
          .where((e) => e.path.endsWith('.seed'));
      expect(left, isEmpty);
    });

    test('⚠️ полную базу набор не заменяет никогда', () async {
      final full = _dat(['RU', 'DE', 'PRIVATE', 'TELEGRAM', 'CN']);
      await write(GeoBase.geoip, full);
      final n = await GeoBases.seedBundled(
          load: (p) async => _miniFor(
              GeoBase.values.firstWhere((b) => p.endsWith(b.fileName))));
      expect(n, 1, reason: 'положен только geosite.dat');
      expect(await (await GeoBases.fileOf(GeoBase.geoip)).readAsBytes(), full);
      final st = await GeoBases.status();
      expect(st.files.firstWhere((f) => f.base == GeoBase.geoip).bundled,
          isFalse);
      expect(st.bundled, isTrue, reason: 'geosite.dat — набор');
    });

    test('испорченный файл заменяется набором', () async {
      await write(GeoBase.geoip, utf8.encode('oops'));
      final n = await GeoBases.seedBundled(
          load: (p) async => _miniFor(
              GeoBase.values.firstWhere((b) => p.endsWith(b.fileName))));
      expect(n, 2);
      expect((await GeoBases.status()).ready, isTrue);
    });

    test('набора в сборке нет (Windows) — ничего не кладём', () async {
      expect(await GeoBases.seedBundled(load: (_) async => null), 0);
      expect((await GeoBases.status()).ready, isFalse);
    });

    test('мусор вместо набора не кладётся', () async {
      final n = await GeoBases.seedBundled(
          load: (_) async => Uint8List.fromList(List.filled(4096, 0x20)));
      expect(n, 0);
      expect((await GeoBases.status()).ready, isFalse);
    });
  });

  group('статус: полная база ≠ набор', () {
    test('полные базы — не набор', () async {
      await write(GeoBase.geoip, _dat(['RU', 'DE', 'PRIVATE']));
      await write(GeoBase.geosite, _dat(['YANDEX', 'GOOGLE']));
      final st = await GeoBases.status();
      expect(st.ready, isTrue);
      expect(st.bundled, isFalse);
    });

    test('scanCategories отдаёт состав обоих файлов', () async {
      await write(GeoBase.geoip, _miniFor(GeoBase.geoip));
      await write(GeoBase.geosite, _miniFor(GeoBase.geosite));
      final cats = await GeoBases.scanCategories();
      expect(cats, isNotNull);
      expect(cats![GeoRefKind.ip]!.has('ru'), isTrue);
      expect(cats[GeoRefKind.ip]!.has('de'), isFalse);
      expect(cats[GeoRefKind.site]!.has('category-ads-all'), isTrue);
    });

    test('scanCategories: файл не разобрался — null, а не «категорий нет»',
        () async {
      await write(GeoBase.geoip, _miniFor(GeoBase.geoip));
      expect(await GeoBases.scanCategories(), isNull);
    });
  });

  group('stripGeodata(keep:) — чистим только то, чего нет в файлах', () {
    bool inSet(GeoRefKind k, String n) => (k == GeoRefKind.ip
            ? GeoBundledSet.ip
            : GeoBundledSet.site)
        .contains(n);

    String cfg() => jsonEncode({
          'routing': {
            'rules': [
              {
                'ip': ['geoip:ru', 'geoip:private'],
                'outboundTag': 'direct'
              },
              {
                'ip': ['geoip:de'],
                'outboundTag': 'direct'
              },
              {
                'domain': ['geosite:category-ru', 'geosite:ext:my.dat:x'],
                'outboundTag': 'direct'
              },
              {'outboundTag': 'proxy', 'network': 'tcp,udp'},
            ]
          },
          'dns': {
            'servers': [
              {
                'address': '203.0.113.53',
                'domains': ['geosite:yandex', 'geosite:cn']
              }
            ]
          }
        });

    test('категории набора остаются, чужие вычищаются', () {
      final r = stripGeodata(cfg(), keep: inSet);
      final rules = (jsonDecode(r.json)['routing']['rules'] as List);
      // Правило только с geoip:de опустело — удалено целиком (иначе стало
      // бы безусловным «всё напрямую»).
      expect(rules, hasLength(3));
      expect(rules[0]['ip'], ['geoip:ru', 'geoip:private']);
      // ⚠️ Внешний файл не наш — не оставляется никогда.
      expect(rules[1]['domain'], ['geosite:category-ru']);
      expect(rules[2]['outboundTag'], 'proxy');
      final dns = jsonDecode(r.json)['dns']['servers'][0]['domains'];
      expect(dns, ['geosite:yandex']);
      expect(r.report.changed, isTrue);
      expect(r.report.rulesRemoved, 1);
      expect(r.report.residual, isFalse,
          reason: 'оставленные ссылки — законный результат');
    });

    test('без keep — прежнее поведение: чистится всё', () {
      final r = stripGeodata(cfg());
      expect(needsGeodata(r.json), isFalse);
      expect(r.report.residual, isFalse);
    });

    test('всё есть в файлах — конфиг не меняется', () {
      final json = jsonEncode({
        'routing': {
          'rules': [
            {
              'ip': ['geoip:ru'],
              'outboundTag': 'direct'
            }
          ]
        }
      });
      final r = stripGeodata(json, keep: inSet);
      expect(r.report.changed, isFalse);
      expect(r.json, json);
    });
  });

  group('shouldPrefetchGeo — когда качать полные базы без вопроса', () {
    GeoBasesStatus st({required bool ok, required bool bundled}) =>
        GeoBasesStatus(dirPath: '', files: [
          for (final b in GeoBase.values)
            GeoFileStatus(
              base: b,
              health: ok ? GeoHealth.ok : GeoHealth.missing,
              bytes: 0,
              updatedAt: null,
              bundled: bundled,
            )
        ]);

    test('Wi-Fi, правила есть, на диске набор — качаем', () {
      expect(
          shouldPrefetchGeo(
              enabled: true,
              unmetered: true,
              rulesInUse: true,
              status: st(ok: true, bundled: true)),
          isTrue);
    });
    test('файлов нет вовсе — тоже качаем', () {
      expect(
          shouldPrefetchGeo(
              enabled: true,
              unmetered: true,
              rulesInUse: true,
              status: st(ok: false, bundled: false)),
          isTrue);
    });
    test('⚠️ мобильная сеть — никогда', () {
      expect(
          shouldPrefetchGeo(
              enabled: true,
              unmetered: false,
              rulesInUse: true,
              status: st(ok: true, bundled: true)),
          isFalse);
    });
    test('тумблер выключен — нет', () {
      expect(
          shouldPrefetchGeo(
              enabled: false,
              unmetered: true,
              rulesInUse: true,
              status: st(ok: true, bundled: true)),
          isFalse);
    });
    test('гео-правил в конфигах нет — 30 МБ ни к чему', () {
      expect(
          shouldPrefetchGeo(
              enabled: true,
              unmetered: true,
              rulesInUse: false,
              status: st(ok: true, bundled: true)),
          isFalse);
    });
    test('полные базы уже на месте — нет', () {
      expect(
          shouldPrefetchGeo(
              enabled: true,
              unmetered: true,
              rulesInUse: true,
              status: st(ok: true, bundled: false)),
          isFalse);
    });
    test('диск ещё не прочитан — нет', () {
      expect(
          shouldPrefetchGeo(
              enabled: true, unmetered: true, rulesInUse: true, status: null),
          isFalse);
    });
  });

  group('контроллер на встроенном наборе', () {
    test('кнопка честно «Скачать», а не «Проверить обновление»', () async {
      await write(GeoBase.geoip, _miniFor(GeoBase.geoip));
      await write(GeoBase.geosite, _miniFor(GeoBase.geosite));
      final c = GeoBasesController(
          client: MockClient((_) async => http.Response('no', 404)));
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.status!.bundled, isTrue);
      expect(c.action, GeoAction.download);
    });

    test('автозакачка не чаще раза в шесть часов', () async {
      var requests = 0;
      final c = GeoBasesController(
          client: MockClient((_) async {
        requests++;
        return http.Response('no', 503);
      }));
      addTearDown(c.dispose);
      final t0 = DateTime(2026, 10, 14, 12);
      await c.prefetch(now: t0);
      final first = requests;
      expect(first, greaterThan(0));
      await c.prefetch(now: t0.add(const Duration(hours: 1)));
      expect(requests, first, reason: 'повтор через час — без сети');
      await c.prefetch(now: t0.add(const Duration(hours: 7)));
      expect(requests, greaterThan(first));
    });
  });

  test('⚠️ две закачки разом — одна по сети, итог общий', () async {
    var fileGets = 0;
    final gate = Completer<void>();
    final client = MockClient((req) async {
      if (req.url.toString() == GeoBase.geoip.url && req.method == 'GET') {
        fileGets++;
        await gate.future;
        return http.Response('no', 503);
      }
      return http.Response('no', 404);
    });
    final a = GeoBases.download(
        files: [GeoBase.geoip], requiredRefs: const {}, client: client);
    final b = GeoBases.download(
        files: [GeoBase.geoip], requiredRefs: const {}, client: client);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    final ra = await a;
    final rb = await b;
    expect(fileGets, 1);
    expect(ra, isNotNull);
    expect(rb, ra);
  });

  group('geoOfferReason — встроенный набор', () {
    EngineNoticeKind? reason({
      bool rulesInUse = true,
      bool autoDownloads = false,
      bool spent = false,
      EngineNoticeKind? verdict,
    }) =>
        geoOfferReason(
          filesAction: GeoAction.download,
          rulesInUse: rulesInUse,
          verdict: verdict,
          dismissed: null,
          bundled: true,
          autoDownloads: autoDownloads,
          bundledOfferSpent: spent,
        );

    test('мобильная сеть — предлагаем полные базы, а не «баз нет»', () {
      expect(reason(), EngineNoticeKind.geoAssetsBundled);
    });
    test('Wi-Fi с автозакачкой — молчим: базы и так едут', () {
      expect(reason(autoDownloads: true), isNull);
    });
    test('⚠️ один раз: уже показывали — молчим', () {
      expect(reason(spent: true), isNull);
    });
    test('гео-правил нет — молчим', () {
      expect(reason(rulesInUse: false), isNull);
    });
    test('ядро не открыло набор — это «перекачать», а не предложение', () {
      expect(reason(verdict: EngineNoticeKind.geoAssetsUnusable),
          EngineNoticeKind.geoAssetsUnusable);
    });
  });

  group('настройка «Скачивать полные базы по Wi-Fi»', () {
    test('по умолчанию включена', () {
      expect(AppSettings.defaults.geoAutoDownloadWifi, isTrue);
    });
    test('выключение переживает сохранение', () {
      final s = AppSettings.defaults.copyWith(geoAutoDownloadWifi: false);
      final back = AppSettings.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.geoAutoDownloadWifi, isFalse);
    });
    test('старые настройки без ключа — включена', () {
      final j = AppSettings.defaults.toJson()..remove('geoAutoDownloadWifi');
      expect(AppSettings.fromJson(j).geoAutoDownloadWifi, isTrue);
    });
  });
}
