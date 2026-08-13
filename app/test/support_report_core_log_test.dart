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
}
