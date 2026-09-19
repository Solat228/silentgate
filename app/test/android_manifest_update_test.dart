import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// СТРАЖ ФАЙЛОВ САМООБНОВЛЕНИЯ НА ANDROID.
///
/// Установка APK держится на договорённостях между четырьмя файлами, которые
/// не компилируются вместе: манифест (разрешение), `file_paths.xml` (корень
/// FileProvider), `PlatformChannels.kt` (методы канала) и Dart-обёртка. Ни
/// компилятор, ни Gradle расхождение не увидят: без разрешения интент молча
/// не сработает, без `cache-path` FileProvider бросит «Failed to find
/// configured root», а метод, разобранный НИЖЕ проверки пустого `url`, будет
/// вечно отвечать `false` — и всё это выглядит как «кнопка ничего не делает».
void main() {
  final root = Directory.current.path.endsWith('app')
      ? Directory.current.path
      : '${Directory.current.path}/app';
  final androidMain = '$root/android/app/src/main';
  final manifest = File('$androidMain/AndroidManifest.xml').readAsStringSync();
  final filePaths =
      File('$androidMain/res/xml/file_paths.xml').readAsStringSync();
  final channels = File(
          '$androidMain/kotlin/lol/silentgate/platform/PlatformChannels.kt')
      .readAsStringSync();
  final mainActivity =
      File('$androidMain/kotlin/lol/silentgate/MainActivity.kt')
          .readAsStringSync();

  group('AndroidManifest.xml', () {
    test('есть REQUEST_INSTALL_PACKAGES', () {
      expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    });

    test('FileProvider authority — applicationId.fileprovider (как в Kotlin)',
        () {
      expect(manifest, contains(r'${applicationId}.fileprovider'));
      expect(channels, contains('context.packageName + ".fileprovider"'));
    });
  });

  group('file_paths.xml', () {
    test('есть cache-path updates/', () {
      expect(
        RegExp(r'<cache-path\s+name="updates"\s+path="updates/"\s*/>')
            .hasMatch(filePaths),
        isTrue,
        reason: 'FileProvider должен знать каталог обновлений',
      );
    });

    test('нет корня шире SilentGate/support/ и updates/', () {
      // Всё, что объявлено, — ровно два узких корня. Любой новый или
      // расширенный (`path="."`, `path="SilentGate/"`) открыл бы наружу
      // подписки с токенами.
      final tags = RegExp(r'<(files-path|cache-path|external-[a-z-]*path|root-path)\b[^>]*>')
          .allMatches(filePaths)
          .map((m) => m.group(0)!)
          .toList();
      expect(tags, hasLength(2));
      for (final t in tags) {
        final path = RegExp(r'path="([^"]*)"').firstMatch(t)?.group(1);
        expect(path, anyOf('SilentGate/support/', 'updates/'),
            reason: 'лишний корень FileProvider: $t');
      }
      final filesTags = tags.where((t) => t.startsWith('<files-path'));
      expect(filesTags, hasLength(1));
      expect(filesTags.single, contains('path="SilentGate/support/"'));
    });
  });

  group('PlatformChannels.kt', () {
    test('методы канала объявлены', () {
      expect(channels, contains('"installApk"'));
      expect(channels, contains('"canInstallPackages"'));
      expect(channels, contains('"openInstallPermission"'));
      expect(channels, contains('"abi"'));
    });

    test('MIME установщика и грант на чтение', () {
      expect(channels, contains('application/vnd.android.package-archive'));
      expect(channels, contains('FLAG_GRANT_READ_URI_PERMISSION'));
      expect(channels, contains('Intent.ACTION_VIEW'));
      expect(channels, contains('Build.SUPPORTED_ABIS'));
    });

    test('⚠️ методы установки разбираются ВЫШЕ проверки пустого url', () {
      final launcher = channels.indexOf('fun handleLauncher(');
      expect(launcher, greaterThan(0));
      final body = channels.substring(launcher);
      // Проверка пустого url — первая, что отвечает false на всё подряд.
      final urlGuard = body.indexOf('if (target.isEmpty())');
      expect(urlGuard, greaterThan(0));
      for (final m in const [
        '"canInstallPackages"',
        '"openInstallPermission"',
        '"installApk"',
      ]) {
        final at = body.indexOf(m);
        expect(at, greaterThan(0), reason: '$m не найден в handleLauncher');
        expect(at, lessThan(urlGuard),
            reason: '$m разбирается после проверки url — будет вечное false');
      }
    });

    test('installApk ограничен каталогом cacheDir/updates', () {
      expect(channels, contains('context.cacheDir'));
      expect(channels, contains('canonicalPath'));
      expect(channels, contains('"updates"'));
    });

    test('MainActivity передаёт аргумент path', () {
      expect(mainActivity, contains('call.argument<String>("path")'));
    });
  });
}
