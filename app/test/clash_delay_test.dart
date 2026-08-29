import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/clash_delay.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/settings/app_settings.dart' show PingMethod;

/// Разбор ответа Clash API (`GET /proxies/{tag}/delay`) — источника ЧЕСТНОГО
/// замера текущего сервера при поднятом туннеле.
///
/// ⚠️ Три исхода различаются намеренно и путать их нельзя:
///  * успех — число миллисекунд;
///  * провал теста — ядро пробовало и НЕ смогло (канал не работает);
///  * недоступность API — ядро вообще не спрошено, вердикта серверу НЕТ.
/// Слить последние два в один «failed» значило бы красить рабочий сервер в
/// мёртвый из-за нашей же ошибки (не тот секрет, не тот порт).
///
/// Сети здесь нет: транспорт подменяется целиком.
void main() {
  group('разбор ответа', () {
    test('200 с числом — успех', () {
      final r = ClashDelayProbe.parse(200, '{"delay": 142}');
      expect(r.ok, isTrue);
      expect(r.outcome, PingOutcome.ok);
      expect(r.delayMs, 142);
      expect(r.unavailable, isFalse);
    });

    test('200 с дробным числом — округляется, а не отбрасывается', () {
      final r = ClashDelayProbe.parse(200, '{"delay": 88.4}');
      expect(r.ok, isTrue);
      expect(r.delayMs, 88);
    });

    test('504 — таймаут теста: канал не отвечает', () {
      final r = ClashDelayProbe.parse(504, '{"message": "Timeout"}');
      expect(r.outcome, PingOutcome.timeout);
      expect(r.unavailable, isFalse, reason: 'ядро ответило — вердикт настоящий');
    });

    test('5xx — ядро пробовало и не смогло: провал канала', () {
      final r = ClashDelayProbe.parse(503, '{"message": "delay test failed"}');
      expect(r.outcome, PingOutcome.failed);
      expect(r.unavailable, isFalse);
    });

    test('4xx про наш запрос — ядро не спрошено, вердикта нет', () {
      // Плохие параметры, чужой секрет, нет такого тега — во всех случаях
      // ошибка НАША, и сервер по ней судить нельзя.
      for (final code in [400, 401, 403, 404]) {
        final r = ClashDelayProbe.parse(code, '{"message": "oops"}');
        expect(r.unavailable, isTrue, reason: 'код $code');
        expect(r.ok, isFalse);
      }
    });

    test('200 с мусором внутри — «не поняли ядро», а не «сервер плохой»', () {
      for (final body in [
        'garbage', // не JSON
        '[]', // не объект
        '{}', // нет delay
        '{"delay": "fast"}', // не число
        '{"delay": 0}', // нулевая задержка не бывает
        '{"delay": -5}',
      ]) {
        final r = ClashDelayProbe.parse(200, body);
        expect(r.unavailable, isTrue, reason: 'тело: $body');
        expect(r.ok, isFalse, reason: 'тело: $body');
      }
    });
  });

  group('запрос', () {
    test('уходит на нужный тег с обоими параметрами и секретом', () async {
      Uri? seen;
      String? seenBearer;
      final probe = ClashDelayProbe(
        port: 9999,
        secret: 'sekret',
        tag: 'proxy',
        httpGet: (url, {required String bearer, required Duration timeout}) //
            async {
          seen = url;
          seenBearer = bearer;
          return const ClashHttpResponse(200, '{"delay": 55}');
        },
      );
      final r = await probe.measure(
          testUrl: 'http://cp.example/generate_204',
          timeout: const Duration(milliseconds: 3000));
      expect(r.delayMs, 55);
      expect(seen!.path, '/proxies/proxy/delay');
      expect(seen!.host, '127.0.0.1');
      expect(seen!.port, 9999);
      // Оба параметра ОБЯЗАТЕЛЬНЫ: без timeout Clash API отвечает 400, а
      // мерить надо тот же адрес, которым ходит проверка канала.
      expect(seen!.queryParameters['url'], 'http://cp.example/generate_204');
      expect(seen!.queryParameters['timeout'], '3000');
      expect(seenBearer, 'sekret');
    });

    test('сбой транспорта — недоступность, а не исключение и не провал',
        () async {
      final probe = ClashDelayProbe(
        port: 1,
        httpGet: (_, {required String bearer, required Duration timeout}) =>
            throw const SocketException('refused'),
      );
      final r = await probe.measure(
          testUrl: 'http://cp.example/x', timeout: const Duration(seconds: 1));
      expect(r.unavailable, isTrue);
    });

    test('молчание самого API — тоже недоступность', () async {
      final probe = ClashDelayProbe(
        port: 1,
        httpGet: (_, {required String bearer, required Duration timeout}) =>
            throw TimeoutException('api'),
      );
      final r = await probe.measure(
          testUrl: 'http://cp.example/x', timeout: const Duration(seconds: 1));
      expect(r.unavailable, isTrue);
    });
  });

  group('PingResult с новыми полями', () {
    test('coreUrl и пометка «сквозь туннель» переживают диск', () {
      final src = PingResult(
        outcome: PingOutcome.ok,
        latencyMs: 3,
        verification: PingVerification.notRun,
        latencyMethod: PingMethod.coreUrl,
        latencyThroughTunnel: true,
        measuredAt: DateTime(2026, 8, 29, 12),
      );
      final back = PingResult.fromJson(src.toJson());
      expect(back.latencyMethod, PingMethod.coreUrl);
      expect(back.latencyThroughTunnel, isTrue);
      // Пометка обязана ехать и через withVerification: финализация прогона
      // (pending → notRun) не должна «отмывать» ложную цифру.
      expect(back.withVerification(PingVerification.notRun).latencyThroughTunnel,
          isTrue);
    });

    test('старый файл без пометки читается как честный замер', () {
      final j = PingResult(outcome: PingOutcome.ok, latencyMs: 42).toJson()
        ..remove('latencyThroughTunnel');
      expect(PingResult.fromJson(j).latencyThroughTunnel, isFalse);
    });
  });
}
