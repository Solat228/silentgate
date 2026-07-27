import 'dart:typed_data';

import '../../core/platform/app_log.dart';
import '../../core/platform/platform_services.dart';
import '../../core/settings/app_settings.dart';

/// Платформенные сервисы Android — **каркас фазы 3**.
///
/// Реализованы те, что не требуют нативного слоя (лог движка читается из
/// файла, как на Windows). Остальные честно отвечают «нечего показать» и ждут
/// своих задач плана `docs/platforms/ANDROID.md`:
///
///  * каталог приложений и иконки — задача 44 (`PackageManager` через
///    `MethodChannel`, обязательно с `<queries>` в манифесте, иначе список
///    окажется пустым);
///  * версия ядра — задача 24 (появится вместе с `libxray.aar`);
///  * разрешение на VPN — задача 33 (`VpnService.prepare()`);
///  * отчёт поддержки — задача 6 фазы 6 (генератор общий, отдача через
///    системное «Поделиться» вместо Проводника).
///
/// Заглушки намеренно пустые, а не «правдоподобные»: пустой список приложений
/// виден пользователю сразу, а выдуманные данные — нет.
PlatformServices buildAndroidPlatformServices() => PlatformServices(
      appCatalog: const _AndroidAppCatalog(),
      appIcons: const _AndroidAppIcons(),
      coreVersions: const _AndroidCoreVersions(),
      tunLog: const _AndroidTunLog(),
      privileges: const _AndroidPrivileges(),
      support: const _AndroidSupport(),
    );

class _AndroidAppCatalog implements AppCatalog {
  const _AndroidAppCatalog();

  // Задача 44: PackageManager.getInstalledApplications через MethodChannel.
  @override
  Future<List<CatalogApp>> list() async => const [];

  /// На Android выбирать «файл приложения» негде — правила задаются пакетом.
  @override
  bool get supportsManualPick => false;
}

class _AndroidAppIcons implements AppIconLoader {
  const _AndroidAppIcons();

  // Задача 44: PackageManager.getApplicationIcon → PNG, кэш по packageName.
  @override
  Uint8List? cached(String key) => null;

  @override
  bool isCached(String key) => false;

  @override
  Future<Uint8List?> load(String key) async => null;
}

class _AndroidCoreVersions implements CoreVersionInfo {
  const _AndroidCoreVersions();

  // Задача 24: версия придёт из libXray, когда AAR появится в сборке.
  @override
  Future<String> xray() async => 'н/д';
}

class _AndroidTunLog implements TunLogReader {
  const _AndroidTunLog();

  /// Лог приложения на Android общий (`AppLog` уже пишет в files-dir).
  /// Отдельный лог ядра появится вместе с ядрами (задача 25).
  @override
  Future<String> tail({int lines = 200}) async {
    final all = await AppLog.dump();
    final rows = all.split('\n');
    return rows.length <= lines
        ? all
        : rows.sublist(rows.length - lines).join('\n');
  }
}

class _AndroidPrivileges implements PrivilegeSetup {
  const _AndroidPrivileges();

  /// Блок прав на Android осмыслен (согласие `VpnService.prepare()`), но пока
  /// нечего настраивать — сервиса ещё нет. Показывать неработающую кнопку
  /// хуже, чем не показывать её вовсе.
  @override
  bool get isApplicable => false;

  @override
  Future<bool> isConfigured() async => false;

  @override
  Future<bool> configure() async => false;

  @override
  Future<bool> remove() async => false;
}

class _AndroidSupport implements SupportReporter {
  const _AndroidSupport();

  // Фаза 6: генератор общий с Windows, отдача — через ACTION_SEND.
  @override
  Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  }) async =>
      throw UnsupportedError(
          'Отчёт поддержки на Android появится вместе с нативным слоем');

  @override
  Future<void> reveal(String path) async {}
}
