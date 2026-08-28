import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/util/country_flag.dart';

/// Дефект: в имени сервера бывает ДВА флага подряд (мост — страна входа и
/// страна выхода), а `isoFromName` брал только первый и на этом `return`-ился.
/// `isoCodesFromName` должен находить оба, а старый `isoFromName` — остаться
/// обёрткой над первым (на него завязаны другие экраны).
void main() {
  group('FlagUtil.isoCodesFromName', () {
    test('один флаг — один код', () {
      expect(FlagUtil.isoCodesFromName('🇳🇱 Amsterdam'), ['NL']);
    });

    test('два флага подряд — оба кода по порядку', () {
      // Мост: вход через NL, выход через CZ.
      expect(FlagUtil.isoCodesFromName('🇳🇱🇨🇿 Bridge'), ['NL', 'CZ']);
    });

    test('два флага с текстом между ними — оба кода', () {
      expect(FlagUtil.isoCodesFromName('🇳🇱 -> 🇨🇿 Bridge'), ['NL', 'CZ']);
    });

    test('без флагов — пусто', () {
      expect(FlagUtil.isoCodesFromName('Plain server name'), isEmpty);
    });

    test('одна одинокая руна regional indicator — пусто, не мусор', () {
      // Один regional indicator без пары не должен склеиваться со следующей
      // обычной руной в мусорный "код".
      expect(FlagUtil.isoCodesFromName('🇳 Amsterdam'), isEmpty);
    });

    test('три флага подряд — не больше двух', () {
      expect(FlagUtil.isoCodesFromName('🇳🇱🇨🇿🇩🇪 Triple'), ['NL', 'CZ']);
    });

    test('индекс после найденной пары двигается на i+2, а не i+1', () {
      // Если бы после первой пары (NL) курсор сдвигался всего на 1, вторая
      // "пара" собралась бы из второй руны NL и первой руны CZ — мусор.
      // Проверяем, что результат именно NL/CZ, а не что-то третье.
      final codes = FlagUtil.isoCodesFromName('🇳🇱🇨🇿');
      expect(codes, ['NL', 'CZ']);
    });
  });

  group('FlagUtil.isoFromName (обратная совместимость)', () {
    test('по-прежнему отдаёт первый код при одном флаге', () {
      expect(FlagUtil.isoFromName('🇳🇱 Amsterdam'), 'NL');
    });

    test('по-прежнему отдаёт первый код при двух флагах', () {
      expect(FlagUtil.isoFromName('🇳🇱🇨🇿 Bridge'), 'NL');
    });

    test('null при отсутствии флагов', () {
      expect(FlagUtil.isoFromName('Plain server name'), isNull);
    });
  });
}
