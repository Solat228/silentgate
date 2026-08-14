import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

/// `stripXrayApi` на ЧУЖОМ конфиге.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Соседний `android_config_test.dart` проверяет
/// вырезание на конфигах НАШИХ построителей, где api-хендлер всегда зовут
/// `api`. Панель присылает Xray-JSON целиком и вправе назвать его как угодно
/// (`api: {tag: "metrics"}` + инбаунд `metrics-in`) — и на таком конфиге
/// вырезание по литеральному тегу оставляло открытым порт, оставляло висячее
/// правило и при этом сносило секцию `api`. То есть делало ХУЖЕ, чем ничего:
/// раньше трафик с этого порта уходил в api-хендлер, а стал уходить в
/// `route.final`, то есть В ТУННЕЛЬ. Настоящий `xray.exe` 26.3.27 такой конфиг
/// принимает без замечаний («Configuration OK») — висячий `outboundTag` он не
/// проверяет, поэтому ловить это может только тест.
///
/// Побочный эффект прогона: конфиги кладутся в `build/xray-api-strip/`, откуда
/// их скармливают настоящему ядру:
/// `engine/windows/bin/xray.exe run -test -c build/xray-api-strip/<файл>.json`.
void main() {
  final outDir = Directory('build/xray-api-strip')..createSync(recursive: true);

  Map<String, dynamic> decode(String json) =>
      Map<String, dynamic>.from(jsonDecode(json) as Map);

  List<Map<String, dynamic>> inboundsOf(String json) =>
      ((decode(json)['inbounds'] ?? const []) as List)
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> rulesOf(String json) {
    final routing = decode(json)['routing'];
    if (routing is! Map) return const [];
    return ((routing['rules'] ?? const []) as List).cast<Map<String, dynamic>>();
  }

  List<String> outboundTagsOf(String json) =>
      ((decode(json)['outbounds'] ?? const []) as List)
          .cast<Map<String, dynamic>>()
          .map((o) => '${o['tag']}')
          .toList();

  /// Ни одно правило не ссылается на то, чего в конфиге нет.
  ///
  /// ⚠️ ИМЕННО ЭТОТ ИНВАРИАНТ И БЫЛ НАРУШЕН. Ядро висячий `outboundTag` не
  /// проверяет: конфиг валиден, ядро стартует, а трафик правила молча падает в
  /// `route.final` — в туннель.
  void expectNoDanglingRefs(String json) {
    final inbounds = inboundsOf(json).map((i) => '${i['tag']}').toSet();
    final outbounds = outboundTagsOf(json).toSet();
    final routing = decode(json)['routing'];
    final balancers = <String>{};
    if (routing is Map && routing['balancers'] is List) {
      for (final b in routing['balancers'] as List) {
        if (b is Map) balancers.add('${b['tag']}');
      }
    }
    for (final r in rulesOf(json)) {
      final out = r['outboundTag'];
      if (out != null) {
        expect(outbounds, contains('$out'),
            reason: 'правило ведёт в несуществующий outbound "$out"');
      }
      final bal = r['balancerTag'];
      if (bal != null) {
        expect(balancers, contains('$bal'),
            reason: 'правило ведёт в несуществующий балансировщик "$bal"');
      }
      final tags = r['inboundTag'];
      if (tags is List) {
        expect(tags, isNotEmpty,
            reason: 'пустое условие подходит ко ВСЕМУ трафику');
        for (final t in tags) {
          expect(inbounds, contains('$t'),
              reason: 'правило ссылается на удалённый инбаунд "$t"');
        }
      }
    }
  }

  /// Панельный конфиг: api-хендлер называется НЕ `api`.
  String panelConfig({
    String apiTag = 'metrics',
    String apiInboundTag = 'metrics-in',
    int apiPort = 10085,
  }) =>
      jsonEncode({
        'log': {'loglevel': 'warning'},
        'inbounds': [
          {
            'tag': 'socks-in',
            'protocol': 'socks',
            'listen': '127.0.0.1',
            'port': 10808,
            'settings': {'udp': true, 'auth': 'noauth'},
          },
          {
            'tag': apiInboundTag,
            'protocol': 'dokodemo-door',
            'listen': '127.0.0.1',
            'port': apiPort,
            'settings': {'address': '127.0.0.1'},
          },
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
        'api': {
          'tag': apiTag,
          'services': ['StatsService'],
        },
        'stats': {},
        'routing': {
          'domainStrategy': 'IPIfNonMatch',
          'rules': [
            {
              'type': 'field',
              'inboundTag': [apiInboundTag],
              'outboundTag': apiTag,
            },
            {
              'type': 'field',
              'inboundTag': ['socks-in'],
              'outboundTag': 'proxy',
            },
          ],
        },
      });

  group('stripXrayApi: тег api берётся ИЗ КОНФИГА', () {
    test('инбаунд чужого api-хендлера удаляется', () {
      final raw = panelConfig();
      expect(
          inboundsOf(raw).any((i) => i['tag'] == 'metrics-in'), isTrue,
          reason: 'предпосылка: панель прислала свой api-инбаунд');

      final out = stripXrayApi(raw);
      expect(inboundsOf(out).any((i) => i['tag'] == 'metrics-in'), isFalse,
          reason: 'порт остался бы слушать 127.0.0.1 без пароля');
      expect(inboundsOf(out).any((i) => i['protocol'] == 'dokodemo-door'),
          isFalse);
    });

    test('правило в чужой api-хендлер удаляется вместе с инбаундом', () {
      final out = stripXrayApi(panelConfig());
      expect(rulesOf(out).any((r) => r['outboundTag'] == 'metrics'), isFalse);
      expectNoDanglingRefs(out);
    });

    test('секция api убирается — и это безопасно только вместе с правилом', () {
      // Ровно эта половина работы и делалась раньше: секция удалялась (она
      // лежит под КЛЮЧОМ 'api', тег ни при чём), а правило и инбаунд
      // оставались. Трафик открытого порта после этого шёл в `route.final`.
      final out = stripXrayApi(panelConfig());
      expect(decode(out).containsKey('api'), isFalse);
      expectNoDanglingRefs(out);
    });

    test('api-секция со СВОИМ слушателем (api.listen) уходит целиком', () {
      // Xray умеет поднимать gRPC-порт прямо из секции api, вообще без
      // инбаунда. Оставить секцию значило бы оставить открытый порт.
      final raw = jsonEncode({
        'inbounds': [
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'api': {
          'tag': 'metrics',
          'listen': '127.0.0.1:10085',
          'services': ['StatsService'],
        },
      });
      expect(decode(stripXrayApi(raw)).containsKey('api'), isFalse);
    });

    test('полезная нагрузка не задета: socks-инбаунд и его правило на месте',
        () {
      final out = stripXrayApi(panelConfig());
      expect(inboundsOf(out).map((i) => i['tag']), contains('socks-in'));
      expect(rulesOf(out).any((r) => r['outboundTag'] == 'proxy'), isTrue);
      expect(outboundTagsOf(out), containsAll(['proxy', 'direct', 'block']));
      expect(decode(out)['stats'], isNotNull,
          reason: 'stats ничего не слушает — трогать его незачем');
    });
  });

  group('stripXrayApi: по ТЕГУ, а не по порту', () {
    test('api-инбаунд на нестандартном порту всё равно удаляется', () {
      // Порт api задаёт панель, и 10085 там не обязателен.
      final out = stripXrayApi(panelConfig(apiPort: 10099));
      expect(inboundsOf(out).any((i) => i['tag'] == 'metrics-in'), isFalse);
      expectNoDanglingRefs(out);
    });

    test('ЧУЖОЙ инбаунд на 10085 остаётся жив', () {
      // Обратная сторона: 10085 — просто число, и вырезание по номеру порта
      // унесло бы рабочий вход туннеля.
      final raw = jsonEncode({
        'inbounds': [
          {
            'tag': 'socks-in',
            'protocol': 'socks',
            'listen': '127.0.0.1',
            'port': 10085,
            'settings': {'udp': true, 'auth': 'noauth'},
          },
          {
            'tag': 'metrics-in',
            'protocol': 'dokodemo-door',
            'listen': '127.0.0.1',
            'port': 10099,
            'settings': {'address': '127.0.0.1'},
          },
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'api': {
          'tag': 'metrics',
          'services': ['StatsService'],
        },
        'routing': {
          'rules': [
            {
              'type': 'field',
              'inboundTag': ['metrics-in'],
              'outboundTag': 'metrics',
            },
            {
              'type': 'field',
              'inboundTag': ['socks-in'],
              'outboundTag': 'proxy',
            },
          ],
        },
      });
      final out = stripXrayApi(raw);
      final kept = inboundsOf(out);
      expect(kept.any((i) => i['tag'] == 'socks-in' && i['port'] == 10085),
          isTrue,
          reason: 'единственный вход туннеля вырезать нельзя');
      expect(kept.any((i) => i['tag'] == 'metrics-in'), isFalse);
      expectNoDanglingRefs(out);
    });
  });

  group('stripXrayApi: наш захват переживает вырезание', () {
    test('инбаунды, дописанные в api-правило normalizeOverridePorts, остаются',
        () {
      // ⚠️ ЖИВОЙ ПОРЯДОК ВЫЗОВОВ (`VpnEngineBase.configFor` → `startArgs`):
      // сначала конфиг подгоняют под наши порты, потом вырезают api.
      // `normalizeOverridePorts` дописывает свои теги в КАЖДОЕ правило, где уже
      // упомянут существующий инбаунд, — включая правило api. Поэтому «удалить
      // всё, на что ведёт api-правило» вынесло бы наш http-инбаунд, то есть
      // единственный вход системного прокси.
      final norm = normalizeOverridePorts(panelConfig(),
          socksPort: 10808, httpPort: 10809);
      final apiRule = rulesOf(norm.json)
          .firstWhere((r) => r['outboundTag'] == 'metrics');
      expect(apiRule['inboundTag'], contains('sg-http-in'),
          reason: 'предпосылка: нормализатор дописал наш тег в api-правило');

      final out = stripXrayApi(norm.json);
      final kept = inboundsOf(out);
      expect(kept.any((i) => i['tag'] == 'sg-http-in' && i['port'] == 10809),
          isTrue,
          reason: 'без http-инбаунда захват мёртв');
      expect(kept.any((i) => i['tag'] == 'metrics-in'), isFalse);
      expectNoDanglingRefs(out);

      File('${outDir.path}/panel-custom-tag-stripped.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonDecode(out)));
      File('${outDir.path}/panel-custom-tag-raw.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ')
              .convert(jsonDecode(norm.json)));
    });
  });

  group('stripXrayApi: наши собственные конфиги — как прежде', () {
    const server = VpnServer(
      protocol: 'vless',
      remark: 'fixture',
      address: 'example.com',
      port: 443,
      id: '11111111-2222-3333-4444-555555555555',
      network: 'tcp',
      security: 'none',
      rawLink: 'vless://fixture',
    );
    const builder = XrayConfigBuilder();

    test('одиночный сервер: инбаунд, правило и секция уходят', () {
      final out = stripXrayApi(builder.buildJson(server));
      expect(inboundsOf(out).any((i) => i['tag'] == kXrayApiTag), isFalse);
      expect(rulesOf(out).any((r) => r['outboundTag'] == kXrayApiTag), isFalse);
      expect(decode(out).containsKey('api'), isFalse);
      expect(inboundsOf(out).map((i) => i['tag']), containsAll(['socks', 'http']));
      expectNoDanglingRefs(out);
    });

    test('«Авто (лучший сервер)»: балансировщик цел', () {
      final out = stripXrayApi(builder.buildBalancerJson([server, server]));
      expect(inboundsOf(out).any((i) => i['tag'] == kXrayApiTag), isFalse);
      expect(rulesOf(out).any((r) => r['balancerTag'] == 'balancer'), isTrue);
      expectNoDanglingRefs(out);
      File('${outDir.path}/balancer-stripped.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonDecode(out)));
    });
  });

  group('stripXrayApi: границы', () {
    test('конфига без api не касаемся — та же строка байт в байт', () {
      final raw = jsonEncode({
        'inbounds': [
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
      });
      expect(stripXrayApi(raw), raw);
    });

    test('повторный вызов ничего не меняет', () {
      final once = stripXrayApi(panelConfig());
      expect(stripXrayApi(once), once);
    });

    test('нечитаемый JSON возвращается как есть — подключение важнее', () {
      expect(stripXrayApi('не json'), 'не json');
      expect(stripXrayApi('[1,2,3]'), '[1,2,3]');
    });

    test('api без тега: откат на константу', () {
      // Xray по умолчанию ждёт тег `api`; конфиг без него встречается.
      final raw = jsonEncode({
        'inbounds': [
          {'tag': 'api', 'protocol': 'dokodemo-door', 'port': 10085},
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
        'api': {
          'services': ['StatsService'],
        },
        'routing': {
          'rules': [
            {
              'type': 'field',
              'inboundTag': ['api'],
              'outboundTag': 'api',
            },
          ],
        },
      });
      final out = stripXrayApi(raw);
      expect(inboundsOf(out).any((i) => i['tag'] == 'api'), isFalse);
      expectNoDanglingRefs(out);
    });
  });
}
