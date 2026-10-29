import 'dart:convert';

import 'balancer_pick.dart';
import 'xray_keys.dart';

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

/// Службы Xray API, которые мы читаем сами (счётчики и выбор балансера).
const _allowedApiServices = {'StatsService', 'RoutingService'};

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
    // Свой api-inbound панели — только на петле: через него идут команды ядру.
    for (final i in inbounds) {
      if (i is Map && '${i['tag']}' == 'api') i['listen'] = '127.0.0.1';
    }
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
    // См. `normalizeOverridePorts`: `listen` у api — слушатель мимо inbound'а.
    api.remove('listen');
    // ⚠️ ТОЛЬКО НУЖНЫЕ НАМ СЛУЖБЫ. `HandlerService` из конфига панели
    // позволял бы любому процессу на петле дописать ядру свой inbound или
    // outbound, `LoggerService` — перезапустить журнал (аудит, F).
    final services = <dynamic>[
      ...(api['services'] is List ? api['services'] as List : const [])
          .where((e) => _allowedApiServices.contains('$e')),
    ];
    if (!services.contains('StatsService')) services.add('StatsService');
    // Балансировщик есть — нужен и RoutingService: без него `xray api bi`
    // не ответит, и выбранный узел «Авто» показать нечем.
    if (BalancerPick.hasBalancer(cfg) && !services.contains('RoutingService')) {
      services.add('RoutingService');
    }
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
/// [socksUser]/[socksPassword] — пароль на ЛОКАЛЬНЫЕ инбаунды Xray.
///
/// ⚠️ Только для Android. Loopback там не изолирован между приложениями, и без
/// пароля к 127.0.0.1:10808 подключается любое установленное приложение,
/// получая VPN пользователя вместе с обходом его же раздельного
/// туннелирования. На Windows пароль ставить НЕЛЬЗЯ: туда смотрит системный
/// прокси, а WinINET креденшелов не несёт — браузер получил бы 407.
OverrideNormalized normalizeOverridePorts(
  String rawJson, {
  required int socksPort,
  required int httpPort,
  String socksUser = '',
  String socksPassword = '',
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
        if (socksUser.isNotEmpty) {
          final st = (raw['settings'] as Map?) ?? <String, dynamic>{};
          st['auth'] = 'password';
          st['accounts'] = [
            {'user': socksUser, 'pass': socksPassword},
          ];
          raw['settings'] = st;
        }
        hasSocks = true;
      } else if (proto == 'http' && !hasHttp) {
        raw['port'] = httpPort;
        raw['listen'] = '127.0.0.1';
        if (socksUser.isNotEmpty) {
          final st = (raw['settings'] as Map?) ?? <String, dynamic>{};
          st['accounts'] = [
            {'user': socksUser, 'pass': socksPassword},
          ];
          raw['settings'] = st;
        }
        hasHttp = true;
      } else {
        // ⚠️ ОСТАЛЬНЫЕ INBOUND'Ы — ТОЛЬКО НА ПЕТЛЕ. Раньше их пропускали как
        // есть, и второй socks панели на `0.0.0.0` открывал VPN всей
        // локальной сети (аудит 25.10.2026, F). На Android — ещё и с тем же
        // паролем: петля там общая для всех приложений.
        raw['listen'] = '127.0.0.1';
        if (socksUser.isNotEmpty && (proto == 'socks' || proto == 'http')) {
          final st = (raw['settings'] as Map?) ?? <String, dynamic>{};
          if (proto == 'socks') st['auth'] = 'password';
          st['accounts'] = [
            {'user': socksUser, 'pass': socksPassword},
          ];
          raw['settings'] = st;
        }
      }
    }

    // ⚠️ ПУТИ ЖУРНАЛОВ ИЗ ЧУЖОГО КОНФИГА НЕ ПРИНИМАЕМ. `log.access` с путём в
    // «Автозагрузку» дал бы панели или импортированной ссылке запись файла
    // с подконтрольным содержимым (имена сайтов) — то есть запуск кода при
    // следующем входе. Без путей ядро пишет в stdout, который собираем мы.
    final log = cfg['log'];
    if (log is Map) {
      log.remove('access');
      log.remove('error');
    }

    // ⚠️ СВОИ СЛУШАТЕЛИ ЯДРА — ТОЛЬКО ЧЕРЕЗ INBOUND НА ПЕТЛЕ (ревью 29.10.2026,
    // M1/L14). Непустой `listen` у `api` открывает gRPC управления ядром
    // напрямую, мимо inbound'ов, — то есть мимо `127.0.0.1` выше; у `metrics`
    // — pprof и expvar (история назначений соединений). С `0.0.0.0` из чужого
    // конфига это видела вся сеть. Без `listen` раздел работает через inbound
    // с его тегом, а без тега у `metrics` достучаться до него нечем.
    final api = cfg['api'];
    if (api is Map) api.remove('listen');
    final metrics = cfg['metrics'];
    if (metrics is Map) {
      metrics.remove('listen');
      if ('${metrics['tag'] ?? ''}'.isEmpty) cfg.remove('metrics');
    } else if (metrics != null) {
      cfg.remove('metrics');
    }
    stripMasterKeyLog(cfg);

    final added = <String>[];
    if (!hasSocks) {
      inbounds.add({
        'tag': _socksTag,
        'protocol': 'socks',
        'listen': '127.0.0.1',
        'port': socksPort,
        'settings': socksUser.isEmpty
            ? {'udp': true, 'auth': 'noauth'}
            : {
                'udp': true,
                'auth': 'password',
                'accounts': [
                  {'user': socksUser, 'pass': socksPassword},
                ],
              },
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
        'settings': socksUser.isEmpty
            ? {'allowTransparent': false}
            : {
                'allowTransparent': false,
                'accounts': [
                  {'user': socksUser, 'pass': socksPassword},
                ],
              },
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
