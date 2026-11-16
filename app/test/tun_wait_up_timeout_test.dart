import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/singbox_router_windows.dart';
import 'package:silentgate/engine/windows/tun/tun_router.dart';

void main() {
  group('Таймаут подъёма адаптера Wintun и пропуск дубликатов стека', () {
    test('потолок ожидания адаптера не ниже 15 секунд', () {
      // У sing-tun собственный WARN "open interface take too much time to finish!"
      // срабатывает на 10-й секунде, а на Windows 10 с NDIS-фильтрами создание
      // интерфейса занимает 10-13 с. Срез до 5 с убивал рабочий запуск.
      expect(
        SingboxRouterWindows.waitUpTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 15)),
      );
    });

    test('isAdapterOpenTimeout узнаёт долгое открытие интерфейса', () {
      expect(
        SingboxRouterWindows.isAdapterOpenTimeout(
          TunStartException(
            'TUN-адаптер не поднялся за 15 секунд - sing-box не запустился.',
            details:
                'WARN inbound/tun[tun-in]: open interface take too much time to finish!',
          ),
        ),
        isTrue,
      );
      expect(
        SingboxRouterWindows.isAdapterOpenTimeout(
          TunStartException(
            'TUN-адаптер не поднялся за 15 секунд - sing-box не запустился.',
            adapterOpenTimeout: true,
            details: 'INFO inbound/tun[tun-in]: starting...',
          ),
        ),
        isTrue,
      );
    });

    test('isAdapterOpenTimeout НЕ помечает фатальную ошибку конфига/стека как таймаут адаптера',
        () {
      expect(
        SingboxRouterWindows.isAdapterOpenTimeout(
          TunStartException(
            'TUN-адаптер не поднялся за 15 секунд - sing-box не запустился.',
            adapterOpenTimeout: true,
            details: 'FATAL[0000] start service: initialize inbound/tun[tun-in]: invalid mtu',
          ),
        ),
        isFalse,
      );
    });
  });
}
