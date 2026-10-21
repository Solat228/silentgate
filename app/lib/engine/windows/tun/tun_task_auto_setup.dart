import '../../../core/platform/app_log.dart';
import '../../../core/platform/package_identity_windows.dart';
import '../../../core/platform/platform_services.dart';
import '../../../core/settings/app_settings.dart';
import 'tun_router.dart';
import 'tun_scheduled_task.dart';

/// Пакет MSIX: задача Планировщика для TUN ставится сама при первом
/// подключении туннеля.
///
/// Решение владельца 21.10.2026: права для TUN — выбор в настройках (задача
/// или окно UAC на каждое подключение), по умолчанию — задача. Вне пакета
/// умолчание прежнее: задачу ставят руками («TUN и маршрутизация»), потому что
/// у GitHub-версии TUN не способ захвата по умолчанию.
///
/// Окно UAC при этом ровно одно — то же, что спросил бы и обычный запуск
/// помощника; дальше подключения идут без него. Отказ в UAC останавливает
/// подключение сразу: второй раз за одно нажатие спрашивать нельзя.
abstract final class TunTaskAutoSetup {
  /// Ставить ли задачу самим.
  static bool wanted({required bool packaged, required AppSettings settings}) =>
      packaged &&
      settings.captureMode == CaptureMode.tun &&
      !settings.tunTaskDeclined;

  /// Поставить задачу, если она нужна и её нет. Бросает [TunElevationDenied],
  /// если человек отказал в правах; любая другая неудача — запись в журнал и
  /// прежний путь (окно UAC на запуск помощника).
  static Future<void> ensure(
    AppSettings settings, {
    bool? packaged,
    Future<bool> Function()? configured,
    Future<PrivilegeSetupResult> Function()? install,
  }) async {
    if (!wanted(
        packaged: packaged ?? PackageIdentity.isPackaged, settings: settings)) {
      return;
    }
    final isConfigured = configured ??
        () async =>
            await TunScheduledTask.exists() && await TunScheduledTask.isCurrent();
    if (await isConfigured()) return;
    AppLog.i('TUN: ставлю задачу Планировщика «${TunScheduledTask.taskName}» '
        '(один раз, дальше подключения без окна UAC)');
    final result = await (install ?? TunScheduledTask.install)();
    switch (result) {
      case PrivilegeSetupResult.done:
        AppLog.i('TUN: задача Планировщика поставлена');
      case PrivilegeSetupResult.denied:
        throw TunElevationDenied(
          'Не удалось получить права администратора для TUN (UAC отклонён).',
        );
      case PrivilegeSetupResult.failed:
        AppLog.w('TUN: задача Планировщика не поставилась — запускаю помощника '
            'с окном UAC');
    }
  }
}
