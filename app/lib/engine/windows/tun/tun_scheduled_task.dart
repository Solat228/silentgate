import 'dart:io';

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
