import 'dart:io';

import '../url_scheme.dart';

/// Регистрация/снятие протоколов в реестре Windows (HKCU — без прав администратора).
/// Клик по ссылке в браузере запускает приложение с URL в качестве аргумента.
///
/// Разбор ссылок сюда НЕ входит — он платформо-независим и живёт в
/// [AppUrlScheme] (`core/url_scheme.dart`), потому что на Android те же ссылки
/// приходят интентом, а не аргументом запуска.
class UrlSchemeWindows {
  static const scheme = AppUrlScheme.scheme;

  /// Схемы одиночных серверов — см. [AppUrlScheme.serverSchemes].
  static const serverSchemes = AppUrlScheme.serverSchemes;

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
