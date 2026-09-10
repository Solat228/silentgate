import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/cp866.dart';
import 'package:silentgate/core/platform/network_recovery.dart';

/// БАТНИКИ ВОССТАНОВЛЕНИЯ СЕТИ ЗАПИСАНЫ В CP866, А НЕ В UTF-8.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. До 10.09.2026 `.bat` собирался `writeAsString`, то
/// есть в UTF-8, а внутри — кириллица. `cmd` перечитывает батник по БАЙТОВЫМ
/// СМЕЩЕНИЯМ: на многобайтных символах он сбивается и продолжает исполнение с
/// середины строки. Здесь это не косметика — файл запускается ОТ ИМЕНИ
/// АДМИНИСТРАТОРА и сбрасывает winsock, IP-стек и настройки прокси. Сброс,
/// выполнившийся наполовину, оставляет человека без сети.
///
/// ⚠️ ГЛАВНОЕ: ЭТО СТРАЖ НА ВЫЗОВ, А НЕ НА КОДИРОВЩИК. `Cp866` покрыт своим
/// тестом, и без этого файла он мог бы существовать, быть зелёным и не
/// вызываться — класс бед «написано и не используется» в этом проекте ловили
/// четырежды. Поэтому тест не проверяет функцию, а прогоняет НАСТОЯЩИЙ
/// `NetworkRecovery.run()` и читает БАЙТЫ РЕАЛЬНО ЗАПИСАННОГО ФАЙЛА.
///
/// ⚠️ ПРОГОНЯЮТСЯ ОБА НАБОРА. С 10.09.2026 кнопки две, и батник у каждой свой;
/// проверить один и решить, что «кодировка в порядке», значило бы оставить
/// второй файл без стража ровно в тот момент, когда он появился.
///
/// ⚠️ Подменяется только элевация ([NetworkRecovery.launcherForTests]) — запись
/// остаётся настоящей. `runnerForTests` здесь НЕ годится: он обрывает путь до
/// записи, и байты никто бы не увидел.
void main() {
  /// Байты, которые cp866 разрешает после правки текста батника.
  ///
  /// ⚠️ Дыра 0xB0…0xDF (псевдографика) и хвост 0xF2…0xFF оставлены ЗАПРЕЩЁННЫМИ
  /// намеренно: в тексте батника им взяться неоткуда, зато ведущие байты
  /// UTF-8-кириллицы — это ровно 0xD0/0xD1. Возврат на `writeAsString` попадает
  /// в эту дыру с первой же русской буквы.
  bool allowedByte(int b) =>
      b < 0x80 || // ASCII
      (b >= 0x80 && b <= 0x9F) || // 'А'…'Я'
      (b >= 0xA0 && b <= 0xAF) || // 'а'…'п'
      (b >= 0xE0 && b <= 0xEF) || // 'р'…'я'
      b == 0xF0 || // 'Ё'
      b == 0xF1; // 'ё'

  /// Байты и обстоятельства запуска для одного набора.
  final bytes = <bool, List<int>>{};
  final launches = <bool, int>{false: 0, true: 0};
  final capturedArgs = <bool, String>{};
  var capturedExe = '';

  setUpAll(() async {
    for (final full in const [false, true]) {
      NetworkRecovery.launcherForTests = (exe, args) async {
        launches[full] = launches[full]! + 1;
        capturedExe = exe;
        capturedArgs[full] = args;
        return true;
      };
      final ok = await NetworkRecovery.run(full: full);
      expect(ok, isTrue);
      bytes[full] = await File(NetworkRecovery.batPathFor(full: full))
          .readAsBytes();
    }
  });

  tearDownAll(() async {
    NetworkRecovery.launcherForTests = null;
    for (final full in const [false, true]) {
      final f = File(NetworkRecovery.batPathFor(full: full));
      if (f.existsSync()) await f.delete();
    }
  });

  test('⚠️ у наборов РАЗНЫЕ файлы', () {
    // Один путь на два набора означал бы, что вторая нажатая кнопка
    // перезаписывает батник, который прямо сейчас исполняется под
    // администратором: cmd дочитывает его по смещениям ПО ХОДУ работы и
    // продолжил бы с середины чужой строки.
    expect(NetworkRecovery.batPathFor(full: false),
        isNot(NetworkRecovery.batPathFor(full: true)));
  });

  for (final full in const [false, true]) {
    final name = full ? 'полный сброс' : 'мягкое восстановление';
    final expectedCommands =
        full ? NetworkRecovery.fullCommands : NetworkRecovery.softCommands;

    group('$name: ', () {
      test('run() вообще дошёл до записи и до запуска', () {
        expect(launches[full], 1, reason: 'батник не запускается — кнопка мертва');
        expect(capturedExe, 'cmd.exe');
        expect(capturedArgs[full],
            contains(NetworkRecovery.batPathFor(full: full)));
        expect(bytes[full], isNotEmpty, reason: 'записан пустой .bat');
      });

      test('⚠️ в файле нет ни одного байта вне таблицы cp866', () {
        final bad = <String>[];
        final data = bytes[full]!;
        for (var i = 0; i < data.length; i++) {
          if (!allowedByte(data[i])) {
            bad.add('смещение $i: 0x${data[i].toRadixString(16)}');
          }
        }
        expect(bad, isEmpty,
            reason: 'в .bat просочились байты не из cp866 (скорее всего вернули '
                'writeAsString, и это UTF-8): ${bad.take(5).join(', ')}');
      });

      test('⚠️ русский текст лежит именно в cp866, а не в чём-то похожем', () {
        // «сети» в cp866 — посчитано сторонним кодеком, не этим кодом.
        // Слово есть в заголовке обоих батников.
        const expected = [0xE1, 0xA5, 0xE2, 0xA8];
        expect(_indexOfSub(bytes[full]!, expected), isNonNegative,
            reason: 'слова «сети» в cp866 в файле нет — текст записан другой '
                'кодировкой либо потерян');
      });

      test('⚠️ ни одна кириллическая буква не выродилась в «?»', () {
        // Подстановка `?` безопасна для cmd, но означает НЕЧИТАЕМОЕ сообщение
        // человеку, которому сейчас правят сеть. В тексте батника «?» нет.
        expect(bytes[full], isNot(contains(0x3F)),
            reason: 'символ вне cp866 попал в текст батника и стал «?» — '
                'замените его на ASCII при сборке строк');
      });

      test('CRLF сохранён: каждый перевод строки — пара 0x0D 0x0A', () {
        final data = bytes[full]!;
        expect(_indexOfSub(data, const [0x0D, 0x0A]), isNonNegative,
            reason: 'CRLF пропал — cmd не разберёт файл по строкам');
        for (var i = 0; i < data.length; i++) {
          if (data[i] == 0x0A) {
            expect(i > 0 && data[i - 1] == 0x0D, isTrue,
                reason: 'голый LF на смещении $i');
          }
        }
        expect(data.sublist(data.length - 2), const [0x0D, 0x0A],
            reason: 'последняя строка без CRLF — cmd может её не выполнить');
      });

      test('⚠️ каждая строка будущего батника переживает cp866', () {
        // Гейт на ПРАВКИ ТЕКСТА: тот, кто допишет строку с «…» или неразрывным
        // пробелом, узнает об этом здесь, а не от пользователя.
        for (final line in NetworkRecovery.scriptLinesFor(full: full)) {
          expect(Cp866.isEncodable(line), isTrue,
              reason: 'строка «$line» содержит символ вне cp866 — замените его '
                  'на ASCII, иначе он станет «?» либо (при откате на '
                  'writeAsString) собьёт cmd');
        }
      });

      test('команды набора попали в файл дословно', () {
        for (final cmd in expectedCommands) {
          expect(_indexOfSub(bytes[full]!, cmd.codeUnits), isNonNegative,
              reason: 'команда «$cmd» не дошла до .bat');
        }
      });
    });
  }

  test('⚠️ в батнике МЯГКОГО восстановления опасных команд нет физически', () {
    // Дублирует страж на список — и намеренно. Здесь проверяется не замысел, а
    // то, что реально уедет администратору на исполнение: между списком и
    // файлом стоит сборка строк, и перепутанный там флаг `full` вернул бы
    // человеку ровно тот сброс, от которого его увели.
    final data = bytes[false]!;
    for (final cmd in const [
      'ipconfig /release',
      'netsh winsock reset',
      'netsh int ip reset',
    ]) {
      expect(_indexOfSub(data, cmd.codeUnits), -1,
          reason: 'в батник мягкого восстановления попала опасная команда '
              '«$cmd» — вероятно, перепутан флаг full при сборке строк');
    }
  });

  test('⚠️ перезагрузки требует только батник полного сброса', () {
    // «Перезагрузите компьютер» в конце мягкой чистки кешей — враньё, которое
    // человек выполнит: он перезагрузит машину посреди работы без нужды.
    // Мягкому батнику про перезагрузку сказать можно ровно одно — что она НЕ
    // нужна, и слова «Перезагрузите» там быть не должно.
    const reboot = [
      0x8F, 0xA5, 0xE0, 0xA5, 0xA7, 0xA0, 0xA3, 0xE0, 0xE3, 0xA7, 0xA8, //
      0xE2, 0xA5,
    ]; // «Перезагрузите» в cp866
    expect(_indexOfSub(bytes[true]!, reboot), isNonNegative,
        reason: 'полный сброс не сказал про перезагрузку, а без неё winsock и '
            'IP-стек не сбросятся');
    expect(_indexOfSub(bytes[false]!, reboot), -1,
        reason: 'мягкое восстановление требует перезагрузки, которая ему не '
            'нужна');
  });
}

/// Индекс первого вхождения [needle] в [hay] или -1.
int _indexOfSub(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return i;
  }
  return -1;
}
