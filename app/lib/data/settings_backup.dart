import 'dart:convert';
import 'dart:io';

import '../core/app_info.dart';
import '../core/backup/settings_bundle.dart';
import '../core/platform/app_log.dart';
import '../core/platform/app_paths.dart';
import '../core/platform/secret_files.dart';
import 'app_storage.dart';
import 'atomic_file.dart';

/// Откуда пришли восстановленные данные — для сообщения на старте.
enum RestoreSource { importFile, googleBackup }

/// Экспорт и импорт настроек файлом, снимок для Android Auto Backup (P11).
///
/// Формат и правила слияния — [SettingsBundle]; здесь только диск.
///
/// ⚠️ ИМПОРТ ПРИМЕНЯЕТСЯ ПОСЛЕ ПЕРЕЗАПУСКА, А НЕ НА ЖИВОМ ПРИЛОЖЕНИИ.
/// Настройки, подписки, пины и правки серверов держат в памяти пять разных
/// хранилищ, и каждое переписывает свой файл из памяти при следующем
/// сохранении. Подменить файлы под живым приложением значит получить смесь
/// старого и нового — или старое целиком, перезаписанное через минуту.
/// Поэтому импорт кладёт готовые файлы в [pendingFile], а раскладывает их
/// [applyPending] на следующем старте ДО того, как хранилища что-то прочли.
abstract final class SettingsBackup {
  /// Файлы, ждущие применения на следующем старте. Содержит секреты (подписки),
  /// поэтому на Windows пишется через DPAPI, как и сами хранилища.
  static const pendingFile = 'restore_pending.json';

  /// Каталог снимка для Android Auto Backup. Правила резервного копирования
  /// (`res/xml/backup_rules.xml`, `data_extraction_rules.xml`) пускают в
  /// копию ТОЛЬКО его — журналы, кэш значков, гео-базы и секреты сессии туда
  /// не попадают по построению.
  static const snapshotDir = 'backup';
  static const snapshotFile = 'snapshot.json';

  /// Что восстановлено на этом старте (`null` — ничего). Читает главный экран,
  /// чтобы сказать об этом человеку один раз.
  static RestoreSource? restoredOnStart;

  /// Платформа в терминах пакета.
  static String get platform => Platform.isAndroid ? 'android' : 'windows';

  static Future<File> _file(String name) async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Прочитать файлы данных. Отсутствующий или нечитаемый файл пропускается.
  static Future<Map<String, Object?>> readFiles() async {
    final out = <String, Object?>{};
    for (final name in SettingsBundle.allFiles) {
      final f = await _file(name);
      try {
        if (!await f.exists()) continue;
        var text = await SecretFiles.read(f);
        if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
          text = text.substring(1);
        }
        if (text.trim().isEmpty) continue;
        out[name] = jsonDecode(text);
      } catch (e) {
        AppLog.w('Экспорт настроек: $name не прочитан ($e) — пропущен');
      }
    }
    return out;
  }

  /// Текст файла экспорта.
  static Future<String> exportText({required bool includeSubscriptions}) async {
    final bundle = SettingsBundle.build(
      files: await readFiles(),
      includeSubscriptions: includeSubscriptions,
      platform: platform,
      appVersion: AppInfo.version,
    );
    AppLog.i('Экспорт настроек: подписки — '
        '${includeSubscriptions ? 'да' : 'нет'}');
    return SettingsBundle.encode(bundle);
  }

  /// Имя файла экспорта: `SilentGate-settings-20261020-1430.sgsettings`.
  static String exportFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'SilentGate-settings-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.${SettingsBundle.extension}';
  }

  /// Android: положить экспорт в каталог, открытый FileProvider-у
  /// (`res/xml/file_paths.xml`, корень `export`), — оттуда его забирает
  /// системное «Поделиться». Прежние экспорты удаляются: в файле могут быть
  /// подписки, и копиться в памяти телефона им незачем.
  static Future<File> writeAndroidExport(String text, {DateTime? now}) async {
    final root = await AppPaths.supportDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}export');
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    } else {
      await dir.create(recursive: true);
    }
    final f = File('${dir.path}${Platform.pathSeparator}'
        '${exportFileName(now ?? DateTime.now())}');
    await f.writeAsString(text, flush: true);
    return f;
  }

  /// Подготовить импорт: слить с местными настройками и положить в
  /// [pendingFile]. Применится на следующем старте ([applyPending]).
  static Future<bool> stageImport(
    BundleContents bundle, {
    required bool includeSubscriptions,
  }) async {
    final local = await readFiles();
    final localSettings = local[SettingsBundle.settingsFile];
    final files = SettingsBundle.merge(
      bundle,
      localSettings:
          localSettings is Map ? Map<String, Object?>.from(localSettings) : {},
      platform: platform,
      includeSubscriptions: includeSubscriptions,
    );
    if (files.isEmpty) return false;
    final ok = await SecretFiles.write(await _file(pendingFile),
        jsonEncode({'source': RestoreSource.importFile.name, 'files': files}));
    AppLog.i('Импорт настроек подготовлен: ${files.keys.join(', ')} — '
        'применится после перезапуска');
    return ok;
  }

  /// Разложить отложенный импорт по файлам. Зовётся на старте ДО того, как
  /// хранилища прочли диск. Возвращает `true`, если что-то применено.
  static Future<bool> applyPending() async {
    final f = await _file(pendingFile);
    if (!await f.exists()) return false;
    try {
      final j = jsonDecode(await SecretFiles.read(f));
      final files = j is Map ? j['files'] : null;
      if (files is! Map) throw const FormatException('нет files');
      await _writeFiles(Map<String, Object?>.from(files));
      restoredOnStart = RestoreSource.values.asNameMap()['${j['source']}'] ??
          RestoreSource.importFile;
      AppLog.i('Импорт настроек применён: ${files.keys.join(', ')}');
      return true;
    } catch (e) {
      AppLog.e('Импорт настроек не применён: $e');
      return false;
    } finally {
      // Файл удаляется и при ошибке: иначе битый импорт ломал бы каждый старт.
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static Future<void> _writeFiles(Map<String, Object?> files) async {
    for (final e in files.entries) {
      if (!SettingsBundle.allFiles.contains(e.key)) continue;
      await SecretFiles.write(await _file(e.key), jsonEncode(e.value));
    }
    if (files.containsKey(SettingsBundle.subscriptionsFile)) {
      await _forgetActiveSubscription();
    }
  }

  /// Подписки заменены целиком — прежний выбор сервера и карточка подписки в
  /// файле состояния указывают на старые. Флаги гео-баз остаются.
  static Future<void> _forgetActiveSubscription() async {
    final storage = AppStorage();
    final state = await storage.load();
    if (state.isEmpty) return;
    for (final k in const [
      'subscriptionUrl',
      'servers',
      'selectedIndex',
      'selectedVariant',
      'logoPath',
      'info',
    ]) {
      state.remove(k);
    }
    await storage.save(state);
  }

  // ── Android Auto Backup ────────────────────────────────────────────────────

  static Future<File> _snapshot() async {
    final dir = await AppPaths.supportDir();
    final sep = Platform.pathSeparator;
    return File('${dir.path}$sep$snapshotDir$sep$snapshotFile');
  }

  /// Обновить снимок для резервной копии Google. Пишется только при
  /// изменении содержимого: система копирует каталог раз в сутки, а лишние
  /// записи на телефоне — это лишний износ памяти.
  static Future<void> writeSnapshot({required bool includeSubscriptions}) async {
    try {
      final bundle = SettingsBundle.build(
        files: await readFiles(),
        includeSubscriptions: includeSubscriptions,
        platform: platform,
        appVersion: AppInfo.version,
        // Время в снимке не пишем — иначе он «менялся» бы на каждой записи.
        now: DateTime.utc(2000),
      );
      final text = SettingsBundle.encode(bundle);
      final f = await _snapshot();
      if (await f.exists() && await f.readAsString() == text) return;
      await f.parent.create(recursive: true);
      await AtomicFile.writeString(f, text);
    } catch (e) {
      AppLog.w('Снимок для резервной копии не записан: $e');
    }
  }

  /// Новая установка, восстановленная системой из резервной копии: снимок
  /// есть, а настроек и подписок нет — разложить снимок по файлам.
  ///
  /// Уже настроенное приложение снимок не трогает никогда: он мог остаться
  /// от прошлой жизни, а живые данные новее.
  static Future<bool> restoreSnapshotIfFresh() async {
    try {
      final snap = await _snapshot();
      if (!await snap.exists()) return false;
      final settings = await _file(SettingsBundle.settingsFile);
      final subs = await _file(SettingsBundle.subscriptionsFile);
      if (await settings.exists() || await subs.exists()) return false;
      final bundle = SettingsBundle.parse(await snap.readAsString());
      if (bundle == null) {
        AppLog.w('Снимок резервной копии не разобран — пропущен');
        return false;
      }
      final files = SettingsBundle.merge(bundle,
          localSettings: const {},
          platform: platform,
          includeSubscriptions: true);
      if (files.isEmpty) return false;
      await _writeFiles(files);
      restoredOnStart = RestoreSource.googleBackup;
      AppLog.i('Восстановлено из резервной копии Google: '
          '${files.keys.join(', ')}');
      return true;
    } catch (e) {
      AppLog.w('Восстановление из резервной копии не удалось: $e');
      return false;
    }
  }
}
