import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/speed_score.dart';

void main() {
  double s({double? server, double? own, int? lat}) =>
      SpeedScore.of(serverMbps: server, ownMbps: own, latencyMs: lat);

  // Случай, названный владельцем: 95 % канала при 200 мс против 60 % при 30 мс.
  test('быстрый и далёкий обгоняет медленный и близкий', () {
    expect(s(server: 47.5, own: 50, lat: 200),
        greaterThan(s(server: 30, own: 50, lat: 30)));
  });

  // Смысл «взвешенно относительно своего канала»: когда сервер уже отдаёт почти
  // весь канал, лишние мегабиты не стоят ничего, и решать должна задержка.
  test('при насыщении канала выигрывает меньшая задержка', () {
    final fast = s(server: 300, own: 50, lat: 200); // втрое «быстрее» канала
    final near = s(server: 46, own: 50, lat: 30); // 92 % канала, но близко
    expect(near, greaterThan(fast),
        reason: 'лишняя скорость сверх канала пользователю не достаётся');
  });

  test('одинаковая скорость — выигрывает меньшая задержка', () {
    expect(s(server: 40, own: 50, lat: 20),
        greaterThan(s(server: 40, own: 50, lat: 300)));
  });

  test('одинаковая задержка — выигрывает большая скорость', () {
    expect(s(server: 45, own: 50, lat: 100),
        greaterThan(s(server: 10, own: 50, lat: 100)));
  });

  // Сервер без замера не должен обгонять измеренный и подтверждённо быстрый:
  // иначе достаточно «не измериться», чтобы оказаться первым.
  test('неизмеренный сервер уступает измеренному', () {
    expect(s(server: null, lat: 10), lessThan(s(server: 45, own: 50, lat: 100)));
  });

  test('без своей скорости сравниваем сервера между собой', () {
    final a = SpeedScore.of(
        serverMbps: 90, ownMbps: null, latencyMs: 50, bestServerMbps: 100);
    final b = SpeedScore.of(
        serverMbps: 20, ownMbps: null, latencyMs: 50, bestServerMbps: 100);
    expect(a, greaterThan(b));
  });

  test('оценка всегда в пределах 0..1', () {
    for (final v in [
      s(server: 1000, own: 1, lat: 0),
      s(server: 0.1, own: 1000, lat: 5000),
      s(server: null, lat: null),
    ]) {
      expect(v, inInclusiveRange(0, 1));
    }
  });

  test('доля канала показывается в процентах', () {
    expect(SpeedScore.sharePercent(serverMbps: 45, ownMbps: 50), 90);
    expect(SpeedScore.sharePercent(serverMbps: 45, ownMbps: null), isNull);
  });
}
