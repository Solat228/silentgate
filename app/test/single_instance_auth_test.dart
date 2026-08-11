import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/single_instance.dart';

/// Порт single-instance принимал произвольную строку без аутентификации.
///
/// ⚠️ Это тот самый «путь БЕЗ подтверждения пользователя», который владелец
/// сам записал условием пересмотра принятого риска url-схем: через браузер
/// переход подтверждает человек, а через сокет — никто. Любой локальный
/// процесс мог переключить сервер или подменить подписку.
void main() {
  group('Разбор сообщения', () {
    test('строка с токеном разбирается на две части', () {
      final m = SingleInstance.splitMessage('tok123\nsilentgate://connect');
      expect(m.token, 'tok123');
      expect(m.url, 'silentgate://connect');
    });

    test('строка без перевода строки — это просто ссылка', () {
      final m = SingleInstance.splitMessage('silentgate://import?url=https://x');
      expect(m.token, isNull);
      expect(m.url, 'silentgate://import?url=https://x');
    });
  });

  group('Что требует токена', () {
    test('команды управления требуют', () {
      for (final a in ['connect', 'disconnect', 'toggle', 'update']) {
        expect(SingleInstance.needsToken('silentgate://$a'), isTrue,
            reason: '$a обязано требовать токен');
      }
    });

    test('⚠️ импорт НЕ требует — его инициировал человек', () {
      // Второй экземпляр приложения передаёт ссылку, по которой пользователь
      // щёлкнул в браузере или проводнике. Сломать этот путь нельзя.
      expect(SingleInstance.needsToken('silentgate://import?url=https://x'),
          isFalse);
      expect(SingleInstance.needsToken('https://panel.example/sub/abc'),
          isFalse);
    });
  });
}
