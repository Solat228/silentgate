import 'dart:io';

import 'update_installer.dart';

/// Один вызов [FakeUpdateInstaller.launch] — что именно просили запустить.
class FakeLaunch {
  final File file;
  final String version;
  final String expectedSha256;
  final bool forceQuit;
  final bool allowDowngrade;

  const FakeLaunch({
    required this.file,
    required this.version,
    required this.expectedSha256,
    required this.forceQuit,
    required this.allowDowngrade,
  });
}

/// Подменный установщик для тестов контроллера обновлений.
///
/// Ничего не запускает и не читает: записывает вызовы и отдаёт то, что в
/// него положил тест. Лежит в `lib/`, а не в `test/`, чтобы им могли
/// пользоваться тесты разных файлов без копирования.
class FakeUpdateInstaller implements UpdateInstaller {
  /// Каталог закачек — тест даёт временный.
  final Directory staging;

  FakeUpdateInstaller({required this.staging});

  /// Что ответит [capability].
  InstallCapability capabilityResult = InstallCapability.ready;

  /// Что ответит ПЕРВЫЙ [reconcileAfterStart]; дальше — `null`, как и у
  /// настоящего (файл после разбора удалён).
  PendingResult? pendingResult;

  /// Что ответит [canInstallNow].
  bool canInstallNowResult = true;
  int canInstallNowCalls = 0;

  /// Если задано — [launch] бросает это вместо записи вызова.
  Object? launchError;

  final List<FakeLaunch> launches = [];
  final List<String> reconcileCalls = [];
  final List<String?> purgeCalls = [];
  int capabilityCalls = 0;

  @override
  Future<Directory> stagingDir() async {
    if (!staging.existsSync()) staging.createSync(recursive: true);
    return staging;
  }

  @override
  Future<InstallCapability> capability() async {
    capabilityCalls++;
    return capabilityResult;
  }

  @override
  Future<bool> canInstallNow() async {
    canInstallNowCalls++;
    return canInstallNowResult;
  }

  @override
  Future<void> launch(
    File verified, {
    required String version,
    required String expectedSha256,
    bool forceQuit = false,
    bool allowDowngrade = false,
  }) async {
    final err = launchError;
    if (err != null) throw err;
    launches.add(FakeLaunch(
      file: verified,
      version: version,
      expectedSha256: expectedSha256,
      forceQuit: forceQuit,
      allowDowngrade: allowDowngrade,
    ));
  }

  @override
  Future<PendingResult?> reconcileAfterStart({required String currentVersion}) async {
    reconcileCalls.add(currentVersion);
    final r = pendingResult;
    pendingResult = null;
    return r;
  }

  @override
  Future<void> purgeStaging({String? keepVersion}) async {
    purgeCalls.add(keepVersion);
  }
}
