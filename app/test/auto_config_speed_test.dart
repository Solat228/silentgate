import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';

void main() {
  // Сервер строим ПАРСЕРОМ ссылки: так же, как приложение получает их из
  // подписки, — иначе тест проверял бы конструктор, а не рабочий путь.
  VpnServer srv(String name) => ShareLinkParser.tryParse(
      'vless://00000000-0000-0000-0000-000000000000@$name.example:443'
      '?type=tcp&security=none#$name')!;

  AutoConfigResult res(String name, {double? mbps, int? share}) =>
      AutoConfigResult(
        server: srv(name),
        variant: OutboundVariant.none,
        detail: CandidateResult(
            server: srv(name), variant: OutboundVariant.none, passed: const {},
            avgLatencyMs: 50),
        mbps: mbps,
        sharePercent: share,
      );

  // Замер стоит 5 МБ трафика подписки на сервер. Потерять его при перезапуске —
  // значит заставить пользователя заплатить за него второй раз.
  group('Скорость переживает сохранение', () {
    test('mbps и доля канала возвращаются из JSON', () {
      final j = res('a', mbps: 42.5, share: 85).toJson();
      expect(j['mbps'], 42.5);
      expect(j['sharePercent'], 85);

      final back = AutoConfigResult.fromJson(j);
      expect(back, isNotNull);
      expect(back!.mbps, 42.5);
      expect(back.sharePercent, 85);
    });

    test('без замера полей в JSON нет и чтение не падает', () {
      final j = res('b').toJson();
      expect(j.containsKey('mbps'), isFalse);
      expect(AutoConfigResult.fromJson(j)?.mbps, isNull);
    });

    test('withSpeed сохраняет всё остальное', () {
      final r = res('c').withSpeed(mbps: 10, sharePercent: 20);
      expect(r.server.remark, 'c');
      expect(r.detail.avgLatencyMs, 50);
      expect(r.mbps, 10);
    });
  });

  // Владелец: «сервер отображается по несколько раз». Причина — вариации:
  // у каждого сервера перебираются обычная, fragment и отпечатки, и КАЖДАЯ
  // прошедшая попадала в результаты отдельной строкой.
  group('Один сервер — одна строка', () {
    test('ключ сервера не зависит от вариации', () {
      // Дедупликация в движке идёт по `server.key`. Если бы ключ включал
      // вариацию, она бы не сработала вовсе.
      final a = srv('x');
      final b = srv('x');
      expect(a.key, b.key);
    });

    test('разные серверы различаются ключом', () {
      expect(srv('x').key, isNot(srv('y').key));
    });
  });
}
