import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/block_notice_watcher.dart';

/// Уведомление «сайт заблокирован вашим правилом».
///
/// ⚠️ ЧТО ЭТО ЗАМЕНИЛО И ПОЧЕМУ. Раньше стояла страница-заглушка: ядро уводило
/// http-соединение на локальный сервер, и тот показывал объяснение. До
/// пользователя она почти не доходила — браузеры идут в `https` сразу, HSTS
/// переписывает адрес ДО отправки запроса, и человек видел
/// `ERR_CONNECTION_RESET`. Подменить `https` без своего корневого сертификата
/// нельзя, а ставить такой сертификат значит получить возможность читать весь
/// TLS пользователя.
///
/// Уведомление ничего не подменяет и работает на любом протоколе. Разбор
/// снимка соединений вынесен в статический метод именно чтобы его можно было
/// проверить без сети и без ядра.
void main() {
  Map<String, dynamic> conn(String host, {List<String> chains = const []}) => {
        'chains': chains,
        'metadata': {'host': host},
      };

  group('Что считается блокировкой', () {
    test('точное совпадение с правилом', () {
      final hosts = BlockNoticeWatcher.blockedHostsIn(
          {'connections': [conn('ads.example')]}, {'ads.example'});
      expect(hosts, {'ads.example'});
    });

    test('поддомен закрытого домена — тоже блокировка', () {
      // Ядро матчит `domain_suffix`, значит `cdn.ads.example` закрыт правилом
      // `ads.example`. Сообщать надо об этом же правиле.
      final hosts = BlockNoticeWatcher.blockedHostsIn(
          {'connections': [conn('cdn.ads.example')]}, {'ads.example'});
      expect(hosts, {'ads.example'},
          reason: 'называем ПРАВИЛО, а не хост: человек ищет в списке то, '
              'что он туда вписывал');
    });

    test('чужой домен не считается', () {
      // ⚠️ Наивная проверка `contains` дала бы ложное срабатывание на
      // `notads.example` и `ads.example.evil.com`.
      for (final host in ['notads.example', 'ads.example.evil.com', 'other.com']) {
        expect(
            BlockNoticeWatcher.blockedHostsIn(
                {'connections': [conn(host)]}, {'ads.example'}),
            isEmpty,
            reason: '$host не закрыт правилом ads.example');
      }
    });

    test('побеждает САМОЕ конкретное правило', () {
      // В ядре первым срабатывает более конкретное — и в сообщении должно
      // стоять оно же, иначе человек пойдёт править не ту строку.
      final hosts = BlockNoticeWatcher.blockedHostsIn(
          {'connections': [conn('cdn.ads.example')]},
          {'ads.example', 'cdn.ads.example'});
      expect(hosts, {'cdn.ads.example'});
    });

    test('регистр не мешает', () {
      final hosts = BlockNoticeWatcher.blockedHostsIn(
          {'connections': [conn('ADS.Example')]}, {'ads.example'});
      expect(hosts, {'ads.example'});
    });

    test('цепочка не требуется', () {
      // ⚠️ Блокируем действием `reject` на ПРАВИЛЕ, а не отдельным
      // outbound-ом, поэтому блок-тега в `chains` может не быть вовсе.
      // Требовать его значило бы не заметить ни одной блокировки.
      final hosts = BlockNoticeWatcher.blockedHostsIn(
          {'connections': [conn('ads.example', chains: ['proxy'])]},
          {'ads.example'});
      expect(hosts, {'ads.example'});
    });
  });

  group('Мусор на входе не роняет разбор', () {
    test('пустой список правил — ничего не ищем', () {
      expect(
          BlockNoticeWatcher.blockedHostsIn(
              {'connections': [conn('ads.example')]}, const {}),
          isEmpty);
    });

    test('соединение без метаданных и без хоста пропускается', () {
      final raw = {
        'connections': [
          {'chains': []},
          {'metadata': {}},
          {'metadata': {'host': ''}},
          'не карта',
        ]
      };
      expect(
          BlockNoticeWatcher.blockedHostsIn(raw, {'ads.example'}), isEmpty);
    });

    test('не тот формат ответа — пустой результат, а не исключение', () {
      // Ядро другой версии может отдать что угодно. Падать здесь нельзя:
      // это фоновый опрос, его сбой не должен трогать подключение.
      for (final raw in [null, 'строка', 42, <String, Object>{}]) {
        expect(BlockNoticeWatcher.blockedHostsIn(raw, {'ads.example'}), isEmpty);
      }
    });

    test('пустое правило в списке игнорируется', () {
      // Пустая строка совпала бы с чем угодно по суффиксу.
      expect(
          BlockNoticeWatcher.blockedHostsIn(
              {'connections': [conn('any.com')]}, {'', '   '}),
          isEmpty);
    });
  });

  group('Сопоставление правила', () {
    test('matchBlocked отдаёт имя правила либо null', () {
      expect(BlockNoticeWatcher.matchBlocked('a.b.com', {'b.com'}), 'b.com');
      expect(BlockNoticeWatcher.matchBlocked('b.com', {'b.com'}), 'b.com');
      expect(BlockNoticeWatcher.matchBlocked('xb.com', {'b.com'}), isNull);
      expect(BlockNoticeWatcher.matchBlocked('b.com', const {}), isNull);
    });
  });

  group('Жизненный цикл', () {
    test('без правил сторож не опрашивает ядро вовсе', () async {
      // Порт заведомо мёртвый: если бы опрос шёл, тест ловил бы таймауты.
      final w = BlockNoticeWatcher(apiPort: 1, secret: '');
      w.start();
      expect(w.isRunning, isTrue);
      await w.dispose();
      expect(w.isRunning, isFalse);
    });

    test('повторный start не плодит таймеры', () async {
      final w = BlockNoticeWatcher(apiPort: 1, secret: '');
      w.start();
      w.start();
      expect(w.isRunning, isTrue);
      await w.dispose();
    });
  });
}
