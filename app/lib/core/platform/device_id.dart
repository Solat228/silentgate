import 'dart:io';

import 'device_id_android.dart';
import 'device_id_windows.dart';

/// Идентификатор устройства и заголовки, которыми клиент представляется панели
/// Remnawave (совместимо с её device-limit, как в Happ/v2RayTun).
///
/// Реализация платформенная, контракт общий. Диспетчеризация рантайм-ная:
/// условные импорты Dart различают доступность библиотек (`dart.library.io`),
/// а не операционную систему, поэтому выбрать Windows или Android на этапе
/// компиляции ими нельзя.
abstract interface class DeviceIdProvider {
  /// Стабильный идентификатор устройства. При любой ошибке — `'unknown'`
  /// (запрос подписки не должен падать из-за недоступного идентификатора).
  Future<String> hwid();

  /// Имя ОС для заголовка `X-Device-OS`.
  String osName();

  /// Версия ОС для `X-Ver-OS` (сырая, до [DeviceHeaders.headerSafe]).
  Future<String> osVersion();

  /// Модель устройства для `X-Device-Model`.
  Future<String> deviceModel();
}

DeviceIdProvider? _override;

/// Подменить провайдера (тесты).
void setDeviceIdProviderForTests(DeviceIdProvider? p) => _override = p;

DeviceIdProvider deviceIdProvider() {
  final o = _override;
  if (o != null) return o;
  if (Platform.isAndroid) return AndroidDeviceId();
  return WindowsDeviceId();
}

/// Совместимость с прежним API (`Hwid.get()` зовут «О программе» и отчёт
/// поддержки). Кэш живёт в платформенной реализации.
abstract final class Hwid {
  static Future<String> get() => deviceIdProvider().hwid();
}

abstract final class DeviceHeaders {
  /// Заголовки устройства, отправляемые вместе с запросом подписки.
  static Future<Map<String, String>> build() async {
    final p = deviceIdProvider();
    return {
      'X-HWID': headerSafe(await p.hwid()),
      'X-Device-OS': headerSafe(p.osName()),
      'X-Ver-OS': headerSafe(await p.osVersion()),
      'X-Device-Model': headerSafe(await p.deviceModel()),
    };
  }

  /// Значение, безопасное для HTTP-заголовка.
  ///
  /// Не «windows-фикс», а общее требование. На локализованной Windows
  /// `Platform.operatingSystemVersion` возвращает строку вида
  /// `"Майкрософт Windows 11 Корпоративная" 10.0 (Build 26100)` — кириллица и
  /// кавычки недопустимы в заголовке, и запрос подписки падал с
  /// FormatException (импорт и автообновление переставали работать целиком).
  /// На Android то же самое делает `Build.MODEL` у части производителей.
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
