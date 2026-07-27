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
    test('версия совпадает с pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
          .firstMatch(pubspec);

      expect(m, isNotNull, reason: 'в pubspec.yaml не найдена строка version:');
      expect(
        AppInfo.version,
        m!.group(1),
        reason: 'AppInfo.version разошёлся с pubspec.yaml — при бампе версии '
            'правятся ОБА места (плюс CHANGELOG и README)',
      );
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
  });
}
