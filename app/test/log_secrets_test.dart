import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';

/// Секреты не попадают в журнал.
///
/// ⚠️ НАЙДЕНО ЖИВЫМ ТЕСТОМ В VM 13.08.2026 — статикой такое не видно. В госте
/// не было сети, обновление подписки упало, и текст исключения http-клиента лёг
/// в `app.log` ЦЕЛИКОМ: вместе с адресом подписки, а у Remnawave последний
/// сегмент этого адреса И ЕСТЬ токен доступа ко всей подписке.
///
/// Цена высокая: `app.log` вкладывается в отчёт для поддержки, который
/// пользователь по нашей же кнопке отправляет в чат. Шапка отчёта URL
/// маскирует — и именно это создавало ложное ощущение, что всё закрыто.
void main() {
  group('Адрес подписки', () {
    test('токен из пути вырезается, хост остаётся', () {
      const msg = 'Обновление подписки: ClientException, '
          'uri=https://sub.example.lol/sub/Sub7oKeN-Fake01';
      final out = scrubSecrets(msg);
      expect(out, contains('sub.example.lol'),
          reason: 'без хоста не разобрать, к какой панели не достучались');
      expect(out, isNot(contains('Sub7oKeN-Fake01')));
      expect(out, contains('****'));
    });

    test('строка запроса тоже уходит', () {
      final out = scrubSecrets('GET https://panel.example/api?token=SECRET');
      expect(out, isNot(contains('SECRET')));
    });

    test('http так же, как https', () {
      expect(scrubSecrets('http://p.example/sub/TOKEN'), isNot(contains('TOKEN')));
    });

    test('голый хост без пути не портим', () {
      // «Не достучались до panel.example» должно остаться читаемым.
      expect(scrubSecrets('нет связи с https://panel.example'),
          contains('panel.example'));
    });
  });

  group('Ссылки на серверы', () {
    test('vless вырезается целиком — там uuid', () {
      final out = scrubSecrets(
          'Сервер vless://00000000-0000-0000-0000-000000000000@a.b:443?x=1#N');
      expect(out, isNot(contains('00000000-0000-0000-0000-000000000000')));
      expect(out, contains('vless://****'));
    });

    for (final scheme in ['trojan', 'ss', 'hysteria2', 'hy2', 'vmess']) {
      test('$scheme тоже', () {
        final out = scrubSecrets('$scheme://SECRETPASS@host:443#N');
        expect(out, isNot(contains('SECRETPASS')));
      });
    }
  });

  group('Обычные строки не портятся', () {
    test('текст без адресов остаётся как есть', () {
      const msg = 'Автопереподключение: обрыв → попытка 1 через 2 с';
      expect(scrubSecrets(msg), msg);
    });

    test('локальные адреса ядра остаются читаемыми', () {
      // По ним разбирают конфликты портов, секрета в них нет.
      const msg = 'Порт 127.0.0.1:10808 занят процессом happ.exe';
      expect(scrubSecrets(msg), msg);
    });
  });

  group('Очистка идёт на ГРАНИЦЕ журнала', () {
    test('AppLog.e чистит запись, а не место вызова', () {
      // ⚠️ Смысл именно в этом: обработчик, забывший про новый случай, обошёл
      // бы проверку молча. Через _add проходит КАЖДАЯ строка журнала.
      AppLog.e('падение: uri=https://sub.example.lol/sub/TOKEN123');
      final last = AppLog.entries.last.message;
      expect(last, isNot(contains('TOKEN123')));
      expect(last, contains('sub.example.lol'));
    });
  });

  /// Адрес СВОЕГО сервера в журнале.
  ///
  /// ⚠️ КЛАСС, А НЕ СЛУЧАЙ. `VpnServer.displayName` при пустом имени
  /// вырождается в «адрес:порт» и уходит в `AppLog` из девяти мест. Одно из
  /// них (диф подписки) закрыли в месте вызова — остальные восемь продолжали
  /// писать боевой адрес узла в файл, который целиком уезжает в отчёт
  /// поддержки. Здесь стережётся именно граница: строку пишет НЕ тот код, что
  /// её чистит.
  ///
  /// ⚠️ И ровно так же стережётся ЦЕНА: вырезать из журнала все адреса подряд
  /// значило бы вылечить утечку ценой диагностики, ради которой журнал и
  /// существует. Полезные адреса проверяются здесь же — поимённо.
  group('Адреса своих серверов', () {
    setUp(SensitiveAddresses.forgetAllForTest);
    tearDown(SensitiveAddresses.forgetAllForTest);

    test('боевой узел подписки уходит замаскированным, а 127.0.0.1 и TUN — нет',
        () {
      SensitiveAddresses.remember('ru1.example.net');

      // Ровно то, что писал `displayName` у сервера без имени.
      final out = scrubSecrets('Переключаюсь на запасной сервер: '
          'ru1.example.net:443');
      expect(out, isNot(contains('ru1.example.net')),
          reason: 'боевой адрес узла подписки в журнал попадать не должен');
      expect(out, contains(':443'),
          reason: 'порт не секрет и нужен для разбора');

      // ⚠️ Без этой половины лечение хуже болезни: по этим адресам разбирают
      // конфликты портов ядра и подъём туннеля.
      const core = 'Порт 127.0.0.1:10808 занят процессом happ.exe';
      expect(scrubSecrets(core), core);
      const tun = 'TUN поднят: адрес 172.19.0.1, DNS 172.19.0.2';
      expect(scrubSecrets(tun), tun);
      const dns = 'Резолвер для «Прямо»: 1.1.1.1';
      expect(scrubSecrets(dns), dns);
    });

    test('одна и та же метка в разных строках — иначе разбирать нечем', () {
      SensitiveAddresses.remember('ru1.example.net');
      SensitiveAddresses.remember('de2.example.net');

      final a = scrubSecrets('Пинг ru1.example.net:443 не прошёл');
      final b = scrubSecrets('Не удалось отрезолвить ru1.example.net');
      final c = scrubSecrets('Пинг de2.example.net:443 не прошёл');

      String? labelOf(String line) =>
          RegExp('адрес №[0-9]+').firstMatch(line)?.group(0);

      expect(labelOf(a), isNotNull);
      expect(labelOf(b), labelOf(a),
          reason: 'по журналу должно быть видно, что это тот же узел');
      expect(labelOf(c), isNotNull);
      expect(labelOf(c), isNot(labelOf(a)),
          reason: 'разные узлы — разные метки');
    });

    test('разные порты одного хоста различимы', () {
      SensitiveAddresses.remember('ru1.example.net');
      final out = scrubSecrets('ru1.example.net:443 и ru1.example.net:8443');
      expect(out, contains(':443'));
      expect(out, contains(':8443'));
      expect(out, isNot(contains('ru1.example.net')));
    });

    test('всё, что реестр ПРИНЯЛ, сканер журнала находит', () {
      // ⚠️ Страж согласованности двух разборов. Реестр, принявший адрес,
      // который сканер не ловит, выглядел бы закрытой дырой — а это хуже
      // открытой.
      const forms = [
        'ru1.example.net', // домен
        '203.0.113.10', // IPv4
        '2001:db8::1', // IPv6
      ];
      for (final form in forms) {
        SensitiveAddresses.forgetAllForTest();
        SensitiveAddresses.remember(form);
        expect(SensitiveAddresses.count, 1, reason: 'реестр принял $form');
        expect(scrubSecrets('узел $form отвечает'), isNot(contains(form)),
            reason: '$form принят реестром, но не найден в строке');
      }
    });

    test('IPv6 маскируется и в скобках, и с портом', () {
      SensitiveAddresses.remember('2001:db8::1');
      expect(scrubSecrets('dial [2001:db8::1]:443'), isNot(contains('db8')));
      expect(scrubSecrets('dial [2001:db8::1]:443'), contains(':443'));
    });

    test('регистр и хвостовая пунктуация не спасают адрес', () {
      SensitiveAddresses.remember('RU1.Example.NET');
      expect(scrubSecrets('не достучались до ru1.example.net.'),
          isNot(contains('example')));
      expect(scrubSecrets('(203.0.113.10)'), contains('203.0.113.10'),
          reason: 'чужой адрес не наш — трогать его нечего');
    });

    test('IP из НАЗВАНИЯ узла тоже секрет, домен из названия — нет', () {
      // Панель раздаёт узлы по домену, а зовёт по IP: «DE-1 (203.0.113.10)».
      // Поле address такой адрес не содержит вовсе.
      SensitiveAddresses.remember('de1.panel.net', name: 'DE-1 (203.0.113.10)');
      expect(scrubSecrets('сервер 203.0.113.10 не отвечает'),
          isNot(contains('203.0.113.10')));

      // А доменное имя внутри названия — почти всегда часть самого названия;
      // маскируй мы и его, из журнала пропали бы имена сервисов, по которым
      // разбирают проверки доступности.
      SensitiveAddresses.remember('nl9.panel.net', name: 'YouTube.com Fast');
      expect(scrubSecrets('Проверка youtube.com: 200'), contains('youtube.com'));
    });

    test('пустой реестр ничего не трогает', () {
      const msg = 'Пинг ru1.example.net:443 не прошёл';
      expect(SensitiveAddresses.count, 0);
      expect(scrubSecrets(msg), msg);
    });

    test('адрес-заглушка истёкшей подписки в реестр не идёт', () {
      // Серверы-уведомления приходят с адресом 0.0.0.0:1 — маскировать его
      // значило бы прятать признак, по которому такую подписку и опознают.
      SensitiveAddresses.remember('0.0.0.0');
      SensitiveAddresses.remember('127.0.0.1');
      SensitiveAddresses.remember('172.19.0.1');
      expect(SensitiveAddresses.count, 0);
    });

    test('AppLog.i чистит адрес на границе, а не в месте вызова', () {
      SensitiveAddresses.remember('ru1.example.net');
      AppLog.i('Сервер выбран по имени из ссылки: ru1.example.net:443');
      expect(AppLog.entries.last.message, isNot(contains('ru1.example.net')));
      expect(AppLog.entries.last.message, contains('адрес №'));
    });

    test('dump маскирует и то, что легло в ФАЙЛ до наполнения реестра',
        () async {
      // ⚠️ Не теория: файл живёт до 512 КБ, то есть днями, и переживает
      // перезапуск. Строки прошлых запусков (и прошлых версий) реестра не
      // проходили — а в отчёт поддержки уезжает файл целиком, и читает его
      // именно `dump()`.
      final tmp = Directory.systemTemp.createTempSync('sg_log_mask_');
      await AppLog.useFileForTest(
          '${tmp.path}${Platform.pathSeparator}app.log');
      try {
        AppLog.i('Ранний старт: ru1.example.net:443');
        await AppLog.flushFile();
        SensitiveAddresses.remember('ru1.example.net');

        final text = await AppLog.dump();
        expect(text, isNot(contains('ru1.example.net')));
        expect(text, contains('адрес №'));
      } finally {
        await AppLog.resetFileForTest();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
