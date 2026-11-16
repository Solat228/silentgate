import 'package:flutter/services.dart';

/// Android: Google Play на устройстве — есть ли он и как открыть нашу страницу.
///
/// Нативная сторона — `platform/PlatformChannels.kt` (`handleLauncher`:
/// `playStoreInstalled`, `openPlayStore`). Сбой канала — «Play нет»: тогда
/// сборка GitHub просто предлагает скачать APK, как раньше.
class PlayStoreAndroid {
  final MethodChannel _launcher;

  PlayStoreAndroid({MethodChannel? launcher})
      : _launcher = launcher ?? const MethodChannel('lol.silentgate/launcher');

  Future<bool> installed() async {
    try {
      return await _launcher.invokeMethod<bool>('playStoreInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Открыть страницу приложения: в приложении Play, без него — в браузере.
  /// `false` — не открылось ни то, ни другое.
  Future<bool> open() async {
    try {
      return await _launcher.invokeMethod<bool>('openPlayStore') ?? false;
    } catch (_) {
      return false;
    }
  }
}
