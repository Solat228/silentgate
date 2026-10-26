import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// Отказ подъёма TUN на автовосстановлении не имеет права снимать kill switch.
///
/// Аудит 25.10.2026 (D1): сторож уронил канал, переподъём бросил
/// `TunStartException`, и ветка звала `cleanup()` — тот снимает TUN, прокси и
/// фильтры WFP. Защита пропадала после ОДНОЙ неудачной попытки.
void main() {
  test('повторяем только автовосстановление и не при отказе в правах', () {
    expect(
        WindowsEngine.tunFailureRetries(
            freshUserConnect: false, elevationDenied: false),
        isTrue);
    expect(
        WindowsEngine.tunFailureRetries(
            freshUserConnect: true, elevationDenied: false),
        isFalse,
        reason: 'нажатие человека: автоподбор уже всё перебрал');
    expect(
        WindowsEngine.tunFailureRetries(
            freshUserConnect: false, elevationDenied: true),
        isFalse,
        reason: 'иначе окно UAC каждые 30 с');
  });

  test('ветка TunStartException идёт в scheduleRetry ДО cleanup()', () {
    final src =
        File('lib/engine/windows/windows_engine.dart').readAsStringSync();
    final start = src.indexOf('} on TunStartException catch (e) {');
    final end = src.indexOf('} catch (e) {', start);
    expect(start, greaterThan(0));
    final body = src.substring(start, end);
    final retry = body.indexOf('scheduleRetry(');
    final clean = body.indexOf('await cleanup();');
    expect(retry, greaterThan(0));
    expect(clean, greaterThan(retry));
    expect(body, contains('tunFailureRetries('));
  });
}
