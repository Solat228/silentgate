import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/rotating_log.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Логи: порча нулевыми байтами, потеря строк, размер и срок хранения.
///
/// ⚠️ ВСЁ ЭТО ИЗМЕРЕНО НА ЖИВЫХ ФАЙЛАХ ВЛАДЕЛЬЦА 12.08.2026, а не придумано:
/// `app.log` — 457 КБ, из них 93 % нулевые байты (434 847 подряд) при 218
/// реальных строках; `singbox.log` — 12 МБ и 98 % нулей при 2240 строках.
/// Причина: лог открывался на дозапись (`openWrite(FileMode.append)`), а
/// обрезался (`writeAsString('')`) в ДРУГОМ месте кода. `IOSink` запоминает
/// смещение при открытии и после чужой обрезки пишет по старому адресу —
/// Windows заполняет пропуск нулями.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_logs_');
  });

  tearDown(() async {
    await AppLog.resetFileForTest();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  Future<List<int>> bytesOf(String path) => File(path).readAsBytes();

  int zerosIn(List<int> bytes) => bytes.where((b) => b == 0).length;

  /// ⚠️ Именно utf8.decode, а не `String.fromCharCodes`: наши строки русские, в
  /// UTF-8 они двухбайтовые, и побайтовое «декодирование» превращает их в
  /// мусор — поиск подстроки после него не находит ничего и тест врёт.
  String textOf(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  // ──────────────────────────────────────────────────────────────────────────
  group('порча нулевыми байтами', () {
    test('AppLog.clear() не оставляет нулевых байт: поток пересоздаётся',
        () async {
      final path = p('app.log');
      await AppLog.useFileForTest(path);

      // Пишем достаточно, чтобы смещение потока ушло далеко от нуля: именно на
      // это расстояние Windows и заливала нули после обрезки.
      for (var i = 0; i < 300; i++) {
        AppLog.i('строка номер $i, чтобы файл не был крошечным');
      }
      await AppLog.flushFile();
      expect(await File(path).length(), greaterThan(1000));

      await AppLog.clear();
      AppLog.i('первая строка после очистки');
      await AppLog.flushFile();

      final bytes = await bytesOf(path);
      expect(zerosIn(bytes), 0,
          reason: 'обрезка мимо потока оставляла дыру, забитую нулями: у '
              'владельца так набралось 434 847 нулевых байт в app.log');
      final text = textOf(bytes);
      expect(text.contains('первая строка после очистки'), isTrue,
          reason: 'после очистки запись обязана продолжаться');
      expect(text.contains('строка номер 0'), isFalse,
          reason: 'очистка обязана реально очищать');
    });

    test('RotatingLog.truncate() обрезает и продолжает писать без дыр',
        () async {
      final path = p('core.log');
      final log = RotatingLog(path, maxBytes: 1024 * 1024);
      await log.open();
      for (var i = 0; i < 200; i++) {
        await log.write('строка ядра $i');
      }
      await log.truncate(header: '--- лог начат заново\n');
      await log.write('после обрезки');
      await log.close();

      final bytes = await bytesOf(path);
      expect(zerosIn(bytes), 0);
      final text = textOf(bytes);
      expect(text.contains('--- лог начат заново'), isTrue);
      expect(text.contains('после обрезки'), isTrue);
      expect(text.contains('строка ядра 5'), isFalse);
    });

    test('ротация по порогу не оставляет нулевых байт', () async {
      final path = p('rot.log');
      final log = RotatingLog(path, maxBytes: 300);
      await log.open();
      for (var i = 0; i < 200; i++) {
        await log.write('x' * 40);
      }
      await log.close();

      expect(zerosIn(await bytesOf(path)), 0);
    });

    // Контроль механизма: показывает, ПОЧЕМУ обрезка обязана идти через
    // RotatingLog. Если этот тест однажды перестанет находить нули, значит
    // Dart сменил семантику `FileMode.append` на Windows — и тогда защиту
    // можно пересмотреть, но не раньше.
    test('НАИВНЫЙ способ (обрезка мимо потока) действительно портит файл',
        () async {
      // На POSIX `append` — это O_APPEND, запись всегда идёт в конец файла, и
      // дыры не возникает. Проверяем там, где беда и живёт.
      if (!Platform.isWindows) return;
      final path = p('naive.log');
      final f = File(path);
      await f.writeAsString('');
      final sink = f.openWrite(mode: FileMode.append);
      for (var i = 0; i < 500; i++) {
        sink.writeln('строка $i');
      }
      await sink.flush();
      await f.writeAsString(''); // обрезка МИМО потока — так делал прежний код
      sink.writeln('строка после обрезки');
      await sink.flush();
      await sink.close();

      expect(zerosIn(await bytesOf(path)), greaterThan(0),
          reason: 'ради этого поведения и заведён RotatingLog.truncate()');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('потеря строк', () {
    test('пачка записей подряд доходит до файла целиком', () async {
      final path = p('burst.log');
      await AppLog.useFileForTest(path);

      // ⚠️ Ровно так лог и пишется — синхронно, без await. Прежний `_write`
      // был `async void` и ставил флаг «инициализация начата» ДО своих await:
      // следующие вызовы шли сразу на `_sink?.writeln`, а `_sink` был ещё
      // null. Замер на этой машине: из десяти строк доезжала ОДНА.
      for (var i = 0; i < 200; i++) {
        AppLog.i('LINE$i');
      }
      await AppLog.flushFile();

      final text = await File(path).readAsString();
      final lines =
          text.split('\n').where((l) => l.contains('LINE')).toList();
      expect(lines.length, 200,
          reason: 'ни одна строка не имеет права потеряться на инициализации');
      expect(lines.first.contains('LINE0'), isTrue);
      expect(lines.last.contains('LINE199'), isTrue,
          reason: 'порядок записи обязан сохраняться');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('две копии приложения', () {
    test('гость не обрезает чужой лог и пишет в его конец', () async {
      final path = p('shared.log');
      final owner = RotatingLog(path, maxBytes: 1024 * 1024);
      await owner.open();
      expect(owner.isOwner, isTrue);
      for (var i = 0; i < 50; i++) {
        await owner.write('владелец $i');
      }
      await owner.flush();

      final guest = RotatingLog(path, maxBytes: 1024 * 1024);
      await guest.open();
      expect(guest.isOwner, isFalse,
          reason: 'файл уже ведёт первый экземпляр');

      final sizeBefore = await File(path).length();
      await guest.truncate(header: 'ПОПЫТКА ОБРЕЗКИ\n');
      expect(await File(path).length(), greaterThanOrEqualTo(sizeBefore),
          reason: 'вторая копия обрезала бы лог первой — и её живой поток '
              'залил бы разрыв нулями');

      await guest.write('гость дописал');
      await guest.close();
      await owner.close();

      final bytes = await bytesOf(path);
      expect(zerosIn(bytes), 0);
      final text = textOf(bytes);
      expect(text.contains('владелец 49'), isTrue);
      expect(text.contains('гость дописал'), isTrue);
      expect(text.contains('ПОПЫТКА ОБРЕЗКИ'), isFalse);
    });

    test('после закрытия владельца следующий экземпляр снова владелец',
        () async {
      final path = p('handover.log');
      final first = RotatingLog(path);
      await first.open();
      await first.close();

      final second = RotatingLog(path);
      await second.open();
      expect(second.isOwner, isTrue,
          reason: 'иначе после перезапуска ядра ротация умерла бы навсегда');
      await second.close();
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('срок хранения', () {
    test('настройка переживает сохранение и загрузку', () {
      for (final r in LogRetention.values) {
        final json = const AppSettings().copyWith(logRetention: r).toJson();
        final loaded = AppSettings.fromJson(json);
        expect(loaded.logRetention, r,
            reason: 'поле пишется в toJson, но не читается в fromJson — '
                'выбор пользователя молча возвращается к умолчанию');
      }
    });

    test('умолчание — месяц, «никогда» не даёт срока', () {
      expect(const AppSettings().logRetention, LogRetention.month);
      expect(LogRetention.never.maxAge, isNull);
      expect(LogRetention.day.maxAge, const Duration(days: 1));
      expect(LogRetention.twoWeeks.maxAge, const Duration(days: 14));
      expect(LogRetention.month.maxAge, const Duration(days: 30));
    });

    test('чистка не трогает свежее и не трогает ничего при «никогда»',
        () async {
      // Свой app.log уводим в тестовую папку: иначе чистка сверялась бы с
      // боевым %APPDATA%.
      await AppLog.useFileForTest(p('app.log'));
      final old = DateTime.now().subtract(const Duration(days: 40));

      final staleLog = File(p('singbox.log'))..writeAsStringSync('x' * 500);
      staleLog.setLastModifiedSync(old);
      final freshLog = File(p('xray.log'))..writeAsStringSync('y' * 100);

      final reports = Directory('${tmp.path}${Platform.pathSeparator}support')
        ..createSync();
      final staleReport = File(
          '${reports.path}${Platform.pathSeparator}report-old.txt')
        ..writeAsStringSync('z' * 300);
      staleReport.setLastModifiedSync(old);
      final freshReport = File(
          '${reports.path}${Platform.pathSeparator}report-new.txt')
        ..writeAsStringSync('w' * 200);

      final nothing =
          await LogMaintenance.clean(maxAge: null, dir: tmp);
      expect(nothing.isEmpty, isTrue,
          reason: '«Никогда не удалять» обязано означать именно это');
      expect(staleLog.existsSync(), isTrue);
      expect(staleReport.existsSync(), isTrue);

      final done = await LogMaintenance.clean(
          maxAge: const Duration(days: 30), dir: tmp);
      expect(done.files, 2, reason: 'удаляются только просроченные');
      expect(done.bytes, 800);
      expect(staleLog.existsSync(), isFalse);
      expect(staleReport.existsSync(), isFalse);
      expect(freshLog.existsSync(), isTrue);
      expect(freshReport.existsSync(), isTrue);
    });

    test('свой app.log обрезается, а не удаляется', () async {
      final path = p('app.log');
      await AppLog.useFileForTest(path);
      AppLog.i('старая запись');
      await AppLog.flushFile();
      File(path).setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 40)));

      final res =
          await LogMaintenance.clean(maxAge: const Duration(days: 1), dir: tmp);
      expect(res.files, 1);
      // ⚠️ Именно обрезка: удалить файл, в который открыт поток, значит снова
      // получить дыру от нуля до его смещения.
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), 0);

      AppLog.i('после чистки');
      await AppLog.flushFile();
      expect(zerosIn(await bytesOf(path)), 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('перепись: размер и строки', () {
    test('считает размер, строки и нулевые байты каждого лога', () async {
      File(p('a.log')).writeAsStringSync('первая\nвторая\nтретья\n');
      // Файл без перевода строки в конце — его последняя строка тоже строка.
      File(p('b.log')).writeAsStringSync('одна строка');
      File(p('c.txt')).writeAsStringSync('не лог, в перепись не попадает');
      File(p('holes.log')).writeAsBytesSync([65, 0, 0, 10, 66, 10]);

      final reports = Directory('${tmp.path}${Platform.pathSeparator}support')
        ..createSync();
      File('${reports.path}${Platform.pathSeparator}r1.txt')
          .writeAsStringSync('12345');
      File('${reports.path}${Platform.pathSeparator}r2.txt')
          .writeAsStringSync('123');

      final inv = await LogMaintenance.inventory(dir: tmp);
      final names = inv.logs.map((f) => f.name).toList();
      expect(names, ['a.log', 'b.log', 'holes.log'],
          reason: 'перепись собирается по маске *.log, а не по списку имён: '
              'список устареет с шестым логом, и он молча выпадет из отчёта');

      final a = inv.logs.firstWhere((f) => f.name == 'a.log');
      expect(a.lines, 3);
      expect(a.zeros, 0);

      final b = inv.logs.firstWhere((f) => f.name == 'b.log');
      expect(b.lines, 1);
      expect(b.bytes, 21, reason: 'кириллица в UTF-8 двухбайтовая');

      final holes = inv.logs.firstWhere((f) => f.name == 'holes.log');
      expect(holes.zeros, 2,
          reason: 'нули считаются, чтобы возврат порчи был виден в отчёте, '
              'а не через год по жалобе');

      expect(inv.reportCount, 2);
      expect(inv.reportBytes, 8);
    });
  });
}
