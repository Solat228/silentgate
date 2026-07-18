import 'dart:convert';

import '../models/vpn_server.dart';
import 'singbox_outbound_factory.dart';

/// Порты локального прокси, который поднимает sing-box вместо Xray.
///
/// Совпадают с [XrayPorts] намеренно: остальная часть приложения (системный
/// прокси, TUN-роутер, проверка занятости портов) не должна знать, какое ядро
/// сейчас работает — она видит один и тот же socks/http на 127.0.0.1.
class SingboxProxyPorts {
  final int socks;
  final int http;

  /// Clash API — источник счётчиков трафика (аналог `xray api statsquery`).
  final int api;
  const SingboxProxyPorts({this.socks = 10808, this.http = 10809, this.api = 10085});
}

/// Конфиг sing-box в роли **прокси-ядра** (не TUN): два локальных inbound'а и
/// hysteria2-outbound'ы. TUN, если он включён, поднимается ОТДЕЛЬНЫМ процессом
/// sing-box и заворачивает трафик в этот же socks — ему всё равно, кто на другом
/// конце, Xray или sing-box.
///
/// Оба inbound'а типа `mixed`: он принимает и SOCKS5, и HTTP CONNECT на одном
/// порту, так что системный прокси Windows (http) и TUN (socks) работают
/// одновременно без дублирования настроек.
class SingboxProxyConfigBuilder {
  final SingboxProxyPorts ports;

  /// Пароль Clash API. **Без него эндпоинт открыт всем**: sing-box при пустом
  /// secret пропускает любой запрос и отдаёт CORS `*`, то есть метаданные всех
  /// соединений (домены, адреса, объёмы) прочитал бы и соседний процесс, и любая
  /// открытая в браузере страница — а через `PUT /proxies` можно ещё и увести
  /// трафик на другой узел. Для VPN-клиента это утечка истории мимо самого VPN.
  /// Секрет генерируется на каждую сессию в движке и живёт только в памяти.
  final String apiSecret;

  const SingboxProxyConfigBuilder({
    this.ports = const SingboxProxyPorts(),
    this.apiSecret = '',
  });

  String buildJson(List<VpnServer> servers) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(servers));

  Map<String, dynamic> buildMap(List<VpnServer> servers) {
    if (servers.isEmpty) {
      throw ArgumentError('Нужен хотя бы один сервер');
    }

    final outbounds = <Map<String, dynamic>>[];
    final tags = <String>[];
    for (var i = 0; i < servers.length; i++) {
      // При единственном сервере он сразу и есть «proxy» — без лишней группы.
      final tag = servers.length == 1 ? 'proxy' : 'node-$i';
      outbounds.add(SingboxOutboundFactory.build(servers[i], tag: tag));
      tags.add(tag);
    }

    // Несколько серверов — автовыбор по реальной задержке (аналог balancer +
    // burstObservatory у Xray): sing-box сам меряет и переключается на лучший.
    if (servers.length > 1) {
      outbounds.add({
        'type': 'urltest',
        'tag': 'proxy',
        'outbounds': tags,
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '3m',
        'tolerance': 50,
      });
    }
    outbounds.add({'type': 'direct', 'tag': 'direct'});

    return {
      'log': {'level': 'warn', 'timestamp': true},
      'inbounds': [
        _mixed('socks-in', ports.socks),
        _mixed('http-in', ports.http),
      ],
      'outbounds': outbounds,
      'route': {
        'rules': [
          {'action': 'sniff'},
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
      },
      // Счётчики трафика: у sing-box нет `statsquery`, зато есть Clash API,
      // откуда мы читаем суммарные upload/download (см. SingboxStats).
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:${ports.api}',
          if (apiSecret.isNotEmpty) 'secret': apiSecret,
        },
      },
    };
  }

  static Map<String, dynamic> _mixed(String tag, int port) => {
        'type': 'mixed',
        'tag': tag,
        'listen': '127.0.0.1',
        'listen_port': port,
      };
}
