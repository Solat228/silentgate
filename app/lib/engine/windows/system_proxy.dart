import 'dart:ffi';
import 'dart:io';

/// Управление системным прокси Windows (WinINET) через реестр + уведомление
/// wininet.dll о смене настроек. Это MVP-способ перехвата трафика: без TUN-драйвера
/// и без прав администратора. Применяется к WinINET/WinHTTP-приложениям (браузеры и др.).
///
/// Полный перехват (включая UDP и приложения, игнорирующие прокси) — это TUN-режим (этап M5).
class SystemProxy {
  static const String _regKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  // Маркер «прокси установлен нами» — чтобы восстановиться после аварийного выхода.
  static File get _markerFile =>
      File('${Directory.systemTemp.path}\\silentgate_proxy.lock');

  /// Установить системный прокси на host:port (обычно 127.0.0.1:10809).
  static Future<void> set(String hostPort) async {
    await _reg(['/v', 'ProxyServer', '/t', 'REG_SZ', '/d', hostPort, '/f']);
    await _reg([
      '/v', 'ProxyOverride', '/t', 'REG_SZ',
      '/d', 'localhost;127.*;10.*;172.16.*;192.168.*;<local>', '/f',
    ]);
    await _reg(['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    _notifyChanged();
    try {
      _markerFile.writeAsStringSync(hostPort);
    } catch (_) {}
  }

  /// Снять системный прокси.
  static Future<void> clear() async {
    await _reg(['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    _notifyChanged();
    try {
      if (_markerFile.existsSync()) _markerFile.deleteSync();
    } catch (_) {}
  }

  /// Восстановление при старте: если прошлый запуск упал с включённым прокси,
  /// маркер остался — снимаем прокси, чтобы у пользователя не «пропал» интернет.
  static Future<void> recoverIfDirty() async {
    try {
      if (_markerFile.existsSync()) {
        await clear();
      }
    } catch (_) {}
  }

  static Future<void> _reg(List<String> args) async {
    await Process.run('reg', ['add', _regKey, ...args]);
  }

  // ── wininet.dll: InternetSetOptionW для мгновенного применения ─────────────
  static void _notifyChanged() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final setOption = wininet.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer, Uint32),
          int Function(int, int, Pointer, int)>('InternetSetOptionW');
      const internetOptionSettingsChanged = 39;
      const internetOptionRefresh = 37;
      setOption(0, internetOptionSettingsChanged, nullptr, 0);
      setOption(0, internetOptionRefresh, nullptr, 0);
    } catch (_) {
      // Не критично: настройки применятся при следующем создании соединения.
    }
  }
}
