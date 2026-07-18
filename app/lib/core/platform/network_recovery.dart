import 'dart:io';

import '../../engine/windows/elevation.dart';

/// Восстановление сети после сбоя/выключения ПК с включённым VPN.
/// Команды требуют прав администратора; winsock/int ip reset вступают в силу после перезагрузки.
class NetworkRecovery {
  static const commands = <String>[
    'ipconfig /release',
    'ipconfig /renew',
    'netsh winsock reset',
    'netsh int ip reset',
    'ipconfig /flushdns',
    'netsh winhttp reset proxy',
    r'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /f',
    r'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f',
  ];

  /// Записывает .bat и запускает его элевейтнуто (с видимым окном). Возвращает true, если запущено.
  static Future<bool> run() async {
    final bat = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}silentgate_netrecover.bat');
    final lines = <String>[
      '@echo off',
      'echo Восстановление сети SilentGate...',
      ...commands,
      'echo.',
      'echo Готово. Перезагрузите компьютер для применения сброса winsock/IP.',
      'pause',
    ];
    await bat.writeAsString('${lines.join('\r\n')}\r\n');
    return Elevation.runElevated('cmd.exe', '/c "${bat.path}"', show: true);
  }
}
