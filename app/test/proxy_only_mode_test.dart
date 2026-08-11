import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Режим захвата «Только прокси».
///
/// Смысл режима: ядро поднимается, локальные порты слушают, а машина при этом
/// НЕ в туннеле — через VPN идёт только тот, кто явно целится в порт.
void main() {
  group('Значение перечисления', () {
    test('proxyOnly существует и не ломает разбор старых файлов', () {
      expect(CaptureMode.values, contains(CaptureMode.proxyOnly));
      // Старый файл со значением 'tun' обязан читаться как прежде: добавление
      // значения в конец перечисления не должно сдвигать разбор.
      expect(AppSettings.fromJson({'captureMode': 'tun'}).captureMode,
          CaptureMode.tun);
      expect(AppSettings.fromJson({'captureMode': 'systemProxy'}).captureMode,
          CaptureMode.systemProxy);
    });

    test('переживает диск', () {
      const s = AppSettings(captureMode: CaptureMode.proxyOnly);
      expect(AppSettings.fromJson(s.toJson()).captureMode,
          CaptureMode.proxyOnly);
    });
  });

  group('Kill switch недоступен в этом режиме', () {
    test('killSwitchApplies ложно только для proxyOnly', () {
      // Он держит трафик МАШИНЫ, а машина здесь и так не в туннеле. Включённый
      // тумблер, который ничего не делает, — ровно тот класс дефектов, за
      // который в этом проекте платили дороже всего.
      expect(
          const AppSettings(captureMode: CaptureMode.proxyOnly)
              .killSwitchApplies,
          isFalse);
      expect(
          const AppSettings(captureMode: CaptureMode.tun).killSwitchApplies,
          isTrue);
      expect(
          const AppSettings(captureMode: CaptureMode.systemProxy)
              .killSwitchApplies,
          isTrue);
    });
  });
}
