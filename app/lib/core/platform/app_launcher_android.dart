import 'package:flutter/services.dart';

import '../util/telegram_link.dart';
import 'app_launcher.dart';

/// Android: открытие через интент `ACTION_VIEW` на нативной стороне.
///
/// ⚠️ Проверка «установлен ли Telegram» на Android 11+ требует объявления
/// `<queries>` в манифесте (package visibility). Без него `resolveActivity`
/// всегда вернёт null, и мы уйдём в браузер даже при установленном Telegram —
/// см. `docs/platforms/ANDROID.md`, камень §6.6 #45.
class AndroidAppLauncher implements AppLauncher {
  /// Канал реализуется в фазе 3 (`platform/Launcher.kt`). До его появления
  /// вызовы бросают `MissingPluginException` и молча ничего не делают — как и
  /// прежняя Windows-реализация при сбое `cmd`.
  static const channel = MethodChannel('lol.silentgate/launcher');

  @override
  Future<void> open(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    try {
      await channel.invokeMethod<void>('open', {'url': u});
    } catch (_) {}
  }

  @override
  Future<void> openTelegram(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final deep = telegramDeepLink(u);
    if (deep != null) {
      try {
        final handled =
            await channel.invokeMethod<bool>('openIfHandled', {'url': deep});
        if (handled == true) return;
      } catch (_) {}
    }
    await open(u); // запасной вариант — браузер
  }
}
