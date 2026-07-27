/// Контракт url-схем приложения: константы и РАЗБОР ссылок.
///
/// Платформо-независимо и не зависит от `dart:io`: разбор одинаков на Windows
/// (ссылка приходит аргументом запуска через реестр) и на Android (приходит
/// интентом `ACTION_VIEW`/`ACTION_SEND`). Регистрация схем, наоборот, у каждой
/// платформы своя — она живёт в `core/platform/url_scheme_windows.dart`
/// (реестр HKCU) и в манифесте Android (`intent-filter` + `activity-alias`).
abstract final class AppUrlScheme {
  static const scheme = 'silentgate';

  /// Схемы одиночных серверов. Регистрируются ОТДЕЛЬНО и по умолчанию выключены:
  /// эти ссылки обычно уже привязаны к другому клиенту (Happ, v2rayTun), и молча
  /// забирать их у пользователя нельзя.
  static const serverSchemes = [
    'vless',
    'vmess',
    'trojan',
    'ss',
    'hysteria2',
    'hy2',
  ];

  /// Управляющие действия `silentgate://connect|disconnect|toggle|update`.
  static const controlActions = {'connect', 'disconnect', 'toggle', 'update'};

  /// Управляющее действие из ссылки (или null, если это не оно).
  ///
  /// Регистронезависимо, хвостовой слэш допустим: и `silentgate://connect`,
  /// и `SilentGate://Connect/` дают `connect`.
  static String? controlAction(String url) {
    final u = url.trim();
    if (!u.toLowerCase().startsWith('$scheme://')) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    final action = (uri.host.isNotEmpty
            ? uri.host
            : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : ''))
        .toLowerCase();
    return controlActions.contains(action) ? action : null;
  }

  /// Полезная нагрузка `silentgate://import?url=…` / `?config=…` — внутренний
  /// URL подписки или ссылка сервера. null — не наш import-URL.
  ///
  /// `config` приоритетнее `url`: если пришли оба, применяем готовый конфиг.
  static String? importPayload(String url) {
    final u = url.trim();
    if (!u.toLowerCase().startsWith('$scheme://')) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    return uri.queryParameters['config'] ?? uri.queryParameters['url'];
  }

  /// Понимает ли приложение такую ссылку (фильтр аргументов запуска на Windows
  /// и входящих интентов на Android).
  static bool isSupportedLink(String arg) {
    final a = arg.trim().toLowerCase();
    if (a.startsWith('$scheme://')) return true;
    return serverSchemes.any((s) => a.startsWith('$s://'));
  }
}
