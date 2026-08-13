import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';

/// АДРЕС, СЛИПШИЙСЯ С ОКРУЖЕНИЕМ, — ТРЕТИЙ ЗАХОД ОДНОГО И ТОГО ЖЕ ДЕФЕКТА.
///
/// ⚠️ Сначала на схеме «страна-адрес» споткнулась проверка формы адреса в дифе
/// подписки: `NL-185.199.108.153` она считала обычным названием. Починили там —
/// и ровно та же слепота нашлась в маскировке журнала, по той же причине: дефис
/// входит в класс символов адреса (без него не разобрать `my-node.example.com`),
/// поэтому весь `NL-185.199.108.153` разбирается как ОДИН кусок, и поиск по
/// реестру его не находит.
///
/// А «страна-адрес» — самая частая схема именования узлов у панелей. Значит без
/// второго прохода боевой IP уезжал в `app.log` из каждой строки, печатающей имя
/// сервера, — и дальше в отчёт поддержки, который владелец отправляет в чат.
void main() {
  const domain = 'de7.node.example';
  const ip = '203.0.113.77';

  setUp(() {
    SensitiveAddresses.remember(domain);
    SensitiveAddresses.remember(ip);
  });

  String labelOf(String address) {
    final masked = SensitiveAddresses.mask('узел $address отвечает');
    return RegExp(r'адрес №\d+').firstMatch(masked)!.group(0)!;
  }

  group('Адрес, приклеенный к названию', () {
    test('⚠️ ГЛАВНОЕ: «СТРАНА-АДРЕС» больше не проходит', () {
      final out = SensitiveAddresses.mask('Скорость «NL-$ip» — 42 Мбит/с');
      expect(out, isNot(contains(ip)),
          reason: 'ЗДЕСЬ БЫЛА ДЫРА: кусок с дефисом не искался в реестре');
      expect(out, contains('NL-'), reason: 'название узла терять незачем');
      expect(out, contains('42 Мбит/с'));
    });

    test('домен так же — «DE1-de7.node.example»', () {
      final out = SensitiveAddresses.mask('пробую DE1-$domain');
      expect(out, isNot(contains(domain)));
    });

    test('в скобках, как пишет панель: «DE-1 (203.0.113.77)»', () {
      final out = SensitiveAddresses.mask('сервер DE-1 ($ip) выбран');
      expect(out, isNot(contains(ip)));
      expect(out, contains('DE-1'));
    });

    test('метка та же, что у отдельно стоящего адреса', () {
      // Иначе один узел получил бы в журнале две разные метки, и строки о нём
      // перестали бы сходиться — а ради этого маскировка и делалась узнаваемой.
      expect(SensitiveAddresses.mask('NL-$ip'), contains(labelOf(ip)));
    });

    test('порт рядом сохраняется', () {
      final out = SensitiveAddresses.mask('dial tcp NL-$ip:443: timeout');
      expect(out, isNot(contains(ip)));
      expect(out, contains(':443'));
    });
  });

  group('Границы: чужое не задето', () {
    test('поддомен известного адреса НЕ маскируется', () {
      // Сознательное решение: суффиксное сравнение начало бы цеплять чужие
      // имена. Здесь важно, что второй проход эту границу не сломал.
      const sub = 'edge.$domain';
      expect(SensitiveAddresses.mask('идём на $sub'), contains(sub));
    });

    test('адрес — начало более длинного имени, не трогаем', () {
      expect(SensitiveAddresses.mask('${ip}7'), contains('${ip}7'));
      expect(SensitiveAddresses.mask('${domain}s'), contains('${domain}s'));
    });

    test('точка как знак препинания маскировке не мешает', () {
      final out = SensitiveAddresses.mask('не достучались до $domain.');
      expect(out, isNot(contains(domain)));
      expect(out.trim(), endsWith('.'));
    });

    test('служебные адреса целы и во втором проходе', () {
      const raw = 'socks 127.0.0.1:10808, tun 172.19.0.1, dns 1.1.1.1';
      expect(SensitiveAddresses.mask(raw), raw);
    });
  });

  group('Реестр пополняется на ходу', () {
    test('⚠️ адрес, добавленный ПОСЛЕ первой маскировки, тоже маскируется', () {
      // Второй проход собирает регулярку из самих адресов и кэширует её. Забудь
      // сбросить кэш при добавлении — и последний импортированный сервер
      // остался бы открытым, а обычный тест этого не заметил бы: в тестах
      // реестр наполняют до первой маскировки.
      const late = '198.51.100.9';
      SensitiveAddresses.mask('прогрев кэша: NL-$ip');
      SensitiveAddresses.remember(late);

      expect(SensitiveAddresses.mask('новый узел RU-$late'),
          isNot(contains(late)));
    });
  });
}
