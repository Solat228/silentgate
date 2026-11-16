import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';

/// Запасной DNS доспрашивает резолвер провайдера, когда туннельный молчит.
/// Форвардер живёт в нашем процессе, и блокировка kill switch его пропускает
/// — под ней это утечка имён (аудит 25.10.2026, E).
void main() {
  test('решение: провайдер только без kill switch и без noRealIp', () {
    const base = AppSettings();
    expect(VpnEngineBase.providerDnsFallbackAllowed(base), isTrue);
    expect(
        VpnEngineBase.providerDnsFallbackAllowed(
            base.copyWith(killSwitch: true)),
        isFalse);
    expect(
        VpnEngineBase.providerDnsFallbackAllowed(base.copyWith(noRealIp: true)),
        isFalse);
  });

  test('Windows спрашивает решение ДО подъёма форвардера', () {
    final src =
        File('lib/engine/windows/windows_engine.dart').readAsStringSync();
    final start = src.indexOf('Future<int> _startFallbackDns(');
    final end = src.indexOf('DnsFallbackServer(', start);
    expect(start, greaterThan(0));
    expect(src.substring(start, end),
        contains('providerDnsFallbackAllowed(s)'));
  });
}
