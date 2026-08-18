import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/site_favicon.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/ui/widgets/site_favicon.dart';

/// Жалоба владельца после добавления пяти новых сервисов: «иконки из-за ватсапа
/// сломались» — три сервиса подряд показывали иконку WhatsApp, у части висел
/// серый глобус. Причины были три, и все они здесь:
///  * виджет применял ответ, не проверив, тот ли ещё домен (элемент списка
///    Flutter переиспользует под другой сервис);
///  * промах кэшировался НАВСЕГДА — один сбой сети при старте оставлял глобус
///    до перезапуска приложения;
///  * бренд-иконок не было в поставке вовсе, все 14 качались из сети.
void main() {
  late Directory tmp;
  late String pathA;
  late String pathB;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_favicon_race');
    AppPaths.overrideRoot(tmp);
    SiteFaviconService.resetCacheForTest();
    // Настоящий PNG: виджет рисует файл только если он существует.
    final png = File('assets/services/youtube.png').readAsBytesSync();
    pathA = '${tmp.path}${Platform.pathSeparator}a.png';
    pathB = '${tmp.path}${Platform.pathSeparator}b.png';
    File(pathA).writeAsBytesSync(png);
    File(pathB).writeAsBytesSync(png);
  });

  tearDown(() {
    SiteFaviconService.resetCacheForTest();
    SiteFaviconService.missTtl = const Duration(minutes: 10);
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SiteFavicon: сторож актуальности', () {
    testWidgets('поздний ответ прежнего домена не затирает иконку текущего',
        (tester) async {
      final pending = <String, Completer<String?>>{
        'a.example': Completer<String?>(),
        'b.example': Completer<String?>(),
      };
      Future<String?> resolve(String domain, {required bool builtIn}) =>
          pending[domain]!.future;

      Widget tree(List<String> domains) => MaterialApp(
            home: Column(
              children: [
                // ⚠️ НАМЕРЕННО БЕЗ КЛЮЧЕЙ: так список сервисов и устроен, и
                // именно поэтому один State успевает поработать на два домена.
                for (final d in domains)
                  SiteFavicon(domain: d, resolver: resolve),
              ],
            ),
          );

      await tester.pumpWidget(tree(['a.example', 'b.example']));
      // Порядок сменился — те же два State теперь под ДРУГИМИ доменами.
      await tester.pumpWidget(tree(['b.example', 'a.example']));

      // Сначала отвечает актуальный домен верхней строки, потом — прежний.
      // Старый код применял оба подряд, и верхняя строка оставалась с чужой
      // иконкой: ровно «три WhatsApp подряд» из жалобы.
      pending['b.example']!.complete(pathB);
      await _settle(tester);
      pending['a.example']!.complete(pathA);
      await _settle(tester);

      final files = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => (i.image as FileImage).file.path)
          .toList();
      expect(files, [pathB, pathA],
          reason: 'каждая строка обязана показать иконку СВОЕГО домена');
    });

    testWidgets('смена домена у одного виджета: старый ответ игнорируется',
        (tester) async {
      final slow = Completer<String?>();
      Future<String?> resolve(String domain, {required bool builtIn}) async {
        if (domain == 'old.example') return slow.future;
        return pathB;
      }

      await tester.pumpWidget(MaterialApp(
        home: SiteFavicon(domain: 'old.example', resolver: resolve),
      ));
      await tester.pumpWidget(MaterialApp(
        home: SiteFavicon(domain: 'new.example', resolver: resolve),
      ));
      await _settle(tester);
      slow.complete(pathA); // ответ прежнего домена пришёл последним
      await _settle(tester);

      final img = tester.widget<Image>(find.byType(Image));
      expect((img.image as FileImage).file.path, pathB);
    });
  });

  group('SiteFavicon: иконка из поставки', () {
    testWidgets('вшитый сервис рисуется ассетом и в сеть не идёт',
        (tester) async {
      var calls = 0;
      Future<String?> resolve(String domain, {required bool builtIn}) async {
        calls++;
        return null;
      }

      await tester.pumpWidget(MaterialApp(
        home: SiteFavicon(
            domain: 'youtube.com', builtIn: true, resolver: resolve),
      ));

      final img = tester.widget<Image>(find.byType(Image));
      expect(
          (img.image as AssetImage).assetName, 'assets/services/youtube.png');
      expect(calls, 0, reason: 'иконка есть в поставке — сеть не нужна');
    });

    testWidgets('домен из правил пользователя ассетом не подменяется',
        (tester) async {
      var asked = 0;
      Future<String?> resolve(String domain, {required bool builtIn}) async {
        asked++;
        return null;
      }

      // Тот же домен, но НЕ вшитый: путь прежний, через кэш/сеть.
      await tester.pumpWidget(MaterialApp(
        home: SiteFavicon(domain: 'youtube.com', resolver: resolve),
      ));
      await tester.pump();
      expect(asked, 1);
      expect(find.byIcon(Icons.language), findsOneWidget);
    });

    test('у каждого сервиса свой файл в поставке', () {
      final assets = SiteFaviconService.bundledAssets;
      expect(assets.length, ProbeService.values.length);
      final seen = <String>{};
      for (final s in ProbeService.values) {
        final rel = assets[s.domain];
        expect(rel, isNotNull, reason: 'нет иконки для ${s.label}');
        expect(rel, 'assets/services/${s.name}.png',
            reason: 'имя файла — по имени сервиса, не по домену');
        expect(seen.add(rel!), isTrue, reason: 'иконка ${s.label} не своя');
        final f = File(rel);
        expect(f.existsSync(), isTrue, reason: '$rel нет на диске');
        final bytes = f.readAsBytesSync();
        expect(bytes.length, greaterThan(64), reason: '$rel пустой');
        // Проверяем именно PNG: сервер отдаёт HTML-заглушку с кодом 200, и
        // Flutter показал бы вместо иконки пустоту.
        expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47],
            reason: '$rel не PNG');
        // ⚠️ РАЗМЕР СТЕРЕЖЁМ ОТДЕЛЬНО ОТ ФОРМАТА. Первый заход притащил
        // whatsapp 23×23: формально PNG, а на телефоне (плотность 3×,
        // чип 24 логических px) это мыло вместо логотипа — то же «сломанные
        // иконки», только другой причиной. Ширина и высота лежат в IHDR:
        // байты 16..24, big-endian.
        final head = ByteData.sublistView(bytes, 16, 24);
        final w = head.getUint32(0);
        final h = head.getUint32(4);
        expect(w, greaterThanOrEqualTo(32), reason: '$rel мелкий: $w×$h');
        expect(h, greaterThanOrEqualTo(32), reason: '$rel мелкий: $w×$h');
      }
    });

    test('иконки объявлены в pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/services/'), isTrue,
          reason: 'без строки в pubspec ассеты не попадут в сборку');
    });

    test('www. и регистр не мешают найти иконку', () {
      expect(SiteFaviconService.bundledAsset('WWW.YouTube.com'),
          'assets/services/youtube.png');
      expect(SiteFaviconService.bundledAsset('nalog.ru'), isNull);
    });
  });

  group('SiteFaviconService: промах не залипает навсегда', () {
    // Домен из RFC 2606: в сеть за ним не сходить даже случайно.
    const dead = 'nothing.invalid';

    test('пока срок не вышел — не перепроверяем', () async {
      SiteFaviconService.missTtl = const Duration(minutes: 10);
      expect(await SiteFaviconService.iconFor(dead), isNull);
      _seedCache(tmp, dead);
      expect(await SiteFaviconService.iconFor(dead), isNull,
          reason: 'срок не вышел — лишних походов быть не должно');
    });

    test('после срока пробуем снова и находим', () async {
      SiteFaviconService.missTtl = Duration.zero;
      expect(await SiteFaviconService.iconFor(dead), isNull);
      final seeded = _seedCache(tmp, dead);
      // Старый код клал промах в кэш навсегда и возвращал бы null даже теперь —
      // это и был серый глобус до перезапуска приложения.
      expect(await SiteFaviconService.iconFor(dead), seeded);
    });

    test('исчезнувший файл не остаётся в кэше путём в пустоту', () async {
      SiteFaviconService.missTtl = Duration.zero;
      final seeded = _seedCache(tmp, dead);
      expect(await SiteFaviconService.iconFor(dead), seeded);
      File(seeded).deleteSync();
      expect(await SiteFaviconService.iconFor(dead), isNull);
    });
  });

  group('SiteFaviconService: предел одновременных загрузок', () {
    test('больше ${SiteFaviconService.maxParallel} разом не запускается',
        () async {
      var running = 0;
      var peak = 0;
      final gates = List.generate(8, (_) => Completer<void>());
      final runs = <Future<int>>[];
      for (var i = 0; i < gates.length; i++) {
        runs.add(SiteFaviconService.throttled(() async {
          running++;
          if (running > peak) peak = running;
          await gates[i].future;
          running--;
          return i;
        }));
      }
      // Даём очереди раскрутиться и отпускаем по одному: если бы предел не
      // держался, к этому моменту работали бы все восемь.
      await Future<void>.delayed(Duration.zero);
      expect(peak, SiteFaviconService.maxParallel);
      for (final g in gates) {
        g.complete();
        await Future<void>.delayed(Duration.zero);
      }
      expect(await Future.wait(runs), List.generate(8, (i) => i));
      expect(peak, SiteFaviconService.maxParallel);
    });
  });
}

/// Догоняет отложенную работу: ответ резолвера доезжает до `setState` не за
/// один кадр (цепочка из нескольких микрозадач), и одного `pump` мало — с ним
/// тест зеленел бы и на старом коде, ничего не стережа.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// Кладёт готовую иконку туда, где её ищет `SiteFaviconService._resolve`.
String _seedCache(Directory root, String domain) {
  final dir = Directory('${root.path}${Platform.pathSeparator}site_icons');
  dir.createSync(recursive: true);
  final f = File('${dir.path}${Platform.pathSeparator}$domain.png');
  f.writeAsBytesSync(File('assets/services/youtube.png').readAsBytesSync());
  return f.path;
}
