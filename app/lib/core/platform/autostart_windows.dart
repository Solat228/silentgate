import 'dart:io';

import 'app_env.dart';
import 'app_log.dart';
import 'package_identity_windows.dart';

/// Запуск вместе с Windows: значение в `HKCU\…\CurrentVersion\Run`.
///
/// Решение владельца (24.09.2026): по умолчанию ВЫКЛЮЧЕН, включается в
/// настройках. Приложение при автозапуске стартует свёрнутым в трей — окно
/// посреди экрана при каждом входе в систему раздражает и учит выключать
/// автозапуск совсем.
///
/// ⚠️ ПОЧЕМУ `Run`, А НЕ ЗАДАЧА ПЛАНИРОВЩИКА. Задача нужна ради прав
/// администратора (так делает TUN), а приложению при входе права не нужны:
/// туннель всё равно поднимается через свою задачу `SilentGateTun`. `Run` в
/// HKCU пишется без UAC и виден человеку в «Диспетчере задач → Автозагрузка»,
/// где его можно выключить привычным способом.
///
/// ⚠️ ИСТОЧНИК ПРАВДЫ — НАСТРОЙКА, А НЕ РЕЕСТР. На каждом старте значение
/// сверяется с ней ([sync]): после переустановки в другую папку путь в `Run`
/// устарел бы, а чистка при удалении снимает его без ведома настроек.
abstract final class AutostartWindows {
  static const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const valueName = 'SilentGate';

  /// Аргумент, по которому приложение узнаёт, что его запустила система.
  static const flag = '--autostart';

  /// Строка для `Run`: путь в кавычках (в нём бывают пробелы) и флаг.
  static String commandFor(String exe) => '"$exe" $flag';

  /// Запущено ли приложение системой при входе.
  static bool launchedByAutostart(List<String> args) => args.contains(flag);

  /// Изолированная тестовая копия (`SILENTGATE_PORT_OFFSET`) в автозапуск не
  /// пишется никогда: она заводится, чтобы не трогать установленную, а `Run`
  /// у них общий.
  static bool get applicable => Platform.isWindows && AppEnv.portOffset == 0;

  /// Значение `Run` из вывода `reg query` или `null`.
  static String? parseQuery(String regOut) {
    for (final line in regOut.split(RegExp(r'\r?\n'))) {
      final m = RegExp(r'^\s*' + valueName + r'\s+REG_SZ\s+(.*)$')
          .firstMatch(line);
      if (m != null) return m.group(1)!.trim();
    }
    return null;
  }

  /// Привести реестр к настройке [enabled]. Никогда не бросает.
  static Future<void> sync(bool enabled) async {
    if (!applicable) return;
    try {
      // В пакете MSIX — постоянный псевдоним: путь самого exe меняется с
      // каждым обновлением из Store.
      final want = commandFor(PackageIdentity.launchPath());
      final have = await _current();
      if (enabled) {
        if (have == want) return;
        final r = await Process.run('reg', [
          'add', runKey, '/v', valueName, '/t', 'REG_SZ', '/d', want, '/f'
        ]);
        if (r.exitCode == 0) {
          AppLog.i(have == null
              ? 'Автозапуск с Windows включён'
              : 'Автозапуск с Windows: путь обновлён');
        } else {
          AppLog.w('Автозапуск не включён: reg add вернул ${r.exitCode}');
        }
      } else {
        if (have == null) return;
        await remove();
        AppLog.i('Автозапуск с Windows выключен');
      }
    } catch (e) {
      AppLog.w('Автозапуск: не удалось свериться с реестром: $e');
    }
  }

  /// Снять значение (настройка выключена или приложение удаляется).
  static Future<void> remove() async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('reg', ['delete', runKey, '/v', valueName, '/f']);
    } catch (_) {}
  }

  static Future<String?> _current() async {
    final r = await Process.run('reg', ['query', runKey, '/v', valueName]);
    if (r.exitCode != 0) return null;
    return parseQuery('${r.stdout}');
  }
}
