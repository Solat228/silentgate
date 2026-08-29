import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/core/platform/rotating_log.dart';

/// ГРАНИЦА КУСКА ПРИ ЖИВОМ ЧТЕНИИ — ТАМ, ГДЕ ПОРЧА ПРОИСХОДИТ РАНЬШЕ ЛЮБОГО
/// РАЗБОРА.
///
/// ⚠️ ЗАЧЕМ ЭТОТ ФАЙЛ ВООБЩЕ ЕСТЬ. Экран логов читает прирост по БАЙТОВОМУ
/// смещению, и кусок мог оборваться посреди строки. Ломались сразу две вещи, и
/// обе — до того, как строку кто-то попытается разобрать:
///
///  1. Многобайтный символ (кириллица — 2 байта, «№» — 2, тире — 3), разрезанный
///     границей куска, превращается в «□» В ОБЕИХ ПОЛОВИНАХ и НЕОБРАТИМО:
///     склейка испорченных половинок целого символа не вернёт. Ни один тест на
///     разбор этого не увидит — он сверяет разбор испорченного текста с самим
///     собой.
///  2. Маска адресов накладывается НА КАЖДЫЙ КУСОК ОТДЕЛЬНО, и адрес своего
///     узла, разрезанный пополам, под неё не попадает — он уезжает на экран
///     открытым.
///
/// Лечение одно: откатывать байтовое смещение до последнего `\n` ДО
/// декодирования. Здесь это проверяется на КАЖДОЙ возможной границе.
void main() {
  late Directory tmp;
  late String path;

  const node = 'de7.node.example';

  /// Эталон: кириллица, «№», длинное тире, адрес из реестра — всё, что рвётся
  /// по-разному.
  const reference = '04.08.2026 01:23:33 [INFO] переключаюсь на $node:443\n'
      '04.08.2026 01:23:34 [WARN] адрес №3 — не ответил\n'
      '04.08.2026 01:23:35 [ERROR] Ошибка: соединение закрыто\n';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_chunk_');
    AppPaths.overrideRoot(tmp);
    path = '${tmp.path}${Platform.pathSeparator}app.log';
    SensitiveAddresses.remember(node);
  });

  tearDown(() async {
    AppPaths.resetForTests();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  final full = utf8.encode(reference);

  test('⚠️ на ЛЮБОЙ границе куски склеиваются в исходный текст', () async {
    for (var k = 0; k <= full.length; k++) {
      // Файл дописан наполовину — ровно то, что видит опрос раз в полсекунды.
      await File(path).writeAsBytes(full.sublist(0, k), flush: true);
      final first = await RotatingLog.readSince(path, 0, wholeLines: true);
      // Писатель дописал остаток.
      await File(path).writeAsBytes(full, flush: true);
      final second =
          await RotatingLog.readSince(path, first.offset, wholeLines: true);

      expect(first.text + second.text, reference,
          reason: 'граница на байте $k потеряла или продублировала текст');
      expect((first.text + second.text).contains('�'), isFalse,
          reason: 'на байте $k разорван многобайтный символ');
    }
  });

  test('⚠️ адрес узла не утекает через границу куска', () async {
    // Маска накладывается на каждый кусок ОТДЕЛЬНО — как на экране логов.
    for (var k = 0; k <= full.length; k++) {
      await File(path).writeAsBytes(full.sublist(0, k), flush: true);
      final first = await RotatingLog.readSince(path, 0, wholeLines: true);
      await File(path).writeAsBytes(full, flush: true);
      final second =
          await RotatingLog.readSince(path, first.offset, wholeLines: true);

      final shown = SensitiveAddresses.mask(first.text) +
          SensitiveAddresses.mask(second.text);
      expect(shown.contains(node), isFalse,
          reason: 'ЗДЕСЬ БЫЛА УТЕЧКА: адрес, разрезанный на байте $k, '
              'не попадал под маску ни в одной половине');
    }
  });

  test('смещение всегда стоит на переводе строки', () async {
    for (var k = 0; k <= full.length; k++) {
      await File(path).writeAsBytes(full.sublist(0, k), flush: true);
      final c = await RotatingLog.readSince(path, 0, wholeLines: true);
      if (c.offset == 0) continue; // целой строки ещё не набралось
      expect(full[c.offset - 1], 0x0a,
          reason: 'на байте $k смещение встало посреди строки');
    }
  });

  test('недописанная строка не отдаётся, но и не теряется', () async {
    // Первая строка ещё без «\n» — показывать её нельзя (см. комментарий у
    // readSince), но следующим опросом она обязана прийти целиком.
    final half = reference.indexOf('\n');
    await File(path).writeAsBytes(full.sublist(0, half), flush: true);
    final first = await RotatingLog.readSince(path, 0, wholeLines: true);
    expect(first.text, isEmpty);
    expect(first.offset, 0, reason: 'смещение двигать нечем — строки нет');

    await File(path).writeAsBytes(full, flush: true);
    final second =
        await RotatingLog.readSince(path, first.offset, wholeLines: true);
    expect(second.text, reference);
  });

  test('разбор куска совпадает с разбором целого текста', () async {
    // Итог всей цепочки: то, что увидит экран, не зависит от того, где
    // прошла граница чтения.
    final whole = reference
        .split('\n')
        .map((l) => parseLogLine(l).text)
        .join('\n');
    for (var k = 0; k <= full.length; k++) {
      await File(path).writeAsBytes(full.sublist(0, k), flush: true);
      final first = await RotatingLog.readSince(path, 0, wholeLines: true);
      await File(path).writeAsBytes(full, flush: true);
      final second =
          await RotatingLog.readSince(path, first.offset, wholeLines: true);
      final glued = (first.text + second.text)
          .split('\n')
          .map((l) => parseLogLine(l).text)
          .join('\n');
      expect(glued, whole, reason: 'граница на байте $k изменила показ');
    }
  });

  test('старое поведение без флага сохранено', () async {
    // ⚠️ Флаг добавлен, а не включён везде: `readSince` зовут и другие места,
    // и менять им поведение молча нельзя.
    await File(path).writeAsBytes(full.sublist(0, 10), flush: true);
    final c = await RotatingLog.readSince(path, 0);
    expect(c.offset, 10);
    expect(c.text.length, greaterThan(0));
  });
}
