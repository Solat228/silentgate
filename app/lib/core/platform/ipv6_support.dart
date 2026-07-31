import 'dart:io';

import 'app_log.dart';

/// Есть ли у машины НАСТОЯЩИЙ выход в IPv6.
///
/// ## Зачем это нужно
///
/// Туннель объявляет себя IPv6-способным (адрес `fdfe:dcba:9876::1`), и с этого
/// момента приложения считают IPv6 доступным: резолвер отдаёт AAAA, браузер
/// сначала идёт по IPv6. Если наружу IPv6 нет, ядро честно пытается и получает
/// `A socket operation was attempted to an unreachable network` — на каждый
/// двустековый сайт.
///
/// Снаружи это выглядит ровно как «всё зависает, хотя блока нет»: страницы
/// открываются с задержкой в секунды или не открываются вовсе. Проверено живьём
/// в изолированной VM без IPv6: настоящий браузер получал
/// `ERR_CONNECTION_RESET` на example.com, а после отключения IPv6 в туннеле —
/// загружал страницу. В логе ядра при этом было больше сотни ошибок
/// «unreachable network» и ни одного успешного IPv6-соединения.
///
/// ⚠️ Проверяем НАЛИЧИЕ ГЛОБАЛЬНОГО АДРЕСА, а не «интерфейс поднят». Windows
/// щедро раздаёт IPv6-адреса, по которым никуда не уехать: link-local `fe80::`,
/// уникальные локальные `fd00::/8` (в том числе наш собственный туннель),
/// Teredo `2001:0::/32` и 6to4 `2002::/16` — это переходные механизмы, которые
/// давно не работают, но адрес выдают. Настоящий признак — глобальный unicast
/// из `2000::/3`, не считая двух исключений выше.
class Ipv6Support {
  static bool? _cached;

  /// Сбросить кэш — сеть могла смениться (Wi-Fi → LTE, докстанция, VPN).
  static void invalidate() => _cached = null;

  /// Есть ли глобальный IPv6-адрес хоть на одном интерфейсе.
  ///
  /// Результат кэшируется на время сессии: вызывается перед каждым подъёмом
  /// туннеля, а перечисление интерфейсов на Windows не бесплатно.
  static Future<bool> hasGlobalIpv6() async {
    final cached = _cached;
    if (cached != null) return cached;
    var found = false;
    try {
      final list = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv6,
      );
      for (final iface in list) {
        for (final addr in iface.addresses) {
          if (isGlobalIpv6(addr.address)) {
            found = true;
            break;
          }
        }
        if (found) break;
      }
    } catch (e) {
      // Не смогли спросить — считаем, что IPv6 есть, и ничего не меняем.
      // Ошибка диагностики не должна молча урезать возможности пользователя.
      AppLog.w('Проверка IPv6 не удалась: $e');
      found = true;
    }
    return _cached = found;
  }

  /// Глобальный unicast IPv6 (`2000::/3`), кроме нерабочих переходных схем.
  static bool isGlobalIpv6(String ip) {
    final a = ip.toLowerCase();
    if (!a.contains(':')) return false;
    if (a.startsWith('fe80')) return false; // link-local
    if (a.startsWith('fc') || a.startsWith('fd')) return false; // ULA, наш туннель
    if (a.startsWith('ff')) return false; // multicast
    if (a.startsWith('::')) return false; // ::1 и прочее неопределённое
    if (a.startsWith('2001:0:')) return false; // Teredo
    if (a.startsWith('2002:')) return false; // 6to4
    // 2000::/3 — первая шестнадцатеричная группа от 2000 до 3fff.
    final head = int.tryParse(a.split(':').first, radix: 16);
    return head != null && head >= 0x2000 && head <= 0x3fff;
  }
}
