import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';

/// Раскладка портов локального API.
///
/// ⚠️ Порядок обязан быть детерминированным: скрипт хардкодит номер порта, и
/// «дышащая» между запусками раскладка увела бы запрос в другую страну — молча
/// и без единой ошибки.
void main() {
  group('Раскладка', () {
    test('управляющий порт и порт «Прямо» фиксированы', () {
      expect(ApiPorts.control, 10870);
      expect(ApiPorts.direct, 10819);
    });

    test('серверы получают порты по возрастанию ключа', () {
      // Ключи нарочно переданы НЕ по порядку: функция обязана отсортировать их
      // сама, тем же способом, что и ExitOutbounds.build.
      final keys = ['vless://c', 'vless://a', 'vless://b'];
      expect(ApiPorts.forServer(keys, 'vless://a'), 10820);
      expect(ApiPorts.forServer(keys, 'vless://b'), 10821);
      expect(ApiPorts.forServer(keys, 'vless://c'), 10822);
    });

    test('неизвестный ключ порта не получает', () {
      expect(ApiPorts.forServer(['vless://a'], 'vless://zzz'), isNull);
    });

    test('сверх диапазона порта нет', () {
      // 40 портов — 10820..10859. Сорок первый обязан вернуть null, а не 10860:
      // молча заехать в чужой диапазон хуже, чем честно отказать.
      final keys = [for (var i = 0; i < 41; i++) 'vless://${i.toString().padLeft(3, '0')}'];
      expect(ApiPorts.forServer(keys, keys[39]), 10859);
      expect(ApiPorts.forServer(keys, keys[40]), isNull);
    });

    test('пустой список никому ничего не даёт', () {
      expect(ApiPorts.forServer(const [], 'vless://a'), isNull);
    });
  });

  group('Теги инбаундов', () {
    test('тег выводится из ключа и стабилен', () {
      final a = apiExitInboundTag('vless://a');
      expect(a, apiExitInboundTag('vless://a'));
      expect(a, isNot(apiExitInboundTag('vless://b')));
      expect(a, startsWith('api-exit-'));
    });
  });
}
