import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/engine/windows/support_report.dart';

/// ЛОГИ ЯДЕР В ОТЧЁТЕ ПОДДЕРЖКИ — ВТОРАЯ ДВЕРЬ ДЛЯ ТЕХ ЖЕ АДРЕСОВ.
///
/// ⚠️ Барьер в `AppLog` закрывает НАШ журнал, но логи ядер пишет не приложение:
/// `singbox.log`, `singbox_proxy.log` и `singbox_exit_router.log` читаются
/// файлами напрямую и в отчёт попадают своим путём. Адресов в них БОЛЬШЕ, чем в
/// нашем журнале — каждая строка `dial tcp <адрес>:443` называет боевой узел
/// подписки. А отчёт владелец отправляет постороннему человеку в чат.
///
/// Закрой мы только `app.log` — работа была бы напрасной: тот же адрес уехал бы
/// секцией ниже.
void main() {
  const node = 'de7.node.example';
  const nodeIp = '203.0.113.77';

  setUp(() {
    SensitiveAddresses.remember(node);
    SensitiveAddresses.remember(nodeIp);
  });

  group('Лог ядра в отчёте поддержки', () {
    test('⚠️ адрес узла подписки не уходит в отчёт', () {
      const raw = 'ERROR connection: open outbound connection: '
          'dial tcp $node:443: i/o timeout';

      final out = SupportReport.maskCoreLog(raw);

      expect(out, isNot(contains(node)),
          reason: 'ЗДЕСЬ БЫЛА ДЫРА: app.log чистили, а лог ядра — нет');
      expect(out, contains('адрес №'),
          reason: 'место адреса должно остаться видимым, иначе строку не понять');
      expect(out, contains(':443'),
          reason: 'порт не секрет, а без него не отличить узел от узла');
      expect(out, contains('i/o timeout'),
          reason: 'сама ошибка обязана дойти до поддержки');
    });

    test('адрес в виде IP — так же', () {
      final out = SupportReport.maskCoreLog('dial tcp $nodeIp:8443: refused');
      expect(out, isNot(contains(nodeIp)));
      expect(out, contains(':8443'));
    });

    test('⚠️ метка ОДНА И ТА ЖЕ, что в нашем журнале', () {
      // Реестр общий, поэтому «адрес №3» в app.log и в логе ядра — один узел.
      // Разойдись нумерация — сопоставить две секции отчёта стало бы нечем, а
      // ради этого сопоставления отчёт и собирают.
      final ours = scrubSecrets('Переключаюсь на запасной: $node:443');
      final core = SupportReport.maskCoreLog('dial tcp $node:443: timeout');

      final label = RegExp(r'адрес №\d+').firstMatch(ours)?.group(0);
      expect(label, isNotNull, reason: 'наш журнал обязан маскировать');
      expect(core, contains(label!));
    });

    test('служебные адреса остаются как есть — иначе лог бесполезен', () {
      const raw = 'inbound/mixed[probe-in]: tcp connection from 127.0.0.1:10808\n'
          'router: found process, dns 1.1.1.1, tun 172.19.0.1';

      final out = SupportReport.maskCoreLog(raw);

      expect(out, contains('127.0.0.1:10808'));
      expect(out, contains('1.1.1.1'));
      expect(out, contains('172.19.0.1'),
          reason: 'адрес нашего TUN — первое, что смотрят при разборе');
    });

    test('причёсывание лога никуда не делось', () {
      // Смещение часового пояса ядро печатает ПЕРЕД датой; маска не должна
      // отменять перестановку, ради которой лог и причёсывают.
      final out = SupportReport.maskCoreLog('+0700 2026-08-11 02:09:08 INFO старт');
      expect(out, isNot(startsWith('+0700')));
      expect(out, contains('INFO'));
    });
  });

  group('Пароли в логе ядра', () {
    // Строка из настоящего отчёта владельца (13.10.2026): sing-box при отказе
    // в доступе к локальному порту печатает присланные креды целиком. Это
    // пароль живого инбаунда проб — с ним любой процесс телефона получает
    // туннель. Отчёт уходит в чат постороннему человеку.
    const secret = '0123456789abcdef0123456789abcdef';
    const leaking = 'ERROR inbound/mixed[probe-in]: process connection from '
        '127.0.0.1:46218: http: authentication failed, username=sg, '
        'password=$secret';

    test('⚠️ пароль из отказа в доступе не уходит в отчёт', () {
      final out = SupportReport.maskCoreLog(leaking);
      expect(out, isNot(contains(secret)));
      expect(out, contains('password=***'));
      expect(out, contains('authentication failed'),
          reason: 'сам факт отказа поддержке нужен');
      expect(out, contains('127.0.0.1:46218'));
    });

    test('⚠️ маска работает и при пустом реестре адресов', () {
      // Реестр пуст до импорта подписки — и раньше `mask` выходил сразу,
      // ничего не трогая. Пароль от реестра не зависит.
      SensitiveAddresses.forgetAllForTest();
      expect(SupportReport.maskCoreLog(leaking), isNot(contains(secret)));
      expect(SensitiveAddresses.mask(leaking), isNot(contains(secret)));
    });

    test('наш журнал — та же граница', () {
      SensitiveAddresses.forgetAllForTest();
      expect(scrubSecrets(leaking), isNot(contains(secret)));
    });

    test('другие формы секрета', () {
      for (final line in [
        'clash api: secret=$secret',
        'auth token=$secret;',
        'Authorization: Bearer $secret',
        'passwd=$secret&x=1',
      ]) {
        expect(SensitiveAddresses.mask(line), isNot(contains(secret)),
            reason: line);
      }
    });

    test('обычные строки не портятся', () {
      const plain = 'router: match[3] outbound=direct, network=tcp, port=443';
      expect(SensitiveAddresses.mask(plain), plain);
    });
  });
}
