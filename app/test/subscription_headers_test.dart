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

  group('Переезд подписки запоминается ТОЛЬКО постоянный', () {
    // Хелпер: панель отдаёт [code] с Location на [to] для стартового адреса,
    // а по [to] — обычный 200 со списком серверов.
    MockClient redirectOnce(String from, String to, int code) =>
        MockClient((req) async {
          if (req.url.toString() == from) {
            return http.Response('', code, headers: {'location': to});
          }
          return http.Response(link, 200);
        });

    test('301 (постоянный) — новый адрес запоминается', () async {
      final svc = SubscriptionService(client: redirectOnce(
          'https://old.example.org/sub', 'https://new.example.org/sub', 301));
      final r = await svc.fetch('https://old.example.org/sub');
      expect(r.movedTo, 'https://new.example.org/sub');
    });

    test('308 (постоянный) — новый адрес запоминается', () async {
      final svc = SubscriptionService(client: redirectOnce(
          'https://old.example.org/sub', 'https://new.example.org/sub', 308));
      final r = await svc.fetch('https://old.example.org/sub');
      expect(r.movedTo, 'https://new.example.org/sub');
    });

    // ⚠️ ГЛАВНЫЙ РЕГРЕСС. Инфраструктура отдаёт 302: короткая ссылка
    // `s.silentgate.lol/<id>` (новый канон) при попадании на мейн уводит на
    // легаси `sub.silentgate.lol/sub/<id>`. Запомнить конечный адрес — значит
    // молча перенести пользователя на старый домен и сменить id профиля, из-за
    // чего автообновление теряет подписку. За 302 следуем, адрес НЕ меняем.
    test('302 (временный) — movedTo пуст, следуем ради ответа', () async {
      final svc = SubscriptionService(client: redirectOnce(
          'https://s.example.org/id', 'https://sub.example.org/sub/id', 302));
      final r = await svc.fetch('https://s.example.org/id');
      expect(r.movedTo, isNull, reason: '302 — временный, адрес не запоминаем');
      expect(r.servers, isNotEmpty, reason: 'но по редиректу подписку получили');
    });

    test('307 (временный) — movedTo пуст', () async {
      final svc = SubscriptionService(client: redirectOnce(
          'https://s.example.org/id', 'https://sub.example.org/sub/id', 307));
      final r = await svc.fetch('https://s.example.org/id');
      expect(r.movedTo, isNull);
    });

    test('301, затем 302 — запоминаем адрес до временного хопа', () async {
      final svc = SubscriptionService(client: MockClient((req) async {
        switch (req.url.toString()) {
          case 'https://a.example.org/sub':
            return http.Response('', 301,
                headers: {'location': 'https://b.example.org/sub'});
          case 'https://b.example.org/sub':
            return http.Response('', 302,
                headers: {'location': 'https://c.example.org/sub'});
          default:
            return http.Response(link, 200);
        }
      }));
      final r = await svc.fetch('https://a.example.org/sub');
      expect(r.movedTo, 'https://b.example.org/sub',
          reason: 'постоянный переезд A→B закрепляем, временный B→C — нет');
    });

    test('без переезда movedTo пуст', () async {
      final svc = SubscriptionService(
        client: MockClient((req) async => http.Response(link, 200)),
      );
      final r = await svc.fetch('https://example.org/sub');
      expect(r.movedTo, isNull);
    });

    test('петля редиректов обрывается ошибкой, а не висит', () async {
      final svc = SubscriptionService(
        client: MockClient((req) async => http.Response('', 302,
            headers: {'location': 'https://loop.example.org/sub'})),
      );
      await expectLater(
        svc.fetch('https://loop.example.org/sub'),
        throwsA(predicate((e) => '$e'.contains('редирект'))),
      );
    });
  });

  group('User-Agent переживает редирект', () {
    // ⚠️ FlClash на этом горел (v0.8.79 «Fix get profile redirect client ua
    // issues»): при 301/302 UA терялся, и панель отдавала НЕ ТОТ формат —
    // base64 вместо XRAY_JSON. Снаружи это «конфиги вдруг стали хуже».
    // Теперь UA ставится на КАЖДЫЙ хоп явно — проверяем это на обоих запросах.
    test('UA наш и на первом, и на редиректном запросе', () async {
      final seen = <String>[];
      final svc = SubscriptionService(
        client: MockClient((req) async {
          seen.add(req.headers['User-Agent'] ?? req.headers['user-agent'] ?? '');
          if (req.url.toString() == 'https://start.example.org/sub') {
            return http.Response('', 302,
                headers: {'location': 'https://end.example.org/sub'});
          }
          return http.Response(link, 200);
        }),
      );
      await svc.fetch('https://start.example.org/sub');
      expect(seen.length, 2, reason: 'два хопа: старт + редирект');
      expect(seen.every((ua) => ua.contains('SilentGate')), isTrue,
          reason: 'панель выбирает формат по UA — потеряв его, получим base64');
    });
  });
}
