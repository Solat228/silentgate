import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/tun_helper.dart';

/// ⚠️ «ОТКЛЮЧИТЬ» ОБЯЗАНО ДЕЙСТВОВАТЬ ВО ВРЕМЯ ПОДБОРА ПАРАМЕТРОВ TUN.
///
/// Жалоба владельца 28.08.2026: «при включении VPN, если идёт перебор адресов,
/// его не даёт выключить, пока она не завершится». Автоподбор перебирает до
/// девяти комбинаций стека и MTU, и в каждой попытке есть ожидания, которые о
/// нажатии «Отключить» не знали:
///
///  * ожидание, пока прошлый помощник заберёт stop-файл — до 5 секунд;
///  * запуск элевейтнутого помощника — то есть ещё и окно UAC.
///
/// Девять комбинаций × пять секунд — до сорока пяти секунд, когда кнопка не
/// действует. Человек вправе прекратить то, что начал, в любой момент; это не
/// удобство, а его решение против нашего.
void main() {
  group('⚠️ Ожидание stop-файла слушает отмену', () {
    late Directory tmp;
    late String stopPath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_cancel_');
      stopPath = '${tmp.path}${Platform.pathSeparator}tun_stop';
      // Файл на месте и никто его не забирает — то самое ожидание, в котором
      // раньше застревала отмена.
      File(stopPath).writeAsStringSync('stop');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('⚠️ отмена прекращает ожидание, не досиживая до конца', () async {
      final sw = Stopwatch()..start();
      final r = await TunHelper.waitStopConsumed(
        stopPath,
        timeout: const Duration(seconds: 5),
        abort: () => true,
      );
      sw.stop();
      expect(r, isTrue,
          reason: 'отмена — это «ждать больше нечего», а не «файл никто не '
              'забрал»: иначе вызывающий сотрёт файл и добьёт прошлого '
              'помощника ради уже отменённой попытки');
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'ожидание обязано прерваться сразу, а не через таймаут');
    });

    test('без отмены ожидание досиживает таймаут и честно говорит «нет»', () async {
      // Прежнее поведение не должно измениться: файл на месте, никто не забрал.
      final sw = Stopwatch()..start();
      final r = await TunHelper.waitStopConsumed(stopPath,
          timeout: const Duration(milliseconds: 600));
      sw.stop();
      expect(r, isFalse);
      expect(sw.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 500)));
    });

    test('файл забрали — ждать нечего и без отмены', () async {
      File(stopPath).deleteSync();
      expect(await TunHelper.waitStopConsumed(stopPath), isTrue);
    });

    test('отмена не мешает вернуть «забрали», если файла уже нет', () async {
      File(stopPath).deleteSync();
      expect(
          await TunHelper.waitStopConsumed(stopPath, abort: () => false), isTrue);
    });
  });

  group('⚠️ Стражи по исходнику: отмена доходит до всех ожиданий', () {
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join(String.fromCharCode(10));

    late String router;
    setUp(() =>
        router = code('lib/engine/windows/tun/singbox_router_windows.dart'));

    test('⚠️ ожидание stop-файла получает признак отмены', () {
      // Забыть здесь `abort:` легко — параметр необязательный, компилятор
      // промолчит, а кнопка снова перестанет действовать на пять секунд.
      expect(router, contains('waitStopConsumed(_stopPath, abort: abort)'),
          reason: 'ожидание stop-файла снова глухо к отмене');
    });

    test('⚠️ помощник не запускается после отмены', () {
      // Запуск элевейтнутого помощника — точка невозврата: дальше туннель уже
      // поднимется, и «отменить» превратится в «снять поднятое».
      final at = router.indexOf('TunScheduledTask.exists()');
      expect(at, greaterThan(0));
      final before = router.substring(0, at);
      final guardAt = before.lastIndexOf('abort?.call()');
      expect(guardAt, greaterThan(0),
          reason: 'перед запуском помощника нет проверки отмены');
      expect(before.substring(guardAt), contains('помощник не запускается'));
    });

    test('перебор комбинаций по-прежнему прерывается', () {
      // Прежние проверки отмены никуда не делись — новые их дополняют.
      expect(router, contains('TUN автоподбор прерван'));
      expect(router, contains('TUN поднялся после отмены'));
    });
  });
}
