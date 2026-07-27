import 'dart:io';

import 'app_launcher_android.dart';
import 'app_launcher_windows.dart';

/// Открытие ссылок во внешних приложениях.
///
/// Платформенная часть — только сам способ открыть URL: на Windows это
/// `cmd /c start` и проверка протокола `tg` в реестре, на Android — интент
/// `ACTION_VIEW` и `resolveActivity`. Разбор телеграм-ссылок общий
/// (`core/util/telegram_link.dart`).
abstract interface class AppLauncher {
  /// Открыть URL во внешнем приложении по умолчанию (обычно браузер).
  Future<void> open(String url);

  /// Открыть ссылку Telegram, отдав приоритет установленному приложению.
  /// Если его нет — открыть обычную ссылку, не показывая системный диалог
  /// «нет приложения».
  Future<void> openTelegram(String url);
}

AppLauncher? _override;

/// Подменить реализацию (тесты).
void setAppLauncherForTests(AppLauncher? l) => _override = l;

AppLauncher appLauncher() {
  final o = _override;
  if (o != null) return o;
  if (Platform.isAndroid) return AndroidAppLauncher();
  return WindowsAppLauncher();
}

/// Совместимость с прежним статическим API — его зовут из UI в полутора
/// десятках мест.
abstract final class UrlOpener {
  static Future<void> open(String url) => appLauncher().open(url);
  static Future<void> openTelegram(String url) =>
      appLauncher().openTelegram(url);
}
