import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// ⚠️ ПЕРЕПОДКЛЮЧЕНИЕ ПРЕДЛАГАЕТСЯ, ТОЛЬКО ЕСЛИ КОНФИГ ВПРАВДУ ИЗМЕНИТСЯ.
///
/// Требование владельца дословно: «Для ВСЕХ настроек проверяй, точно ли нужно
/// в текущий момент перезапускать ядро».
///
/// Вред от лишней просьбы двойной. Первое — рвётся живое соединение ради
/// конфига, который не изменится. Второе, и худшее: переподключение читается
/// человеком как «применилось». Он включает пароль на локальный прокси в
/// режиме системного прокси, видит просьбу переподключиться, переподключается
/// — и считает порт закрытым, хотя движок в этом режиме креды принудительно
/// обнуляет.
void main() {
  const tun = AppSettings(captureMode: CaptureMode.tun);
  const proxy = AppSettings(captureMode: CaptureMode.systemProxy);

  group('⚠️ Пароль на локальный прокси', () {
    // ⚠️ Умолчание поля — `true` (порт закрыт паролем сразу после установки),
    // поэтому «правкой» здесь является ВЫКЛЮЧЕНИЕ пароля.
    test('в режиме туннеля переподключения требует', () {
      expect(tun.reconnectReasons(tun.copyWith(localProxyAuth: false)),
          contains('пароль на локальный прокси'));
      expect(tun.reconnectReasons(tun.copyWith(localProxyUser: 'u')),
          contains('логин локального прокси'));
      expect(tun.reconnectReasons(tun.copyWith(localProxyPassword: 'p')),
          contains('пароль локального прокси'));
    });

    test('⚠️ в режиме системного прокси — НЕ требует', () {
      expect(proxy.reconnectReasons(proxy.copyWith(localProxyAuth: false)),
          isEmpty);
      expect(proxy.reconnectReasons(proxy.copyWith(localProxyUser: 'u')),
          isEmpty);
    });

    test('⚠️ и в смешанном режиме (туннель + системный прокси) — тоже НЕ', () {
      // `applyLocalProxyAuth` обнуляет креды и здесь: системный прокси
      // включён, значит порт 10809 обязан отвечать без пароля.
      const mixed =
          AppSettings(captureMode: CaptureMode.tun, alsoSetSystemProxy: true);
      expect(mixed.reconnectReasons(mixed.copyWith(localProxyAuth: false)),
          isEmpty);
    });
  });

  group('⚠️ Уровень лога ядра', () {
    test('в режиме туннеля требует', () {
      expect(
          tun.reconnectReasons(
              tun.copyWith(singboxLogLevel: SingboxLogLevel.debug)),
          contains('уровень лога ядра'));
    });

    test('⚠️ вне туннеля — НЕ требует: прокси-ядро уровень не спрашивает', () {
      expect(
          proxy.reconnectReasons(
              proxy.copyWith(singboxLogLevel: SingboxLogLevel.debug)),
          isEmpty);
    });
  });

  group('⚠️ Таймаут сторожа туннеля', () {
    test('правка требует переподключения — иначе она молча не подействует', () {
      // Сторож читает таймаут ОДИН раз при подъёме и держит его в замыкании
      // таймера. Без этой строки человек менял значение, ничего не менялось, и
      // понять почему было нельзя.
      expect(tun.reconnectReasons(tun.copyWith(tunWatchdogSeconds: 45)),
          contains('таймаут сторожа туннеля'));
    });

    test('вне туннеля сторожа нет — и просьбы тоже', () {
      expect(proxy.reconnectReasons(proxy.copyWith(tunWatchdogSeconds: 45)),
          isEmpty);
    });
  });

  group('⚠️ Стражи от перегиба', () {
    test('настройки самого туннеля в режиме TUN по-прежнему требуют', () {
      expect(tun.reconnectReasons(tun.copyWith(tunMtu: 1400)),
          contains('MTU'));
      expect(tun.reconnectReasons(tun.copyWith(tunStrictRoute: false)),
          contains('строгая маршрутизация'));
    });

    test('правила раздельного туннелирования требуют в ЛЮБОМ режиме', () {
      // Они запекаются в конфиг и прокси-ядра тоже — гейт по режиму захвата
      // не имеет права их проглотить.
      final changed = proxy.copyWith(
          splitTunnel: const SplitTunnelConfig(mode: SplitMode.onlySelected));
      expect(proxy.reconnectReasons(changed),
          contains('правила раздельного туннелирования'));
    });

    test('смена способа захвата называется всегда', () {
      expect(proxy.reconnectReasons(proxy.copyWith(captureMode: CaptureMode.tun)),
          contains('способ захвата'));
    });

    test('одинаковые настройки не требуют ничего', () {
      expect(tun.reconnectReasons(tun), isEmpty);
      expect(proxy.reconnectReasons(proxy), isEmpty);
    });
  });
}
