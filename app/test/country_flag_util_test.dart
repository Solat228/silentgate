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

  /// Решение владельца 25.09.2026: в тексте у имени сервера флаг либо
  /// картинка ([FlagText]), либо (если уже показан в [FlagCell] рядом) вырезан
  /// целиком — никогда не буквы кода страны. `stripIconFlags` обязан резать
  /// РОВНО те пары, что `isoCodesFromName` берёт себе (первые две) — общий
  /// проход `_scanFirstTwoPairs` гарантирует, что выбор не разойдётся.
  group('FlagUtil.stripIconFlags', () {
    test('без флагов — текст как есть', () {
      expect(FlagUtil.stripIconFlags('Plain server name'), 'Plain server name');
    });

    test('один флаг — вырезается целиком', () {
      expect(FlagUtil.stripIconFlags('🇳🇱 Amsterdam'), 'Amsterdam');
    });

    test('два флага подряд — оба вырезаются', () {
      expect(FlagUtil.stripIconFlags('🇳🇱🇨🇿 Bridge'), 'Bridge');
    });

    test('третий флаг остаётся в тексте — его FlagCell не рисует', () {
      // FlagCell показывает только первые два (isoCodesFromName), третий и
      // далее обязаны уцелеть в тексте и достаться FlagText как картинка.
      expect(FlagUtil.stripIconFlags('🇳🇱🇨🇿🇩🇪 Triple'), '🇩🇪 Triple');
    });

    test('флаг в середине имени — вырезается, соседний текст схлопывается',
        () {
      expect(FlagUtil.stripIconFlags('Node 🇳🇱 premium'), 'Node premium');
    });

    test('два флага в середине и в конце — оба вырезаются', () {
      expect(FlagUtil.stripIconFlags('Bridge 🇳🇱 -> 🇨🇿 edge'), 'Bridge -> edge');
    });

    test('обычные эмодзи (не regional-indicator) не трогаются', () {
      // 🚀 и 🏳️ не собраны из пары regional-indicator — это не флаг-пара
      // в смысле [FlagUtil], значит вырезать нечего.
      expect(FlagUtil.stripIconFlags('🚀Германия 2.7 (edge)'),
          '🚀Германия 2.7 (edge)');
      expect(FlagUtil.stripIconFlags('🏳️ White flag'), '🏳️ White flag');
    });

    test('флаг рядом с обычным эмодзи — вырезается только сам флаг', () {
      expect(FlagUtil.stripIconFlags('🇩🇪 🚀Германия 2.7 (edge)'),
          '🚀Германия 2.7 (edge)');
    });

    test('одинокая непарная руна indicator не вырезается как мусор', () {
      expect(FlagUtil.stripIconFlags('🇳 Amsterdam'), '🇳 Amsterdam');
    });
  });
}
