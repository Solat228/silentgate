import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/tun_reload.dart';

/// ПРОСЬБА О ПЕРЕЗАПУСКЕ ЯДРА ТУННЕЛЯ И ОТВЕТ ПОМОЩНИКА.
///
/// ⚠️ Главное, что здесь стережётся, — токен. Ответ на брошенную просьбу
/// (интерфейс не дождался и пошёл обычным путём) не должен приниматься за
/// ответ на новую: иначе интерфейс счёл бы туннель перезапущенным, когда его
/// нет.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sg_tun_reload_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('просьба забирается один раз', () {
    final token = TunReload.request(dir);
    expect(TunReload.take(dir), token);
    expect(TunReload.take(dir), isNull);
  });

  test('ответ «запущено» доходит по своему токену', () async {
    final token = TunReload.request(dir);
    final taken = TunReload.take(dir)!;
    TunReload.answer(dir, taken, const TunReloadAnswer.started());

    final a = await TunReload.waitAnswer(dir, token,
        timeout: const Duration(seconds: 2));
    expect(a?.started, isTrue);
    expect(File(TunReload.answerPathFor(dir)).existsSync(), isFalse,
        reason: 'прочитанный ответ удаляется');
  });

  test('отказ приносит причину', () async {
    final token = TunReload.request(dir);
    TunReload.answer(
        dir, token, const TunReloadAnswer.refused('блокировка не поднялась'));
    final a = await TunReload.waitAnswer(dir, token,
        timeout: const Duration(seconds: 2));
    expect(a?.started, isFalse);
    expect(a?.reason, 'блокировка не поднялась');
  });

  test('ответ на чужую просьбу не принимается', () async {
    final old = TunReload.request(dir);
    final fresh = TunReload.request(dir);
    expect(fresh, isNot(old));
    TunReload.answer(dir, old, const TunReloadAnswer.started());

    final a = await TunReload.waitAnswer(dir, fresh,
        timeout: const Duration(milliseconds: 400),
        poll: const Duration(milliseconds: 50));
    expect(a, isNull);
  });

  test('новая просьба стирает ответ на прошлую', () {
    final old = TunReload.request(dir);
    TunReload.answer(dir, old, const TunReloadAnswer.started());
    TunReload.request(dir);
    expect(File(TunReload.answerPathFor(dir)).existsSync(), isFalse);
  });

  test('отмена убирает невзятую просьбу', () {
    TunReload.request(dir);
    TunReload.cancel(dir);
    expect(TunReload.take(dir), isNull);
  });

  test('ожидание прерывается по abort', () async {
    final token = TunReload.request(dir);
    final sw = Stopwatch()..start();
    final a = await TunReload.waitAnswer(dir, token,
        timeout: const Duration(seconds: 10), abort: () => true);
    expect(a, isNull);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  group('decode', () {
    test('недописанный ответ — null', () {
      expect(TunReloadAnswer.decode('t1', 't1'), isNull);
      expect(TunReloadAnswer.decode('t1\nstar', 't1'), isNull);
    });

    test('CRLF не мешает', () {
      expect(TunReloadAnswer.decode('t1\r\nstarted\r\n', 't1')?.started,
          isTrue);
    });

    test('кодирование и разбор согласованы', () {
      const r = TunReloadAnswer.refused('a\nb');
      final back = TunReloadAnswer.decode(r.encode('t'), 't')!;
      expect(back.started, isFalse);
      expect(back.reason, 'a\nb');
    });
  });
}
