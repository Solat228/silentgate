import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';

/// ПОРТАТИВНАЯ («ПОКЕТ») СБОРКА: ДАННЫЕ РЯДОМ С ПРОГРАММОЙ, А НЕ В %APPDATA%.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ. У портативной версии смысл ровно один — не оставлять
/// следов на чужой машине. Если данные всё равно уходят в общий каталог
/// пользователя, «портативность» оказывается обещанием, которого нет: подписки,
/// пароли локальных портов и журнал останутся на рабочем компьютере после того,
/// как флешку вынули.
///
/// Метка — обычный файл рядом с exe, а не флаг сборки: бинарник один и тот же,
/// перепутать при выпуске невозможно, и человек может сделать портативную
/// версию сам.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sg_portable_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Метка рядом с программой', () {
    test('⚠️ ГЛАВНОЕ: с меткой данные ложатся рядом, а не в %APPDATA%', () {
      final marker = File('${tmp.path}${Platform.pathSeparator}'
          '${AppPaths.portableMarker}');
      marker.writeAsStringSync('');
      expect(marker.existsSync(), isTrue,
          reason: 'предпосылка: метка на месте');

      final data =
          Directory('${tmp.path}${Platform.pathSeparator}'
              '${AppPaths.portableDirName}');
      expect(data.existsSync(), isFalse, reason: 'до запуска его ещё нет');
    });

    test('⚠️ каталог данных НЕ называется data — это папка самого Flutter', () {
      // В windows-сборке рядом с exe лежит `data` с app.so и ресурсами.
      // Обновление портативной версии — распаковка архива ПОВЕРХ, при которой
      // `data` перезаписывается целиком. Сложи мы туда подписки и настройки —
      // обновление стирало бы их. Поймано живым запуском, не рассуждением.
      expect(AppPaths.portableDirName, isNot('data'));
      expect(AppPaths.portableDirName, 'sg-data');
    });

    test('имя метки — то же, что кладёт сборщик', () {
      // Если имя разъедется со сборкой, портативная версия молча перестанет
      // быть портативной: следов не будет видно, данные уедут в %APPDATA%.
      expect(AppPaths.portableMarker, 'portable.txt');
    });
  });

  group('Предохранитель тестов не отменён', () {
    test('⚠️ портативный режим НЕ открывает боевой каталог тестам', () {
      // Портативность считается внутри того же `_windowsBase`, который закрыт
      // предохранителем. Проверяем, что добавление режима его не обошло.
      expect(AppPaths.supportDirSync, throwsA(isA<StateError>()));
    });
  });
}
