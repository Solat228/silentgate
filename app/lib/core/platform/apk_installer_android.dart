import 'package:flutter/services.dart';

import '../update/app_update_defaults.dart';

/// Нативная сторона ответила `false`: файла нет, он вне `cacheDir/updates/`
/// либо системный установщик не запустился (нет активности под ACTION_VIEW —
/// бывает на урезанных прошивках). Подробность — в logcat `SilentGateUpdate`;
/// интерфейсу достаточно факта, чтобы показать ссылку вместо кнопки.
class ApkInstallRefused implements Exception {
  final String path;
  const ApkInstallRefused(this.path);

  @override
  String toString() => 'ApkInstallRefused: установщик не принял файл';
}

/// Android: установка скачанного APK через СИСТЕМНЫЙ установщик.
///
/// Тихой установки без root на Android нет — приложение может лишь передать
/// файл установщику (`ACTION_VIEW` + `application/vnd.android.package-archive`),
/// а лист согласия человек видит всегда. Нативная сторона — `platform/
/// PlatformChannels.kt` (`handleLauncher`: `installApk`, `canInstallPackages`,
/// `openInstallPermission`; `handleDevice`: `abi`).
///
/// ⚠️ Файл обязан лежать в `cacheDir/updates/` (см. `UpdateInstallerAndroid.
/// stagingDir` и `res/xml/file_paths.xml`): Kotlin отвергает любой другой путь,
/// иначе канал выдавал бы наружу произвольные файлы приложения.
class ApkInstallerAndroid {
  /// Те же каналы, что у `AndroidDeviceId` и `AndroidAppLauncher`; свои
  /// экземпляры — только для тестов.
  final MethodChannel _device;
  final MethodChannel _launcher;

  ApkInstallerAndroid({MethodChannel? device, MethodChannel? launcher})
      : _device = device ?? const MethodChannel('lol.silentgate/device'),
        _launcher = launcher ?? const MethodChannel('lol.silentgate/launcher');

  /// Суффикс имени актива релиза под ABI устройства; `null` — сборки под эту
  /// ABI нет (armeabi-v7a, x86), и подбирать «похожую» нельзя: чужая ABI
  /// установится и не запустится, а versionCode у x86_64 (4000+) больше, чем
  /// у arm64 (2000+), — она выглядела бы «новее».
  ///
  /// Таблица одна на приложение — [androidAssetHintForAbi] в
  /// `app_update_defaults.dart` (проверка обновлений выбирает актив по ней же).
  static String? assetHintForAbi(String? abi) => androidAssetHintForAbi(abi);

  /// Предпочтительная ABI устройства (`Build.SUPPORTED_ABIS[0]`); `null` —
  /// канала нет или он не ответил.
  Future<String?> deviceAbi() async {
    try {
      final v = await _device.invokeMethod<String>('abi');
      final s = (v ?? '').trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// Выдано ли разрешение на установку из этого приложения (API 26+). Сбой
  /// канала — `false`: лучше лишний раз отправить человека в настройки, чем
  /// дёрнуть установщик и получить молчание.
  Future<bool> canInstallPackages() async {
    try {
      return await _launcher.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Открыть системный экран выдачи разрешения. Ошибки глотаются: экрана на
  /// части прошивок нет, и падать из-за этого нельзя.
  Future<void> openInstallPermission() async {
    try {
      await _launcher.invokeMethod<bool>('openInstallPermission');
    } catch (_) {}
  }

  /// Передать APK установщику. Бросает [ApkInstallRefused], если нативная
  /// сторона отказала; сбой самого канала — тоже отказ.
  Future<void> installApk(String path) async {
    bool ok;
    try {
      ok = await _launcher.invokeMethod<bool>('installApk', {'path': path}) ??
          false;
    } catch (_) {
      ok = false;
    }
    if (!ok) throw ApkInstallRefused(path);
  }
}
