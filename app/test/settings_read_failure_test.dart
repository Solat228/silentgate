import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/data/settings_storage.dart';

/// Файл настроек есть, но прочитать его не вышло. Аудит 25.10.2026, G:
/// раньше брались значения по умолчанию, и первое же сохранение затирало
/// настройки пользователя без следа.
void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_settings_read_');
    AppPaths.overrideRoot(tmp);
    file = File('${tmp.path}${Platform.pathSeparator}silentgate_settings.json');
    SettingsStorage.readRetryDelay = const Duration(milliseconds: 40);
  });

  tearDown(() {
    AppPaths.resetForTests();
    SettingsStorage.readRetryDelay = const Duration(milliseconds: 300);
    tmp.deleteSync(recursive: true);
  });

  test('сбой чтения проходит сам — настройки берутся из файла', () async {
    file.writeAsStringSync('SGDPAPI1:!!!');
    final real = jsonEncode(
        AppSettings.defaults.copyWith(killSwitch: true).toJson());
    // Файл «отпустили» во время повторов.
    Timer(const Duration(milliseconds: 10), () => file.writeAsStringSync(real));
    final s = await SettingsStorage().load();
    expect(s.killSwitch, isTrue);
  });

  test('не прочитался совсем — копия остаётся в .bad', () async {
    file.writeAsStringSync('SGDPAPI1:!!!');
    final s = await SettingsStorage().load();
    expect(s.killSwitch, AppSettings.defaults.killSwitch);
    final bad = File('${file.path}.bad');
    expect(bad.existsSync(), isTrue);
    expect(bad.readAsStringSync(), 'SGDPAPI1:!!!');
  });
}
