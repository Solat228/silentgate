import 'dart:io';

import 'xray_paths.dart';

/// Версия ядра Xray (парсинг `xray.exe version` → «Xray X.Y.Z»). Кэшируется.
class XrayVersion {
  static String? _cached;
  static final _re = RegExp(r'Xray\s+v?([0-9][^\s(]*)');

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final loc = XrayPaths.locate();
      if (loc == null) return 'не найдено';
      final r = await Process.run(loc.executable, ['version'])
          .timeout(const Duration(seconds: 3));
      final m = _re.firstMatch('${r.stdout}');
      _cached = m != null ? m.group(1)! : 'неизвестно';
      return _cached!;
    } catch (_) {
      return 'неизвестно';
    }
  }
}
