import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';
import 'package_identity_windows.dart';
import 'single_instance.dart';
import 'tray_window.dart';

/// Перезапуск приложения — после импорта настроек (P11).
///
/// Импорт кладёт файлы рядом и применяется на следующем старте (почему не на
/// живом приложении — см. `SettingsBackup`). VPN к моменту перезапуска обязан
/// быть выключен: это проверяет экран импорта.
abstract final class AppRestart {
  /// Аргумент новой копии на Windows: «старая ещё закрывается, подожди её».
  static const waitArg = '--restart-wait';

  /// Сколько новая копия ждёт, пока старая отпустит порт single-instance.
  static const waitLimit = Duration(seconds: 15);

  static const _channel = MethodChannel('lol.silentgate/launcher');

  /// Перезапустить. `false` — не вышло, человеку нужно перезапустить руками.
  static Future<bool> restart() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('restartApp') == true;
      }
      if (Platform.isWindows) {
        // Новая копия стартует ДО выхода старой и ждёт её (см.
        // [becomePrimaryAfterRestart]). Наоборот нельзя: после выхода
        // запускать было бы уже некому.
        // В пакете MSIX — через псевдоним: так новая копия гарантированно
        // получает идентификацию пакета (и его каталог данных).
        await Process.start(PackageIdentity.launchPath(), const [waitArg],
            mode: ProcessStartMode.detached);
        await TrayWindow.quitNow();
        return true;
      }
    } catch (e) {
      AppLog.w('Перезапуск приложения не удался: $e');
    }
    return false;
  }

  /// Windows, новая копия после [restart]: старая ещё держит порт
  /// single-instance — пробуем, пока не отпустит. Без этого новая копия
  /// приняла бы старую за «уже запущенное приложение», переслала бы ей
  /// «покажи окно» и вышла — и не осталось бы ни одной.
  static Future<ServerSocket?> becomePrimaryAfterRestart(
    Future<ServerSocket?> Function() tryBecomePrimary, {
    Duration limit = waitLimit,
    Duration step = const Duration(milliseconds: 300),
  }) async {
    final until = DateTime.now().add(limit);
    while (true) {
      final s = await tryBecomePrimary();
      if (s != null || DateTime.now().isAfter(until)) return s;
      await Future<void>.delayed(step);
    }
  }

  /// То же для обычного вызова из `main`.
  static Future<ServerSocket?> tryBecomePrimary(List<String> args) =>
      args.contains(waitArg)
          ? becomePrimaryAfterRestart(SingleInstance.tryBecomePrimary)
          : SingleInstance.tryBecomePrimary();
}
