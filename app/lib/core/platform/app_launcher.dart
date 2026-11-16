import 'dart:io';

import 'app_launcher_android.dart';
import 'app_log.dart';
import 'launch_uri.dart';
import 'app_launcher_windows.dart';

/// Открытие ссылок во внешних приложениях.
///
/// Платформенная часть — только сам способ открыть URL: на Windows это
/// `rundll32 url.dll,FileProtocolHandler` и проверка протокола `tg` в реестре, на Android — интент
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
///
/// ⚠️ ПРОВЕРКА ССЫЛКИ ЗДЕСЬ, А НЕ В ПЛАТФОРМАХ: вход один на обе, и ни одна
/// не получит ссылку, которую нельзя открывать (см. `launch_uri.dart`).
abstract final class UrlOpener {
  static Future<void> open(String url) async {
    final safe = _checked(url);
    if (safe != null) await appLauncher().open(safe);
  }

  static Future<void> openTelegram(String url) async {
    final safe = _checked(url);
    if (safe != null) await appLauncher().openTelegram(safe);
  }

  static String? _checked(String url) {
    final safe = safeLaunchUri(url);
    if (safe == null && url.trim().isNotEmpty) {
      // Саму ссылку в журнал не пишем: в ней бывает токен подписки.
      AppLog.w('Ссылка не открыта: схема '
          '«${Uri.tryParse(url.trim())?.scheme ?? '?'}» не из разрешённых');
    }
    return safe;
  }
}
