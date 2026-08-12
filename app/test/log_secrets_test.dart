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
}
