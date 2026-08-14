import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/site_favicon.dart';

/// Список сайтов пользователя не уходит на сторону.
///
/// Домены в раздельном туннелировании — это правила VPN, то есть прямой ответ
/// на вопрос «что человек хочет скрыть». `SiteFaviconService` спрашивал иконки
/// у `google.com/s2/favicons?domain=…` и `favicone.com/…`, то есть отдавал имя
/// каждого такого сайта третьей стороне вместе с адресом пользователя — ровно
/// та утечка, ради защиты от которой VPN и ставят.
///
/// Проверяем в четыре эшелона: адреса проб, гейт, ЖИВЫЕ редиректы на настоящем
/// сокете и страж по исходникам `lib/` — чтобы посредник не вернулся другим
/// файлом.
void main() {
  group('Вшитые сервисы: послабление и его границы', _builtInGateTests);

  group('SiteFaviconService.iconSources: только сам сайт', () {
    test('ни один адрес не ведёт к посреднику', () {
      final urls = SiteFaviconService.iconSources('nalog.ru');
      expect(urls, isNotEmpty);
      for (final u in urls) {
        final host = Uri.parse(u).host;
        expect(host == 'nalog.ru' || host.endsWith('.nalog.ru'), isTrue,
            reason: 'имя сайта из правил уехало на $host: $u');
      }
      // Явно про тех, кто там стоял: имя домена было ЗНАЧЕНИЕМ параметра.
      expect(urls.any((u) => u.contains('google.com')), isFalse);
      expect(urls.any((u) => u.contains('favicone')), isFalse);
    });

    test('поддомен пробует и свой корень — но не выходит за него', () {
      final urls = SiteFaviconService.iconSources('shop.example.co.uk');
      expect(urls, contains('https://shop.example.co.uk/favicon.png'));
      expect(urls, contains('https://example.co.uk/favicon.png'));
      for (final u in urls) {
        final host = Uri.parse(u).host;
        expect(host.endsWith('example.co.uk'), isTrue, reason: u);
      }
    });

    test('иконка из HTML сайта проходит тот же гейт', () {
      // Своя статика — годится: это тот же сайт.
      expect(
          SiteFaviconService.iconSources('example.com',
              fromHtml: 'https://static.example.com/i.png'),
          contains('https://static.example.com/i.png'));
      // ⚠️ Чужой хост — нет, ДАЖЕ ЕСЛИ его назвал сам сайт в своём HTML
      // (`x.com` → `abs.twimg.com`). Решение разобрано в doc-комментарии
      // `iconSources`: наблюдатель опознаёт сайт по самому адресу иконки, а
      // общих CDN на всю сеть несколько штук — один такой собрал бы заметную
      // часть списка правил, как это делал `s2/favicons`.
      expect(
          SiteFaviconService.iconSources('example.com',
              fromHtml: 'https://cdn.tracker.net/i.png'),
          isNot(contains('https://cdn.tracker.net/i.png')));
      expect(
          SiteFaviconService.iconSources('x.com',
              fromHtml: 'https://abs.twimg.com/favicons/twitter.png'),
          isNot(contains('https://abs.twimg.com/favicons/twitter.png')));
    });
  });

  group('SiteFaviconService.allowedIconUrl', () {
    test('сам сайт и его поддомены — можно', () {
      expect(SiteFaviconService.allowedIconUrl(
          'https://example.com/favicon.png', 'example.com'), isTrue);
      expect(SiteFaviconService.allowedIconUrl(
          'https://www.example.com/favicon.png', 'example.com'), isTrue);
      // Правило на поддомене: корень — это всё ещё тот же сайт.
      expect(SiteFaviconService.allowedIconUrl(
          'https://example.com/favicon.png', 'shop.example.com'), isTrue);
    });

    test('посредники — нельзя', () {
      expect(
          SiteFaviconService.allowedIconUrl(
              'https://www.google.com/s2/favicons?sz=64&domain=nalog.ru',
              'nalog.ru'),
          isFalse);
      expect(
          SiteFaviconService.allowedIconUrl(
              'https://favicone.com/nalog.ru?s=64', 'nalog.ru'),
          isFalse);
    });

    test('похожее имя — не то же самое', () {
      // ⚠️ Голый суффикс строки пустил бы `evilexample.com` за `example.com`:
      // сравнение идёт по метке `.<корень>`.
      expect(SiteFaviconService.allowedIconUrl(
          'https://evilexample.com/f.png', 'example.com'), isFalse);
      expect(SiteFaviconService.allowedIconUrl(
          'https://example.com.attacker.net/f.png', 'example.com'), isFalse);
    });

    test('сосед по общему хостингу — не «тот же сайт»', () {
      // ⚠️ `rootDomain` разбирает домен без списка публичных суффиксов:
      // «корнем» `user.github.io` он считает `github.io`. Пока гейт пускал всё
      // под корнем, сюда проходил ЧУЖОЙ арендатор того же хостинга.
      expect(SiteFaviconService.allowedIconUrl(
          'https://evil.github.io/f.png', 'user.github.io'), isFalse);
      expect(
          SiteFaviconService.allowedIconUrl(
              'https://other.s3.amazonaws.com/f.png',
              'bucket.s3.amazonaws.com'),
          isFalse);
      // Тот же запрет и для обычного домена: сосед по корню — не наш сайт.
      expect(SiteFaviconService.allowedIconUrl(
          'https://sibling.example.com/f.png', 'shop.example.com'), isFalse);
      // Сам корень при этом разрешён: `https://github.io/favicon.png` о
      // конкретном `user.` ничего не сообщает, а фавикон чаще лежит на корне.
      expect(SiteFaviconService.allowedIconUrl(
          'https://github.io/favicon.png', 'user.github.io'), isTrue);
      // Свои поддомены домена из правила — по-прежнему можно.
      expect(SiteFaviconService.allowedIconUrl(
          'https://static.example.com/f.png', 'example.com'), isTrue);
    });

    test('только https и только http(s)-схемы', () {
      expect(SiteFaviconService.allowedIconUrl(
          'http://example.com/f.png', 'example.com'), isFalse);
      expect(SiteFaviconService.allowedIconUrl(
          'data:image/png;base64,AAA', 'example.com'), isFalse);
      expect(SiteFaviconService.allowedIconUrl('', 'example.com'), isFalse);
      expect(SiteFaviconService.allowedIconUrl(
          '/favicon.png', 'example.com'), isFalse);
    });

    test('литеральный адрес — только точное совпадение', () {
      expect(SiteFaviconService.allowedIconUrl(
          'https://192.168.1.1/favicon.png', '192.168.1.1'), isTrue);
      // Без особого случая «корнем» 192.168.1.1 оказался бы `1.1`, и сюда
      // прошёл бы любой хост, кончающийся на `.1.1`.
      expect(SiteFaviconService.allowedIconUrl(
          'https://tracker.1.1/favicon.png', '192.168.1.1'), isFalse);
    });

    test('iconGateFor — тот же гейт, что уходит в сеть', () {
      final gate = SiteFaviconService.iconGateFor('example.com');
      expect(gate(Uri.parse('https://example.com/favicon.png')), isTrue);
      expect(gate(Uri.parse('https://static.example.com/i.png')), isTrue);
      expect(gate(Uri.parse('https://cdn.tracker.net/i.png')), isFalse);
      expect(gate(Uri.parse('http://example.com/favicon.png')), isFalse);
    });
  });

  /// ⚠️ ГЛАВНОЕ. Гейт на редиректах был МЁРТВЫМ КОДОМ: `HttpClient` по
  /// умолчанию `followRedirects = true` и уходит по 30x САМ, ещё до того как
  /// код увидит статус. Проверить это можно только настоящим сокетом —
  /// поэтому здесь два живых сервера.
  ///
  /// Роль «чужого CDN» играет ВТОРОЙ локальный сервер: офлайн у нас нет ни
  /// https, ни настоящих доменов, а проверяемый механизм (автоследование
  /// выключено + каждый переход спрашивает гейт) от имени хоста не зависит —
  /// гейт здесь свой, «только этот источник». Он же ловит и подмену:
  /// решающая проверка — СЧЁТЧИК ЗАПРОСОВ на чужом сервере, а не только null
  /// в ответе (при живом автоследовании счётчик станет 1, то есть имя сайта
  /// уже уехало бы к постороннему).
  group('редиректы: клиент не уходит по 30x сам', () {
    late HttpServer site;
    late HttpServer foreign;
    var foreignHits = 0;

    // Минимальный валидный PNG (сигнатура + IHDR-заголовок): распознаётся и по
    // магическим байтам, и по Content-Type.
    final png = <int>[
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
    ];

    setUp(() async {
      foreignHits = 0;
      foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      foreign.listen((r) {
        foreignHits++;
        r.response
          ..statusCode = 200
          ..headers.contentType = ContentType('image', 'png')
          ..add(png);
        r.response.close();
      });
      site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      site.listen((r) {
        final res = r.response;
        final path = r.uri.path;
        if (path == '/off.png') {
          // 302 к постороннему источнику
          res.statusCode = 302;
          res.headers.set(HttpHeaders.locationHeader,
              'http://127.0.0.1:${foreign.port}/i.png');
        } else if (path == '/on.png') {
          // 302 внутри своего же источника
          res.statusCode = 302;
          res.headers.set(HttpHeaders.locationHeader, '/real.png');
        } else if (path == '/loop.png') {
          // бесконечная цепочка
          res.statusCode = 302;
          res.headers.set(HttpHeaders.locationHeader, '/loop.png');
        } else if (path == '/real.png') {
          res.statusCode = 200;
          res.headers.contentType = ContentType('image', 'png');
          res.add(png);
        } else {
          res.statusCode = 404;
        }
        res.close();
      });
    });

    tearDown(() async {
      await site.close(force: true);
      await foreign.close(force: true);
    });

    // Гейт теста: разрешён ровно «свой» сервер, всё прочее — посторонний.
    bool Function(Uri) onlySite() =>
        (u) => u.host == '127.0.0.1' && u.port == site.port;

    test('302 на посторонний источник — не идём, и он нас не видит', () async {
      final bytes = await SiteFaviconService.fetchIconBytes(
          Uri.parse('http://127.0.0.1:${site.port}/off.png'), onlySite());
      // Счётчик первым: утечка — это САМ ЗАПРОС, а не то, что мы с ответом
      // сделали. Клиент, ушедший по 30x сам, уже сообщил постороннему всё.
      expect(foreignHits, 0,
          reason: 'клиент ушёл по 30x сам — гейт на редиректах мёртв, '
              'и посторонний узнал о домене из правил пользователя');
      expect(bytes, isNull, reason: 'иконку с постороннего хоста не берём');
    });

    test('302 внутри своего источника — идём, иконка берётся', () async {
      final bytes = await SiteFaviconService.fetchIconBytes(
          Uri.parse('http://127.0.0.1:${site.port}/on.png'), onlySite());
      expect(bytes, isNotNull, reason: 'свои редиректы ломать не хотели');
      expect(bytes!.take(4), [0x89, 0x50, 0x4e, 0x47]);
      expect(foreignHits, 0);
    });

    test('бесконечная цепочка обрывается', () async {
      final bytes = await SiteFaviconService.fetchIconBytes(
          Uri.parse('http://127.0.0.1:${site.port}/loop.png'), onlySite());
      expect(bytes, isNull);
    });

    test('посторонний адрес не запрашивается и без редиректа', () async {
      // Гейт спрашивается и про ПЕРВЫЙ адрес: иначе правило жило бы в двух
      // местах (список источников и загрузка), а расходятся именно такие пары.
      final bytes = await SiteFaviconService.fetchIconBytes(
          Uri.parse('http://127.0.0.1:${foreign.port}/i.png'), onlySite());
      expect(bytes, isNull);
      expect(foreignHits, 0, reason: 'сходили к постороннему до проверки');
    });
  });

  group('страж: посредников нет нигде в lib/', () {
    /// Комментарии выбрасываем: разбор дефекта в doc-комментарии (а он тут
    /// есть — про прежние источники) сам считался бы нарушением.
    String stripCommentLines(String src) => src
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              !t.startsWith('/*');
        })
        .join('\n');

    // Сервисы, которым имя сайта отдаётся ЗНАЧЕНИЕМ параметра.
    const brokers = ['s2/favicons', 'favicone.com', 'icons.duckduckgo.com'];

    String? brokerProblem(String source) {
      final src = stripCommentLines(source).toLowerCase();
      for (final b in brokers) {
        if (src.contains(b)) return 'иконки через посредника $b';
      }
      return null;
    }

    test('исходники lib/ чисты', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final problem = brokerProblem(f.readAsStringSync());
        if (problem != null) {
          offenders.add('${f.path.replaceAll(r'\', '/')} — $problem');
        }
      }
      expect(offenders, isEmpty,
          reason: 'список сайтов пользователя уходит третьей стороне: '
              '$offenders');
    });

    test('страж ловит нарушение — проверено на образцах', () {
      // ⚠️ Страж выше зелёный, пока в lib/ чисто, — при ЛЮБОЙ своей логике,
      // включая сломанную. Здесь та же функция гоняется по образцам.
      expect(
          brokerProblem(
              "'https://www.google.com/s2/favicons?sz=64&domain=\$domain',"),
          isNotNull);
      expect(brokerProblem("'https://favicone.com/\$domain?s=64',"), isNotNull);
      expect(brokerProblem("'https://\$domain/favicon.png',"), isNull);
      expect(brokerProblem('/// Раньше ходили в favicone.com — больше нет'),
          isNull);
    });

    test('автоследование редиректов выключено в КОДЕ, а не в комментарии', () {
      // Живой тест выше падает, если строку убрать, но падает он и от десятка
      // других причин; здесь — прямо про строку, из-за отсутствия которой гейт
      // выглядел защитой, ничего не защищая.
      // ⚠️ И обязательно БЕЗ комментариев: рядом со строкой лежит абзац, где
      // `followRedirects = false` упомянуто словами. На первом же прогоне этот
      // страж остался зелёным при `= true` в коде — искал он комментарий.
      final src = stripCommentLines(
          File('lib/core/net/site_favicon.dart').readAsStringSync());
      expect(src.contains('followRedirects = false'), isTrue,
          reason: 'HttpClient по умолчанию идёт по 30x сам — гейт мёртв');
      expect(src.contains('followRedirects = true'), isFalse);
    });

    test('запрос в сеть ровно один — и он гейтнутый', () {
      // ⚠️ Гейт защищает столько адресов, сколько запросов идёт ЧЕРЕЗ него.
      // Второй `getUrl` в файле — это второй путь наружу, который про правила
      // пользователя ничего не знает (так и жил разбор HTML до этого круга).
      final src = stripCommentLines(
          File('lib/core/net/site_favicon.dart').readAsStringSync());
      expect('getUrl('.allMatches(src).length, 1,
          reason: 'запрос мимо _openGated — гейт его не увидит');
    });
  });
}

/// ⚠️ ГРАНИЦА ПОСЛАБЛЕНИЯ ДЛЯ ВШИТЫХ СЕРВИСОВ.
///
/// Строгий гейт заводился ради ОДНОГО: список сайтов из правил раздельного
/// туннелирования — это перечень того, что человек хочет скрыть, и он у каждого
/// свой. Вшитый список сервис-чипов одинаков у всех, кто поставил приложение, и
/// обращение за иконкой `x.com` не сообщает о пользователе ничего сверх факта
/// установки. Поэтому там разрешается ОДИН адрес — тот, что сайт назвал в своём
/// HTML, — иначе у `x.com` и `instagram.com` осталась бы буква вместо картинки.
///
/// Опасность послабления в том, что оно легко расползается: «разрешить хост»
/// открыло бы весь общий CDN, а общий кэш вернул бы чужую иконку в правила
/// пользователя. Здесь проверяется, что не расползлось.
void _builtInGateTests() {
  const site = 'example-site.com';
  const declared = 'https://cdn.example-net.com/icon.png';

  test('вшитому сервису разрешён ИМЕННО объявленный адрес', () {
    final gate = SiteFaviconService.iconGateFor(site, allowSiteDeclared: declared);
    expect(gate(Uri.parse(declared)), isTrue);
  });

  test('⚠️ и только он: соседний файл на том же чужом хосте — отказ', () {
    final gate = SiteFaviconService.iconGateFor(site, allowSiteDeclared: declared);
    expect(gate(Uri.parse('https://cdn.example-net.com/other.png')), isFalse,
        reason: 'разрешение хоста открыло бы весь общий CDN');
    expect(gate(Uri.parse('https://cdn.example-net.com/')), isFalse);
  });

  test('⚠️ послабление НЕ действует для домена из правил пользователя', () {
    final gate = SiteFaviconService.iconGateFor(site);
    expect(gate(Uri.parse(declared)), isFalse,
        reason: 'ЗДЕСЬ И БЫЛА БЫ УТЕЧКА: список правил уехал бы к посреднику');
  });

  test('послабление не отменяет требования https', () {
    const plain = 'http://cdn.example-net.com/icon.png';
    final gate = SiteFaviconService.iconGateFor(site, allowSiteDeclared: plain);
    expect(gate(Uri.parse(plain)), isFalse);
  });

  test('сам сайт разрешён в обоих режимах', () {
    for (final gate in [
      SiteFaviconService.iconGateFor(site),
      SiteFaviconService.iconGateFor(site, allowSiteDeclared: declared),
    ]) {
      expect(gate(Uri.parse('https://$site/favicon.png')), isTrue);
    }
  });
}
