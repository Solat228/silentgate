import 'dart:io';

/// Стабильный идентификатор устройства (HWID) и заголовки устройства для запроса подписки
/// (совместимо с device-limit Remnawave, как в Happ/v2RayTun).
class Hwid {
  static String? _cached;

  /// HWID на основе Windows MachineGuid (стабилен для машины). Кэшируется.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final r = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)')
          .firstMatch('${r.stdout}');
      _cached = m?.group(1)?.trim() ?? 'unknown';
    } catch (_) {
      _cached = 'unknown';
    }
    return _cached!;
  }
}

class DeviceHeaders {
  /// Заголовки устройства, отправляемые вместе с запросом подписки.
  static Future<Map<String, String>> build() async {
    final hwid = await Hwid.get();
    return {
      'X-HWID': headerSafe(hwid),
      'X-Device-OS': 'Windows',
      'X-Ver-OS': headerSafe(Platform.operatingSystemVersion),
      'X-Device-Model': 'Desktop',
    };
  }

  /// Значение, безопасное для HTTP-заголовка.
  ///
  /// На локализованной Windows `Platform.operatingSystemVersion` возвращает строку вида
  /// `"Майкрософт Windows 11 Корпоративная" 10.0 (Build 26100)` — кириллица и кавычки
  /// недопустимы в заголовке, и запрос подписки падал с FormatException
  /// (импорт и автообновление переставали работать целиком).
  static String headerSafe(String value) {
    final sb = StringBuffer();
    for (final unit in value.codeUnits) {
      // Печатаемый ASCII, кроме кавычек (портят кавычкование значения).
      if (unit >= 0x20 && unit <= 0x7E && unit != 0x22) {
        sb.writeCharCode(unit);
      } else {
        sb.write(' ');
      }
    }
    final cleaned = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'unknown';
    return cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned;
  }
}
