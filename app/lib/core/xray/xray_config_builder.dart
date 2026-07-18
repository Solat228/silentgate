import 'dart:convert';

import '../models/vpn_server.dart';
import 'outbound_variant.dart';
import 'xray_outbound_factory.dart';

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
  const XrayConfigBuilder({this.ports = const XrayPorts()});

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
          'settings': {'udp': true, 'auth': 'noauth'},
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
          'settings': {},
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
            'ip': ['geoip:private'],
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
          'settings': {'udp': true, 'auth': 'noauth'},
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
          'settings': {},
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
            'ip': ['geoip:private'],
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
