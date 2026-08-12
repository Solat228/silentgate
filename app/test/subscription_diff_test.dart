import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/subscription_sync.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';

/// Баннер обновления подписки обязан говорить правду.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА (13.08.2026): у сервера «Москва 1. GRPC» КАЖДОЕ обновление
/// подписки писалось «+1 · −1», хотя серверы не менялись. Причина: состав
/// считался по [VpnServer.key], то есть по полной share-ссылке. Ссылка законно
/// меняется, когда панель поправила серверу отпечаток, sni или путь, — для
/// баннера это ложь, сервер никуда не девался.
///
/// Первая линия защиты — канонический ключ (см. `canonical_key_test.dart`).
/// Здесь — вторая: диф сравнивает состав по [VpnServer.identityKey], поэтому
/// баннер останется честным даже при будущем расхождении форматов.
void main() {
  const uuid = '00000000-0000-0000-0000-000000000000';

  String link({
    String host = 'ru1.example.com',
    int port = 443,
    String fp = 'chrome',
    String sni = 'a.example.org',
    String name = 'Москва 1. GRPC',
  }) =>
      'vless://$uuid@$host:$port?type=grpc&security=reality&encryption=none'
      '&sni=$sni&fp=$fp&pbk=KEY&sid=ab&path=my-service'
      '#${Uri.encodeComponent(name)}';

  VpnServer parse(String l) {
    final s = ShareLinkParser.tryParse(l);
    expect(s, isNotNull, reason: 'ссылка теста должна разбираться: $l');
    return s!;
  }

  SubscriptionSyncResult diff(List<VpnServer> before, List<VpnServer> after) =>
      SubscriptionSyncResult.diff(
        before: before,
        after: after,
        withPanelConfig: 0,
        panelProfiles: 0,
        at: DateTime(2026, 8, 13),
      );

  group('Правка сервера — это не «+1 · −1»', () {
    test('сменился отпечаток: ни добавления, ни удаления', () {
      final was = parse(link(fp: 'chrome'));
      final now = parse(link(fp: 'firefox'));

      // Предпосылка теста: ключ действительно другой — иначе проверка ниже
      // была бы зелёной сама по себе и ничего не ловила.
      expect(was.key, isNot(now.key),
          reason: 'смена fp обязана менять ссылку, иначе тест бессмысленный');

      final r = diff([was], [now]);
      expect(r.added, isEmpty);
      expect(r.removed, isEmpty);
      expect(r.hasChanges, isFalse);
      expect(r.summary, contains('без изменений'));
    });

    test('сменился sni — тоже правка, а не пересоздание сервера', () {
      final r = diff([parse(link())], [parse(link(sni: 'b.example.org'))]);
      expect(r.added, isEmpty);
      expect(r.removed, isEmpty);
    });

    test('⚠️ ПО-СТАРОМУ (по ключу) вышло бы ровно +1 · −1 — это и был дефект', () {
      final was = parse(link(fp: 'chrome'));
      final now = parse(link(fp: 'firefox'));
      // Прежний счёт: карты по s.key. Воспроизводим его здесь, чтобы дефект был
      // виден в самом тесте, а не только в описании коммита.
      final byKeyBefore = {was.key};
      final byKeyAfter = {now.key};
      expect(byKeyAfter.difference(byKeyBefore), hasLength(1));
      expect(byKeyBefore.difference(byKeyAfter), hasLength(1));
    });
  });

  group('Настоящие изменения состава считаются как прежде', () {
    test('новый сервер — добавление', () {
      final old = parse(link());
      final fresh = parse(link(host: 'de1.example.com', name: 'Берлин 1'));
      final r = diff([old], [old, fresh]);
      expect(r.added, ['Берлин 1']);
      expect(r.removed, isEmpty);
      expect(r.total, 2);
      expect(r.hasChanges, isTrue);
    });

    test('исчезнувший сервер — удаление', () {
      final stay = parse(link());
      final gone = parse(link(host: 'de1.example.com', name: 'Берлин 1'));
      final r = diff([stay, gone], [stay]);
      expect(r.added, isEmpty);
      expect(r.removed, ['Берлин 1']);
    });

    test('другой порт того же хоста — другой сервер', () {
      final r = diff([parse(link(port: 443))], [parse(link(port: 8443))]);
      expect(r.added, hasLength(1));
      expect(r.removed, hasLength(1));
    });

    test('переименование — это добавление + удаление, и так и надо', () {
      // Человек узнаёт узел ПО ИМЕНИ: «Москва 1» вместо «Москва 2» для него
      // другой сервер, и умолчать об этом было бы такой же ложью, как «+1 · −1».
      final was = parse(link(name: 'Москва 1. GRPC'));
      final now = parse(link(name: 'Москва 2. GRPC'));
      final r = diff([was], [now]);
      expect(r.added, ['Москва 2. GRPC']);
      expect(r.removed, ['Москва 1. GRPC']);
    });

    test('пустая подписка: все серверы удалены', () {
      final r = diff([parse(link())], []);
      expect(r.removed, hasLength(1));
      expect(r.total, 0);
    });
  });

  group('Диагностика: ключ сменился, сервер тот же', () {
    test('названы ИМЕНА изменившихся полей', () {
      final r = diff([parse(link(fp: 'chrome'))], [parse(link(fp: 'firefox'))]);
      expect(r.keyChanges, hasLength(1));
      expect(r.keyChanges.single.fields, ['fingerprint']);
      expect(r.keyChanges.single.name, 'Москва 1. GRPC');

      final report = r.keyChangeReport;
      expect(report, hasLength(1));
      expect(report.single, contains('fingerprint'));
      expect(report.single, contains('Москва 1. GRPC'));
    });

    test('⚠️ ЗНАЧЕНИЯ НЕ ПИШУТСЯ: в ссылке лежат учётные данные', () {
      // uuid VLESS (у trojan/ss — пароль) уходит в отчёт поддержки вместе с
      // журналом, поэтому в диагностике допустимы только имена полей.
      final r = diff(
        [parse(link(fp: 'chrome'))],
        [parse(link(fp: 'firefox').replaceFirst(uuid, '11111111-1111-1111-1111-111111111111'))],
      );
      final all = r.keyChangeReport.join('\n');
      expect(all, isNot(contains(uuid)));
      expect(all, isNot(contains('11111111')));
      expect(all, isNot(contains('vless://')));
      expect(all, isNot(contains('chrome')));
      expect(all, isNot(contains('firefox')));
      expect(all, contains('id'), reason: 'имя поля назвать надо');
    });

    test('поля совпали, разошлась только запись ссылки', () {
      // Ровно тот случай, что съел данные владельца: gRPC приходил то с
      // `serviceName=`, то с `path=` — поля одинаковы, строка разная.
      final a = parse(link());
      final b = VpnServer(
        protocol: a.protocol,
        remark: a.remark,
        address: a.address,
        port: a.port,
        id: a.id,
        encryption: a.encryption,
        flow: a.flow,
        network: a.network,
        security: a.security,
        sni: a.sni,
        host: a.host,
        path: a.path,
        fingerprint: a.fingerprint,
        publicKey: a.publicKey,
        shortId: a.shortId,
        rawLink: '${a.rawLink}&legacy=1',
      );
      final r = diff([a], [b]);
      expect(r.added, isEmpty);
      expect(r.removed, isEmpty);
      expect(r.keyChanges.single.fields, isEmpty);
      expect(r.keyChangeReport.single, contains('только запись ссылки'));
    });

    test('одинаковые расхождения сворачиваются в одну строку журнала', () {
      // У владельца таких серверов было 190 — по строке на каждый вытеснило бы
      // из журнала всё остальное ротацией.
      final before = <VpnServer>[];
      final after = <VpnServer>[];
      for (var i = 0; i < 5; i++) {
        before.add(parse(link(host: 'ru$i.example.com', name: 'Москва $i')));
        after.add(parse(
            link(host: 'ru$i.example.com', name: 'Москва $i', fp: 'firefox')));
      }
      final r = diff(before, after);
      expect(r.keyChanges, hasLength(5));
      expect(r.keyChangeReport, hasLength(1), reason: 'одно расхождение — одна строка');
      expect(r.keyChangeReport.single, contains('5 шт.'));
      expect(r.keyChangeReport.single, contains('и ещё 2'),
          reason: 'примеров показываем три, остальные — числом');
    });

    test('состав не менялся — диагностики нет вовсе', () {
      final s = parse(link());
      final r = diff([s], [s]);
      expect(r.keyChanges, isEmpty);
      expect(r.keyChangeReport, isEmpty);
    });

    test('новый сервер в диагностику не попадает', () {
      final old = parse(link());
      final fresh = parse(link(host: 'de1.example.com', name: 'Берлин 1'));
      final r = diff([old], [old, fresh]);
      expect(r.keyChanges, isEmpty, reason: 'это добавление, а не смена ключа');
    });
  });

  group('Проводка в AppState', () {
    // Чистая функция может быть трижды правильной, а состав по-прежнему
    // считаться по ключу — как оно и было. Сверяем сам вызов: поднимать здесь
    // весь AppState (хранилище, движок, сеть) дороже, чем прочитать исходник.
    final src = File('lib/state/app_state.dart').readAsStringSync();

    test('диф строится фабрикой по тождеству', () {
      expect(src, contains('SubscriptionSyncResult.diff('));
    });

    test('старая карта «ключ → имя» не вернулась', () {
      expect(src, isNot(contains('s.key: s.displayName')));
    });

    test('диагностика уходит в журнал', () {
      expect(src, contains('keyChangeReport'));
    });
  });
}
