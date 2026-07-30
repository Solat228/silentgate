import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/adapter_dns_windows.dart';

void main() {
  test('DNS адаптеров читается напрямую и быстро', () {
    if (!Platform.isWindows) return;
    final sw = Stopwatch()..start();
    final list = AdapterDnsWindows.servers();
    sw.stop();

    // Прежний PowerShell-путь укладывался в 5 секунд не всегда и молча
    // отказывал. Прямой вызов API обязан отвечать за миллисекунды.
    expect(sw.elapsedMilliseconds, lessThan(1000),
        reason: 'определение DNS не должно быть заметной операцией');
    // ignore: avoid_print
    print('  DNS адаптеров: ${list.join(", ")} — за ${sw.elapsedMilliseconds} мс');

    for (final ip in list) {
      expect(InternetAddress.tryParse(ip), isNotNull,
          reason: '«$ip» не разбирается как адрес');
    }
  });
}
