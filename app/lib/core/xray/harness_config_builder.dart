import 'dart:convert';

import '../models/vpn_server.dart';
import 'outbound_variant.dart';
import 'xray_outbound_factory.dart';

/// Порты проброс-харнесса (отдельный экземпляр Xray для пинга/проб).
class HarnessPorts {
  final int base;
  const HarnessPorts({this.base = 21000});
}

/// Один кандидат в харнессе: сервер + вариация настроек.
class HarnessEntry {
  final String key; // стабильный ключ (обычно rawLink сервера + метка вариации)
  final VpnServer server;
  final OutboundVariant variant;
  const HarnessEntry({
    required this.key,
    required this.server,
    this.variant = OutboundVariant.none,
  });
}

/// Строит конфиг проброс-харнесса: по одному http-inbound на кандидата,
/// маршрутизируемому на его outbound. Проба сервера i = HTTP-запрос через 127.0.0.1:(base+i).
///
/// Важно: харнесс НЕ содержит api/stats/policy и НЕ трогает системный прокси —
/// все inbound'ы слушают только 127.0.0.1. Dart HttpClient умеет ходить через http-прокси нативно.
class HarnessConfigBuilder {
  final HarnessPorts ports;
  const HarnessConfigBuilder({this.ports = const HarnessPorts()});

  int portFor(int index) => ports.base + index;

  Map<String, dynamic> buildMap(List<HarnessEntry> entries) {
    // #8.2 — сервер с полным JSON-override: поднимаем его собственный конфиг
    // (со всеми outbounds/balancers/burstObservatory), но заменяем inbounds на
    // единственный http-inbound харнесса и роутим его на цель исходного конфига.
    if (entries.length == 1) {
      // Полный конфиг: правка пользователя либо профиль-автовыбор от панели.
      final s = entries.first.server;
      final raw = (s.rawJsonOverride ?? '').isNotEmpty
          ? s.rawJsonOverride
          : s.rawPanelConfig;
      if (raw != null && raw.isNotEmpty) {
        final map = _tryOverrideMap(raw, portFor(0));
        if (map != null) return map;
      }
    }

    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final inTag = 'in-$i';
      final outTag = 'out-$i';
      inbounds.add({
        'tag': inTag,
        'listen': '127.0.0.1',
        'port': portFor(i),
        'protocol': 'http',
        'settings': {},
      });
      outbounds.addAll(
        XrayOutboundFactory.build(e.server, tag: outTag, variant: e.variant),
      );
      rules.add({
        'type': 'field',
        'inboundTag': [inTag],
        'outboundTag': outTag,
      });
    }

    outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
    outbounds.add({'protocol': 'blackhole', 'tag': 'block'});

    return {
      'log': {'loglevel': 'warning'},
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {'domainStrategy': 'AsIs', 'rules': rules},
    };
  }

  String buildJson(List<HarnessEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(entries));

  /// Строит harness-конфиг из полного пользовательского JSON. Возвращает null,
  /// если JSON нераспарсиваемый или без outbounds (тогда откат на обычный путь).
  Map<String, dynamic>? _tryOverrideMap(String raw, int port) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cfg = Map<String, dynamic>.from(decoded);
      final outbounds = cfg['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) return null;

      // Цель роутинга: balancerTag из исходных правил, иначе первый proxy-outbound.
      final routing = cfg['routing'] is Map
          ? Map<String, dynamic>.from(cfg['routing'] as Map)
          : <String, dynamic>{};
      String? balancerTag;
      final origRules = routing['rules'];
      if (origRules is List) {
        for (final r in origRules) {
          if (r is Map && r['balancerTag'] != null) {
            balancerTag = '${r['balancerTag']}';
            break;
          }
        }
      }
      String? outTag;
      if (balancerTag == null) {
        for (final o in outbounds) {
          if (o is! Map) continue;
          final proto = '${o['protocol']}';
          if (proto == 'freedom' || proto == 'blackhole' || proto == 'dns') {
            continue;
          }
          final tag = '${o['tag'] ?? ''}';
          if (tag.isNotEmpty) {
            outTag = tag;
            break;
          }
        }
        outTag ??= '${(outbounds.first as Map)['tag'] ?? ''}';
      }

      const inTag = 'in-0';
      routing['domainStrategy'] = routing['domainStrategy'] ?? 'AsIs';
      routing['rules'] = [
        {
          'type': 'field',
          'inboundTag': [inTag],
          if (balancerTag != null)
            'balancerTag': balancerTag
          else
            'outboundTag': outTag,
        },
      ];

      cfg['log'] = {'loglevel': 'warning'};
      cfg['inbounds'] = [
        {
          'tag': inTag,
          'listen': '127.0.0.1',
          'port': port,
          'protocol': 'http',
          'settings': <String, dynamic>{},
        },
      ];
      cfg['routing'] = routing;
      cfg.remove('api');
      cfg.remove('stats');
      cfg.remove('policy');
      return cfg;
    } catch (_) {
      return null;
    }
  }
}
