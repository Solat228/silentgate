import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// Сторож зависшего TUN-ядра не имеет права снимать блокировку kill switch.
///
/// Найдено живым прогоном в VM 09.10.2026: TUN-ядро убито, сторож через 20 с
/// снял туннель ВМЕСТЕ с захватом — стоп-файл велел помощнику снять и
/// фильтры WFP, — а новая попытка сперва ~8 с опрашивала резолверы. Всё это
/// время `api.ipify.org` отвечал настоящим адресом машины при включённом
/// kill switch.
void main() {
  test('с kill switch захват удерживается, без него — снимается', () {
    const base = AppSettings();
    expect(WindowsEngine.hungTunKeepsCapture(base.copyWith(killSwitch: true)),
        isTrue);
    expect(WindowsEngine.hungTunKeepsCapture(base.copyWith(killSwitch: false)),
        isFalse);
    // Бесшовность про ЖИВОЙ туннель: держать мёртвый адаптер ради неё нельзя
    // — без блокировки он просто глотает трафик машины.
    expect(
        WindowsEngine.hungTunKeepsCapture(
            base.copyWith(killSwitch: false, seamlessKeepTun: true)),
        isFalse);
  });

  test('сторож зовёт teardownCore через это решение, а не голым вызовом', () {
    final src =
        File('lib/engine/windows/windows_engine.dart').readAsStringSync();
    final start = src.indexOf('void _startTunWatchdog(');
    final end = src.indexOf('Future<bool> _tunApiAlive()', start);
    expect(start, greaterThan(0));
    final body = src.substring(start, end);
    expect(body,
        contains('teardownCore(keepCapture: hungTunKeepsCapture(settings))'));
    expect(body, isNot(contains('teardownCore();')));
  });
}
