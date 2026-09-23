import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../geo/sha256.dart';
import '../platform/apk_installer_android.dart';
import '../platform/app_log.dart';
import 'update_installer.dart';

/// Разрешения «устанавливать из этого приложения» нет (API 26+).
///
/// Отдельный тип, а не текст в [UpdateInstallException]: контроллер на него
/// отвечает не карточкой отказа, а кнопкой «Открыть настройки»
/// ([ApkInstallerAndroid.openInstallPermission]) и повтором после возврата.
class NeedsInstallPermission extends UpdateInstallException {
  const NeedsInstallPermission()
      : super('нет разрешения на установку из этого приложения');
}

/// Android: установка обновления через системный установщик пакетов.
///
/// Отличия от Windows, и все — не по выбору, а по устройству платформы:
///  * **Staging — `cacheDir/updates/`**, а не `files/SilentGate/support/updates/`
///    базового [StagedUpdateInstaller]. Установщик — чужой процесс, ему нужен
///    `content://`-доступ через FileProvider, а его корень объявлен ровно на
///    этот каталог (`res/xml/file_paths.xml`, `<cache-path name="updates">`).
///    `files/SilentGate` наружу не открывается: там подписки с токенами. Kotlin
///    (`PlatformChannels.installApk`) отвергает путь вне `cacheDir/updates/`.
///  * **Тихой установки нет.** Мы лишь передаём файл; лист согласия человек
///    видит всегда, а «установлено или нет» узнаёт следующий запуск по
///    `pending.json` ([reconcileAfterStart] базы). Журнала установщика нет —
///    у отказа `logTail` всегда `null`.
///  * **`capability` всегда [InstallCapability.ready]**: портативных,
///    изолированных и «не установленных» копий на Android не бывает.
///  * `forceQuit`/`allowDowngrade` смысла не имеют: установщик сам снимает наш
///    процесс, а откат на Android — только ссылка (пакет с меньшим versionCode
///    система не поставит поверх).
class UpdateInstallerAndroid extends StagedUpdateInstaller {
  final ApkInstallerAndroid _apk;

  /// Каталог cache приложения. По умолчанию `getTemporaryDirectory()`
  /// (`path_provider`) — в тесте подменяется временной папкой.
  final Future<Directory> Function() _tempDir;

  UpdateInstallerAndroid({
    ApkInstallerAndroid? apk,
    Future<Directory> Function()? tempDir,
    super.clock,
  })  : _apk = apk ?? ApkInstallerAndroid(),
        _tempDir = tempDir ?? getTemporaryDirectory;

  /// `<cache>/updates` — обязан совпадать с `cache-path` FileProvider и с
  /// границей в Kotlin (`UPDATES_DIR`).
  @override
  Future<Directory> stagingDir() async {
    final root = await _tempDir();
    final dir = Directory(
        '${root.path}${Platform.pathSeparator}${StagedUpdateInstaller.stagingDirName}');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<InstallCapability> capability() async => InstallCapability.ready;

  /// Тот же вопрос, что задаёт [launch], — но до закачки (см. интерфейс).
  @override
  Future<bool> canInstallNow() => _apk.canInstallPackages();

  @override
  Future<void> launch(
    File verified, {
    required String version,
    required String expectedSha256,
    bool forceQuit = false,
    bool allowDowngrade = false,
  }) async {
    // 1. Повторная сверка хэша — ПЕРВОЙ, до любых вопросов системе: между
    //    проверкой манифеста и этим вызовом файл в cache мог подменить любой
    //    процесс с правами нашего пользователя (TOCTOU).
    if (!verified.existsSync()) {
      throw const UpdateInstallException('файл обновления исчез');
    }
    final actual = await Sha256.ofFile(verified);
    if (actual.toLowerCase() != expectedSha256.trim().toLowerCase()) {
      AppLog.e('Обновление: хэш APK изменился после проверки — установка отменена');
      throw const UpdateInstallException(
          'файл обновления изменился после проверки');
    }

    // 2. Разрешение. Без него ACTION_VIEW молча не сработает — это не отказ,
    //    а шаг, который делает человек.
    if (!await _apk.canInstallPackages()) {
      AppLog.w('Обновление: нет разрешения на установку из приложения');
      throw const NeedsInstallPermission();
    }

    // 3. Передать установщику. Запись pending.json — ДО вызова: установщик
    //    может снять процесс раньше, чем мы дописали бы её после.
    final pending = PendingInstall(
      version: version,
      startedAt: clock().toUtc(),
      exePath: verified.path,
      // Журнала у системного установщика нет.
      logPath: '',
    );
    await writePending(pending);
    try {
      await _apk.installApk(verified.path);
    } on ApkInstallRefused {
      // Установщик не принял файл — итога ждать нечего, запись снимаем.
      await _dropPending();
      AppLog.e('Обновление: системный установщик не принял APK');
      throw const UpdateInstallException('системный установщик не запустился');
    }
    AppLog.i('Обновление: APK $version передан системному установщику');
  }

  /// База чистит `AppPaths.supportDir()/updates` — на Android это не наш
  /// каталог, поэтому та же логика поверх [stagingDir].
  @override
  Future<void> purgeStaging({String? keepVersion}) async {
    final dir = await stagingDir();
    for (final entry in dir.listSync()) {
      final name = entry.uri.pathSegments
          .lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (name == PendingInstall.fileName) continue;
      if (keepVersion != null &&
          keepVersion.isNotEmpty &&
          name.contains(keepVersion)) {
        continue;
      }
      try {
        entry.deleteSync(recursive: true);
      } catch (_) {
        // Файл занят установщиком — уберём в следующий раз.
      }
    }
  }

  Future<void> _dropPending() async {
    try {
      final f = await pendingFile();
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
