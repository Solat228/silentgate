import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/data/settings_backup.dart';

/// Android Auto Backup (P11): в копию Google идёт ТОЛЬКО снимок, который
/// собирает приложение. Журналы, кэш значков, гео-базы и секреты сессии туда
/// не попадают по построению. Страж — на файлы, которые не компилируются
/// вместе с Dart: манифест и два XML правил.
void main() {
  const main = 'android/app/src/main';
  String read(String p) => File('$main/$p').readAsStringSync();
  final snapshotPath =
      'SilentGate/${SettingsBackup.snapshotDir}/';

  test('бэкап включён и указывает на оба файла правил', () {
    final m = read('AndroidManifest.xml');
    expect(m, contains('android:allowBackup="true"'));
    expect(m, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(m, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  test('⚠️ Android 12+: в облако и на новое устройство — только снимок', () {
    final x = read('res/xml/data_extraction_rules.xml')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    final includes = RegExp(r'<include\b[^>]*>').allMatches(x).toList();
    expect(includes, hasLength(2), reason: 'cloud-backup и device-transfer');
    for (final i in includes) {
      expect(i.group(0), contains('domain="file"'));
      expect(i.group(0), contains('path="$snapshotPath"'));
    }
    expect(x, contains('disableIfNoEncryptionCapabilities="true"'),
        reason: 'токен подписки — только в копию с шифрованием на устройстве');
    expect(x, isNot(contains('<exclude')),
        reason: 'при include система и так берёт только перечисленное');
  });

  test('⚠️ Android 11 и ниже: только снимок и только с шифрованием', () {
    final x = read('res/xml/backup_rules.xml')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    final includes = RegExp(r'<include\b[^>]*>').allMatches(x).toList();
    expect(includes, hasLength(1));
    expect(includes.single.group(0), contains('path="$snapshotPath"'));
    expect(includes.single.group(0),
        contains('requireFlags="clientSideEncryption"'));
  });

  test('метод перезапуска объявлен до проверки пустого url', () {
    final k = File('$main/kotlin/lol/silentgate/platform/PlatformChannels.kt')
        .readAsStringSync();
    final launcher = k.indexOf('fun handleLauncher(');
    final restart = k.indexOf('"restartApp"', launcher);
    final urlCheck = k.indexOf('if (target.isEmpty())', launcher);
    expect(restart, greaterThan(launcher));
    expect(restart, lessThan(urlCheck));
  });
}
