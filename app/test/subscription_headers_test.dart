import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silentgate/core/subscription/subscription_service.dart';

/// Заголовки ответа панели — источник поведения, а не украшение.
void main() {
  const link =
      'vless://00000000-0000-0000-0000-000000000001@203.0.113.10:443'
      '?encryption=none&type=tcp#Test';

  group('HWID-ответы панели объясняют отказ', () {
    test('исчерпанный лимит устройств называется прямо', () async {
      final svc = SubscriptionService(
        client: MockClient((_) async => http.Response('', 404, headers: {
              'x-hwid-max-devices-reached': 'true',
              'x-hwid-limit': '3',
            })),
      );
      await expectLater(
        svc.fetch('https://example.org/sub'),
        throwsA(predicate((e) => '$e'.contains('лимит устройств') && '$e'.contains('3'))),
      );
    });

    test('без заголовков остаётся обычный код ответа', () async {
      final svc = SubscriptionService(
        client: MockClient((_) async => http.Response('', 500)),
      );
      await expectLater(
        svc.fetch('https://example.org/sub'),
        throwsA(predicate((e) => '$e'.contains('500'))),
      );
    });
  });

  group('Формат берётся из content-type', () {
    test('заголовок json разбирается как XRAY_JSON даже без явных признаков',
        () async {
      // Тело — валидный XRAY_JSON из одного конфига.
      const body = '[{"outbounds":[{"protocol":"vless","tag":"proxy",'
          '"settings":{"vnext":[{"address":"203.0.113.10","port":443,'
          '"users":[{"id":"00000000-0000-0000-0000-000000000001",'
          '"encryption":"none"}]}]},'
          '"streamSettings":{"network":"tcp","security":"none"}}],'
          '"remarks":"Panel"}]';
      final svc = SubscriptionService(
        client: MockClient((_) async => http.Response(body, 200,
            headers: {'content-type': 'application/json'})),
      );
      final r = await svc.fetch('https://example.org/sub');
      expect(r.servers, isNotEmpty);
    });
  });

  group('Переезд подписки запоминается', () {
    test('конечный адрес отличается — он и возвращается', () async {
      final svc = SubscriptionService(
        client: MockClient((req) async => http.Response(link, 200,
            request: http.Request('GET', Uri.parse('https://new.example.org/sub')))),
      );
      final r = await svc.fetch('https://old.example.org/sub');
      expect(r.movedTo, 'https://new.example.org/sub');
    });

    test('без переезда movedTo пуст', () async {
      final svc = SubscriptionService(
        client: MockClient((req) async => http.Response(link, 200,
            request: http.Request('GET', Uri.parse('https://example.org/sub')))),
      );
      final r = await svc.fetch('https://example.org/sub');
      expect(r.movedTo, isNull);
    });
  });

  group('User-Agent переживает редирект', () {
    // ⚠️ FlClash на этом горел (v0.8.79 «Fix get profile redirect client ua
    // issues»): при 301/302 UA терялся, и панель отдавала НЕ ТОТ формат —
    // base64 вместо XRAY_JSON. Снаружи это «конфиги вдруг стали хуже».
    test('на конечном запросе UA всё ещё наш', () async {
      final seen = <String>[];
      final svc = SubscriptionService(
        client: MockClient((req) async {
          seen.add(req.headers['User-Agent'] ?? req.headers['user-agent'] ?? '');
          return http.Response(link, 200, request: req);
        }),
      );
      await svc.fetch('https://example.org/sub');
      expect(seen, isNotEmpty);
      expect(seen.last, contains('SilentGate'),
          reason: 'панель выбирает формат по UA — потеряв его, получим base64');
    });
  });
}
