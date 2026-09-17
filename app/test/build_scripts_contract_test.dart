import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// СТРАЖ КОНТРАКТА СБОРОЧНЫХ БАТНИКОВ С САЙТОМ.
///
/// ⚠️ РАДИ ЧЕГО. Имена файлов, которые кладут `build-exe.bat`/`build-apk.bat`,
/// нигде не компилируются вместе с `docs/APP_UPDATE_SERVER.md` — это
/// договорённость между текстом и `.bat`-скриптами, которую не видит ни
/// анализатор, ни один из прочих тестов. При выпуске 1.13.0 (10.09.2026) два
/// расхождения (APK без версии в имени, отсутствие портативного архива)
/// нашли и закрыли руками — здесь застолблено, чтобы это не повторялось.
///
/// ⚠️ ВТОРАЯ ПРИЧИНА ЭТОГО ФАЙЛА — CLAUDE.md, правило №3: батники обязаны
/// быть в OEM-кодировке (cp866) с CRLF. `cmd` перечитывает `.bat` по БАЙТОВЫМ
/// смещениям, и на UTF-8 многобайтных символах сбивается — исполнение
/// продолжается с середины строки. Это не ловит ни один текстовый редактор,
/// открывающий файл в «угаданной» кодировке: он покажет читаемый текст и для
/// испорченного файла. Единственная надёжная проверка — прочитать файл как
/// БАЙТЫ и декодировать их сначала как cp866 (должно дать осмысленный
/// русский текст), потом как utf-8 (должно провалиться: если бы файл на
/// самом деле лежал в utf-8, эта проверка стала бы бесполезной).
void main() {
  final apkBat = File('../build-apk.bat');
  final exeBat = File('../build-exe.bat');
  final contract = File('../docs/APP_UPDATE_SERVER.md');

  setUpAll(() {
    expect(apkBat.existsSync(), isTrue,
        reason: 'build-apk.bat — часть поставки, тест обязан его видеть');
    expect(exeBat.existsSync(), isTrue,
        reason: 'build-exe.bat — часть поставки, тест обязан его видеть');
    expect(contract.existsSync(), isTrue,
        reason: 'контракт имён с сайтом — docs/APP_UPDATE_SERVER.md');
  });

  group('кодировка батников (CLAUDE.md, правило №3)', () {
    for (final entry in {'build-apk.bat': apkBat, 'build-exe.bat': exeBat}.entries) {
      final name = entry.key;
      final file = entry.value;

      test('$name — валидный cp866, но НЕ валидный utf-8', () {
        final bytes = file.readAsBytesSync();

        // Любая последовательность байт декодируется как cp866 без ошибки —
        // это однобайтная кодировка без запрещённых значений (0..255 — все
        // валидны). Поэтому доказательство даёт не факт декодирования, а
        // РЕЗУЛЬТАТ: он обязан читаться как связный русский текст.
        final decoded = _decodeCp866(bytes);
        expect(decoded, contains('SilentGate'),
            reason: '$name: декодированный как cp866 текст должен быть осмысленным');
        expect(decoded, contains('pubspec.yaml'),
            reason: '$name: декодированный как cp866 текст должен быть осмысленным');

        // А вот это — настоящая проверка. Если файл был бы пересохранён в
        // utf-8 (частая случайность редактора/агента), он бы остался читаемым
        // как cp866-мусор здесь не провалился бы предыдущий assert случайно —
        // но перестал бы проваливаться utf-8-декод, и мы обязаны это поймать.
        expect(
          () => utf8.decode(bytes, allowMalformed: false),
          throwsFormatException,
          reason: '$name: строгий utf-8-декод обязан падать на кириллице cp866 — '
              'иначе файл только что тихо пересохранили в utf-8, и `cmd` будет '
              'сбоить на многобайтных символах (см. CLAUDE.md, правило №3)',
        );
      });

      test('$name — каждая строка заканчивается CRLF', () {
        final bytes = file.readAsBytesSync();
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] == 0x0A) {
            expect(i > 0 && bytes[i - 1] == 0x0D, isTrue,
                reason: '$name: LF без предшествующего CR на смещении байта $i — '
                    'файл сохранён с LF-концами строк, а не CRLF');
          }
        }
      });
    }
  });

  group('контракт имён артефактов с сайтом (docs/APP_UPDATE_SERVER.md)', () {
    // Таблица контракта — строки 151..154 на момент постановки задачи, но
    // тест читает ИХ ИЗ ДОКУМЕНТА, а не копирует руками: документ обязан
    // остаться источником правды, а не тест.
    final contractText = contract.readAsStringSync();
    final rowPattern = RegExp(r'^\|[^|]*\|\s*`([^`]+)`\s*\|', multiLine: true);
    final patterns = rowPattern
        .allMatches(contractText)
        .map((m) => m.group(1)!)
        .where((p) => p.contains('<версия>'))
        .toList();

    setUpAll(() {
      expect(patterns, isNotEmpty,
          reason: 'не нашли ни одного шаблона имени файла в таблице контракта — '
              'формат таблицы в docs/APP_UPDATE_SERVER.md изменился, тест ослеп');
    });

    test('таблица контракта содержит оба APK и портативный zip', () {
      // Страховка на сам разбор: если кто-то поправит таблицу и уберёт
      // строку — тест обязан упасть здесь, а не молча проверить меньше.
      expect(patterns.any((p) => p.endsWith('-arm64-v8a.apk')), isTrue);
      expect(patterns.any((p) => p.endsWith('-x86_64.apk')), isTrue);
      expect(patterns.any((p) => p.endsWith('.zip')), isTrue);
    });

    test('build-apk.bat переименовывает оба APK с версией по контракту', () {
      final content = _decodeCp866(apkBat.readAsBytesSync());

      // Версия в батнике — переменная %VER%, а не подставленное число: с
      // документом сверяем ФОРМУ имени (плейсхолдер <версия> -> %VER%), а не
      // конкретную версию сборки.
      for (final pattern in patterns.where((p) => p.endsWith('.apk'))) {
        final expected = pattern.replaceAll('<версия>', '%VER%');
        expect(content, contains(expected),
            reason: 'build-apk.bat обязан класть файл по имени "$expected" '
                '(контракт: "$pattern") — иначе сайт получит APK без версии, '
                'как было в релизе 1.13.0, и его придётся переименовывать руками');
      }

      // Версия обязана читаться из pubspec.yaml, а не быть захардкожена.
      expect(content, contains('pubspec.yaml'),
          reason: 'версия артефакта обязана браться из app/pubspec.yaml, '
              'а не быть вписана в батник руками (её пришлось бы держать в двух местах)');
    });

    test('build-exe.bat собирает портативный zip по контракту', () {
      final content = _decodeCp866(exeBat.readAsBytesSync());

      final zipPattern = patterns.firstWhere((p) => p.endsWith('.zip'));
      final expectedZip = zipPattern.replaceAll('<версия>', '%VER%');
      expect(content, contains(expectedZip),
          reason: 'build-exe.bat обязан собирать архив "$expectedZip" '
              '(контракт: "$zipPattern") — раньше сборка портативного архива '
              'не делалась вовсе, хотя приложение портативный режим поддерживает');

      expect(content, contains('Compress-Archive'),
          reason: 'архивирование — через powershell Compress-Archive: AppLocker '
              'на диске I: не пускает .ps1-скрипты, а powershell.exe — не скрипт');

      expect(content, contains('portable.txt'),
          reason: 'маркер портативности (AppPaths.portableMarker) обязан лежать '
              'внутри архива, иначе распакованная версия не узнает себя как портативную');

      // Версия обязана читаться из pubspec.yaml, а не быть захардкожена.
      expect(content, contains('pubspec.yaml'),
          reason: 'версия артефакта обязана браться из app/pubspec.yaml, '
              'а не быть вписана в батник руками (её пришлось бы держать в двух местах)');
    });

    test('маркер portable.txt НЕ копируется в обычный (не портативный) Release', () {
      final content = _decodeCp866(exeBat.readAsBytesSync());

      // ⚠️ Если portable.txt кладётся прямо в %REL%, обычная установка,
      // собранная тем же батником и той же папкой Release, начинает вести
      // себя как портативная (AppPaths._portableBase проверяет только факт
      // существования файла рядом с exe). Ищем ЛЮБУЮ строку записи маркера
      // прямо в переменную REL и требуем, чтобы таких не было.
      final writesMarkerIntoRel = RegExp(
        r'"%REL%\\?[\\/]?portable\.txt"',
        caseSensitive: false,
      );
      expect(writesMarkerIntoRel.hasMatch(content), isFalse,
          reason: 'portable.txt не должен попадать напрямую в %REL% — это папка '
              'обычной сборки, которую использует и инсталлятор; маркер обязан '
              'жить только в промежуточной копии, упаковываемой в zip');
    });
  });
  group('⚠️ Батник не выдаёт старые APK за новую сборку', () {
    // 18.09.2026: Gradle упал (в зеркале не оказалось cores.aar), а батник
    // дошёл до конца, скопировал ПРЕЖНИЕ APK из зеркала и напечатал «ГОТОВО».
    // Бета +78 была бы выдана за эксперимент +79 — на телефон владельца.
    test('после flutter build apk стоит проверка кода возврата', () {
      final content = _decodeCp866(apkBat.readAsBytesSync());
      final lines = content.split(String.fromCharCode(10)).map((l) => l.trimRight()).toList();
      final i = lines.indexWhere((l) => l.contains('build apk --release'));
      expect(i, greaterThanOrEqualTo(0), reason: 'строка сборки APK пропала');
      // В пределах следующих десяти строк обязана быть ветка отказа.
      final after = lines.skip(i + 1).take(10).join(' ');
      expect(after, contains('if errorlevel 1'),
          reason: 'после падения сборки батник снова понесёт старые APK');
      expect(after, contains('exit /b 1'),
          reason: 'ветка отказа обязана завершать батник, а не только ругаться');
    });
  });

}

/// Таблица перекодировки CP866 -> Unicode для байт 0x00..0xFF.
/// Сгенерирована `bytes([b]).decode('cp866')` для каждого b в 0..255 —
/// не переписывать руками, значения совпадают с реальной кодовой страницей.
const _cp866Table = <int>[
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
  48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
  64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
  80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
  96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
  112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127,
  1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055,
  1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071,
  1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087,
  9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488,
  9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575,
  9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600,
  1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103,
  1025, 1105, 1028, 1108, 1031, 1111, 1038, 1118, 176, 8729, 183, 8730, 8470, 164, 9632, 160,
];

String _decodeCp866(List<int> bytes) =>
    String.fromCharCodes(bytes.map((b) => _cp866Table[b]));
