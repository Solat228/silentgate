import 'dart:typed_data';

import 'dart:io';

import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/rotating_log.dart';
import '../../core/platform/platform_services.dart';
import 'support_report_android.dart';

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
      support: const AndroidSupportReporter(),
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

  /// Лог ядра: сюда `VpnService` перенаправляет вывод sing-box и — что важнее —
  /// паники Go (`Libbox.redirectStderr`). Без него причина падения туннеля не
  /// видна нигде.
  ///
  /// Если ядро ещё ни разу не запускалось, файла нет — тогда отдаём лог
  /// приложения, чтобы экран не выглядел сломанным.
  @override
  Future<String> tail({int lines = 200}) async {
    final dir = await AppPaths.supportDir();
    // Читаем хвост с конца файла: лог ядра ничем не ограничен, а прежний
    // readAsString() затягивал его целиком в память (та же беда, что подвешивала
    // Windows-версию на кнопке поддержки).
    final text = await RotatingLog.tail(
      '${dir.path}${Platform.pathSeparator}singbox.log',
      lines: lines,
    );
    if (text.trim().isNotEmpty) return text;
    // Ядро ещё не поднималось — показываем хотя бы лог приложения.
    final fallback = await AppLog.dump();
    final rows = fallback.split('\n');
    return rows.length <= lines
        ? fallback
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

