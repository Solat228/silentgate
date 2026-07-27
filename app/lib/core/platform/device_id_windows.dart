import 'dart:io';

import 'device_id.dart';

/// Windows: HWID из `MachineGuid` (стабилен для машины, переживает
/// переустановку приложения и смену оборудования).
class WindowsDeviceId implements DeviceIdProvider {
  static String? _cached;

  @override
  Future<String> hwid() async {
    final known = _cached;
    if (known != null) return known;
    try {
      final r = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)')
          .firstMatch('${r.stdout}');
      return _cached = m?.group(1)?.trim() ?? 'unknown';
    } catch (_) {
      return _cached = 'unknown';
    }
  }

  @override
  String osName() => 'Windows';

  @override
  Future<String> osVersion() async => Platform.operatingSystemVersion;

  @override
  Future<String> deviceModel() async => 'Desktop';
}
