import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/rotating_log.dart';

/// Две копии приложения пишут в ОДИН файл лога.
///
/// ⚠️ ЭТО НЕ ВЫДУМАННЫЙ СЦЕНАРИЙ. У владельца запущены два экземпляра
/// SilentGate одновременно, и оба ведут `%APPDATA%\SilentGate\*.log`. Ровно на
/// этом файл и портился: 69 % байтов `singbox.log` оказались НУЛЯМИ.
///
/// Разбор 1.4.1 объяснил порчу так: поток открыт на дозапись в одном месте, а
/// обрезается в другом — смещение остаётся старым, и Windows заливает разрыв
/// нулями. Правка развела роли: владелец держит поток, гость дописывает каждую
/// строку отдельным открытием.
///
/// Здесь проверяется ВТОРАЯ половина того же утверждения, которую легко принять
/// на веру: не затирает ли поток ВЛАДЕЛЬЦА строки, дописанные гостем между его
/// записями. Ответ должен быть получен опытом, а не рассуждением о семантике
/// `FileMode.append`.
void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sg_log_two_copies');
    path = '${dir.path}${Platform.pathSeparator}app.log';
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('строки гостя не затираются потоком владельца', () async {
    final owner = RotatingLog(path, maxBytes: 1 << 20);
    await owner.open();
    await owner.write('владелец-1');

    // Вторая копия приложения: дописывает своим открытием файла.
    await File(path).writeAsString('гость-1\n', mode: FileMode.append);

    await owner.write('владелец-2');
    await owner.close();

    final bytes = await File(path).readAsBytes();
    final text = utf8.decode(bytes);

    expect(bytes.where((b) => b == 0), isEmpty,
        reason: 'нулевые байты — это и есть та самая порча лога');
    expect(text, contains('владелец-1'));
    expect(text, contains('владелец-2'));
    expect(text, contains('гость-1'),
        reason: 'строку второй копии затёрло смещение потока владельца');
  });

  test('гость не заливает нулями файл, обрезанный владельцем', () async {
    // Обратное направление той же беды: владелец обрезал файл по превышению
    // объёма, а гость продолжает писать со своим прежним представлением о
    // размере.
    final owner = RotatingLog(path, maxBytes: 64);
    await owner.open();
    for (var i = 0; i < 20; i++) {
      await owner.write('строка-владельца-$i');
    }
    await File(path).writeAsString('гость-после-обрезки\n',
        mode: FileMode.append);
    await owner.write('владелец-после-гостя');
    await owner.close();

    final bytes = await File(path).readAsBytes();
    expect(bytes.where((b) => b == 0), isEmpty,
        reason: 'обрезка при живом потоке — исходная причина порчи');
    // ⚠️ Строку гостя тут проверять НЕЛЬЗЯ: порог 64 байта, и усечение
    // законно снесло всё старое. Значимо ровно одно — что усечение при живой
    // записи второй копии не оставило нулевых байтов.
    expect(utf8.decode(bytes), isNotEmpty);
  });
}
