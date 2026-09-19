import 'dart:convert';
import 'dart:io';

import '../platform/app_log.dart';
import '../platform/app_paths.dart';

/// УСТАНОВЩИК ВНУТРИ ПРИЛОЖЕНИЯ — платформенно-независимая часть.
///
/// До 1.14.0 приложение при новой версии только открывало ссылку. Теперь оно
/// само скачивает, проверяет и ставит обновление; этот файл — договор между
/// контроллером обновлений и платформенными реализациями (`update_installer_
/// windows.dart`, Android — своя), плюс общая механика «отложенного итога»:
/// установщик убивает нас, чтобы заменить файлы, и результат установки узнаёт
/// уже СЛЕДУЮЩИЙ запуск приложения по `updates/pending.json`.
///
/// ⚠️ ОТКАЗ УСТАНОВЩИКА ОБЯЗАН БЫТЬ ВИДЕН. Если после перезапуска версия не
/// изменилась, человек должен получить не молчание, а карточку с хвостом
/// журнала установки — иначе «обновление» неотличимо от «ничего не произошло».

/// Можно ли ставить обновление САМИМ, и если нет — почему.
///
/// Всё, кроме [ready], означает «показать ссылку и объяснить». Причины
/// различаются, потому что различается объяснение и лечение.
enum InstallCapability {
  /// Установленная копия: путь из реестра совпадает с каталогом exe.
  ready,

  /// Портативная копия (`portable.txt` рядом с exe): обновляется распаковкой
  /// архива поверх, установщик к ней отношения не имеет.
  portable,

  /// Изолированная копия (`SILENTGATE_PORT_OFFSET`): заведена, чтобы НЕ
  /// мешать установленной, — трогать установку из неё нельзя.
  isolated,

  /// Записи об установке в реестре нет: exe запущен из распакованного архива
  /// или из папки сборки.
  notInstalled,

  /// Установка есть, но exe запущен не из неё (вторая копия в другом месте).
  locationMismatch,

  /// Приложение возвышено. `PrivilegesRequired=lowest` — условие безопасности:
  /// путь берётся из HKCU, доступного пользователю на запись; запуск оттуда
  /// из-под администратора превратил бы строку реестра в повышение прав.
  elevated,

  /// Платформа, где самообновления нет.
  unsupported,
}

/// Запись о запущенном установщике — живёт в `updates/pending.json` ровно
/// между запуском установщика и следующим стартом приложения.
class PendingInstall {
  static const fileName = 'pending.json';

  /// Старше этого — итог уже не разобрать: человек мог ставить и удалять что
  /// угодно, и хвост журнала суточной давности объяснит не то.
  static const staleAfter = Duration(hours: 24);

  /// Версия, которую ставили.
  final String version;

  /// Момент запуска установщика (UTC).
  final DateTime startedAt;

  /// Скачанный установщик — удаляется после успешной установки.
  final String exePath;

  /// Журнал установщика (`/LOG=`) — по нему разбирается отказ.
  final String logPath;

  const PendingInstall({
    required this.version,
    required this.startedAt,
    required this.exePath,
    required this.logPath,
  });

  Map<String, Object?> toJson() => {
        'version': version,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'exePath': exePath,
        'logPath': logPath,
      };

  /// Бросает [FormatException] на неполном объекте — разбор битого файла
  /// решает [tryParse].
  factory PendingInstall.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final startedAt = json['startedAt'];
    final exePath = json['exePath'];
    final logPath = json['logPath'];
    if (version is! String ||
        version.isEmpty ||
        startedAt is! String ||
        exePath is! String ||
        logPath is! String) {
      throw const FormatException('pending.json: не хватает полей');
    }
    final at = DateTime.tryParse(startedAt);
    if (at == null) throw const FormatException('pending.json: startedAt');
    return PendingInstall(
        version: version, startedAt: at.toUtc(), exePath: exePath, logPath: logPath);
  }

  /// `null` на любом мусоре: файл пишем мы сами, но между записью и чтением
  /// его мог обрезать выключенный питанием диск.
  static PendingInstall? tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return null;
      return PendingInstall.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  bool isStale(DateTime now) => now.toUtc().difference(startedAt) > staleAfter;
}

/// Чем кончилась установка, запущенная в прошлой жизни процесса.
enum PendingOutcome {
  /// Версия приложения совпала с той, что ставили.
  updated,

  /// Версия не та, установка свежая — установщик отказал или его прервали.
  failed,

  /// Запись старше [PendingInstall.staleAfter]: итог не разбираем.
  stale,
}

class PendingResult {
  final PendingOutcome outcome;
  final PendingInstall pending;

  /// Хвост журнала установщика — только у [PendingOutcome.failed] и только
  /// если журнал существует.
  final String? logTail;

  const PendingResult({required this.outcome, required this.pending, this.logTail});
}

/// Отказ запустить установку. Сообщение — для журнала и карточки.
class UpdateInstallException implements Exception {
  final String message;

  const UpdateInstallException(this.message);

  @override
  String toString() => 'UpdateInstallException: $message';
}

/// Контракт для контроллера обновлений. Реализация на платформу.
abstract class UpdateInstaller {
  /// Каталог, куда качаются установщики и где лежит `pending.json`.
  Future<Directory> stagingDir();

  /// Можно ли ставить самим (см. [InstallCapability]).
  Future<InstallCapability> capability();

  /// Запустить установщик [verified] — файл, УЖЕ прошедший проверку подписи
  /// манифеста и хэша. [expectedSha256] сверяется ПОВТОРНО прямо перед
  /// запуском: между проверкой и запуском файл мог подменить кто угодно с
  /// правами пользователя (TOCTOU).
  ///
  /// [forceQuit] — согласие человека на разрыв живого VPN уже получено;
  /// [allowDowngrade] — осознанный откат на прежнюю версию.
  ///
  /// Бросает [UpdateInstallException]; после успешного возврата установщик
  /// вскоре попросит приложение закрыться.
  Future<void> launch(
    File verified, {
    required String version,
    required String expectedSha256,
    bool forceQuit = false,
    bool allowDowngrade = false,
  });

  /// Разобрать итог прошлой установки по `pending.json`. `null` — ставить
  /// ничего не пытались. Файл после разбора удаляется всегда.
  Future<PendingResult?> reconcileAfterStart({required String currentVersion});

  /// Вычистить каталог закачек. [keepVersion] — файлы этой версии остаются
  /// (журнал неудачной установки нужен кнопке «Показать журнал»).
  Future<void> purgeStaging({String? keepVersion});
}

/// Общая механика `updates/`: каталог, `pending.json`, разбор итога, чистка.
/// Платформа добавляет только [capability] и [launch].
abstract class StagedUpdateInstaller implements UpdateInstaller {
  /// Часы — подменяются тестом на «через сутки».
  final DateTime Function() clock;

  StagedUpdateInstaller({DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  /// Имя подкаталога закачек внутри корня данных.
  static const stagingDirName = 'updates';

  @override
  Future<Directory> stagingDir() async {
    final root = await AppPaths.supportDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}$stagingDirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> pendingFile() async {
    final dir = await stagingDir();
    return File('${dir.path}${Platform.pathSeparator}${PendingInstall.fileName}');
  }

  /// Путь журнала установщика для версии — ОДНО место, по которому его и
  /// пишет [launch], и ищет [reconcileAfterStart].
  Future<String> logPathFor(String version) async {
    final dir = await stagingDir();
    return '${dir.path}${Platform.pathSeparator}install-$version.log';
  }

  Future<void> writePending(PendingInstall p) async {
    final f = await pendingFile();
    await f.writeAsString(jsonEncode(p.toJson()), flush: true);
  }

  @override
  Future<PendingResult?> reconcileAfterStart({required String currentVersion}) async {
    final f = await pendingFile();
    if (!f.existsSync()) return null;

    PendingInstall? pending;
    try {
      pending = PendingInstall.tryParse(await f.readAsString());
    } catch (_) {
      pending = null;
    }
    // ⚠️ Удаляем ДО разбора: что бы ни случилось ниже, второй старт не должен
    // показать ту же карточку ещё раз.
    _deleteQuietly(f);
    if (pending == null) {
      AppLog.w('Обновление: pending.json не разобрался — удалён');
      return null;
    }

    if (pending.version == currentVersion) {
      // Установщик своё дело сделал — его файлы больше не нужны.
      _deleteQuietly(File(pending.exePath));
      _deleteQuietly(File(pending.logPath));
      AppLog.i('Обновление: установлена версия ${pending.version}');
      return PendingResult(outcome: PendingOutcome.updated, pending: pending);
    }

    if (pending.isStale(clock())) {
      AppLog.w('Обновление: запись об установке ${pending.version} старше суток — '
          'итог не разбираю');
      return PendingResult(outcome: PendingOutcome.stale, pending: pending);
    }

    String? tail;
    final log = File(pending.logPath);
    if (log.existsSync()) {
      try {
        tail = logTail(decodeInstallLog(await log.readAsBytes()));
      } catch (e) {
        AppLog.w('Обновление: журнал установщика не прочитан: $e');
      }
    }
    AppLog.e('Обновление: установка ${pending.version} не завершилась '
        '(текущая версия $currentVersion)');
    return PendingResult(outcome: PendingOutcome.failed, pending: pending, logTail: tail);
  }

  @override
  Future<void> purgeStaging({String? keepVersion}) async {
    final root = await AppPaths.supportDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}$stagingDirName');
    if (!dir.existsSync()) return;
    for (final entry in dir.listSync()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      // `pending.json` — забота reconcileAfterStart: чистка, вызванная до
      // разбора, не имеет права стереть итог установки.
      if (name == PendingInstall.fileName) continue;
      if (keepVersion != null && keepVersion.isNotEmpty && name.contains(keepVersion)) {
        continue;
      }
      try {
        entry.deleteSync(recursive: true);
      } catch (_) {
        // Занятый файл (установщик ещё работает) — уберём в следующий раз.
      }
    }
  }

  static void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// Текст журнала установщика из байтов.
///
/// Inno пишет `/LOG=` в UTF-8 с BOM; на всякий случай понимаем и UTF-16LE с
/// BOM, и UTF-8 без него. Всё, что не UTF-8, читается как latin1 — хвост
/// журнала с мусором вместо кириллицы лучше исключения, из-за которого
/// карточка отказа не покажется вовсе.
String decodeInstallLog(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Последние [maxLines] строк, не длиннее [maxChars] символов.
///
/// Причина отказа у Inno всегда в конце журнала; начало — тысячи строк про
/// распакованные файлы, которые в карточке никому не нужны.
String logTail(String text, {int maxLines = 40, int maxChars = 4000}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final tail = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
  final joined = tail.join('\n');
  return joined.length > maxChars ? joined.substring(joined.length - maxChars) : joined;
}
