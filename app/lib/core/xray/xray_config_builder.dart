import 'dart:convert';

import '../models/vpn_server.dart';
import 'outbound_variant.dart';
import 'xray_outbound_factory.dart';
import 'private_networks.dart';

/// Порты локальных inbound'ов Xray. Системный прокси Windows указывает на [http].
class XrayPorts {
  final int socks;
  final int http;
  final int api;
  const XrayPorts({this.socks = 10808, this.http = 10809, this.api = 10085});
}

/// Тег служебного api-инбаунда Xray в НАШИХ конфигах.
///
/// ⚠️ ОДНА КОНСТАНТА НА СОЗДАНИЕ И НА УДАЛЕНИЕ — но только там, где конфиг
/// собираем мы сами ([XrayConfigBuilder], `ensureXrayStats`). Разойдись два
/// написания — вырезание молча перестало бы находить инбаунд, а порт остался
/// бы открытым при зелёных тестах.
///
/// ⚠️ ЧУЖОЙ КОНФИГ ЭТОЙ КОНСТАНТЕ НЕ ПОДЧИНЯЕТСЯ. Панель отдаёт Xray-JSON
/// целиком и вправе назвать api-хендлер как угодно (`api: {tag: "metrics"}`).
/// Поэтому [stripXrayApi] читает тег ИЗ КОНФИГА, а сюда откатывается только
/// когда в конфиге тега нет.
const kXrayApiTag = 'api';

/// Строит JSON-конфиг основного туннеля Xray для одного выбранного сервера.
///
/// inbounds: socks + http (для системного прокси) + dokodemo "api" (StatsService);
/// outbounds: proxy (через [XrayOutboundFactory], с учётом [OutboundVariant]) + direct + block;
/// routing/stats/policy/api: счётчики трафика включены.
class XrayConfigBuilder {
  final XrayPorts ports;

  /// Логин и пароль локальных inbound'ов.
  ///
  /// ⚠️ ЗАЧЕМ ОНИ ЗДЕСЬ. Раньше построитель умел только `auth: noauth`, и
  /// по этому пути идут ВСЕ обычные серверы подписки и режим «Авто (лучший
  /// сервер)» — то есть подавляющее большинство подключений. При включённом по
  /// умолчанию пароле порты 10808/10809 всё равно оставались открыты любому
  /// процессу машины: это и есть та самая дыра, от которой настройка защищает
  /// по её же тексту. Пароль при этом ВЫДАВАЛСЯ и уходил туннелю — sing-box
  /// предлагал Xray метод username/password, а тот его не знал.
  ///
  /// Пусто — inbound без пароля (режим системного прокси: WinINET креденшелов
  /// не передаёт, и пароль там сломал бы весь интернет).
  final String user;
  final String password;

  const XrayConfigBuilder({
    this.ports = const XrayPorts(),
    this.user = '',
    this.password = '',
  });

  /// Копия построителя с другими кредами (порты те же).
  XrayConfigBuilder withAuth(String user, String password) =>
      XrayConfigBuilder(ports: ports, user: user, password: password);

  bool get _hasAuth => user.isNotEmpty && password.isNotEmpty;

  Map<String, dynamic> get _socksSettings => {
        'udp': true,
        if (_hasAuth) ...{
          'auth': 'password',
          'accounts': [
            {'user': user, 'pass': password}
          ],
        } else
          'auth': 'noauth',
      };

  Map<String, dynamic> get _httpSettings => {
        if (_hasAuth)
          'accounts': [
            {'user': user, 'pass': password}
          ],
      };

  /// Служебный inbound `StatsService`: через него `xray api statsquery`
  /// читает счётчики трафика.
  ///
  /// ⚠️ ОДНО ОПРЕДЕЛЕНИЕ НА ОБА ПОСТРОИТЕЛЯ. Раньше их было два (одиночный
  /// сервер и автовыбор), одинаковых с точностью до буквы, — и разошлись бы
  /// они молча: конфиг остаётся валидным, ядро стартует, а расхождение видно
  /// только тому, кто сравнит два места руками.
  ///
  /// ⚠️ АУТЕНТИФИКАЦИИ У НЕГО НЕТ И БЫТЬ НЕ МОЖЕТ: Xray для `api` её не
  /// предусматривает. Значит открытый порт — это просто открытый порт: на
  /// Windows его видит любой процесс машины, на Android (loopback между
  /// приложениями не изолирован) — любое установленное приложение, а
  /// детекторы VPN ищут gRPC API Xray отдельной проверкой. Там, где счётчики
  /// отсюда не читают, инбаунд до ядра доезжать не должен — [stripXrayApi].
  Map<String, dynamic> get _apiInbound => {
        'tag': kXrayApiTag,
        'listen': '127.0.0.1',
        'port': ports.api,
        'protocol': 'dokodemo-door',
        'settings': {'address': '127.0.0.1'},
      };

  /// Правило, уводящее трафик api-инбаунда в сам api-хендлер.
  ///
  /// Свежая карта на каждый вызов, а не общая константа: конфиг после
  /// построителя ещё правят на месте (`normalizeOverridePorts` дописывает теги
  /// в `inboundTag`), и общий экземпляр раздал бы эту правку всем сразу.
  Map<String, dynamic> get _apiRule => {
        'type': 'field',
        'inboundTag': [kXrayApiTag],
        'outboundTag': kXrayApiTag,
      };

  String buildJson(VpnServer server, {OutboundVariant variant = OutboundVariant.none}) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(server, variant: variant));

  Map<String, dynamic> buildMap(
    VpnServer server, {
    OutboundVariant variant = OutboundVariant.none,
  }) {
    return {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'tag': 'socks',
          'listen': '127.0.0.1',
          'port': ports.socks,
          'protocol': 'socks',
          'settings': _socksSettings,
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
        {
          'tag': 'http',
          'listen': '127.0.0.1',
          'port': ports.http,
          'protocol': 'http',
          'settings': _httpSettings,
        },
        _apiInbound,
      ],
      'outbounds': [
        ...XrayOutboundFactory.build(server, tag: 'proxy', variant: variant),
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          _apiRule,
          {
            'type': 'field',
            'ip': kPrivateNetworks,
            'outboundTag': 'direct',
          },
        ],
      },
      'api': {
        'tag': 'api',
        'services': ['StatsService'],
      },
      'stats': {},
      'policy': {
        'levels': {
          '0': {'statsUserUplink': true, 'statsUserDownlink': true},
        },
        'system': {
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
    };
  }

  String buildBalancerJson(List<VpnServer> servers) =>
      const JsonEncoder.withIndent('  ').convert(buildBalancerMap(servers));

  /// Автовыбор лучшего сервера: все серверы как outbounds `proxy-i`, `burstObservatory`
  /// периодически пингует их, балансировщик (leastPing) направляет трафик на самый быстрый
  /// и переключается на лету. Ближе всего к «Burst observatory» в Happ.
  Map<String, dynamic> buildBalancerMap(List<VpnServer> servers) {
    final outbounds = <Map<String, dynamic>>[];
    for (var i = 0; i < servers.length; i++) {
      outbounds.addAll(XrayOutboundFactory.build(servers[i], tag: 'proxy-$i'));
    }
    outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
    outbounds.add({'protocol': 'blackhole', 'tag': 'block'});

    return {
      'log': {'loglevel': 'warning'},
      // DNS как у Happ — чтобы пробы/трафик резолвились стабильно.
      'dns': {
        'queryStrategy': 'UseIP',
        'servers': ['1.1.1.1', '8.8.8.8'],
      },
      'inbounds': [
        {
          'tag': 'socks',
          'listen': '127.0.0.1',
          'port': ports.socks,
          'protocol': 'socks',
          'settings': _socksSettings,
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
        {
          'tag': 'http',
          'listen': '127.0.0.1',
          'port': ports.http,
          'protocol': 'http',
          'settings': _httpSettings,
        },
        _apiInbound,
      ],
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'balancers': [
          {
            'tag': 'balancer',
            // Префикс 'proxy' матчит proxy-0, proxy-1, … (как в Happ subjectSelector ["proxy"]).
            'selector': ['proxy'],
            // На холодном старте стратегия возвращает "" → без fallbackTag Xray молча берёт первый outbound.
            'fallbackTag': 'proxy-0',
            'strategy': {'type': 'leastPing'},
          },
        ],
        'rules': [
          _apiRule,
          {
            'type': 'field',
            'ip': kPrivateNetworks,
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'inboundTag': ['socks', 'http'],
            'balancerTag': 'balancer',
          },
        ],
      },
      // Параметры observatory как у рабочего Happ: youtube/generate_204, interval 120s, sampling 1.
      'burstObservatory': {
        'subjectSelector': ['proxy'],
        'pingConfig': {
          'destination': 'https://www.youtube.com/generate_204',
          'interval': '120s',
          'sampling': 1,
          'timeout': '10s',
        },
      },
      'api': {
        'tag': 'api',
        'services': ['StatsService'],
      },
      'stats': {},
      'policy': {
        'levels': {
          '0': {'statsUserUplink': true, 'statsUserDownlink': true},
        },
        'system': {
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
    };
  }
}

/// Убрать из ГОТОВОГО конфига api-инбаунд Xray и всё, что на него ссылается.
///
/// Точная противоположность `ensureXrayStats` (`core/xray/override_normalizer.dart`)
/// и применяется там, где счётчики Xray не читает никто: сегодня это Android
/// (`VpnEngineBase.readsXrayStats == false` — цифры берутся из Clash API
/// sing-box, закрытого паролем). Порт api не имеет и не может иметь пароля, а
/// loopback на Android между приложениями не изолирован: открытым он даёт
/// детектору VPN попадание, а нам — ничего.
///
/// ⚠️ ЧИСТИТЬ НАДО ГОТОВЫЙ КОНФИГ, А НЕ ОТДЕЛЬНЫЙ ПОСТРОИТЕЛЬ. Инбаунд создают
/// РАЗНЫЕ места: [XrayConfigBuilder.buildMap] (одиночный сервер),
/// [XrayConfigBuilder.buildBalancerMap] («Авто (лучший сервер)»),
/// `ensureXrayStats` (панельный профиль), да и сам панельный конфиг может
/// прийти со своим. Гейт на одном из них уже был — и порт всё равно
/// поднимался, потому что в режиме автовыбора конфиг собирает ДРУГОЙ метод.
///
/// ⚠️ ТЕГ ХЕНДЛЕРА БЕРЁТСЯ ИЗ КОНФИГА, А НЕ ИЗ [kXrayApiTag]. Константа
/// описывает только наши построители; панель присылает конфиг целиком и вправе
/// назвать хендлер как угодно (`api: {tag: "metrics"}` + инбаунд `metrics-in`).
/// Вырезание по литеральному `api` на таком конфиге сносило ОДНУ секцию `api`
/// (она лежит под КЛЮЧОМ, тег ни при чём) и оставляло инбаунд слушать, а
/// правило — висеть. Это хуже, чем не трогать ничего: раньше трафик открытого
/// порта уходил в api-хендлер, а стал уходить в `route.final`, то есть В
/// ТУННЕЛЬ. Настоящий `xray.exe` 26.3.27 такой конфиг принимает без единого
/// замечания — висячий `outboundTag` он не проверяет (тот же урок уже записан
/// про `sing-box check`), так что поймать это может только тест.
///
/// Что делается:
///  * находится тег api-хендлера: `api.tag`, иначе [kXrayApiTag];
///  * удаляются api-инбаунды — тот, что назван тем же тегом, И те, на которые
///    ведут правила в этот `outboundTag` (их тег произволен и в общем случае
///    узнаётся ТОЛЬКО по ссылке правила);
///  * правила, которые вели в api-хендлер, удаляются целиком. ⚠️ Именно
///    удаляются: правило с опустевшим `inboundTag` не сужается до нуля, а
///    наоборот — перестаёт ограничивать хоть что-нибудь;
///  * из остальных правил вычёркиваются теги удалённых инбаундов;
///  * секция `api` убирается — вместе с ней уходит и `api.listen`, которым
///    Xray умеет поднимать порт вообще без инбаунда.
///
/// ⚠️ ПО ТЕГУ, А НЕ ПО ПОРТУ. Номер порта api задаёт панель, 10085 там не
/// обязателен, а на самом 10085 у чужого конфига может стоять рабочий вход
/// туннеля. Вырезание по номеру промахнулось бы в обе стороны.
///
/// ⚠️ ЧЕГО ЗДЕСЬ НЕ ДЕЛАЕТСЯ (чтобы не считать сделанным): `dokodemo-door`,
/// на который не ведёт НИ ОДНО правило и чей тег не совпадает с тегом
/// хендлера, остаётся в конфиге. В api-хендлер он не попадает, но порт слушает.
/// Вырезать такие вслепую — значит решать за панель, чего у неё быть не может.
///
/// `stats` и `policy` остаются: они ничего не слушают, только включают счёт
/// внутри ядра, и трогать их значило бы менять конфиг сверх необходимого.
///
/// Не разобрали JSON — возвращаем как есть: подключение важнее.
String stripXrayApi(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return rawJson;
    final cfg = Map<String, dynamic>.from(decoded);
    var changed = false;

    final apiSection = cfg['api'];
    final declaredTag =
        apiSection is Map ? '${apiSection['tag'] ?? ''}'.trim() : '';
    final apiTag = declaredTag.isEmpty ? kXrayApiTag : declaredTag;

    final routing = cfg['routing'];
    final rules = routing is Map ? routing['rules'] : null;

    // Кандидаты в api-инбаунды. Тег хендлера — потому что так называет свой
    // инбаунд каждый наш построитель; [kXrayApiTag] — на случай, когда панель
    // переименовала хендлер, а инбаунд от нашего `ensureXrayStats` остался.
    final suspects = <String>{apiTag, kXrayApiTag};
    if (rules is List) {
      for (final r in rules) {
        if (r is! Map || '${r['outboundTag']}' != apiTag) continue;
        final tags = r['inboundTag'];
        if (tags is List) suspects.addAll(tags.map((t) => '$t'));
      }
    }

    // ⚠️ ТОЛЬКО `dokodemo-door`, И ЭТО НЕ ПРИДИРКА. В то же api-правило наши
    // socks/http дописывает `normalizeOverridePorts` (оно расширяет
    // `inboundTag` каждого правила, где уже упомянут существующий инбаунд), и
    // «удалить всё, на что ведёт правило» вынесло бы единственный вход
    // туннеля. api-хендлер же обслуживается именно dokodemo-door.
    final dropped = <String>{};
    final inbounds = cfg['inbounds'];
    if (inbounds is List) {
      final kept = <dynamic>[];
      for (final i in inbounds) {
        if (i is Map &&
            suspects.contains('${i['tag']}') &&
            '${i['protocol']}' == 'dokodemo-door') {
          dropped.add('${i['tag']}');
          continue;
        }
        kept.add(i);
      }
      if (kept.length != inbounds.length) {
        cfg['inbounds'] = kept;
        changed = true;
      }
    }

    if (routing is Map && rules is List) {
      final kept = <dynamic>[];
      var rulesChanged = false;
      for (final r in rules) {
        if (r is! Map) {
          kept.add(r);
          continue;
        }
        // Правило ведёт В api-хендлер — без инбаунда оно бессмысленно, а
        // ссылка на несуществующий outbound остаётся висеть.
        if ('${r['outboundTag']}' == apiTag) {
          rulesChanged = true;
          continue;
        }
        final tags = r['inboundTag'];
        if (tags is! List || !tags.any((t) => dropped.contains('$t'))) {
          kept.add(r);
          continue;
        }
        final rest = tags.where((t) => !dropped.contains('$t')).toList();
        rulesChanged = true;
        // Опустевший список условий = «подходит всё». Такое правило
        // выбрасываем целиком, а не оставляем пустым.
        if (rest.isEmpty) continue;
        kept.add({...r.cast<String, dynamic>(), 'inboundTag': rest});
      }
      if (rulesChanged) {
        routing['rules'] = kept;
        changed = true;
      }
    }

    if (cfg.remove('api') != null) changed = true;

    return changed ? jsonEncode(cfg) : rawJson;
  } catch (_) {
    return rawJson;
  }
}
