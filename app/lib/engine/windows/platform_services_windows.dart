import 'dart:typed_data';

import '../../core/platform/platform_services.dart';
import '../../core/settings/app_settings.dart';
import 'app_icon_windows.dart';
import 'process_list_windows.dart';
import 'support_report.dart';
import 'tun/tun_helper.dart';
import 'tun/tun_scheduled_task.dart';
import 'xray_version.dart';

/// Windows-реализации платформенных сервисов интерфейса.
///
/// Тонкие обёртки над уже существующим кодом: логика не меняется, меняется
/// только то, что UI зовёт её через контракт, а не через прямой импорт.
PlatformServices buildWindowsPlatformServices() => PlatformServices(
      appCatalog: _WindowsAppCatalog(),
      appIcons: _WindowsAppIcons(),
      coreVersions: _WindowsCoreVersions(),
      tunLog: _WindowsTunLog(),
      privileges: _WindowsPrivileges(),
      support: _WindowsSupport(),
    );

class _WindowsAppCatalog implements AppCatalog {
  /// На Windows правило адресует конкретный exe, поэтому список строится из
  /// ЗАПУЩЕННЫХ процессов: так пользователь выбирает то, что у него реально
  /// работает, и получает верный путь.
  @override
  Future<List<CatalogApp>> list() async => ProcessListWindows.enumerate()
      .map((p) => CatalogApp(key: p.path, label: p.name))
      .toList();

  /// Приложение может быть не запущено — остаётся выбор .exe вручную.
  @override
  bool get supportsManualPick => true;

  /// На Windows метка выводится из самого ключа: правило адресует путь к exe, а
  /// показывается его имя файла (`AppRule.name`). Отдельный источник имени
  /// здесь не нужен и только расходился бы с тем, что уходит в `process_name`.
  @override
  String? cachedLabel(String key) => null;

  @override
  Future<String?> labelFor(String key) async => null;
}

class _WindowsAppIcons implements AppIconLoader {
  @override
  Uint8List? cached(String key) => AppIconWindows.cached(key);

  @override
  bool isCached(String key) => AppIconWindows.isCached(key);

  @override
  Future<Uint8List?> load(String key) => AppIconWindows.load(key);
}

class _WindowsCoreVersions implements CoreVersionInfo {
  @override
  Future<String> xray() => XrayVersion.get();
}

class _WindowsTunLog implements TunLogReader {
  @override
  Future<String> tail({int lines = 40}) => TunHelper.tailLog(lines: lines);
}

class _WindowsPrivileges implements PrivilegeSetup {
  /// Задача Планировщика нужна только в режиме TUN, но сам блок в настройках
  /// на Windows осмыслен всегда.
  @override
  bool get isApplicable => true;

  /// ⚠️ «НАСТРОЕНО» ЗНАЧИТ «ЗАДАЧА ЕСТЬ И ЗАПУСКАЕТ ТО, ЧТО НАДО».
  ///
  /// Раньше здесь стояло одно `exists()`, а экран настроек первой строкой
  /// делает `if (isConfigured()) return` — то есть существующая задача не
  /// пересоздавалась НИКОГДА. На машине владельца из-за этого живёт задача от
  /// 20.07.2026, запускающая exe из папки сборки и без путей конфига.
  @override
  Future<bool> isConfigured() async =>
      await TunScheduledTask.exists() && await TunScheduledTask.isCurrent();

  @override
  Future<bool> configure() => TunScheduledTask.install();

  @override
  Future<bool> remove() => TunScheduledTask.uninstall();
}

class _WindowsSupport implements SupportReporter {
  @override
  Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  }) =>
      SupportReport.generate(settings: settings, ctx: ctx);

  @override
  Future<void> reveal(String path) => SupportReport.reveal(path);
}
