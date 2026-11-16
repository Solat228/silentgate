import '../models/vpn_server.dart';
import '../settings/app_settings.dart';
import '../singbox/exit_outbounds.dart';
import '../singbox/exit_tags.dart';

/// Раскладка локальных портов API.
///
/// Поддерживает:
/// * Управляющий HTTP-API (`control`, по умолчанию `10870`);
/// * Умный балансируемый порт «Автовыбор» (`auto`, по умолчанию `10818`);
/// * Прямой порт в обход VPN (`direct`, по умолчанию `10819`);
/// * Липкие (`sticky`) и ручные порты отдельных серверов до [maxServers] (`250`),
///   пропускающие зарезервированные служебные порты (`10855`, `10870`, `10910..11199`).
class ApiPorts {
  /// Управляющий HTTP-API по умолчанию.
  static const int control = 10870;

  /// Умный балансируемый порт «Автовыбор» (`urltest` по пулу рабочих серверов).
  static const int auto = 10818;

  /// «Прямо» — мимо VPN, реальный IP.
  static const int direct = 10819;

  /// Первый порт диапазона серверов.
  static const int firstServer = 10820;

  /// Сколько серверов могут одновременно получить отдельный порт.
  static const int maxServers = 250;

  /// Зарезервированные внутренние порты ядер, которые нельзя выдавать серверам.
  static bool isReservedSystemPort(
    int port, {
    int controlPort = control,
    int autoPort = auto,
    int directPort = direct,
  }) {
    if (port <= 1024 || port > 65535) return true;
    if (port == controlPort || port == autoPort || port == directPort) {
      return true;
    }
    if (port == 10085 || port == 10855 || port == 10870) return true;
    if (port >= 10808 && port <= 10813) return true;
    // Диапазон локальных Xray-мостов (kXrayExitBridgeBasePort = 10910)
    if (port >= 10910 && port <= 11199) return true;
    return false;
  }

  /// Детерминированный номер порта для слота `0 .. maxServers - 1`:
  /// * `0..34`  → `10820..10854` (35 портов)
  /// * пропуск `10855` (`whitelist-bypass.exe`)
  /// * `35..48` → `10856..10869` (14 портов)
  /// * пропуск `10870` (`control`) и `10910..11199` (`xray_exit_bridge`)
  /// * `49..249` → `11200..11400` (201 порт)
  static int? slotToPort(int slot) {
    if (slot < 0 || slot >= maxServers) return null;
    if (slot < 35) return 10820 + slot; // 10820..10854
    if (slot < 49) return 10821 + slot; // 10856..10869 (пропуск 10855)
    return 11200 + (slot - 49); // 11200..11400
  }

  /// Вычислить стабильную карту `serverKey -> port` для [keys] с учётом
  /// сохранённых липких/ручных портов [assignedPorts].
  static Map<String, int> resolvePortMap(
    Iterable<String> keys, {
    Map<String, int> assignedPorts = const {},
    int controlPort = control,
    int autoPort = auto,
    int directPort = direct,
  }) {
    final uniqueSorted = keys.where((k) => k.isNotEmpty).toSet().toList()..sort();
    final capped = uniqueSorted.length <= maxServers
        ? uniqueSorted
        : uniqueSorted.sublist(0, maxServers);
    if (capped.isEmpty) return const {};

    final result = <String, int>{};
    final usedPorts = <int>{};

    // 1. Сначала сохраняем уже закреплённые за серверами валидные порты (sticky / custom)
    for (final k in capped) {
      final p = assignedPorts[k];
      if (p != null &&
          !usedPorts.contains(p) &&
          !isReservedSystemPort(
            p,
            controlPort: controlPort,
            autoPort: autoPort,
            directPort: directPort,
          )) {
        result[k] = p;
        usedPorts.add(p);
      }
    }

    // 2. Оставшимся серверам выдаём минимальные свободные слоты из пула
    var slot = 0;
    for (final k in capped) {
      if (result.containsKey(k)) continue;
      int? chosen;
      while (slot < maxServers + 64) {
        final cand = slot < maxServers ? slotToPort(slot) : (11401 + (slot - maxServers));
        slot++;
        if (cand == null) continue;
        if (!usedPorts.contains(cand) &&
            !isReservedSystemPort(
              cand,
              controlPort: controlPort,
              autoPort: autoPort,
              directPort: directPort,
            )) {
          chosen = cand;
          break;
        }
      }
      if (chosen != null) {
        result[k] = chosen;
        usedPorts.add(chosen);
      }
    }
    return result;
  }

  /// Обновить сохранённую карту `apiAssignedPorts`: удерживает прежние порты
  /// всех активных серверов (и не удаляет временно снятые галочки, если не просили
  /// полный сброс, чтобы повторное включение возвращало тот же порт!).
  static Map<String, int> assignStickyPorts(
    Iterable<String> activeKeys,
    Map<String, int> existingAssigned, {
    int controlPort = control,
    int autoPort = auto,
    int directPort = direct,
  }) {
    final resolvedActive = resolvePortMap(
      activeKeys,
      assignedPorts: existingAssigned,
      controlPort: controlPort,
      autoPort: autoPort,
      directPort: directPort,
    );
    final merged = <String, int>{};
    final takenByActive = resolvedActive.values.toSet();
    for (final e in existingAssigned.entries) {
      if (resolvedActive.containsKey(e.key)) continue;
      if (!takenByActive.contains(e.value) &&
          !isReservedSystemPort(
            e.value,
            controlPort: controlPort,
            autoPort: autoPort,
            directPort: directPort,
          )) {
        merged[e.key] = e.value;
      }
    }
    merged.addAll(resolvedActive);
    return merged;
  }

  /// Порт сервера [key] среди [keys]. `null` — ключа нет или он сверх диапазона.
  static int? forServer(
    List<String> keys,
    String key, {
    Map<String, int> assignedPorts = const {},
    int controlPort = control,
    int autoPort = auto,
    int directPort = direct,
  }) {
    if (keys.isEmpty || !keys.contains(key)) return null;
    final map = resolvePortMap(
      keys,
      assignedPorts: assignedPorts,
      controlPort: controlPort,
      autoPort: autoPort,
      directPort: directPort,
    );
    return map[key];
  }

  /// Ключи, которым порт реально достанется (первые [maxServers] по порядку).
  static List<String> withinRange(
    List<String> keys, {
    Map<String, int> assignedPorts = const {},
  }) {
    final map = resolvePortMap(keys, assignedPorts: assignedPorts);
    final sorted = keys.where(map.containsKey).toSet().toList()..sort();
    return sorted;
  }

  /// Итоговый список ключей серверов с отдельным портом с учётом опции
  /// автоматического включения всех панельных профилей «Авто» (`apiAutoIncludeAutoProfiles`).
  static List<String> effectiveServerKeys(
    AppSettings s, [
    Iterable<VpnServer> catalog = const [],
  ]) {
    final set = <String>{
      for (final k in s.apiExitServerKeys)
        if (k.isNotEmpty) k,
    };
    if (s.apiAutoIncludeAutoProfiles) {
      for (final srv in catalog) {
        if (srv.key.isNotEmpty && srv.isPanelProfile && canBeExitServer(srv)) {
          set.add(srv.key);
        }
      }
    }
    return set.toList();
  }

  /// Ключи серверов, входящих в балансируемый пул порта «Умный Автовыбор» (`10818`).
  static List<String> autoPoolServerKeys(
    AppSettings s, {
    required Iterable<VpnServer> activeServers,
    required Iterable<VpnServer> allServers,
  }) {
    if (!s.apiAutoPortEnabled) return const [];
    final Iterable<VpnServer> source = switch (s.apiAutoPoolScope) {
      ApiAutoPoolScope.allSubscriptions =>
        allServers.isNotEmpty ? allServers : activeServers,
      ApiAutoPoolScope.activeSubscription => activeServers,
      ApiAutoPoolScope.checkedOnly => () {
          final checked = effectiveServerKeys(s, allServers).toSet();
          final pool = allServers.isNotEmpty ? allServers : activeServers;
          return pool.where((srv) => checked.contains(srv.key));
        }(),
    };
    final out = <String>[];
    final seen = <String>{};
    for (final srv in source) {
      if (srv.key.isEmpty || seen.contains(srv.key)) continue;
      if (!canBeExitServer(srv)) continue;
      // Пропускаем служебные/платёжные ноды с множителем x10 в автопуле, чтобы
      // скрипт случайно не сжёг трафик x10 через порт «Авто», если есть обычные локации.
      final lowName = srv.displayName.toLowerCase();
      if (lowName.contains('x10') ||
          lowName.contains('×10') ||
          lowName.contains('10x')) {
        continue;
      }
      seen.add(srv.key);
      out.add(srv.key);
      if (out.length >= 80) break;
    }
    // Если кроме x10 вообще ничего нет, берём любые пригодные
    if (out.isEmpty) {
      for (final srv in source) {
        if (srv.key.isNotEmpty &&
            !seen.contains(srv.key) &&
            canBeExitServer(srv)) {
          seen.add(srv.key);
          out.add(srv.key);
          if (out.length >= 80) break;
        }
      }
    }
    return out;
  }

  /// Гейт «канал API реально поднят»: тумблер включён И задан управляющий токен.
  static bool exitsActive({required bool enabled, required String token}) =>
      enabled && token.isNotEmpty;

  /// Создаются ли инбаунды портов выходов при таком способе захвата.
  ///
  /// Начиная с 1.18.7 порты выходов поддерживаются во ВСЕХ режимах захвата:
  /// * `tun` — внутри туннельного `sing-box`;
  /// * `systemProxy` и `proxyOnly` (а также при выключенном VPN с
  ///   `apiKeepAliveWhenDisconnected`) — через фоновый пользовательский
  ///   маршрутизатор `ExitRouterConfigBuilder` без прав администратора.
  static bool exitPortsExistIn(CaptureMode mode) => true;

  /// Полный гейт портов выходов: тумблер + токен + способ захвата.
  static bool exitPortsActive(AppSettings s) =>
      exitsActive(enabled: s.apiEnabled, token: s.apiToken) &&
      exitPortsExistIn(s.captureMode);

  /// Сформировать список пользователей `users` для `mixed`-инбаунда `sing-box`
  /// в соответствии с режимом авторизации прокси-портов.
  /// Возвращает `null`, если выбран режим «Без пароля на 127.0.0.1».
  static List<Map<String, String>>? buildInboundUsers({
    required String token,
    ApiProxyAuthMode authMode = ApiProxyAuthMode.apiToken,
    String customUser = '',
    String customPassword = '',
  }) {
    switch (authMode) {
      case ApiProxyAuthMode.none:
        return null;
      case ApiProxyAuthMode.custom:
        if (customUser.trim().isNotEmpty && customPassword.isNotEmpty) {
          return [
            {'username': customUser.trim(), 'password': customPassword},
          ];
        }
        return [
          {'username': 'sg', 'password': token},
        ];
      case ApiProxyAuthMode.apiToken:
        return [
          {'username': 'sg', 'password': token},
        ];
    }
  }

  /// Готовая строка прокси (`http://...` или `socks5://...`) для копирования в UI.
  static String formatProxyUrl(
    AppSettings s,
    int port, {
    String scheme = 'http',
  }) {
    switch (s.apiProxyAuthMode) {
      case ApiProxyAuthMode.none:
        return '$scheme://127.0.0.1:$port';
      case ApiProxyAuthMode.custom:
        if (s.apiProxyCustomUser.trim().isNotEmpty &&
            s.apiProxyCustomPassword.isNotEmpty) {
          final u = Uri.encodeComponent(s.apiProxyCustomUser.trim());
          final p = Uri.encodeComponent(s.apiProxyCustomPassword);
          return '$scheme://$u:$p@127.0.0.1:$port';
        }
        final tok = s.apiToken.isEmpty ? '<токен>' : s.apiToken;
        return '$scheme://sg:$tok@127.0.0.1:$port';
      case ApiProxyAuthMode.apiToken:
        final tok = s.apiToken.isEmpty ? '<токен>' : s.apiToken;
        return '$scheme://sg:$tok@127.0.0.1:$port';
    }
  }
}

/// Тег inbound-а, ведущего в сервер [serverKey].
String apiExitInboundTag(String serverKey) => 'api-${exitTagFor(serverKey)}';

/// Обратное преобразование тега инбаунда в тег его outbound-а.
String apiExitOutboundOf(String inboundTag) =>
    inboundTag.substring('api-'.length);

/// Инбаунды отдельных портов API: по одному `mixed` на сервер из [serverKeys],
/// у которого есть живой outbound (тег входит в [liveExitTags]).
List<Map<String, dynamic>> buildApiExitInbounds({
  required List<String> serverKeys,
  required String token,
  required Set<String> liveExitTags,
  Map<String, int> assignedPorts = const {},
  int controlPort = ApiPorts.control,
  int autoPort = ApiPorts.auto,
  int directPort = ApiPorts.direct,
  ApiProxyAuthMode authMode = ApiProxyAuthMode.apiToken,
  String customUser = '',
  String customPassword = '',
}) {
  if (token.isEmpty) return const [];
  final portMap = ApiPorts.resolvePortMap(
    serverKeys,
    assignedPorts: assignedPorts,
    controlPort: controlPort,
    autoPort: autoPort,
    directPort: directPort,
  );
  final users = ApiPorts.buildInboundUsers(
    token: token,
    authMode: authMode,
    customUser: customUser,
    customPassword: customPassword,
  );
  final sortedKeys = portMap.keys.toList()..sort();
  final out = <Map<String, dynamic>>[];
  for (final key in sortedKeys) {
    if (!liveExitTags.contains(exitTagFor(key))) continue;
    final port = portMap[key];
    if (port == null) continue;
    out.add({
      'type': 'mixed',
      'tag': apiExitInboundTag(key),
      'listen': '127.0.0.1',
      'listen_port': port,
      if (users != null) 'users': users,
    });
  }
  return out;
}

/// Правила «инбаунд конкретного сервера → его же выход».
List<Map<String, dynamic>> buildApiExitRules(
  List<Map<String, dynamic>> apiExitInbounds,
) =>
    [
      for (final i in apiExitInbounds)
        {
          'inbound': [i['tag']],
          'action': 'route',
          'outbound': apiExitOutboundOf('${i['tag']}'),
        },
    ];

/// Тег inbound-а порта «Прямо» (см. [ApiPorts.direct]).
const String apiDirectInboundTag = 'api-direct';

/// Инбаунд порта «Прямо».
List<Map<String, dynamic>> buildApiDirectInbound({
  required String token,
  int port = ApiPorts.direct,
  ApiProxyAuthMode authMode = ApiProxyAuthMode.apiToken,
  String customUser = '',
  String customPassword = '',
}) {
  if (token.isEmpty || port <= 0) return const [];
  final users = ApiPorts.buildInboundUsers(
    token: token,
    authMode: authMode,
    customUser: customUser,
    customPassword: customPassword,
  );
  return [
    {
      'type': 'mixed',
      'tag': apiDirectInboundTag,
      'listen': '127.0.0.1',
      'listen_port': port,
      if (users != null) 'users': users,
    },
  ];
}

/// Правило «порт «Прямо» → outbound `direct`».
List<Map<String, dynamic>> buildApiDirectRule(
  List<Map<String, dynamic>> apiDirectInbound,
) =>
    [
      for (final i in apiDirectInbound)
        {
          'inbound': [i['tag']],
          'action': 'route',
          'outbound': 'direct',
        },
    ];

/// Тег inbound-а и outbound-а умного балансируемого порта «Автовыбор» (`10818`).
const String apiAutoInboundTag = 'api-auto';
const String apiAutoOutboundTag = 'api-auto-out';

/// Собрать `urltest` outbound для порта «Умный Автовыбор» по живым кандидатам.
Map<String, dynamic>? buildApiAutoOutbound({
  required List<String> candidateTags,
  String url = 'https://www.gstatic.com/generate_204',
  int intervalSec = 180,
}) {
  final unique = candidateTags.where((t) => t.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return null;
  final cleanUrl =
      url.trim().isEmpty ? 'https://www.gstatic.com/generate_204' : url.trim();
  final cleanInterval = intervalSec.clamp(15, 3600);
  return {
    'type': 'urltest',
    'tag': apiAutoOutboundTag,
    'outbounds': unique,
    'url': cleanUrl,
    'interval': '${cleanInterval}s',
    'tolerance': 50,
  };
}

/// Инбаунд порта «Умный Автовыбор» (`10818`). Создаётся только если собран
/// живой `api-auto-out`!
List<Map<String, dynamic>> buildApiAutoInbound({
  required String token,
  required bool hasAutoOutbound,
  bool enabled = true,
  int port = ApiPorts.auto,
  ApiProxyAuthMode authMode = ApiProxyAuthMode.apiToken,
  String customUser = '',
  String customPassword = '',
}) {
  if (!enabled || !hasAutoOutbound || token.isEmpty || port <= 0) {
    return const [];
  }
  final users = ApiPorts.buildInboundUsers(
    token: token,
    authMode: authMode,
    customUser: customUser,
    customPassword: customPassword,
  );
  return [
    {
      'type': 'mixed',
      'tag': apiAutoInboundTag,
      'listen': '127.0.0.1',
      'listen_port': port,
      if (users != null) 'users': users,
    },
  ];
}

/// Правило «порт «Умный Автовыбор» → `api-auto-out`».
List<Map<String, dynamic>> buildApiAutoRule(
  List<Map<String, dynamic>> apiAutoInbound,
) =>
    [
      for (final i in apiAutoInbound)
        {
          'inbound': [i['tag']],
          'action': 'route',
          'outbound': apiAutoOutboundTag,
        },
    ];

/// Единый неизменяемый снимок параметров локальных прокси-портов API для
/// `SingboxConfigBuilder`, `ExitRouterConfigBuilder` и `SingboxRouterWindows`.
class ApiExitRouterOptions {
  final Map<String, int> assignedPorts;
  final int controlPort;
  final bool autoPortEnabled;
  final int autoPort;
  final List<String> autoPoolKeys;
  final int directPort;
  final ApiProxyAuthMode authMode;
  final String customUser;
  final String customPassword;
  final bool dnsViaExit;
  final String urltestUrl;
  final int urltestIntervalSec;

  const ApiExitRouterOptions({
    this.assignedPorts = const {},
    this.controlPort = ApiPorts.control,
    this.autoPortEnabled = false,
    this.autoPort = ApiPorts.auto,
    this.autoPoolKeys = const [],
    this.directPort = ApiPorts.direct,
    this.authMode = ApiProxyAuthMode.apiToken,
    this.customUser = '',
    this.customPassword = '',
    this.dnsViaExit = false,
    this.urltestUrl = 'https://www.gstatic.com/generate_204',
    this.urltestIntervalSec = 180,
  });

  factory ApiExitRouterOptions.fromSettings(
    AppSettings s, {
    List<String> autoPoolKeys = const [],
  }) =>
      ApiExitRouterOptions(
        assignedPorts: s.apiAssignedPorts,
        controlPort: s.apiControlPort,
        autoPortEnabled: s.apiAutoPortEnabled,
        autoPort: s.apiAutoPort,
        autoPoolKeys: autoPoolKeys,
        directPort: s.apiDirectPort,
        authMode: s.apiProxyAuthMode,
        customUser: s.apiProxyCustomUser,
        customPassword: s.apiProxyCustomPassword,
        dnsViaExit: s.apiDnsViaExit,
        urltestUrl: s.apiUrltestUrl,
        urltestIntervalSec: s.apiUrltestIntervalSec,
      );
}
