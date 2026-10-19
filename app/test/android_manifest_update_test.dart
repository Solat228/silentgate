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
  final githubManifest =
      File('$root/android/app/src/github/AndroidManifest.xml')
          .readAsStringSync();
  final gradle = File('$root/android/app/build.gradle.kts').readAsStringSync();
  final mainActivity =
      File('$androidMain/kotlin/lol/silentgate/MainActivity.kt')
          .readAsStringSync();

  group('AndroidManifest.xml', () {
    // ⚠️ Разрешение живёт ТОЛЬКО в сборке github. Сборке play его иметь
    // нельзя: правило Google Play «Device and Network Abuse» запрещает
    // приложению из Play обновлять себя мимо Play, и с этим разрешением
    // приложение не пройдёт проверку. Перенос строки обратно в main
    // незаметен ни компилятору, ни Gradle — ловит только этот тест.
    test('⚠️ REQUEST_INSTALL_PACKAGES — только в src/github, не в main', () {
      expect(manifest,
          isNot(contains('<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"')));
      expect(githubManifest,
          contains('android.permission.REQUEST_INSTALL_PACKAGES'));
      expect(Directory('$root/android/app/src/play').existsSync(), isFalse,
          reason: 'у сборки play не должно быть своего манифеста с лишним');
    });

    test('сборка github видит Google Play (<queries>)', () {
      // С Android 11 чужой пакет без <queries> невидим: playStoreInstalled
      // отвечал бы «нет» всегда, и обновление через Play не предлагалось бы.
      expect(githubManifest,
          contains('<package android:name="com.android.vending"/>'));
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

    test('нет корня шире SilentGate/support/, SilentGate/export/ и updates/',
        () {
      // Всё, что объявлено, — ровно три узких корня. Любой новый или
      // расширенный (`path="."`, `path="SilentGate/"`) открыл бы наружу
      // подписки с токенами.
      final tags = RegExp(r'<(files-path|cache-path|external-[a-z-]*path|root-path)\b[^>]*>')
          .allMatches(filePaths)
          .map((m) => m.group(0)!)
          .toList();
      expect(tags, hasLength(3));
      for (final t in tags) {
        final path = RegExp(r'path="([^"]*)"').firstMatch(t)?.group(1);
        expect(path,
            anyOf('SilentGate/support/', 'SilentGate/export/', 'updates/'),
            reason: 'лишний корень FileProvider: $t');
      }
      final filesTags = tags.where((t) => t.startsWith('<files-path'));
      expect(filesTags, hasLength(2));
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

    test('методы Google Play разбираются ВЫШЕ проверки пустого url', () {
      final body = channels.substring(channels.indexOf('fun handleLauncher('));
      final urlGuard = body.indexOf('if (target.isEmpty())');
      for (final m in const ['"playStoreInstalled"', '"openPlayStore"']) {
        final at = body.indexOf(m);
        expect(at, greaterThan(0), reason: '$m не найден в handleLauncher');
        expect(at, lessThan(urlGuard), reason: m);
      }
    });

    test('⚠️ сборка play отказывает в установке ДО разбора методов установки',
        () {
      final body = channels.substring(channels.indexOf('fun handleLauncher('));
      final guard = body.indexOf('BuildConfig.FLAVOR == "play"');
      expect(guard, greaterThan(0), reason: 'вторая стена в Kotlin пропала');
      for (final m in const [
        '"canInstallPackages"',
        '"openInstallPermission"',
        '"installApk"',
      ]) {
        expect(body.indexOf(m), greaterThan(guard),
            reason: '$m разбирается до запрета сборки play');
      }
      expect(
          channels,
          contains(
              'setOf("canInstallPackages", "openInstallPermission", "installApk")'));
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

  group('build.gradle.kts — две сборки', () {
    test('флейворы github (по умолчанию) и play', () {
      expect(gradle, contains('flavorDimensions += "store"'));
      expect(gradle, contains('create("github")'));
      expect(gradle, contains('isDefault = true'));
      expect(gradle, contains('create("play")'));
      expect(gradle, contains('buildConfig = true'));
    });

    test('⚠️ код версии play = код arm64-APK (2000 + N)', () {
      // Меньший код не встанет поверх APK с GitHub — версии перестанут
      // обновлять друг друга.
      expect(gradle, contains('versionCode = 2000 + flutter.versionCode'));
    });

    test('⚠️ AAB для Play — только ABI, под которые есть ядро', () {
      // Плагин jni приносит armeabi-v7a; без фильтра Play раздавал бы
      // приложение 32-битным телефонам, где туннель не поднимется.
      // ndk.abiFilters у флейвора не работает: Flutter добавляет все ABI.
      expect(gradle, contains('jniLibs { excludes += "lib/armeabi-v7a/**" }'));
    });

    test('⚠️ подписи: github — ключ выпуска, play — ключ загрузки', () {
      final github = gradle.substring(gradle.indexOf('create("github")'),
          gradle.indexOf('create("play")'));
      final play = gradle.substring(gradle.indexOf('create("play")'),
          gradle.indexOf('buildTypes {'));
      expect(github, contains('signingConfigs.findByName("release")'));
      expect(play, contains('signingConfigs.findByName("upload")'));
      // Подпись у типа сборки перекрыла бы подпись флейвора.
      final buildTypes = gradle.substring(gradle.indexOf('buildTypes {'));
      expect(buildTypes, isNot(contains('signingConfig =')));
    });
  });
}
