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
        {
          'tag': 'api',
          'listen': '127.0.0.1',
          'port': ports.api,
          'protocol': 'dokodemo-door',
          'settings': {'address': '127.0.0.1'},
        },
      ],
      'outbounds': [
        ...XrayOutboundFactory.build(server, tag: 'proxy', variant: variant),
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'type': 'field',
            'inboundTag': ['api'],
            'outboundTag': 'api',
          },
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
        {
          'tag': 'api',
          'listen': '127.0.0.1',
          'port': ports.api,
          'protocol': 'dokodemo-door',
          'settings': {'address': '127.0.0.1'},
        },
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
          {
            'type': 'field',
            'inboundTag': ['api'],
            'outboundTag': 'api',
          },
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
