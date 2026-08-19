import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/platform/app_paths.dart';
import '../elevation.dart';
import 'tun_helper.dart';

/// Запуск TUN без UAC при каждом подключении.
///
/// Идея: один раз (с одним UAC) создаём задачу Планировщика с «Высшими правами».
/// Дальше `schtasks /Run` стартует её **без UAC**. Задача запускает
/// `silentgate.exe --tun-task "<config>" "<stop>"` с ЯВНЫМИ путями (per-user appdata
/// GUI): так туннель читает правильный конфиг, даже если задача выполняется от
/// ОТДЕЛЬНОГО админа (у него другой `%APPDATA%`, #7).
class TunScheduledTask {
  static const taskName = 'SilentGateTun';

  /// Задача зарегистрирована в Планировщике?
  static Future<bool> exists() async {
    try {
      final r = await Process.run('schtasks', ['/Query', '/TN', taskName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Путь к exe и аргументы, которые задача ДОЛЖНА запускать сейчас.
  ///
  /// ⚠️ ВЫНЕСЕНО ОТДЕЛЬНО, ЧТОБЫ БЫЛО С ЧЕМ СРАВНИВАТЬ. Раньше строка запуска
  /// существовала только внутри [install] — то есть проверить, ту ли программу
  /// запускает уже созданная задача, было нечем.
  static Future<({String exe, String args})> expected() async {
    final dir = await AppPaths.supportDir();
    return (
      exe: Platform.resolvedExecutable,
      args: '--tun-task "${TunHelper.configPathFor(dir)}" '
          '"${TunHelper.stopFilePathFor(dir)}"',
    );
  }

  /// Запускает ли СУЩЕСТВУЮЩАЯ задача именно то, что нужно сейчас.
  ///
  /// ⚠️ РАДИ ЧЕГО ЭТО ЕСТЬ. Задача создаётся один раз и не пересматривается
  /// никогда: путь настройки первой строкой делает `if (isConfigured()) return`.
  /// На машине владельца это дало задачу от 20.07.2026, которая до сих пор
  /// запускает **exe из папки сборки** (`appuild\…\Release`) и с голым
  /// `--tun-task` без путей конфига и stop-файла. Следствия тихие и разные:
  /// после обновления интерфейс новый, а туннельное ядро старое; правка с
  /// явными путями (#7) не применилась вовсе; удалите папку сборки — и TUN
  /// перестанет подниматься, а выглядеть это будет как «не работает VPN».
  ///
  /// Возвращает `false` и когда задачи нет, и когда прочитать её не удалось:
  /// «не знаю» здесь обязано вести себя как «не подходит», иначе мы снова
  /// запустим чужой бинарь.
  static Future<bool> isCurrent() async {
    try {
      final r = await Process.run(
          'schtasks', ['/Query', '/TN', taskName, '/XML'],
          stdoutEncoding: null);
      if (r.exitCode != 0) return false;
      // ⚠️ Вывод в UTF-16LE с BOM: `schtasks /XML` печатает именно так, и
      // системная кодировка его не берёт — строка приходила мусором, а
      // сравнение всегда давало «не совпало».
      final want = await expected();
      return matches(decodeUtf16(r.stdout as List<int>), want.exe, want.args);
    } catch (_) {
      return false;
    }
  }

  /// Совпадает ли XML задачи с ожидаемой командой.
  ///
  /// ⚠️ ЧИСТАЯ ФУНКЦИЯ НАМЕРЕННО. Сам [isCurrent] запускает `schtasks` и в
  /// тестах недоступен, а ошибка сравнения здесь тихая и дорогая: «совпало» на
  /// самом деле означает «запускаем чужой бинарь под правами администратора».
  @visibleForTesting
  static bool matches(String xml, String exe, String args) {
    // Пути сравниваем без учёта регистра: Windows его не различает, а
    // Планировщик возвращает то, что записали.
    return tag(xml, 'Command').toLowerCase() == exe.toLowerCase() &&
        tag(xml, 'Arguments').toLowerCase() == args.toLowerCase();
  }

  /// Содержимое одного тега XML. Полноценный разбор здесь не нужен: оба поля
  /// плоские и без вложенности.
  ///
  /// ⚠️ `&quot;` разворачивается обратно в кавычку: пути с пробелами Планировщик
  /// хранит экранированными, и без этого сравнение не совпадало бы НИКОГДА —
  /// то есть задача всегда считалась бы устаревшей, а запуск без UAC пропал бы
  /// у всех.
  @visibleForTesting
  static String tag(String xml, String name) {
    final m = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    return (m?.group(1) ?? '').trim().replaceAll('&quot;', '"');
  }

  /// ⚠️ `schtasks /XML` печатает UTF-16LE с меткой порядка байт. Системная
  /// кодировка его не берёт: строка приходила мусором, и сравнение не совпало
  /// бы ни разу.
  @visibleForTesting
  static String decodeUtf16(List<int> bytes) {
    var b = bytes;
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) b = b.sublist(2);
    final units = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      units.add(b[i] | (b[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  /// Создать/пересоздать задачу. Показывает UAC ОДИН раз. true — запуск подтверждён.
  ///
  /// Ждём появления задачи: `ShellExecuteEx` возвращает управление сразу, а schtasks
  /// отрабатывает уже в элевейтнутом процессе.
  static Future<bool> install() async {
    final exe = Platform.resolvedExecutable;
    // Пути к конфигу/stop берём из per-user appdata GUI и ЗАПЕКАЕМ в команду
    // задачи — иначе задача, выполняясь от отдельного админа, читала бы чужой
    // %APPDATA% и поднимала туннель по пустому конфигу (#7).
    final dir = await AppPaths.supportDir();
    final cfg = TunHelper.configPathFor(dir);
    final stop = TunHelper.stopFilePathFor(dir);
    final args =
        '/Create /TN $taskName /TR "\\"$exe\\" --tun-task \\"$cfg\\" \\"$stop\\"" '
        '/SC ONCE /ST 00:00 /RL HIGHEST /F';
    // ⚠️ Только асинхронно. Эту задачу заводят из настройки «запуск без UAC»,
    // то есть ровно тогда, когда пользователь уже устал от зависаний, — и
    // замерзший здесь интерфейс убил бы сам обходной путь.
    if (!await Elevation.runElevatedAsync('schtasks.exe', args)) return false;

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (await exists()) return true;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// Запустить TUN через задачу — без UAC. false, если задачи нет или запуск не удался.
  static Future<bool> run() async {
    try {
      // #8 — `schtasks /Run` МОЛЧА игнорирует запуск, пока задача в состоянии
      // Running: при частом переподключении новый старт терялся, пока прошлый
      // инстанс доигрывал. Ждём, пока прошлый завершится (до 5 с), потом стартуем.
      await _waitNotRunning();
      final r = await Process.run('schtasks', ['/Run', '/TN', taskName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Ждать, пока задача НЕ в состоянии Running (или истечёт таймаут).
  static Future<void> _waitNotRunning() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isRunning()) return;
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  static Future<bool> _isRunning() async {
    try {
      final r = await Process.run(
          'schtasks', ['/Query', '/TN', taskName, '/FO', 'LIST', '/V']);
      final out = '${r.stdout}';
      // Статус локализован: en «Running», ru «Выполняется».
      return out.contains('Running') || out.contains('Выполняется');
    } catch (_) {
      return false;
    }
  }

  /// Удалить задачу (кнопка в настройках и деинсталлятор).
  static Future<bool> uninstall() async {
    try {
      final r = await Process.run('schtasks', ['/Delete', '/TN', taskName, '/F']);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    // Своя задача обычно удаляется и без прав; если нет — просим их.
    return Elevation.runElevatedAsync('schtasks.exe', '/Delete /TN $taskName /F');
  }
}
