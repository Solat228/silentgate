import 'dart:io';

/// Регистрация/снятие протоколов в реестре Windows (HKCU — без прав администратора).
/// Клик по ссылке в браузере запускает приложение с URL в качестве аргумента.
class UrlSchemeWindows {
  static const scheme = 'silentgate';

  /// Схемы одиночных серверов. Регистрируются ОТДЕЛЬНО и по умолчанию выключены:
  /// эти ссылки обычно уже привязаны к другому клиенту (Happ, v2rayTun), и молча
  /// забирать их у пользователя нельзя.
  static const serverSchemes = ['vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2'];

  /// URL-схемы приложения, сгруппированные для экрана «URL-схемы»
  /// (по образцу Happ/v2raytun). Копируются пользователем; управляющие —
  /// подключают/отключают VPN и обновляют подписку.
  // Группы URL-схем и подсказка импорта отображаются локализованно в
  // ui/url_schemes_screen.dart (`_schemeGroups`, `l.urlSupportedImport`).

  static String _base(String s) => r'HKCU\Software\Classes\' '$s';

  static Future<void> register() => _registerScheme(scheme, 'SilentGate Protocol');

  static Future<void> unregister() => _unregisterScheme(scheme);

  /// Перехватывать ссылки серверов (vless:// и т.д.).
  static Future<void> registerServerSchemes() async {
    for (final s in serverSchemes) {
      await _registerScheme(s, '$s link');
    }
  }

  static Future<void> unregisterServerSchemes() async {
    for (final s in serverSchemes) {
      await _unregisterScheme(s);
    }
  }

  static Future<bool> isRegistered() => _isRegistered(scheme);

  /// Считаем перехват включённым, если зарегистрирована хотя бы vless://.
  static Future<bool> areServerSchemesRegistered() => _isRegistered('vless');

  /// Управляющее действие из `silentgate://connect|disconnect|toggle|update`
  /// (или null, если это не оно).
  static String? controlAction(String url) {
    final u = url.trim();
    if (!u.toLowerCase().startsWith('$scheme://')) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    final action = (uri.host.isNotEmpty
            ? uri.host
            : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : ''))
        .toLowerCase();
    const actions = {'connect', 'disconnect', 'toggle', 'update'};
    return actions.contains(action) ? action : null;
  }

  /// Полезная нагрузка `silentgate://import?url=…` / `?config=…` — внутренний
  /// URL подписки или ссылка сервера. null — не наш import-URL.
  static String? importPayload(String url) {
    final u = url.trim();
    if (!u.toLowerCase().startsWith('$scheme://')) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    return uri.queryParameters['config'] ?? uri.queryParameters['url'];
  }

  /// Понимает ли приложение такую ссылку (для фильтра аргументов запуска).
  static bool isSupportedLink(String arg) {
    final a = arg.trim().toLowerCase();
    if (a.startsWith('$scheme://')) return true;
    return serverSchemes.any((s) => a.startsWith('$s://'));
  }

  static Future<void> _registerScheme(String s, String title) async {
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    final base = _base(s);
    await _reg(['add', base, '/ve', '/d', 'URL:$title', '/f']);
    await _reg(['add', base, '/v', 'URL Protocol', '/d', '', '/f']);
    await _reg(['add', '$base\\DefaultIcon', '/ve', '/d', '$exe,0', '/f']);
    await _reg(['add', '$base\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
  }

  static Future<void> _unregisterScheme(String s) async {
    if (!Platform.isWindows) return;
    await _reg(['delete', _base(s), '/f']);
  }

  static Future<bool> _isRegistered(String s) async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run(
          'reg', ['query', '${_base(s)}\\shell\\open\\command', '/ve']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _reg(List<String> args) async {
    try {
      await Process.run('reg', args);
    } catch (_) {}
  }
}
