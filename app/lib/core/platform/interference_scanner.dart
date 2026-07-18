import 'dart:convert';
import 'dart:io';

import '../../engine/windows/elevation.dart';
import '../../engine/windows/process_list_windows.dart';

class Interference {
  final String kind; // 'adapter' | 'process'
  final String name;
  final String detail;
  final int? pid; // для процессов — чтобы можно было закрыть
  const Interference(this.kind, this.name, this.detail, {this.pid});
}

/// Обнаружение других VPN и вмешательств в сеть (чужие TUN-адаптеры, процессы VPN, zapret),
/// которые могут конфликтовать с SilentGate. Свои процессы/адаптер исключаются.
class InterferenceScanner {
  // Только АКТИВНЫЕ помехи (DPI-инструменты, реально вмешивающиеся в трафик). Обычные VPN-клиенты
  // сами по себе не мешают — их влияние ловим по активному TUN-адаптеру и системному прокси.
  static const _dpiProcNames = <String, String>{
    'winws.exe': 'zapret (winws)',
    'goodbyedpi.exe': 'GoodbyeDPI',
    'winws1.exe': 'zapret (winws)',
  };

  static Future<List<Interference>> scan() async {
    final result = <Interference>[];
    result.addAll(await _scanAdapters());
    result.addAll(_scanProcesses());
    result.addAll(await _scanProxy());
    return result;
  }

  static List<Interference> _scanProcesses() {
    final found = <Interference>[];
    try {
      for (final p in ProcessListWindows.enumerate()) {
        final label = _dpiProcNames[p.name.toLowerCase()];
        if (label != null) {
          found.add(Interference('process', label, p.path, pid: p.pid));
        }
      }
    } catch (_) {}
    return found;
  }

  /// Чужой системный прокси (включён, но не на наш локальный порт).
  static Future<List<Interference>> _scanProxy() async {
    try {
      final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final en = await Process.run('reg', ['query', key, '/v', 'ProxyEnable']);
      if (!'${en.stdout}'.contains('0x1')) return [];
      final sv = await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
      final out = '${sv.stdout}';
      // Наш прокси — 127.0.0.1:10809; любой другой активный прокси считаем помехой.
      if (out.contains('127.0.0.1:10809')) return [];
      final m = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(out);
      final val = m?.group(1)?.trim() ?? 'включён';
      return [Interference('proxy', 'Системный прокси', val)];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Interference>> _scanAdapters() async {
    final found = <Interference>[];
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Get-NetAdapter | Where-Object {\$_.Status -eq 'Up'} | "
            'Select-Object Name,InterfaceDescription | ConvertTo-Json -Compress',
      ]);
      final out = '${r.stdout}'.trim();
      if (out.isEmpty) return found;
      final decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      for (final a in list) {
        if (a is! Map) continue;
        final name = '${a['Name']}';
        final desc = '${a['InterfaceDescription']}';
        final d = desc.toLowerCase();
        if (name.toLowerCase() == 'silentgate-tun') continue; // наш адаптер
        if (d.contains('wintun') ||
            d.contains('sing-tun') ||
            d.contains('wireguard') ||
            d.contains('tap-windows') ||
            d.contains('tunnel')) {
          found.add(Interference('adapter', name, desc));
        }
      }
    } catch (_) {}
    return found;
  }

  /// Закрыть процесс-помеху.
  ///
  /// zapret/GoodbyeDPI обычно запущены с правами администратора, и обычный taskkill
  /// их не берёт («Отказано в доступе») — молча ничего не происходило. Поэтому:
  /// сначала пробуем без прав, а если процесс жив — повторяем через UAC.
  /// Возвращает true, если процесс действительно исчез.
  static Future<bool> kill(int pid) async {
    try {
      await Process.run('taskkill', ['/F', '/PID', '$pid', '/T']);
    } catch (_) {}
    if (!await _alive(pid)) return true;

    Elevation.runElevated('taskkill.exe', '/F /PID $pid /T');
    // Элевейтнутый процесс завершается асинхронно — ждём результата.
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!await _alive(pid)) return true;
    }
    return false;
  }

  static Future<bool> _alive(int pid) async {
    try {
      final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
      return '${r.stdout}'.contains('$pid');
    } catch (_) {
      return false;
    }
  }
}
