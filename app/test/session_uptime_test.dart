import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/util/uptime_format.dart';

/// Время подключения показывается в ДВУХ местах: под кнопкой Connect и внизу
/// шторки «Информация о сервере». Тесты ниже стерегут ровно то, что ломается
/// молча: формулу, её единственность и живость счётчика в шторке.
void main() {
  group('formatUptime — одна формула на оба места', () {
    test('до часа — минуты без ведущего нуля, секунды с ним', () {
      // Ведущий ноль у секунд обязателен: без него строка прыгает при
      // переходе через 10 («1:9» → «1:10»), и цифры дёргаются на глазах.
      expect(formatUptime(const Duration(seconds: 0)), '0:00');
      expect(formatUptime(const Duration(seconds: 9)), '0:09');
      expect(formatUptime(const Duration(seconds: 59)), '0:59');
      expect(formatUptime(const Duration(minutes: 1)), '1:00');
      expect(formatUptime(const Duration(minutes: 7, seconds: 12)), '7:12');
      expect(formatUptime(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('от часа — появляются часы, минуты получают ведущий ноль', () {
      expect(formatUptime(const Duration(hours: 1)), '1:00:00');
      expect(
          formatUptime(const Duration(hours: 1, minutes: 7, seconds: 12)),
          '1:07:12');
      expect(formatUptime(const Duration(hours: 12, minutes: 34, seconds: 56)),
          '12:34:56');
    });

    test('сутки и больше не сбрасываются в ноль, а копятся в часах', () {
      // Always-on VPN живёт сутками. Счётчик, обнуляющийся на 24 часах,
      // выглядел бы как обрыв соединения, которого не было.
      expect(formatUptime(const Duration(days: 1, minutes: 1)), '24:01:00');
      expect(formatUptime(const Duration(days: 3)), '72:00:00');
    });

    test('доли секунды отбрасываются вниз, а не округляются вверх', () {
      // Иначе таймер показал бы «0:01» раньше, чем прошла секунда.
      expect(formatUptime(const Duration(milliseconds: 999)), '0:00');
    });
  });

  group('⚠️ Стражи вёрстки: счётчик в шторке жив и формула не раздвоилась', () {
    String read(String path) => File(path).readAsStringSync();

    test('⚠️ у кнопки Connect НЕТ своей копии формулы', () {
      // Две копии разъезжаются на первой же правке, и пользователь видит два
      // разных числа про одно подключение. Компилятор такое не ловит.
      final src = read('lib/ui/home_screen.dart');
      expect(src.contains('static String format(Duration'), isFalse,
          reason: 'формула вернулась в home_screen — она живёт в '
              'core/util/uptime_format.dart и только там');
      expect(src.contains('formatUptime('), isTrue,
          reason: 'кнопка обязана звать общий форматтер');
    });

    test('⚠️ блок времени стоит В САМОМ НИЗУ шторки', () {
      final src = read('lib/ui/server_info_screen.dart');
      expect(src.contains('const _SessionUptimeBlock(),'), isTrue,
          reason: 'блок пропал из списка детей экрана');
      // «В самый низ» — просьба владельца дословно. Блок обязан идти ПОСЛЕ
      // раздела параметров, иначе он окажется в середине экрана.
      expect(src.indexOf('const _SessionUptimeBlock(),'),
          greaterThan(src.indexOf('srvInfoSectionParams')),
          reason: 'блок уехал выше раздела параметров');
    });

    test('⚠️ у блока СВОЙ тик раз в секунду — иначе число замрёт', () {
      // AppState о ходе connectedFor не уведомляет: это вычисляемое значение
      // от точки отсчёта. Без своего таймера число застынет на том, каким
      // было при открытии шторки, и это выглядит как вставшее подключение.
      final src = read('lib/ui/server_info_screen.dart');
      final block = src.substring(src.indexOf('class _SessionUptimeBlock'));
      expect(block.contains('Timer.periodic(const Duration(seconds: 1)'), isTrue,
          reason: 'у блока пропал собственный таймер');
      expect(block.contains('_tick?.cancel()'), isTrue,
          reason: 'таймер обязан гаснуть в dispose, иначе течёт после закрытия');
      expect(block.contains('formatUptime('), isTrue,
          reason: 'блок обязан звать общий форматтер, а не свой');
    });

    test('⚠️ при выключенном VPN блок не рисуется ЦЕЛИКОМ', () {
      // Заголовок «Текущее подключение» с пустотой под ним читается как
      // поломка, а не как «выключено».
      final src = read('lib/ui/server_info_screen.dart');
      final block = src.substring(src.indexOf('class _SessionUptimeBlock'));
      expect(block.contains('if (d == null) return const SizedBox.shrink();'),
          isTrue,
          reason: 'исчезла проверка на выключенный VPN');
    });

    test('⚠️ оформление блока — общее с остальными разделами экрана', () {
      // Своя копия стиля разъехалась бы с соседними разделами при первой же
      // правке оформления, и низ экрана перестал бы выглядеть как остальное.
      final src = read('lib/ui/server_info_screen.dart');
      final block = src.substring(src.indexOf('class _SessionUptimeBlock'));
      expect(block.contains('_sectionTitle(context,'), isTrue);
      expect(block.contains('_kvRow(context,'), isTrue);
    });
  });
}
