import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_status.dart';

/// Страж признака, по которому работают все три способа сказать «трафик
/// заблокирован»: карточка в приложении, уведомление Android и подсказка трея.
///
/// Признак отдельный, а не разбор текста статуса, — потому что текст
/// локализуется и меняется, а поведение по нему завязано в трёх местах.
void main() {
  test('blocking не включается сам собой', () {
    expect(const VpnStatus(VpnConnectionState.connecting).blocking, isFalse);
    expect(const VpnStatus.disconnected().blocking, isFalse);
  });

  test('blocking переживает создание статуса с сообщением', () {
    const s = VpnStatus(VpnConnectionState.connecting,
        message: 'Соединение потеряно, трафик заблокирован', blocking: true);
    expect(s.blocking, isTrue);
    expect(s.message, contains('заблокирован'));
  });

  test('успешное подключение блокировкой не считается', () {
    expect(const VpnStatus(VpnConnectionState.connected).blocking, isFalse);
  });
}
