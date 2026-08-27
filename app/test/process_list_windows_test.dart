import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/process_list_windows.dart';

/// ВЫБОРКА ПРОЦЕССОВ ПО ИМЕНИ — ОСНОВА ПОСТОЯННОГО НАБЛЮДЕНИЯ KILL SWITCH.
///
/// ⚠️ ПОЧЕМУ ЭТО ВООБЩЕ ОТДЕЛЬНЫЙ ВЫЗОВ, А НЕ ФИЛЬТР ПОВЕРХ `enumerate`.
/// Полное перечисление открывает дескриптор и спрашивает полный путь у КАЖДОГО
/// процесса. Один раз при выборе программы это незаметно; наблюдение же живёт всю
/// сессию, и цена превращается в постоянный фон. Снимок отдаёт имя без единого
/// дескриптора, и открывать их приходится только для совпавших.
///
/// ⚠️ ЧТО ЗДЕСЬ ПРОВЕРИТЬ ЧЕСТНО МОЖНО. Список процессов машины — не наши данные:
/// он разный на каждом прогоне. Зато ОДИН процесс мы знаем наверняка — тот, что
/// прямо сейчас исполняет этот тест. На нём и проверяется, что выборка находит
/// живой процесс и отдаёт его настоящий полный путь.
void main() {
  final selfPath = Platform.resolvedExecutable;
  final selfName = selfPath.split(Platform.pathSeparator).last.toLowerCase();

  group('Выборка процессов по имени', () {
    test('пустой набор имён не трогает систему и даёт пустой ответ', () {
      // Подавляющее большинство сессий — правила по полному пути, имён там нет
      // вовсе. Такие сессии не должны платить за наблюдение ни одного вызова.
      expect(ProcessListWindows.matching(const {}), isEmpty);
    });

    test('находит процесс, который сам же и спрашивает', () {
      final found = ProcessListWindows.matching({selfName});
      expect(found, isNotEmpty,
          reason: 'исполняющий тест процесс обязан найтись по своему имени');
      expect(found.map((p) => p.path.toLowerCase()), contains(selfPath.toLowerCase()),
          reason: 'выборка обязана отдавать полный путь, а не имя: правило WFP '
              'строится только из пути');
      for (final p in found) {
        expect(p.name.toLowerCase(), selfName,
            reason: 'чужие имена в выборку попадать не имеют права');
        expect(p.pid, greaterThan(0));
      }
    }, skip: !Platform.isWindows);

    test('несуществующее имя даёт пустой ответ, а не весь список', () {
      // Обратная ошибка страшнее пропуска: набор «всё подряд» превратился бы в
      // блокировку всей машины по правилу, которого человек не задавал.
      expect(ProcessListWindows.matching({'нетакогопроцесса-0000.exe'}), isEmpty);
    }, skip: !Platform.isWindows);

    test('лишние имена в наборе не мешают найти нужное', () {
      final found = ProcessListWindows.matching(
          {selfName, 'нетакогопроцесса-0001.exe', 'нетакогопроцесса-0002.exe'});
      expect(found.map((p) => p.path.toLowerCase()), contains(selfPath.toLowerCase()));
    }, skip: !Platform.isWindows);

    test('один и тот же путь не повторяется дважды', () {
      // Помощник кладёт находки в набор по пути; дубль здесь означал бы лишнее
      // правило WFP на каждый поток снимка.
      final found = ProcessListWindows.matching({selfName});
      final paths = found.map((p) => p.path.toLowerCase()).toList();
      expect(paths.toSet().length, paths.length);
    }, skip: !Platform.isWindows);
  });
}
