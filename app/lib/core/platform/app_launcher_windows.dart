import 'dart:io';

import '../util/telegram_link.dart';
import 'app_launcher.dart';

/// Windows: открытие через `cmd /c start`, Telegram Desktop — через протокол
/// `tg://`, наличие которого проверяется в реестре.
class WindowsAppLauncher implements AppLauncher {
  @override
  Future<void> open(String url) async {
    if (url.trim().isEmpty) return;
    try {
      await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } catch (_) {}
  }

  /// Для ссылок вида `https://t.me/<name>` или `tg://…` сначала пытаемся отдать
  /// её протоколу `tg://` (его обрабатывает установленный Telegram Desktop), и
  /// только если Telegram на ПК не найден — открываем обычную ссылку в браузере.
  /// Наличие Telegram определяем по зарегистрированному в реестре протоколу
  /// `tg` (HKCR\tg) — так мы не показываем юзеру системный диалог «нет
  /// приложения», когда десктопа нет.
  @override
  Future<void> openTelegram(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final deep = telegramDeepLink(u);
    if (deep != null && await _telegramInstalled()) {
      try {
        await Process.run('cmd', ['/c', 'start', '', deep], runInShell: true);
        return;
      } catch (_) {}
    }
    await open(u); // запасной вариант — браузер
  }

  /// Зарегистрирован ли в системе протокол `tg://` (признак Telegram Desktop).
  static Future<bool> _telegramInstalled() async {
    try {
      final r = await Process.run(
          'reg', ['query', r'HKCR\tg\shell\open\command'],
          runInShell: true);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    try {
      // Запасная проверка — пользовательская ветка (устанавливается без прав).
      final r = await Process.run(
          'reg', ['query', r'HKCU\Software\Classes\tg\shell\open\command'],
          runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
