import 'dart:io';

import 'app_log.dart';

/// Уборка за ядрами (xray.exe / sing-box.exe).
///
/// **Windows не убивает дочерние процессы вместе с родителем.** Любое ядро,
/// живое в момент `exit(0)`, остаётся висеть: у пользователя после закрытия
/// приложения оставались работающие xray и sing-box. Особенно легко это
/// получить с пинг-харнессом — он живёт секунды, но именно в эти секунды
/// пользователь и закрывает окно.
///
/// Два эшелона:
///  1. [register]/[unregister] — все запущенные НАМИ процессы; [killChildren]
///     гасит их прямо перед выходом;
///  2. [sweepOrphans] на старте — добивает то, что осталось от прошлого запуска
///     (аварийное завершение, вылет). Убиваются ТОЛЬКО процессы, запущенные из
///     нашей папки: чужой VPN-клиент со своим xray.exe трогать нельзя.
class CoreCleanup {
  static final Set<Process> _children = {};

  static void register(Process p) => _children.add(p);
  static void unregister(Process p) => _children.remove(p);

  /// Синхронно погасить всё своё. Вызывается перед `exit(0)`: ждать здесь
  /// нельзя — окно уже скрыто, пользователь считает, что приложение закрылось.
  static void killChildren() {
    for (final p in _children.toList()) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _children.clear();
  }

  /// Догнать осиротевшие ядра прошлого запуска.
  ///
  /// [ourBinDir] — папка с нашими xray.exe/sing-box.exe. Сравнение по полному
  /// пути обязательно: имена процессов одинаковые у всех клиентов на Xray.
  static Future<void> sweepOrphans(String ourBinDir) async {
    if (!Platform.isWindows) return;
    final dir = ourBinDir.toLowerCase().replaceAll('/', r'\');
    try {
      // Только чтение: список процессов с путями. Убиваем сами, по PID.
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"Get-Process -Name xray,sing-box -ErrorAction SilentlyContinue | "
            r"ForEach-Object { try { '{0}|{1}' -f $_.Id, $_.Path } catch {} }",
      ]).timeout(const Duration(seconds: 8));

      final killed = <int>[];
      for (final line in '${r.stdout}'.split(RegExp(r'\r?\n'))) {
        final parts = line.trim().split('|');
        if (parts.length != 2) continue;
        final pid = int.tryParse(parts[0]);
        final path = parts[1].toLowerCase().replaceAll('/', r'\');
        if (pid == null || path.isEmpty) continue;
        if (!path.startsWith(dir)) continue; // чужое ядро — не наше дело
        try {
          await Process.run('taskkill', ['/F', '/PID', '$pid']);
          killed.add(pid);
        } catch (_) {}
      }
      if (killed.isNotEmpty) {
        AppLog.w('Убраны осиротевшие ядра прошлого запуска: '
            '${killed.join(", ")}');
      }
    } catch (_) {
      // Нет PowerShell / политика запрещает — не критично, просто не убрали.
    }
  }
}
