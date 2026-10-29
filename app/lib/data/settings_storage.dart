import 'dart:convert';
import 'dart:io';

import '../core/platform/app_log.dart';
import '../core/platform/app_paths.dart';
import '../core/platform/package_identity_windows.dart';
import '../core/settings/app_settings.dart';
import '../core/platform/secret_files.dart';

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

  /// Настройки свежей установки (файла ещё нет).
  ///
  /// В пакете MSIX способ захвата по умолчанию — TUN (решение владельца
  /// 21.10.2026): Store-версия и делалась ради туннеля. Только для СВЕЖЕЙ
  /// установки — у существующего файла настроек способ захвата записан всегда,
  /// и переделывать чужой выбор при обновлении нельзя.
  static AppSettings firstRunDefaults({bool? packaged}) =>
      (packaged ?? PackageIdentity.isPackaged)
          ? AppSettings.defaults.copyWith(captureMode: CaptureMode.tun)
          : AppSettings.defaults;

  Future<AppSettings> load() async {
    final file = await _file();
    try {
      if (!await file.exists()) return firstRunDefaults();
      final parsed = parseContent(await SecretFiles.read(file));
      if (parsed != null) return parsed;
      // Откат к дефолтам остаётся (приложение обязано стартовать), но теперь это
      // ВИДНО в логе и битый файл сохраняется — иначе первое же сохранение
      // затрёт улику, и причина сброса настроек останется неизвестной.
      AppLog.e('Настройки не прочитаны ($_fileName) — взяты значения по умолчанию');
      await _preserveBroken(file);
      return AppSettings.defaults;
    } catch (e) {
      // ⚠️ Файл есть, но прочитать его не вышло (держит антивирус, сбой
      // расшифровки). Раньше брались значения по умолчанию, и первое же
      // сохранение затирало настройки пользователя навсегда (аудит
      // 25.10.2026, G). Теперь — несколько повторов, а если не помогло,
      // копия файла остаётся в `*.bad`.
      for (var i = 0; i < readRetries; i++) {
        await Future<void>.delayed(readRetryDelay);
        try {
          final parsed = parseContent(await SecretFiles.read(file));
          if (parsed != null) return parsed;
          break;
        } catch (_) {}
      }
      AppLog.e('Файл настроек недоступен ($_fileName): $e');
      await _keepCopy(file);
      return AppSettings.defaults;
    }
  }

  /// Сколько раз перечитывать файл после сбоя и с какой паузой.
  static int readRetries = 3;
  static Duration readRetryDelay = const Duration(milliseconds: 300);

  /// Копия нечитаемого файла в `*.bad` — сам файл остаётся на месте.
  Future<void> _keepCopy(File file) async {
    try {
      if (!await file.exists()) return;
      final bad = await _freeBadFile(file);
      if (bad == null) return;
      await file.copy(bad.path);
      AppLog.w('Нечитаемый файл настроек скопирован в ${bad.path}');
    } catch (_) {}
  }

  /// Переименовывает нечитаемый файл в `*.bad`, чтобы его не затёрло сохранением.
  /// Все места для копий заняты — оригинал просто удаляется.
  Future<void> _preserveBroken(File file) async {
    try {
      if (!await file.exists()) return;
      final bad = await _freeBadFile(file);
      if (bad == null) {
        await file.delete();
      } else {
        await file.rename(bad.path);
        AppLog.w('Битый файл настроек сохранён как ${bad.path}');
      }
    } catch (_) {
      // Не смогли сохранить улику — не повод падать.
    }
  }

  /// Сколько копий нечитаемого файла держим.
  static const badCopies = 5;

  /// Свободное имя для копии: `*.bad`, затем `*.bad2` … `*.bad5`.
  ///
  /// ⚠️ РАНЬШЕ БЫЛО ОДНО ИМЯ (ревью 29.10.2026, L5). Существующий `.bad` от
  /// давнего сбоя запрещал сохранить копию нового — именно та копия, ради
  /// которой механизм заведён, терялась молча.
  static Future<File?> _freeBadFile(File file) async {
    for (var i = 1; i <= badCopies; i++) {
      final bad = File('${file.path}.bad${i == 1 ? '' : i}');
      if (!await bad.exists()) return bad;
    }
    return null;
  }

  Future<void> save(AppSettings settings) async {
    try {
      final file = await _file();
      await SecretFiles.write(file, jsonEncode(settings.toJson()));
    } catch (_) {
      // Потеря настроек не критична.
    }
  }
}
