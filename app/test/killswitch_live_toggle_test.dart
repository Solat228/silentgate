import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// KILL SWITCH, ВКЛЮЧЁННЫЙ НА ЖИВОМ СОЕДИНЕНИИ.
///
/// ⚠️ Найдено живьём в VM 10.10.2026: тумблер включался, а блокировка — нет.
/// Состав блокировки уходит помощнику туннеля файлом, на старте, и правка
/// настройки до переподключения не доходила никуда. Человек видел включённый
/// kill switch, а обрыв сервера выпускал трафик под реальным IP.
///
/// Лечение — kill switch в списке причин переподключения (интерфейс тогда
/// предлагает перезапуск, а включение переподключает сразу).
void main() {
  final tun = AppSettings.defaults.copyWith(
      captureMode: CaptureMode.tun, autoReconnect: true, killSwitch: false);

  test('включение kill switch — причина переподключения', () {
    expect(tun.reconnectReasons(tun.copyWith(killSwitch: true)),
        contains('kill switch'));
    expect(tun.requiresReconnect(tun.copyWith(killSwitch: true)), isTrue);
  });

  test('выключение — тоже: помощник держит фильтры до перезапуска', () {
    final on = tun.copyWith(killSwitch: true);
    expect(on.reconnectReasons(on.copyWith(killSwitch: false)),
        contains('kill switch'));
  });

  test('«Только прокси»: kill switch не действует — и не причина', () {
    final p = tun.copyWith(captureMode: CaptureMode.proxyOnly);
    expect(p.reconnectReasons(p.copyWith(killSwitch: true)),
        isNot(contains('kill switch')));
  });

  group('keepCaptureOnSwitch', () {
    test('kill switch удерживает захват и без бесшовности', () {
      expect(
          tun
              .copyWith(killSwitch: true, seamlessServerSwitch: false)
              .keepCaptureOnSwitch,
          isTrue);
    });

    test('без kill switch решает бесшовность, как раньше', () {
      expect(tun.copyWith(seamlessServerSwitch: false).keepCaptureOnSwitch,
          isFalse);
      expect(tun.copyWith(seamlessServerSwitch: true).keepCaptureOnSwitch,
          isTrue);
    });

    test('«Только прокси»: kill switch не действует — и захват не держит', () {
      expect(
          tun
              .copyWith(
                  captureMode: CaptureMode.proxyOnly,
                  killSwitch: true,
                  seamlessServerSwitch: false)
              .keepCaptureOnSwitch,
          isFalse);
    });
  });

  group('killSwitchTurnedOn', () {
    test('выкл → вкл', () {
      expect(tun.killSwitchTurnedOn(tun.copyWith(killSwitch: true)), isTrue);
    });

    test('вкл → выкл и вкл → вкл — нет', () {
      final on = tun.copyWith(killSwitch: true);
      expect(on.killSwitchTurnedOn(on.copyWith(killSwitch: false)), isFalse);
      expect(on.killSwitchTurnedOn(on), isFalse);
    });

    test('смена режима захвата из «Только прокси» в TUN при включённом '
        'тумблере — тоже включение', () {
      final p = tun.copyWith(captureMode: CaptureMode.proxyOnly, killSwitch: true);
      expect(p.killSwitchTurnedOn(p.copyWith(captureMode: CaptureMode.tun)),
          isTrue);
    });
  });
}
