import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_info.dart';

/// Версия приложения живёт в НЕСКОЛЬКИХ местах и синхронизируется руками
/// (правило из CLAUDE.md §4). Рассинхрон незаметен глазу, но ломает вещи:
/// `AppInfo.version` уезжает в User-Agent и заголовок `X-App-Version`, по
/// которым панель Remnawave считает клиентов, а `pubspec.yaml` определяет
/// версию сборки. На Android появится третье место — `versionName` в Gradle,
/// который Flutter берёт из того же `pubspec`.
void main() {
  group('AppInfo', () {
    test('версия и номер сборки (+N) совпадают с pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(m, isNotNull,
          reason: 'в pubspec.yaml не найдена строка version: X.Y.Z+N');
      expect(
        AppInfo.version,
        m!.group(1),
        reason: 'AppInfo.version разошёлся с pubspec.yaml — при бампе версии '
            'правятся ОБА места (плюс CHANGELOG и README)',
      );
      expect(
        AppInfo.buildNumber,
        int.parse(m.group(2)!),
        reason: 'AppInfo.buildNumber разошёлся с +N в pubspec.yaml',
      );
      expect(AppInfo.fullVersion, '${AppInfo.version}+${AppInfo.buildNumber}');
    });

    test('formatAboutVersion сохраняет +N, пре-релиз, Git SHA и нормализует split-ABI Android', () {
      expect(
        AppInfo.formatAboutVersion(
          runtimeVersion: '1.18.0',
          runtimeBuildNumber: '91',
          isAndroid: false,
        ),
        'v1.18.0+91',
      );
      // Android --split-per-abi прибавляет 2000 (arm64) или 4000 (x86_64).
      expect(
        AppInfo.formatAboutVersion(
          runtimeVersion: '1.18.0',
          runtimeBuildNumber: '2091',
          isAndroid: true,
        ),
        'v1.18.0+91',
      );
      expect(
        AppInfo.formatAboutVersion(
          runtimeVersion: '1.18.0',
          runtimeBuildNumber: '4091',
          preReleaseOverride: 'beta.1',
          gitCommitOverride: 'a9101d0',
          isAndroid: true,
        ),
        'v1.18.0-beta.1+91 (a9101d0)',
      );
      expect(AppInfo.patchEntriesForLocale('ru'), isNotEmpty);
      expect(AppInfo.patchEntriesForLocale('en'), isNotEmpty);
    });

    test('User-Agent имеет формат «Имя/версия (платформа)»', () {
      // Панель сопоставляет UA правилом `user-agent CONTAINS SilentGate`,
      // сверка регистрозависимая и требует формата «Имя/версия». Отклонение
      // = base64 вместо XRAY_JSON = молча теряются профили «Авто» и hysteria2.
      expect(
        AppInfo.userAgent,
        matches(RegExp(r'^SilentGate/[0-9]+\.[0-9]+\.[0-9]+ \([A-Za-z]+\)$')),
      );
      expect(AppInfo.userAgent, contains(AppInfo.name));
      expect(AppInfo.userAgent, contains(AppInfo.version));
    });

    test('метка платформы соответствует текущей ОС', () {
      // Тесты гоняются на машине разработчика (Windows/Linux/macOS CI),
      // поэтому проверяем не конкретное значение, а согласованность.
      expect(AppInfo.platformTag, isNotEmpty);
      expect(AppInfo.platformTag, isNot('Unknown'));
      if (Platform.isWindows) expect(AppInfo.platformTag, 'Windows');
      if (Platform.isLinux) expect(AppInfo.platformTag, 'Linux');
      if (Platform.isMacOS) expect(AppInfo.platformTag, 'macOS');
    });

    // ⚠️ Канал — свойство СБОРКИ (`String.fromEnvironment`), а не настроек:
    // обычный прогон `flutter test`/`flutter run` не передаёт
    // `--dart-define=SILENTGATE_CHANNEL=beta`, поэтому здесь всегда видна
    // именно СТАБИЛЬНАЯ ветка. Она и есть то, что обязано остаться
    // умолчанием: build-скрипты добавляют define только при осознанной
    // бета-сборке (build-exe.bat/build-apk.bat, переменная SILENTGATE_CHANNEL).
    test('без --dart-define канал пуст, isBeta=false', () {
      expect(AppInfo.channel, isEmpty,
          reason: 'обычная сборка не задаёт канал вовсе — иначе бета '
              'просочилась бы в стабильный релиз незаметно');
      expect(AppInfo.isBeta, isFalse);
    });

    test('isBeta — это ровно проверка channel == "beta"', () {
      // Не проверка значения (его меняет только --dart-define на сборке),
      // а страж на РЕАЛИЗАЦИЮ: если кто-то заменит сравнение на isNotEmpty
      // или на что-то ещё, любой другой канал ('dev', опечатка) молча стал
      // бы читаться как бета.
      expect(AppInfo.isBeta, AppInfo.channel == 'beta');
    });
  });
}
