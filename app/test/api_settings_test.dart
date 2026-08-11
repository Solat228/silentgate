import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Настройки локального API.
///
/// ⚠️ Класс багов, ради которого этот тест существует: поле пишется в toJson,
/// но не читается в fromJson (или наоборот) — и молча сбрасывается при каждом
/// запуске. Компилятор такое не ловит, потому что toJson и fromJson независимы.
void main() {
  group('Умолчания', () {
    test('API выключен, токена нет, серверов нет', () {
      const s = AppSettings();
      expect(s.apiEnabled, isFalse, reason: 'API обязан быть ВЫКЛ по умолчанию');
      expect(s.apiToken, isEmpty);
      expect(s.apiExitServerKeys, isEmpty);
    });
  });

  group('Переживают диск', () {
    test('все три поля возвращаются как есть', () {
      const s = AppSettings(
        apiEnabled: true,
        apiToken: 'abc123',
        apiExitServerKeys: ['vless://a', 'vless://b'],
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.apiEnabled, isTrue);
      expect(back.apiToken, 'abc123');
      expect(back.apiExitServerKeys, ['vless://a', 'vless://b']);
    });

    test('старый файл без полей читается умолчаниями', () {
      final back = AppSettings.fromJson({'captureMode': 'tun'});
      expect(back.apiEnabled, isFalse);
      expect(back.apiToken, isEmpty);
      expect(back.apiExitServerKeys, isEmpty);
    });
  });

  group('copyWith не теряет поля', () {
    test('правка соседнего поля не сбрасывает настройки API', () {
      const s = AppSettings(
          apiEnabled: true, apiToken: 't', apiExitServerKeys: ['k']);
      final next = s.copyWith(killSwitch: true);
      expect(next.apiEnabled, isTrue);
      expect(next.apiToken, 't');
      expect(next.apiExitServerKeys, ['k']);
    });
  });

  group('Требуют переподключения', () {
    test('все три поля названы в reconnectReasons', () {
      // Поля запекаются в конфиг ядра при подъёме. Без строки здесь правка
      // не применялась бы до ручного переподключения, а плашка «переподключитесь»
      // не появлялась бы — пользователь считал бы настройку сломанной.
      const a = AppSettings();
      expect(a.reconnectReasons(a.copyWith(apiEnabled: true)),
          contains('API для автоматизации'));
      expect(a.reconnectReasons(a.copyWith(apiToken: 'x')),
          contains('токен API'));
      expect(a.reconnectReasons(a.copyWith(apiExitServerKeys: ['k'])),
          contains('серверы с отдельным портом'));
    });
  });
}
