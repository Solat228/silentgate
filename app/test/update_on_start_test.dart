import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Обновление подписки при запуске приложения.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНАЯ НАСТРОЙКА, ЕСЛИ ЕСТЬ АВТООБНОВЛЕНИЕ. Автообновление
/// работает по ТАЙМЕРУ (по умолчанию 12 часов) и между запусками ничего не
/// гарантирует: открыл приложение через сутки — список серверов и остаток
/// трафика показывались прошлые, пока не подойдёт срок или пока не нажмёшь
/// «Обновить» руками. Владелец попросил тянуть подписку на каждом запуске.
void main() {
  group('Умолчание', () {
    test('включено — прямое решение владельца', () {
      expect(const AppSettings().updateSubscriptionOnStart, isTrue);
    });
  });

  group('Переживает диск', () {
    test('выключенная настройка не включается сама при чтении', () {
      const s = AppSettings(updateSubscriptionOnStart: false);
      expect(AppSettings.fromJson(s.toJson()).updateSubscriptionOnStart, isFalse,
          reason: 'класс багов: поле пишется в toJson, но не читается обратно');
    });

    test('старый файл без поля читается умолчанием', () {
      expect(
          AppSettings.fromJson({'captureMode': 'tun'})
              .updateSubscriptionOnStart,
          isTrue);
    });
  });

  group('copyWith не теряет поле', () {
    test('правка соседней настройки не сбрасывает эту', () {
      const s = AppSettings(updateSubscriptionOnStart: false);
      expect(s.copyWith(killSwitch: true).updateSubscriptionOnStart, isFalse);
    });

    test('поле переключается через copyWith', () {
      const s = AppSettings();
      expect(s.copyWith(updateSubscriptionOnStart: false)
          .updateSubscriptionOnStart, isFalse);
    });
  });

  group('Переподключение не требуется', () {
    test('настройка НЕ названа причиной переподключения', () {
      // Обновление подписки конфиг ядра не трогает. Попади оно в список причин
      // — пользователь получал бы плашку «переподключитесь» на ровном месте,
      // а при живом канале это ещё и предложение оборвать себе VPN.
      const a = AppSettings();
      expect(a.reconnectReasons(a.copyWith(updateSubscriptionOnStart: false)),
          isEmpty);
    });
  });
}
