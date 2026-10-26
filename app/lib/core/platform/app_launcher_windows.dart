import 'dart:io';

import '../util/telegram_link.dart';
import 'app_launcher.dart';
import 'launch_uri.dart';

/// Windows: открытие через `rundll32 url.dll,FileProtocolHandler`, Telegram
/// Desktop — через протокол `tg://`, наличие которого проверяется в реестре.
///
/// ⚠️ НЕ ЧЕРЕЗ `cmd /c start`. Там ссылка проходила разбор командной строки:
/// `&`, `|`, `^` в ней исполнялись как команды (аудит 25.10.2026). Здесь
/// оболочки нет вовсе — `rundll32` получает ссылку одной строкой и отдаёт её
/// обработчику протокола. Схему и форму проверяет `UrlOpener` до нас.
class WindowsAppLauncher implements AppLauncher {
  @override
  Future<void> open(String url) async {
    final safe = safeLaunchUri(url);
    if (safe == null) return;
    await _launch(safe);
  }

  /// Отдать ссылку обработчику протокола.
  ///
  /// Полный путь к `rundll32` — чтобы не подхватить одноимённый файл из
  /// текущего каталога или `PATH`.
  static Future<void> _launch(String safe) async {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    try {
      await Process.run('$root\\System32\\rundll32.exe',
          ['url.dll,FileProtocolHandler', safe]);
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
    final safeDeep = deep == null ? null : safeLaunchUri(deep);
    if (safeDeep != null && await _telegramInstalled()) {
      await _launch(safeDeep);
      return;
    }
    await open(u); // запасной вариант — браузер
  }

  /// Зарегистрирован ли в системе протокол `tg://` (признак Telegram Desktop).
  static Future<bool> _telegramInstalled() async {
    try {
      final r =
          await Process.run('reg', ['query', r'HKCR\tg\shell\open\command']);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    try {
      // Запасная проверка — пользовательская ветка (устанавливается без прав).
      final r = await Process.run(
          'reg', ['query', r'HKCU\Software\Classes\tg\shell\open\command']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
