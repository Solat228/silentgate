import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/windows/windows_engine.dart';

/// ВОССТАНОВЛЕНИЕ ПОД KILL SWITCH НЕ ЖДЁТ ТАЙМАУТОВ DNS.
///
/// Журнал владельца 07.10.2026: блокировка держала трафик 28 с, из них ~27 с
/// ушло на ожидание DNS — два прохода резолва адресов серверов (таймаут 5 с на
/// каждую восьмёрку имён) и перебор шести DNS адаптера по 2 с подряд. Пока
/// захват стоит, а ядра нет, DNS не отвечает в принципе: ждать его бесполезно.
void main() {
  final hosts = [for (var i = 0; i < 30; i++) 'node$i.example'];

  group('Резолв с пробой', () {
    test('⚠️ DNS молчит — имена с кэшем не спрашиваются вовсе', () async {
      final asked = <String>[];
      final sw = Stopwatch()..start();
      final got = await VpnEngineBase.resolveWithProbeForTest(
        hosts,
        hosts.take(28).toSet(),
        (host) async {
          asked.add(host);
          // Настоящий таймаут — 5 с. Здесь запрос просто не отвечает дольше
          // пробы.
          await Future<void>.delayed(const Duration(seconds: 1));
          throw TimeoutException('нет ответа');
        },
        probeTimeout: const Duration(milliseconds: 50),
      );
      sw.stop();
      expect(got.skipped, hosts.take(28).toSet(),
          reason: 'адрес из кэша — единственный источник, пока DNS молчит');
      expect(asked, ['node0.example', 'node28.example', 'node29.example'],
          reason: 'спрашиваем пробу и только имена без кэша');
      expect(got.resolved.keys, ['node28.example', 'node29.example']);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)),
          reason: 'было: четыре восьмёрки по полному таймауту');
    });

    test('DNS отвечает — резолв идёт как прежде, кэш не подменяет ответ',
        () async {
      final asked = <String>{};
      final got = await VpnEngineBase.resolveWithProbeForTest(
        hosts,
        hosts.toSet(),
        (host) async {
          asked.add(host);
          return ['203.0.113.${host.length}'];
        },
      );
      expect(got.skipped, isEmpty);
      expect(asked, hosts.toSet());
      expect(got.resolved.keys.toList(), hosts,
          reason: 'порядок — как во входном списке');
    });

    test('ошибка пробы (не таймаут) — это ответ: DNS жив', () async {
      final asked = <String>{};
      final got = await VpnEngineBase.resolveWithProbeForTest(
        hosts,
        hosts.toSet(),
        (host) async {
          asked.add(host);
          if (host == 'node0.example') {
            throw const SocketException('No such host is known');
          }
          return ['203.0.113.1'];
        },
      );
      expect(got.skipped, isEmpty,
          reason: 'исчезнувшее имя не повод считать молчащим весь резолвер');
      expect(asked, hosts.toSet());
      expect(got.resolved['node0.example'], isEmpty);
    });

    test('меньше двух имён в кэше — пробы нет, путь прежний', () async {
      final got = await VpnEngineBase.resolveWithProbeForTest(
        ['a.example', 'b.example'],
        {'a.example'},
        (host) async => throw TimeoutException('нет ответа'),
        probeTimeout: const Duration(milliseconds: 10),
      );
      expect(got.skipped, isEmpty);
      expect(got.resolved.keys, ['a.example', 'b.example']);
    });
  });

  group('DNS адаптера', () {
    late Directory tmp;
    late WindowsEngine engine;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_dns_fast_');
      AppPaths.overrideRoot(tmp);
      // recoverSystemProxy: false — иначе создание движка в тесте сняло бы
      // системный прокси у работающего приложения владельца.
      engine = WindowsEngine(recoverSystemProxy: false);
    });

    tearDown(() async {
      await engine.dispose();
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('⚠️ адреса опрашиваются разом, а не по 2 с подряд', () async {
      engine.adapterDnsForTest =
          () => ['192.0.2.1', '192.0.2.2', 'fec0:0:0:ffff::1', 'fec0:0:0:ffff::2'];
      var inFlight = 0;
      var peak = 0;
      engine.dnsReachableForTest = (ip) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight--;
        return false;
      };
      await engine.systemDnsServerForTest();
      expect(peak, 4, reason: 'последовательный опрос даёт пик 1');
    });

    test('порядок предпочтения прежний: первым берётся первый ответивший '
        'по СПИСКУ, а не по времени', () async {
      engine.adapterDnsForTest = () => ['192.0.2.1', '192.0.2.2', '192.0.2.3'];
      engine.dnsReachableForTest = (ip) async {
        // Второй отвечает быстрее первого — выбор от этого не зависит.
        await Future<void>.delayed(
            Duration(milliseconds: ip == '192.0.2.2' ? 1 : 30));
        return ip != '192.0.2.3';
      };
      expect(await engine.systemDnsServerForTest(), '192.0.2.1');
    });
  });
}
