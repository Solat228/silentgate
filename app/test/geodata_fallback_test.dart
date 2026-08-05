import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/xray/geodata_fallback.dart';
import 'package:silentgate/core/xray/private_networks.dart';

/// Запасной путь для конфигов со ссылками на гео-базы, когда самих баз нет.
///
/// Живой повод: на Android гео-файлов нет, и панельный профиль с российской
/// маршрутизацией не поднимался вовсе — ядро отвергало конфиг целиком, а
/// VPN-сервис останавливался.
void main() {
  Map<String, dynamic> cfg(List<Map<String, dynamic>> rules) => {
        'outbounds': [
          {'protocol': 'freedom', 'tag': 'direct'},
          {'protocol': 'vless', 'tag': 'proxy'},
        ],
        'routing': {'rules': rules},
      };

  List<dynamic> rulesOf(String json) =>
      ((jsonDecode(json) as Map)['routing'] as Map)['rules'] as List;

  test('geoip:private заменяется точным списком приватных подсетей', () {
    final r = stripGeodata(jsonEncode(cfg([
      {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
    ])));
    final rules = rulesOf(r.json);
    expect(rules.length, 1, reason: 'замена точная — правило остаётся');
    expect((rules.first as Map)['ip'], kPrivateNetworks);
    expect(r.report.replaced, 1);
    expect(r.report.rulesRemoved, 0);
  });

  test('⚠️ правило, потерявшее ВСЕ условия, удаляется, а не «упрощается»', () {
    // {"ip":["geoip:ru"],"outboundTag":"direct"} без списка стало бы
    // безусловным «всё напрямую» — то есть тихой утечкой реального IP.
    final r = stripGeodata(jsonEncode(cfg([
      {'type': 'field', 'ip': ['geoip:ru'], 'outboundTag': 'direct'},
    ])));
    expect(rulesOf(r.json), isEmpty,
        reason: 'оставить такое правило = пустить ВЕСЬ трафик мимо VPN');
    expect(r.report.rulesRemoved, 1);
  });

  test('то же для доменного правила', () {
    final r = stripGeodata(jsonEncode(cfg([
      {'type': 'field', 'domain': ['geosite:category-ru'], 'outboundTag': 'direct'},
    ])));
    expect(rulesOf(r.json), isEmpty);
    expect(r.report.rulesRemoved, 1);
  });

  test('смешанное правило теряет только гео-часть и остаётся', () {
    final r = stripGeodata(jsonEncode(cfg([
      {
        'type': 'field',
        'ip': ['geoip:ru', '10.0.0.0/8'],
        'outboundTag': 'direct',
      },
    ])));
    final rules = rulesOf(r.json);
    expect(rules.length, 1);
    expect((rules.first as Map)['ip'], ['10.0.0.0/8']);
    expect(r.report.dropped, 1);
    expect(r.report.rulesRemoved, 0);
  });

  test('правило, у которого условий не было ИЗНАЧАЛЬНО, не трогаем', () {
    // Хвостовой catch-all панельного профиля — законная форма, а не результат
    // нашей вычистки. Удалив его, мы сломали бы профиль вернее, чем гео-ссылки.
    final r = stripGeodata(jsonEncode(cfg([
      {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'},
    ])));
    expect(rulesOf(r.json).length, 1);
    expect(r.report.changed, isFalse);
  });

  test('конфиг без гео-ссылок возвращается БАЙТ В БАЙТ', () {
    final src = jsonEncode(cfg([
      {'type': 'field', 'ip': ['1.2.3.0/24'], 'outboundTag': 'direct'},
    ]));
    final r = stripGeodata(src);
    expect(r.json, same(src), reason: 'лишняя пересборка JSON меняла бы конфиг '
        'там, где мы ничего не чиним');
    expect(r.report.changed, isFalse);
  });

  test('мусор на входе не роняет разбор', () {
    for (final bad in ['[]', '{}', 'не json', '{"routing":{}}']) {
      expect(() => stripGeodata(bad), returnsNormally, reason: bad);
    }
  });

  test('needsGeodata видит обе формы ссылок', () {
    expect(needsGeodata('{"ip":["geoip:ru"]}'), isTrue);
    expect(needsGeodata('{"domain":["geosite:vk"]}'), isTrue);
    expect(needsGeodata('{"ip":["10.0.0.0/8"]}'), isFalse);
  });

  test('набор категорий владельца обрабатывается целиком', () {
    // Ровно то, что лежит в его панельных профилях.
    final r = stripGeodata(jsonEncode(cfg([
      {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
      {'type': 'field', 'ip': ['geoip:ru'], 'outboundTag': 'direct'},
      {
        'type': 'field',
        'domain': ['geosite:category-ru', 'geosite:category-gov-ru',
            'geosite:vk', 'geosite:ok', 'geosite:yandex'],
        'outboundTag': 'direct',
      },
      {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'},
    ])));
    final rules = rulesOf(r.json);
    // Остались: приватные подсети (замена) и хвостовой catch-all.
    expect(rules.length, 2);
    expect((rules.first as Map)['ip'], kPrivateNetworks);
    expect((rules.last as Map)['balancerTag'], 'auto');
    expect(r.report.rulesRemoved, 2);
    expect(r.report.describe(), contains('geosite:vk'));
  });
}
