import 'dart:convert';
import 'dart:io';

import '../core/platform/app_log.dart';
import '../core/platform/app_paths.dart';
import '../core/settings/app_settings.dart';

/// Персистенс настроек в отдельном JSON-файле (не смешиваем с состоянием сети/серверов).
class SettingsStorage {
  static const _fileName = 'silentgate_settings.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// Разбор СОДЕРЖИМОГО файла настроек (чистая функция — тестируется без диска).
  ///
  /// Возвращает `null`, если содержимое нечитаемо (битый JSON или неверный тип
  /// значения) — решение о фолбэке принимает вызывающий. Пустой файл — это не
  /// порча, а «настроек ещё нет»: отдаём дефолты.
  ///
  /// BOM (U+FEFF) срезается: его дописывают почти все редакторы и PowerShell
  /// (`>`, `Out-File`, `Set-Content -Encoding utf8`). `jsonDecode` на BOM бросает
  /// исключение, и раньше это МОЛЧА сбрасывало ВСЕ настройки в дефолт —
  /// пользователь незаметно терял kill switch и уезжал в режим системного прокси.
  static AppSettings? parseContent(String raw) {
    var content = raw;
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    if (content.trim().isEmpty) return AppSettings.defaults;
    try {
      return AppSettings.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<AppSettings> load() async {
    final file = await _file();
    try {
      if (!await file.exists()) return AppSettings.defaults;
      final parsed = parseContent(await file.readAsString());
      if (parsed != null) return parsed;
      // Откат к дефолтам остаётся (приложение обязано стартовать), но теперь это
      // ВИДНО в логе и битый файл сохраняется — иначе первое же сохранение
      // затрёт улику, и причина сброса настроек останется неизвестной.
      AppLog.e('Настройки не прочитаны ($_fileName) — взяты значения по умолчанию');
      await _preserveBroken(file);
      return AppSettings.defaults;
    } catch (e) {
      AppLog.e('Файл настроек недоступен ($_fileName): $e');
      return AppSettings.defaults;
    }
  }

  /// Переименовывает нечитаемый файл в `*.bad`, чтобы его не затёрло сохранением.
  /// Делается один раз: если `.bad` уже есть, оригинал просто удаляется.
  Future<void> _preserveBroken(File file) async {
    try {
      if (!await file.exists()) return;
      final bad = File('${file.path}.bad');
      if (await bad.exists()) {
        await file.delete();
      } else {
        await file.rename(bad.path);
        AppLog.w('Битый файл настроек сохранён как ${bad.path}');
      }
    } catch (_) {
      // Не смогли сохранить улику — не повод падать.
    }
  }

  Future<void> save(AppSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Потеря настроек не критична.
    }
  }
}
