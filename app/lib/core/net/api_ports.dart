import '../singbox/exit_tags.dart';

/// Раскладка локальных портов API.
///
/// ⚠️ ПОРЯДОК — ЧАСТЬ КОНТРАКТА. Скрипт хардкодит номер порта; «дышащая» между
/// запусками раскладка увела бы запрос в другую страну молча и без ошибки.
/// Поэтому ключи сортируются тем же способом, что в `ExitOutbounds.build`.
class ApiPorts {
  /// Управляющий HTTP-API.
  static const int control = 10870;

  /// «Прямо» — мимо VPN, реальный IP. Нужен, чтобы сравнивать «через VPN» и
  /// «без VPN» одной строкой кода, не выключая туннель.
  static const int direct = 10819;

  /// Первый порт диапазона серверов.
  static const int firstServer = 10820;

  /// Сколько серверов могут получить порт.
  ///
  /// ⚠️ Ограничение осмысленное, а не круглое число: каждый порт — это ещё один
  /// inbound в конфиге ядра. Сорок с запасом покрывает любой реальный набор.
  static const int maxServers = 40;

  /// Порт сервера [key] среди [keys]. `null` — ключа нет или он сверх диапазона.
  static int? forServer(List<String> keys, String key) {
    final sorted = [...keys]..sort();
    final i = sorted.indexOf(key);
    if (i < 0 || i >= maxServers) return null;
    return firstServer + i;
  }

  /// Ключи, которым порт реально достанется (первые [maxServers] по порядку).
  static List<String> withinRange(List<String> keys) {
    final sorted = [...keys]..sort();
    return sorted.length <= maxServers
        ? sorted
        : sorted.sublist(0, maxServers);
  }
}

/// Тег inbound-а, ведущего в сервер [serverKey].
///
/// ⚠️ Выводится из ТОГО ЖЕ ключа, что и тег outbound-а (`exitTagFor`), поэтому
/// правило `inboundTag → outboundTag` не может разъехаться. Разойдись они хоть
/// на символ — правило сослалось бы на несуществующий outbound, а `sing-box
/// check` этого НЕ ловит: конфиг принимается с кодом 0, а трафик уходит в
/// `route.final`, то есть мимо выбранного сервера.
String apiExitInboundTag(String serverKey) =>
    'api-${exitTagFor(serverKey)}';
