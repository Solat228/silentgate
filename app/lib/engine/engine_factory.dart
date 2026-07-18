import 'dart:io';

import 'vpn_engine.dart';
import 'windows/windows_engine.dart';

/// Создаёт реализацию движка под текущую платформу.
///
/// Пока реализован только Windows. Android/iOS/macOS/Linux добавятся на своих этапах
/// (см. docs/ROADMAP.md) — здесь появятся соответствующие ветки.
VpnEngine createVpnEngine() {
  if (Platform.isWindows) {
    return WindowsEngine();
  }
  throw UnsupportedError(
    'В MVP реализована только Windows-версия. Текущая ОС: ${Platform.operatingSystem}',
  );
}
