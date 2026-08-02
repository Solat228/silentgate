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

  /// Имя сервера из `silentgate://connect?server=Польша%201.5`.
  ///
  /// Имя — то же, что показывает подписка и что видно в списке. Пусто/нет
  /// параметра → null, тогда действие работает как раньше (текущий выбор).
  ///
  /// Принимаем и `server`, и `name`: снаружи схему пишут люди, и обе формы
  /// одинаково очевидны — отказывать в одной из них незачем.
  static String? serverName(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final v = (uri.queryParameters['server'] ?? uri.queryParameters['name'] ?? '')
        .trim();
    return v.isEmpty ? null : v;
  }

  /// Полезная нагрузка `silentgate://import?url=…` / `?config=…` — внутренний
  /// URL подписки или ссылка сервера. null — не наш import-URL.
  ///
  /// `config` приоритетнее `url`: если пришли оба, применяем готовый конфиг.
  static String? importPayload(String url) {
    final u = url.trim();
    final foreign = foreignImportPayload(u);
    if (foreign != null) return foreign;
    if (!u.toLowerCase().startsWith('$scheme://')) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    // Своя схема принимается в ДВУХ формах: `import?url=` (наша историческая) и
    // `add/<ссылка>` — та, что сложилась в отрасли. Панель подписки строит
    // кнопки клиентов именно по второй форме, поэтому уметь её надо, чтобы
    // SilentGate можно было туда добавить.
    final path = _afterAddRaw(u);
    if (path != null) return path;
    return uri.queryParameters['config'] ?? uri.queryParameters['url'];
  }

  /// Ссылка подписки из схемы ЧУЖОГО клиента.
  ///
  /// ⚠️ Люди пересылают друг другу `happ://add/…` и `clash://install-config?url=…`,
  /// и при переходе с другого клиента такая ссылка — самое частое, что человек
  /// пробует. Стоит нам ноль (разбор строки), а выигрыш заметный: иначе
  /// SilentGate на неё просто не отзовётся, и человек решит, что импорт сломан.
  ///
  /// Формы взяты из документации самих клиентов; там сложились две:
  /// `<схема>://add/<ссылка>` и `<схема>://install-config?url=<ссылка>`.
  static String? foreignImportPayload(String url) {
    final u = url.trim();
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    const known = {
      'happ', 'clash', 'clashmi', 'stash', 'flclashx', 'sing-box',
      'streisand', 'v2raytun', 'hiddify', 'shadowrocket',
    };
    if (!known.contains(uri.scheme.toLowerCase())) return null;
    // ⚠️ `happ://crypt4|crypt5` расшифровывается ключами, вшитыми в САМО
    // приложение Happ, — механизм для того и сделан, чтобы адрес подписки был
    // скрыт от пользователя. Мы её не прочитаем никогда, и честнее сказать это
    // прямо, чем выдать «неверный формат».
    final head = uri.host.isNotEmpty ? uri.host : _firstSegment(uri);
    if (head.toLowerCase().startsWith('crypt')) return null;
    final q = uri.queryParameters['url'];
    if (q != null && q.trim().isNotEmpty) return q.trim();
    return _afterAddRaw(u);
  }

  /// Хвост ссылки после `add/` / `import/` — там лежит сам адрес подписки.
  ///
  /// ⚠️ Берётся из СЫРОЙ строки, а не через `Uri.pathSegments`. Вложенный адрес
  /// сам содержит `://`, и разбор в `Uri` схлопывает двойной слэш: из
  /// `happ://add/https://example.org/sub` получалось бы
  /// `https:/example.org/sub` — ссылка, по которой ничего не откроется.
  static String? _afterAddRaw(String url) {
    final u = url.trim();
    final scheme = u.indexOf('://');
    if (scheme < 0) return null;
    final rest = u.substring(scheme + 3);
    for (final marker in const ['add/', 'import-remote-profile/', 'import/']) {
      if (rest.toLowerCase().startsWith(marker)) {
        var tail = rest.substring(marker.length);
        // Часть клиентов кодирует вложенную ссылку целиком.
        if (!tail.contains('://')) {
          final decoded = Uri.decodeFull(tail);
          if (decoded.contains('://')) tail = decoded;
        }
        // Имя профиля после решётки к адресу не относится.
        final hash = tail.indexOf('#');
        if (hash > 0) tail = tail.substring(0, hash);
        return tail.trim().isEmpty ? null : tail.trim();
      }
    }
    return null;
  }

  static String _firstSegment(Uri uri) =>
      uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;

  /// Ссылка Happ с шифрованием: прочитать её мы не можем в принципе.
  static bool isHappCryptoLink(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'happ') return false;
    final head = uri.host.isNotEmpty ? uri.host : _firstSegment(uri);
    return head.toLowerCase().startsWith('crypt');
  }

  /// Понимает ли приложение такую ссылку (фильтр аргументов запуска на Windows
  /// и входящих интентов на Android).
  static bool isSupportedLink(String arg) {
    final a = arg.trim().toLowerCase();
    if (a.startsWith('$scheme://')) return true;
    return serverSchemes.any((s) => a.startsWith('$s://'));
  }
}
