import 'dart:convert';

/// Результат нормализации полного Xray-конфига (пользовательский override или
/// профиль от панели) под порты захвата приложения.
class OverrideNormalized {
  final String json;
  final bool hasSocks;
  final bool hasHttp;

  /// Каких inbound'ов не было и они были дописаны (для лога/диагностики).
  final List<String> addedInbounds;

  const OverrideNormalized(
    this.json, {
    required this.hasSocks,
    required this.hasHttp,
    this.addedInbounds = const [],
  });
}

const _socksTag = 'sg-socks-in';
const _httpTag = 'sg-http-in';

/// Дописывает в конфиг (профиль панели/override) сервис статистики Xray, если его
/// нет: `api`+`stats`+`policy`+dokodemo-inbound `api` на [apiPort] и правило
/// роутинга api-inbound→api. Без этого `xray api statsquery` не отдаёт счётчики —
/// у панельных профилей StatsService обычно не включён, и трафик показывался как 0.
String ensureXrayStats(String rawJson, {required int apiPort}) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return rawJson;
    final cfg = Map<String, dynamic>.from(decoded);

    final inbounds = <dynamic>[
      ...(cfg['inbounds'] is List ? cfg['inbounds'] as List : const []),
    ];
    final hasApiInbound =
        inbounds.any((i) => i is Map && '${i['tag']}' == 'api');
    if (!hasApiInbound) {
      // Порт api уже занят ЧУЖИМ inbound'ом → второй inbound на нём уронил бы старт
      // Xray целиком. Тогда статистику не добавляем (покажется 0), но туннель жив.
      final portTakenByOther = inbounds.any((i) =>
          i is Map && '${i['port']}' == '$apiPort' && '${i['tag']}' != 'api');
      if (portTakenByOther) return rawJson;
      inbounds.add({
        'tag': 'api',
        'listen': '127.0.0.1',
        'port': apiPort,
        'protocol': 'dokodemo-door',
        'settings': {'address': '127.0.0.1'},
      });
      cfg['inbounds'] = inbounds;
    }

    // api-блок мог уже быть, но без StatsService — тогда трафик всё равно 0.
    final api = <String, dynamic>{
      ...(cfg['api'] is Map ? cfg['api'] as Map : const {}),
    };
    api['tag'] ??= 'api';
    final services = <dynamic>[
      ...(api['services'] is List ? api['services'] as List : const []),
    ];
    if (!services.contains('StatsService')) services.add('StatsService');
    api['services'] = services;
    cfg['api'] = api;
    cfg['stats'] ??= <String, dynamic>{};

    final policy = <String, dynamic>{
      ...(cfg['policy'] is Map ? cfg['policy'] as Map : const {}),
    };
    policy['system'] = {
      ...(policy['system'] is Map ? policy['system'] as Map : const {}),
      'statsInboundUplink': true,
      'statsInboundDownlink': true,
      'statsOutboundUplink': true,
      'statsOutboundDownlink': true,
    };
    cfg['policy'] = policy;

    final routing = <String, dynamic>{
      ...(cfg['routing'] is Map ? cfg['routing'] as Map : const {}),
    };
    final rules = <dynamic>[
      ...(routing['rules'] is List ? routing['rules'] as List : const []),
    ];
    if (!rules.any((r) => r is Map && '${r['outboundTag']}' == 'api')) {
      rules.insert(0, {
        'type': 'field',
        'inboundTag': ['api'],
        'outboundTag': 'api',
      });
      routing['rules'] = rules;
      cfg['routing'] = routing;
    }

    return jsonEncode(cfg);
  } catch (_) {
    return rawJson;
  }
}

/// Подгоняет inbound'ы полного конфига под порты приложения.
///
/// Захват жёстко привязан к нашим портам: системный прокси → http-inbound,
/// TUN/sing-box → socks-inbound. Если в конфиге порты другие — трафик уходил бы
/// в «мёртвый» порт при внешне успешном подключении.
///
/// Профили «Авто …» от панели содержат ТОЛЬКО socks-inbound, поэтому недостающий
/// inbound **дописывается**, а не считается ошибкой. Теги существующих inbound'ов
/// не трогаем (на них может ссылаться роутинг); если правила роутинга адресуют
/// inbound'ы по тегам — новый тег добавляется в те же правила.
OverrideNormalized normalizeOverridePorts(
  String rawJson, {
  required int socksPort,
  required int httpPort,
}) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      return OverrideNormalized(rawJson, hasSocks: false, hasHttp: false);
    }
    final cfg = Map<String, dynamic>.from(decoded);

    final inbounds = <dynamic>[
      ...(cfg['inbounds'] is List ? cfg['inbounds'] as List : const []),
    ];

    final existingTags = <String>[];
    var hasSocks = false, hasHttp = false;
    for (final raw in inbounds) {
      if (raw is! Map) continue;
      final tag = '${raw['tag'] ?? ''}';
      if (tag.isNotEmpty) existingTags.add(tag);
      final proto = '${raw['protocol']}';
      if (proto == 'socks' && !hasSocks) {
        raw['port'] = socksPort;
        raw['listen'] = '127.0.0.1';
        hasSocks = true;
      } else if (proto == 'http' && !hasHttp) {
        raw['port'] = httpPort;
        raw['listen'] = '127.0.0.1';
        hasHttp = true;
      }
    }

    final added = <String>[];
    if (!hasSocks) {
      inbounds.add({
        'tag': _socksTag,
        'protocol': 'socks',
        'listen': '127.0.0.1',
        'port': socksPort,
        'settings': {'udp': true, 'auth': 'noauth'},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
        },
      });
      added.add(_socksTag);
      hasSocks = true;
    }
    if (!hasHttp) {
      inbounds.add({
        'tag': _httpTag,
        'protocol': 'http',
        'listen': '127.0.0.1',
        'port': httpPort,
        'settings': {'allowTransparent': false},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
        },
      });
      added.add(_httpTag);
      hasHttp = true;
    }
    cfg['inbounds'] = inbounds;

    // Правила, адресующие inbound'ы по тегам, должны знать и про дописанные.
    if (added.isNotEmpty) {
      final routing = cfg['routing'];
      if (routing is Map) {
        final rules = routing['rules'];
        if (rules is List) {
          for (final r in rules) {
            if (r is! Map) continue;
            final tags = r['inboundTag'];
            if (tags is! List || tags.isEmpty) continue;
            // Правило уже покрывает какой-то из «боевых» inbound'ов — расширяем.
            if (tags.any((t) => existingTags.contains('$t'))) {
              r['inboundTag'] = [...tags, ...added];
            }
          }
        }
      }
    }

    return OverrideNormalized(
      jsonEncode(cfg),
      hasSocks: hasSocks,
      hasHttp: hasHttp,
      addedInbounds: added,
    );
  } catch (_) {
    return OverrideNormalized(rawJson, hasSocks: false, hasHttp: false);
  }
}
