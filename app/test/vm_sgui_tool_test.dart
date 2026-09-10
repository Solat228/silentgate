import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// СТРАЖ ОСНАСТКИ ЖИВОЙ ПРОВЕРКИ (`tools/vm/sgui.ps1`).
///
/// ⚠️ РАДИ ЧЕГО. Этой оснасткой снимается интерфейс внутри гостя `SG-Test` —
/// то есть ею добывается ЕДИНСТВЕННОЕ доказательство, что вёрстка на самом
/// деле в порядке. У неё был дефект: холст снимка брался по КЛИЕНТСКОЙ области
/// (`GetClientRect`), а `PrintWindow` рисует окно ЦЕЛИКОМ, вместе с заголовком.
/// Каждый снимок терял нижние ~31 px, обрезанная последняя строка выглядела как
/// дефект вёрстки, и 10.09.2026 на этом чуть не завели ложную находку «низ
/// главного экрана снова не влезает».
///
/// ⚠️ Цена такого дефекта выше обычной: инструмент измерения, который врёт,
/// уводит работу в несуществующие баги — и одновременно прячет настоящие.
///
/// Проверяется текстом, как `installer_test.dart` разбирает `.iss`: PowerShell
/// не компилируется вместе с Dart, договорённость между ними не заметит ни
/// компилятор, ни анализатор, ни один из остальных тестов.
void main() {
  final script = File('../tools/vm/sgui.ps1');
  final text = script.existsSync() ? script.readAsStringSync() : '';

  setUpAll(() {
    expect(script.existsSync(), isTrue,
        reason: 'оснастка живой проверки пропала из репозитория — снимать '
            'интерфейс в VM станет нечем');
  });

  /// Тело одного обработчика команды из `switch`: от строки `'<имя>' {` до
  /// следующей такой же метки.
  ///
  /// ⚠️ Разбирается именно ТЕЛО, а не весь файл. `GetClientRect` в файле есть
  /// законно — им отсеиваются служебные окна нулевого размера в
  /// `Find-AppWindow`, — и поиск по всему тексту зеленел бы при любом дефекте.
  String handler(String name) {
    final lines = text.split(RegExp(r'\r?\n'));
    final label = RegExp("^\\s*'([a-z]+)'\\s*\\{");
    final start = lines.indexWhere((l) {
      final m = label.firstMatch(l);
      return m != null && m.group(1) == name;
    });
    expect(start, greaterThanOrEqualTo(0),
        reason: 'команды «$name» в оснастке больше нет');
    var end = lines.length;
    for (var i = start + 1; i < lines.length; i++) {
      if (label.hasMatch(lines[i]) ||
          lines[i].trimLeft().startsWith('default')) {
        end = i;
        break;
      }
    }
    // ⚠️ БЕЗ КОММЕНТАРИЕВ, И ЭТО НЕ ПРИДИРКА. Оба разобранных дефекта описаны
    // в самой оснастке — прямо в теле обработчиков стоят предупреждения вида
    // «здесь стоял `GetClientRect`». Проверяй мы текст с комментариями,
    // страж краснел бы на исправном файле именно из-за объяснения, почему он
    // исправен, — и первым же побуждением было бы стереть объяснение.
    return lines
        .sublist(start, end)
        .where((l) => !l.trimLeft().startsWith('#'))
        .join(String.fromCharCode(10));
  }

  test('⚠️ снимок берёт ОКОННЫЙ прямоугольник, а не клиентский', () {
    final shot = handler('shot');
    expect(shot, contains('GetWindowRect'),
        reason: 'холст снимка снова считается не по тому прямоугольнику — '
            'каждый снимок потеряет высоту заголовка снизу, и обрезанная '
            'последняя строка будет выглядеть дефектом вёрстки');
    expect(shot.contains('GetClientRect'), isFalse,
        reason: 'в обработчике `shot` вернулся `GetClientRect`: `PrintWindow` '
            'рисует окно ЦЕЛИКОМ, и низ снимка снова начнёт пропадать');
  });

  test('⚠️ клик считает те же координаты, что видны на снимке', () {
    // Тот же дефект с другого конца: пиксель (x,y) на картинке отсчитывается
    // от угла ОКНА. Считать его клиентским значит промахиваться на высоту
    // заголовка вниз — молча, при исправном на вид журнале.
    final click = handler('click');
    expect(click, contains('GetWindowRect'));
    expect(click.contains('ClientToScreen'), isFalse,
        reason: 'клик снова пересчитывается через клиентскую область и будет '
            'уезжать ниже цели');
  });

  test('команды cmdid, use и resize на месте', () {
    // Каждая нужна для проверки, которую иначе не сделать вовсе:
    // `resize` — снять вёрстку на минимальном окне (по умолчанию оно больше и
    // беду скрывает), `use` — переключиться на чужое окно (диалог
    // установщика), `cmdid` — нажать кнопку диалога там, где ввод не доходит.
    for (final name in ['cmdid', 'use', 'resize']) {
      expect(() => handler(name), returnsNormally);
    }
    expect(handler('resize'), contains('MoveWindow'),
        reason: '`resize` перестал менять размер окна');
    expect(handler('cmdid'), contains('0x0111'),
        reason: '`cmdid` больше не шлёт WM_COMMAND — нажать кнопку диалога в '
            'госте без VMConnect станет нечем');
    expect(handler('use'), contains('Find-AppWindow'),
        reason: '`use` перестал искать окно другого процесса');
  });
}
