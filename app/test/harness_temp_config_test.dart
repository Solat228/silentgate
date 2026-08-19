import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/probe/harness_temp_config.dart';

/// ВРЕМЕННЫЙ КОНФИГ ХАРНЕССА СОДЕРЖИТ ПАРОЛЬ — И ОБЯЗАН ИСЧЕЗАТЬ.
///
/// ⚠️ ЧТО ИМЕННО ОСТАВАЛОСЬ ЛЕЖАТЬ. Проброс-харнесс поднимает на `127.0.0.1`
/// прокси ВНУТРЬ туннеля проверяемого сервера; с 1.4.1 этот вход закрыт
/// паролем, а пароль уезжает в конфиг ядра — обычный JSON в каталоге данных
/// пользователя. На Windows его не удалял никто: ни остановка харнесса, ни
/// откат неудачного запуска. Секрет одноразовый по замыслу — и бессрочный по
/// факту.
///
/// ⚠️ ПОЧЕМУ ЗДЕСЬ НЕТ ЗАПУСКА ХАРНЕССА. Он поднимает настоящий `xray.exe` или
/// `sing-box.exe` и открывает локальный порт — в тесте этого делать нельзя.
/// Поэтому проверяется сама уборка (обычные файловые операции) плюс страж по
/// исходнику: он доказывает, что уборка вызвана на ОБОИХ путях.
void main() {
  group('Уборка', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sg_harness_cfg_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('существующий файл удаляется', () async {
      final f = File('${tmp.path}${Platform.pathSeparator}h.json')
        ..writeAsStringSync('{"pass":"secret"}');
      expect(f.existsSync(), isTrue);
      await deleteHarnessConfig(f.path);
      expect(f.existsSync(), isFalse);
    });

    test('⚠️ второй вызов не бросает — уборка идёт с двух путей', () async {
      // Откат неудачного старта и `stop()` хендла могут сработать оба: сперва
      // ядро не поднялось и файл убрали, потом кто-то позвал остановку. Падение
      // на уборке мусора обрушило бы прогон целиком.
      final f = File('${tmp.path}${Platform.pathSeparator}h.json')
        ..writeAsStringSync('x');
      await deleteHarnessConfig(f.path);
      await deleteHarnessConfig(f.path);
      expect(f.existsSync(), isFalse);
    });

    test('пустой путь и null проглатываются', () async {
      await deleteHarnessConfig(null);
      await deleteHarnessConfig('');
    });

    test('каталог вместо файла не роняет прогон', () async {
      // Ошибка удаления глотается намеренно: убирать мусор ценой падения
      // проверки серверов незачем.
      await deleteHarnessConfig(tmp.path);
      expect(tmp.existsSync(), isTrue);
    });
  });

  group('⚠️ Страж: уборка вызвана на ОБОИХ путях у каждого харнесса', () {
    // Одного вызова мало и это не придирка: `stop()` закрывает нормальный
    // конец прогона, а файл остаётся именно тогда, когда старт УПАЛ после
    // записи, — то есть в самом частом случае отказа. Хендла в этот момент ещё
    // нет, и звать его остановку некому.
    for (final path in const [
      'lib/engine/windows/probe/xray_harness_windows.dart',
      'lib/engine/windows/probe/singbox_harness_windows.dart',
    ]) {
      test('$path убирает конфиг и при остановке, и при сбое старта', () {
        final src = File(path).readAsLinesSync().where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        }).join(String.fromCharCode(10));

        expect(src, contains('writeAsString'),
            reason: 'страж смотрит не на тот файл — конфиг тут не пишется');
        expect('deleteHarnessConfig('.allMatches(src).length, greaterThanOrEqualTo(2),
            reason: 'уборка обязана быть и в stop(), и в откате старта');
        expect(src, contains('rethrow'),
            reason: 'откат обязан ПРОБРАСЫВАТЬ ошибку дальше: проглоченный сбой '
                'старта выдал бы мёртвый харнесс за живой');
      });
    }
  });
}
