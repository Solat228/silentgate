import 'dart:io';

import '../../engine/windows/system_proxy.dart';
import '../../engine/windows/tun/tun_scheduled_task.dart';
import 'app_paths.dart';
import 'url_scheme_windows.dart';

/// Очистка следов приложения (для деинсталлятора и кнопки «Удалить все данные»).
class AppCleanup {
  /// Без плагинов Flutter — для режима `--cleanup` (вызывается деинсталлятором):
  /// снять системный прокси, снять URL-схему, убить процессы ядра, удалить данные.
  static Future<void> runHeadless() async {
    await SystemProxy.clear();
    await UrlSchemeWindows.unregister();
    // И серверные схемы (vless/vmess/trojan/ss/hysteria2/hy2): если пользователь
    // включал их перехват, после удаления они иначе остаются в реестре и
    // указывают на стёртый exe (в [Registry] установщика их нет — их ставит
    // само приложение). Снятие несуществующих ключей — no-op.
    await UrlSchemeWindows.unregisterServerSchemes();
    await _kill('xray.exe');
    await _kill('sing-box.exe');
    await _deleteTunTask();
    _deleteData();
  }

  /// Задача Планировщика для запуска TUN без UAC (создаётся из приложения).
  static Future<void> _deleteTunTask() async {
    try {
      await Process.run(
          'schtasks', ['/Delete', '/TN', TunScheduledTask.taskName, '/F']);
    } catch (_) {}
  }

  /// Из работающего приложения (кнопка «Удалить все данные»).
  static Future<void> runInApp() async {
    await SystemProxy.clear();
    await UrlSchemeWindows.unregister();
    await UrlSchemeWindows.unregisterServerSchemes();
    _deleteData();
  }

  static void _deleteData() {
    try {
      final dir = AppPaths.supportDirSync();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  static Future<void> _kill(String image) async {
    try {
      await Process.run('taskkill', ['/F', '/IM', image, '/T']);
    } catch (_) {}
  }
}
