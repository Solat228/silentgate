import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/autostart_windows.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/app_state.dart';

/// Автозапуск с Windows (решение владельца 24.09.2026: выключен, включается в
/// настройках). Реестр хоста в тестах не трогаем — это автозагрузка владельца.
void main() {
  test('строка Run: путь в кавычках и флаг', () {
    const exe = r'C:\Users\Иван Петров\AppData\Local\Programs\SilentGate\silentgate.exe';
    final cmd = AutostartWindows.commandFor(exe);
    expect(cmd, '"$exe" --autostart');
    expect(AutostartWindows.launchedByAutostart(['--autostart']), isTrue);
    expect(AutostartWindows.launchedByAutostart(['silentgate://connect']),
        isFalse);
  });

  test('разбор reg query: значение с пробелами целиком', () {
    const out = '\r\n'
        r'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
        '\r\n'
        r'    SilentGate    REG_SZ    "C:\Program Files\SG\silentgate.exe" --autostart'
        '\r\n\r\n';
    expect(AutostartWindows.parseQuery(out),
        r'"C:\Program Files\SG\silentgate.exe" --autostart');
  });

  test('чужое значение с похожим именем не принимается за наше', () {
    const out = r'    SilentGateHelper    REG_SZ    "C:\x.exe"';
    expect(AutostartWindows.parseQuery(out), isNull);
    expect(AutostartWindows.parseQuery(''), isNull);
  });

  test('по умолчанию выключено, оба флага переживают JSON', () {
    const d = AppSettings();
    expect(d.launchAtLogin, isFalse);
    expect(d.connectOnAutostart, isFalse);
    final s = AppSettings.fromJson(
        const AppSettings(launchAtLogin: true, connectOnAutostart: true)
            .toJson());
    expect(s.launchAtLogin, isTrue);
    expect(s.connectOnAutostart, isTrue);
  });

  group('подключаться ли после автозапуска', () {
    const on = AppSettings(launchAtLogin: true, connectOnAutostart: true);

    bool decide({
      bool autostart = true,
      AppSettings settings = on,
      bool connected = false,
      bool hasServers = true,
    }) =>
        AppState.shouldConnectOnAutostart(
            autostart: autostart,
            settings: settings,
            connected: connected,
            hasServers: hasServers);

    test('все условия — да', () => expect(decide(), isTrue));

    test('⚠️ ручной запуск никогда не подключает сам',
        () => expect(decide(autostart: false), isFalse));

    test('галочка подключения выключена — нет', () {
      expect(
          decide(
              settings: const AppSettings(
                  launchAtLogin: true, connectOnAutostart: false)),
          isFalse);
    });

    test('автозапуск выключен в настройках — нет, даже с флагом в запуске', () {
      // Запись в Run могла остаться от прошлой установки.
      expect(
          decide(
              settings: const AppSettings(
                  launchAtLogin: false, connectOnAutostart: true)),
          isFalse);
    });

    test('подхваченный туннель и пустой список — не трогаем', () {
      expect(decide(connected: true), isFalse);
      expect(decide(hasServers: false), isFalse);
    });
  });

  test('main: автозапуск прячет окно и не всплывает поверх работающего', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('init(startHidden: autostart)'));
    expect(src, contains('if (autostart) exit(0);'));
    expect(src, contains('AutostartWindows.sync(s.launchAtLogin)'));
  });

  test('чистка при удалении снимает автозапуск', () {
    final src = File('lib/core/platform/app_cleanup.dart').readAsStringSync();
    expect('AutostartWindows.remove()'.allMatches(src).length, 2,
        reason: 'и деинсталлятор, и «Удалить все данные»');
  });
}
