import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';

/// Экран логов 29.08.2026: диалог «Очистить все логи» чистит РОВНО отмеченные
/// категории, а «за какой период копятся логи» считается по датам последней
/// записи на диске — оба поведения решает [LogMaintenance]/[LogInventory],
/// без диска тест шёл бы в БОЕВОЙ `%APPDATA%`, поэтому каталог подменяется.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_logclean_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() async {
    AppPaths.resetForTests();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  Future<void> write(String name, String content, {DateTime? at}) async {
    final f = File(p(name));
    await f.writeAsString(content);
    if (at != null) await f.setLastModified(at);
  }

  group('LogInventory — классификация по категориям', () {
    test('app.log, singbox.log и всё остальное расходятся по трём корзинам',
        () async {
      await write('app.log', 'a\n');
      await write('singbox.log', 'b\n');
      await write('singbox.prev.log', 'b-prev\n');
      await write('singbox_proxy.log', 'c\n');
      await write('xray.log', 'd\n');

      final inv = await LogMaintenance.inventory(dir: tmp);

      expect(inv.appLog?.name, 'app.log');
      expect(inv.tunLog?.name, 'singbox.log');
      // Прокси-корзина — ВСЁ, что не app.log и не singbox(.prev).log, включая
      // будущий шестой лог, которого здесь ещё никто не назвал по имени.
      expect(inv.proxyLogs.map((f) => f.name).toSet(),
          {'singbox_proxy.log', 'xray.log'});
      expect(inv.proxyBytes, 'c\n'.length + 'd\n'.length);
    });

    test('категории без файла — null/пусто, а не падение', () async {
      final inv = await LogMaintenance.inventory(dir: tmp);
      expect(inv.appLog, isNull);
      expect(inv.tunLog, isNull);
      expect(inv.proxyLogs, isEmpty);
    });
  });

  group('LogInventory — период накопления', () {
    test('от самой старой до самой новой записи среди логов и отчётов',
        () async {
      final oldest = DateTime(2026, 8, 1, 10);
      final newest = DateTime(2026, 8, 29, 18);
      await write('app.log', 'a\n', at: oldest);
      await write('singbox.log', 'b\n', at: DateTime(2026, 8, 15));

      final reports =
          Directory('${tmp.path}${Platform.pathSeparator}support')
            ..createSync();
      final report = File(
          '${reports.path}${Platform.pathSeparator}r1.txt');
      await report.writeAsString('report');
      await report.setLastModified(newest);

      final inv = await LogMaintenance.inventory(dir: tmp);
      expect(inv.oldest, oldest);
      expect(inv.newest, newest);
      // Включительно: 29.08 минус 01.08 = 28 суток разницы + 1 «свой» день.
      expect(inv.periodDays, 29);
    });

    test('нет ни одного файла — период не определён', () async {
      final inv = await LogMaintenance.inventory(dir: tmp);
      expect(inv.oldest, isNull);
      expect(inv.newest, isNull);
      expect(inv.periodDays, isNull);
    });
  });

  group('LogMaintenance.cleanSelected — удаляется ровно отмеченное', () {
    Future<void> seedAll() async {
      await write('app.log', 'a' * 10);
      await write('singbox.log', 'b' * 20);
      await write('singbox_proxy.log', 'c' * 30);
      await write('xray.log', 'd' * 5);
      final reports =
          Directory('${tmp.path}${Platform.pathSeparator}support')
            ..createSync();
      await File('${reports.path}${Platform.pathSeparator}r1.txt')
          .writeAsString('report');
    }

    test('только tun=true трогает singbox.log и его prev-часть, и ничего больше',
        () async {
      await seedAll();
      await write('singbox.prev.log', 'e' * 7);

      final res = await LogMaintenance.cleanSelected(dir: tmp, tun: true);

      expect(await File(p('singbox.log')).exists(), isFalse);
      expect(await File(p('singbox.prev.log')).exists(), isFalse);
      expect(await File(p('app.log')).exists(), isTrue,
          reason: 'app=false — приложение не должно тронуть чужую категорию');
      expect(await File(p('singbox_proxy.log')).exists(), isTrue);
      expect(await File(p('xray.log')).exists(), isTrue);
      expect(
          await Directory('${tmp.path}${Platform.pathSeparator}support')
              .list()
              .length,
          1,
          reason: 'reports=false — отчёты остаются');
      expect(res.files, 2);
      expect(res.bytes, 20 + 7);
    });

    test('только proxy=true трогает singbox_proxy.log и xray.log, но не singbox.log',
        () async {
      await seedAll();

      final res = await LogMaintenance.cleanSelected(dir: tmp, proxy: true);

      expect(await File(p('singbox_proxy.log')).exists(), isFalse);
      expect(await File(p('xray.log')).exists(), isFalse);
      expect(await File(p('singbox.log')).exists(), isTrue);
      expect(await File(p('app.log')).exists(), isTrue);
      expect(res.files, 2);
      expect(res.bytes, 30 + 5);
    });

    test('только app=true убирает app.log и не трогает остальное', () async {
      await seedAll();

      final res = await LogMaintenance.cleanSelected(dir: tmp, app: true);

      // AppLog в этом тесте НЕ открыт (useFileForTest не звали), поэтому файл
      // просто удаляется файлом — обрезка через владельца проверена отдельно
      // в log_rotation_test.dart («срок хранения свой app.log обрезается»).
      expect(await File(p('app.log')).exists(), isFalse);
      expect(res.files, 1);
      expect(res.bytes, 10);
      expect(await File(p('singbox.log')).exists(), isTrue);
      expect(await File(p('singbox_proxy.log')).exists(), isTrue);
    });

    test('только reports=true стирает папку отчётов и ничего из *.log',
        () async {
      await seedAll();

      final res = await LogMaintenance.cleanSelected(dir: tmp, reports: true);

      expect(
          await Directory('${tmp.path}${Platform.pathSeparator}support')
              .list()
              .length,
          0);
      expect(await File(p('app.log')).exists(), isTrue);
      expect(await File(p('singbox.log')).exists(), isTrue);
      expect(await File(p('singbox_proxy.log')).exists(), isTrue);
      expect(res.files, 1);
    });

    test('ничего не отмечено — ничего не удаляется', () async {
      await seedAll();

      final res = await LogMaintenance.cleanSelected(dir: tmp);

      expect(res.isEmpty, isTrue);
      expect(await File(p('app.log')).exists(), isTrue);
      expect(await File(p('singbox.log')).exists(), isTrue);
      expect(await File(p('singbox_proxy.log')).exists(), isTrue);
      expect(await File(p('xray.log')).exists(), isTrue);
    });

    test('все категории сразу — на диске не остаётся ни лога, ни отчёта',
        () async {
      await seedAll();

      final res = await LogMaintenance.cleanSelected(
          dir: tmp, app: true, tun: true, proxy: true, reports: true);

      expect(await File(p('app.log')).exists(), isFalse);
      expect(await File(p('singbox.log')).exists(), isFalse);
      expect(await File(p('singbox_proxy.log')).exists(), isFalse);
      expect(await File(p('xray.log')).exists(), isFalse);
      expect(
          await Directory('${tmp.path}${Platform.pathSeparator}support')
              .list()
              .length,
          0);
      expect(res.files, 5);
    });
  });
}
