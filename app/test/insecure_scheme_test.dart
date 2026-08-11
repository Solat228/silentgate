import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// Пометка «адрес задан как http://» — красный открытый замок в строке правила.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНОЕ ПОЛЕ, А НЕ РАЗБОР СТРОКИ НА ЛЕТУ. [normalizeDomain]
/// срезает схему, и после него `http://site.com` неотличим от `site.com`.
/// Значит признак надо запомнить в момент ввода — иначе замок либо не покажется
/// никогда, либо покажется всем подряд.
///
/// Показываем его ТОЛЬКО когда схему написал сам пользователь: правило по имени
/// домена работает одинаково для http и https, и додумывать за человека то,
/// чего он не вводил, значит пугать без причины.
void main() {
  group('Опознание явной схемы http', () {
    test('явный http:// — считается', () {
      expect(hasInsecureScheme('http://site.com'), isTrue);
      expect(hasInsecureScheme('HTTP://SITE.COM'), isTrue);
      expect(hasInsecureScheme('  http://site.com/lk?x=1  '), isTrue);
    });

    test('https и адрес без схемы — НЕ считается', () {
      // Без схемы браузер сам пойдёт в https: пугать нечем.
      expect(hasInsecureScheme('site.com'), isFalse);
      expect(hasInsecureScheme('https://site.com'), isFalse);
      expect(hasInsecureScheme('www.site.com'), isFalse);
    });

    test('чужие схемы не путаются с http', () {
      // ⚠️ Наивная проверка `contains('http')` дала бы true на каждой из них.
      expect(hasInsecureScheme('ws://site.com'), isFalse);
      expect(hasInsecureScheme('ftp://site.com'), isFalse);
      expect(hasInsecureScheme('site.com/http://x'), isFalse);
      expect(hasInsecureScheme('httpbin.org'), isFalse);
    });
  });

  group('Признак переживает сохранение', () {
    test('флаг доезжает через JSON', () {
      const s = SiteRule('site.com',
          action: AppAction.block, insecureScheme: true);
      expect(SiteRule.fromJson(s.toJson()).insecureScheme, isTrue);
    });

    test('старые правила замка не получают', () {
      // Ключа нет во всём, что заведено раньше. Мы не знаем, что человек тогда
      // вводил, и выдумывать за него нельзя.
      expect(SiteRule.fromJson({'domain': 'old.com'}).insecureScheme, isFalse);
    });

    test('copyWith не теряет флаг', () {
      // Класс багов «поле пишется, но не читается» здесь наиболее вероятен:
      // copyWith зовётся на каждой правке действия и сервера.
      const s = SiteRule('site.com', insecureScheme: true);
      expect(s.copyWith(action: AppAction.tunnel).insecureScheme, isTrue);
      expect(s.copyWith(serverKey: 'vless://x').insecureScheme, isTrue);
      expect(s.copyWith(insecureScheme: false).insecureScheme, isFalse);
    });

    test('флаг НЕ пишется в JSON, когда он ложный', () {
      // Настройки читает человек: лишний ключ у каждого правила — шум.
      const s = SiteRule('site.com');
      expect(s.toJson().containsKey('insecureScheme'), isFalse);
    });
  });

  group('На маршрутизацию не влияет', () {
    test('домен нормализуется одинаково со схемой и без', () {
      // Признак чисто отображательный: правило работает по имени и порту.
      expect(normalizeDomain('http://www.site.com:8080/lk'), 'site.com');
      expect(normalizeDomain('site.com'), 'site.com');
      expect(extractPort('http://site.com:8080'), 8080);
    });
  });
}
