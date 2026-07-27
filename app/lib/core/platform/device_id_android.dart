import 'dart:io';

import 'package:flutter/services.dart';

import 'device_id.dart';

/// Android: идентификатор из `Settings.Secure.ANDROID_ID`, модель и версия —
/// из `Build.*`. Значения отдаёт нативная сторона через [channel].
///
/// ⚠️ `ANDROID_ID` ≠ `MachineGuid`: он меняется при сбросе к заводским
/// настройкам и различается для разных подписей APK и для рабочего профиля.
/// Панель Remnawave посчитает такое устройство новым — это учтено в
/// `docs/platforms/ANDROID.md` (камень §6.4) и обсуждается с владельцем при
/// настройке device-limit.
class AndroidDeviceId implements DeviceIdProvider {
  /// Канал реализуется на этапе Фазы 3 (`platform/DeviceId.kt`). До его
  /// появления вызовы бросают `MissingPluginException`, и мы отдаём `unknown` —
  /// подписка обязана грузиться даже без идентификатора.
  static const channel = MethodChannel('lol.silentgate/device');

  static String? _cachedHwid;
  static String? _cachedVersion;
  static String? _cachedModel;

  /// [fallback] используется, пока нативной стороны нет (или если она не
  /// ответила): у `dart:io` часть сведений об Android доступна и без канала.
  Future<String> _ask(String method, {String Function()? fallback}) async {
    try {
      final v = await channel.invokeMethod<String>(method);
      final s = (v ?? '').trim();
      if (s.isNotEmpty) return s;
    } catch (_) {
      // Канала ещё нет (MissingPluginException) либо нативная сторона упала.
    }
    final f = fallback?.call().trim() ?? '';
    return f.isEmpty ? 'unknown' : f;
  }

  @override
  Future<String> hwid() async => _cachedHwid ??= await _ask('hwid');

  @override
  String osName() => 'Android';

  @override
  Future<String> osVersion() async => _cachedVersion ??= await _ask(
        'osVersion',
        fallback: () => Platform.operatingSystemVersion,
      );

  @override
  Future<String> deviceModel() async => _cachedModel ??= await _ask('model');
}
