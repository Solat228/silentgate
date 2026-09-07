import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/log_archive.dart';

/// НАСТРОЙКА ОБЕЩАЛА СРОК ХРАНЕНИЯ, А ХРАНЕНИЯ НЕ БЫЛО.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 07.09.2026: «разве не для этого мы делали ротацию логов
/// с отсрочками в день, неделю, месяц и навсегда? Хочешь сказать, там всё
/// затёрлось нахуй?»
///
/// Затёрлось. `LogRetention` и `LogMaintenance` в проекте есть, и я сгоряча
/// заявил обратное — за это отдельно стыдно. Но делали они не то, что обещает
/// настройка: `clean()` УДАЛЯЕТ файлы, которым давно не писали, а
/// `RotatingLog` при переполнении сдвигает текущий в единственный `.prev.log`.
///
/// Из этого следует беда, которую владелец и увидел: **активный файл никогда
/// не стареет**, потому что в него пишут постоянно. Удалять нечего, архивов не
/// образуется, и «хранить месяц» на деле означает «хранить последние восемь
/// мегабайт». У `singbox.log` при `debug` это сорок минут.
///
/// Практическая цена уже уплачена: у владельца на Wi-Fi отваливалась половина
/// сайтов, он перезагрузился — и разбирать стало нечего.
///
/// ⚠️ ЧТО ИМЕННО ПРОВЕРЯЕТСЯ ЗДЕСЬ. Не «удаляется ли старое» (это умели и
/// раньше), а появляется ли ИСТОРИЯ: датированный архив за прошлые сутки,
/// который переживает перезапуск и не затирается следующей записью.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sg_log_archive_');
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File log(String name, {required DateTime modified, String body = 'строка\n'}) {
    final f = File('${root.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(body);
    f.setLastModifiedSync(modified);
    return f;
  }

  group('⚠️ Датированный архив за прошлые сутки', () {
    test('при смене суток текущий лог уезжает в архив, а не затирается',
        () async {
      final now = DateTime(2026, 9, 7, 10, 0);
      final f = log('app.log',
          modified: now.subtract(const Duration(days: 1)),
          body: 'вчерашняя запись\n');

      final moved = await LogArchive.rollDaily(dir: root, now: now);
      expect(moved, isNotEmpty, reason: 'ничего не заархивировано');

      // Исходный файл освобождён под новые записи…
      expect(f.existsSync(), isFalse);
      // …а вчерашнее содержимое лежит под своей датой.
      final arch = File('${root.path}${Platform.pathSeparator}'
          '${LogArchive.dirName}${Platform.pathSeparator}app-2026-09-06.log');
      expect(arch.existsSync(), isTrue,
          reason: 'архива за вчера нет — история снова потеряна');
      expect(arch.readAsStringSync(), contains('вчерашняя запись'));
    });

    test('в те же сутки ничего не двигаем', () async {
      // Иначе каждый запуск приложения плодил бы огрызки, и «день истории»
      // распадался бы на два десятка файлов по паре килобайт.
      final now = DateTime(2026, 9, 7, 15, 0);
      log('app.log', modified: DateTime(2026, 9, 7, 9, 0));
      final moved = await LogArchive.rollDaily(dir: root, now: now);
      expect(moved, isEmpty);
    });

    test('⚠️ второй архив за те же сутки не затирает первый', () async {
      // Логов ядра за день бывает несколько частей (порог 8 МиБ), и совпадение
      // имён уничтожило бы ровно то, ради чего архив заводится.
      final now = DateTime(2026, 9, 7, 10, 0);
      final yesterday = now.subtract(const Duration(days: 1));
      log('singbox.log', modified: yesterday, body: 'часть первая\n');
      await LogArchive.rollDaily(dir: root, now: now);
      log('singbox.log', modified: yesterday, body: 'часть вторая\n');
      await LogArchive.rollDaily(dir: root, now: now);

      final dir = Directory(
          '${root.path}${Platform.pathSeparator}${LogArchive.dirName}');
      final names = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('singbox-'))
          .toList();
      expect(names, hasLength(2),
          reason: 'второй архив затёр первый: $names');
      final bodies = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join();
      expect(bodies, contains('часть первая'));
      expect(bodies, contains('часть вторая'));
    });

    test('пустой лог в архив не едет', () async {
      // Пустой файл — это не история, а мусор в списке.
      final now = DateTime(2026, 9, 7, 10, 0);
      log('xray.log',
          modified: now.subtract(const Duration(days: 2)), body: '');
      final moved = await LogArchive.rollDaily(dir: root, now: now);
      expect(moved, isEmpty);
    });
  });

  group('⚠️ Срок хранения применяется К АРХИВАМ', () {
    test('старше срока — удаляются, свежие остаются', () async {
      final now = DateTime(2026, 9, 7, 12, 0);
      final dir = Directory(
          '${root.path}${Platform.pathSeparator}${LogArchive.dirName}')
        ..createSync(recursive: true);
      File mk(String name, int daysAgo) {
        final f = File('${dir.path}${Platform.pathSeparator}$name')
          ..writeAsStringSync('x');
        f.setLastModifiedSync(now.subtract(Duration(days: daysAgo)));
        return f;
      }

      final fresh = mk('app-2026-09-06.log', 1);
      final old = mk('app-2026-08-01.log', 37);

      final res =
          await LogArchive.prune(dir: root, maxAge: const Duration(days: 30), now: now);
      expect(res.files, 1, reason: 'удалили не то количество');
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue,
          reason: 'снесли архив внутри срока хранения');
    });

    test('«навсегда» не удаляет ничего', () async {
      final now = DateTime(2026, 9, 7, 12, 0);
      final dir = Directory(
          '${root.path}${Platform.pathSeparator}${LogArchive.dirName}')
        ..createSync(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}app-2020-01-01.log')
        ..writeAsStringSync('x');
      f.setLastModifiedSync(DateTime(2020, 1, 1));

      final res = await LogArchive.prune(dir: root, maxAge: null, now: now);
      expect(res.files, 0);
      expect(f.existsSync(), isTrue,
          reason: '«навсегда» обязано означать навсегда');
    });
  });

  test('⚠️ архив СДВИГАЕТСЯ на запуске, а не просто умеет сдвигаться', () {
    // Тот же класс бед, что в этом проекте ловили четырежды: код написан,
    // покрыт тестами и не вызывается ниоткуда. Здесь цена особенно высока —
    // молчаливое невыполнение неотличимо от исправной работы ровно до того
    // дня, когда история понадобится.
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('LogArchive.rollDaily('),
        reason: 'сдвиг в архив не вызывается — истории снова не будет');
    expect(src, contains('LogArchive.prune('),
        reason: 'срок хранения к архивам не применяется — они будут копиться '
            'вечно при любой настройке');
  });
}
