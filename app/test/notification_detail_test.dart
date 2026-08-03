import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/android/android_engine.dart';

/// Страж против того, что поймал живой прогон: в подпись шторки уехал ЛИТЕРАЛ
/// `${_human(...)}` вместо числа. Тесты этого не видели, потому что подпись
/// нигде не проверялась — её читал только человек, глядя в шторку.
void main() {
  test('размер форматируется в число с единицей, а не в шаблон', () {
    expect(AndroidEngine.humanBytesForTest(0), '0 B');
    expect(AndroidEngine.humanBytesForTest(999), '999 B');
    expect(AndroidEngine.humanBytesForTest(1024), '1.0 KB');
    expect(AndroidEngine.humanBytesForTest(1536), '1.5 KB');
    expect(AndroidEngine.humanBytesForTest(5 * 1024 * 1024), '5.0 MB');
    expect(AndroidEngine.humanBytesForTest(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  test('в результате нет ни доллара, ни фигурных скобок', () {
    for (final v in [0, 1, 2048, 1234567, 9999999999]) {
      final s = AndroidEngine.humanBytesForTest(v);
      expect(s.contains(r'$'), isFalse, reason: 'литерал интерполяции в "$s"');
      expect(s.contains('{'), isFalse, reason: 'литерал интерполяции в "$s"');
    }
  });
}
