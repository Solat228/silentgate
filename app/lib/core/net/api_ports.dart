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

  /// Гейт «канал API реально поднят»: тумблер включён И задан токен.
  ///
  /// ⚠️ ЕДИНЫЙ ИСТОЧНИК ПРАВДЫ ДЛЯ ОБЕИХ СТОРОН. `PortCheck` (проверяет порты
  /// перед стартом ядра) и сборка TUN-конфига (создаёт инбаунды) обязаны
  /// решать «есть тут порты или нет» ОДИНАКОВО. Разойдись гейты —
  /// `apiEnabled=true` при пустом токене заставил бы `PortCheck` проверять
  /// порты, которых конфиг всё равно не создаст: стороннее приложение на
  /// любом из 10820–10859 давало бы ложный отказ подключения на ровном месте.
  /// Пустой токен сам по себе уже значит «канал не поднимается» (см.
  /// `SingboxConfigBuilder._apiExitInbounds`) — этот гейт то же самое, но
  /// доступное ДО сборки конфига, когда нужно решить, что проверять портами.
  static bool exitsActive({required bool enabled, required String token}) =>
      enabled && token.isNotEmpty;
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
