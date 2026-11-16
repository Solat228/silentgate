import 'dart:convert';

import '../settings/split_tunnel.dart';
import '../singbox/exit_tags.dart';
import '../xray/xray_keys.dart';
import 'dpi_bypass_lists.dart';
import 'dpi_bypass_proxy.dart';

/// Встраивает маршруты встроенного Zapret / обхода DPI в конфиг прокси-ядра
/// (`Xray` или `sing-box`) для режима захвата «Системный прокси»
/// (`CaptureMode.systemProxy`).
///
/// ⚠️ ЗАЩИТА ОТ ПЕТЛИ ПРИ АВТООТКАТЕ В VPN:
/// Браузер и WinINET входят в ядро через HTTP-прокси порт (`httpPort`, обычно `10809`),
/// а запасной путь `LocalDpiBypassProxy` при блокировке по IP входит в локальный
/// SOCKS5 порт ядра (`10808`). Поэтому все инжектируемые правила DPI жёстко
/// привязываются к тегу инбаунда на [httpPort] (`inboundTag` в Xray / `inbound`
/// в sing-box): трафик отката в SOCKS5-порт проходит сразу в VPN без повторного
/// захода в Zapret.
abstract final class DpiProxyConfigInjector {
  static String inject(
    String baseJson, {
    required bool singboxCore,
    required SplitTunnelConfig effectiveSplit,
    required int httpPort,
    int? directPort,
    int? fallbackPort,
  }) {
    if (baseJson.trim().isEmpty) return baseJson;
    if ((directPort == null || directPort <= 0) &&
        (fallbackPort == null || fallbackPort <= 0)) {
      return baseJson;
    }

    final directDomains = <String>{};
    final fallbackDomains = <String>{};
    for (final s in effectiveSplit.sites) {
      if (s.action != AppAction.tunnel) continue;
      final d = s.domain.trim().toLowerCase();
      if (d.isEmpty) continue;
      if (s.serverKey == kDpiBypassDirectKey &&
          directPort != null &&
          directPort > 0) {
        directDomains.add(d);
      } else if (s.serverKey == kDpiBypassFallbackKey &&
          fallbackPort != null &&
          fallbackPort > 0) {
        fallbackDomains.add(d);
      }
    }
    if (directDomains.isEmpty && fallbackDomains.isEmpty) {
      return baseJson;
    }

    try {
      if (singboxCore) {
        return _injectSingbox(
          baseJson,
          httpPort: httpPort,
          directPort: directPort,
          fallbackPort: fallbackPort,
          directDomains: directDomains.toList()..sort(),
          fallbackDomains: fallbackDomains.toList()..sort(),
        );
      }
      return _injectXray(
        baseJson,
        httpPort: httpPort,
        directPort: directPort,
        fallbackPort: fallbackPort,
        directDomains: directDomains.toList()..sort(),
        fallbackDomains: fallbackDomains.toList()..sort(),
      );
    } catch (_) {
      return baseJson;
    }
  }

  static String _injectSingbox(
    String baseJson, {
    required int httpPort,
    required int? directPort,
    required int? fallbackPort,
    required List<String> directDomains,
    required List<String> fallbackDomains,
  }) {
    final decoded = jsonDecode(baseJson);
    if (decoded is! Map) return baseJson;
    final cfg = Map<String, dynamic>.from(decoded);
    final inbounds = <dynamic>[
      ...(cfg['inbounds'] is List ? cfg['inbounds'] as List : const []),
    ];
    String? httpTag;
    for (var i = 0; i < inbounds.length; i++) {
      final inb = inbounds[i];
      if (inb is! Map) continue;
      final p = inb['listen_port'];
      if (p == httpPort) {
        final copy = Map<String, dynamic>.from(inb);
        var tag = '${copy['tag'] ?? ''}'.trim();
        if (tag.isEmpty) {
          tag = 'http-in';
          copy['tag'] = tag;
          inbounds[i] = copy;
        }
        httpTag = tag;
        break;
      }
    }
    if (httpTag == null) return baseJson;

    final outbounds = <dynamic>[
      ...(cfg['outbounds'] is List ? cfg['outbounds'] as List : const []),
      ...LocalDpiBypassProxy.buildExitOutbounds(
        directPort: directDomains.isNotEmpty ? directPort : null,
        fallbackPort: fallbackDomains.isNotEmpty ? fallbackPort : null,
      ),
    ];

    final route = Map<String, dynamic>.from(
      cfg['route'] is Map ? cfg['route'] as Map : const {},
    );
    final rules = <dynamic>[
      ...(route['rules'] is List ? route['rules'] as List : const []),
    ];

    final dpiRules = <Map<String, dynamic>>[
      if (directDomains.isNotEmpty && directPort != null && directPort > 0)
        {
          'inbound': [httpTag],
          'domain_suffix': directDomains,
          'action': 'route',
          'outbound': exitTagFor(kDpiBypassDirectKey),
        },
      if (fallbackDomains.isNotEmpty &&
          fallbackPort != null &&
          fallbackPort > 0)
        {
          'inbound': [httpTag],
          'domain_suffix': fallbackDomains,
          'action': 'route',
          'outbound': exitTagFor(kDpiBypassFallbackKey),
        },
    ];

    var insertAt = 0;
    if (rules.isNotEmpty &&
        rules.first is Map &&
        (rules.first as Map)['action'] == 'sniff') {
      insertAt = 1;
    }
    rules.insertAll(insertAt, dpiRules);
    route['rules'] = rules;
    cfg['inbounds'] = inbounds;
    cfg['outbounds'] = outbounds;
    cfg['route'] = route;
    return const JsonEncoder.withIndent('  ').convert(cfg);
  }

  static String _injectXray(
    String baseJson, {
    required int httpPort,
    required int? directPort,
    required int? fallbackPort,
    required List<String> directDomains,
    required List<String> fallbackDomains,
  }) {
    final decoded = jsonDecode(canonicalXrayJson(baseJson));
    if (decoded is! Map) return baseJson;
    final cfg = Map<String, dynamic>.from(decoded);
    stripMasterKeyLog(cfg);

    final inbounds = <dynamic>[
      ...(cfg['inbounds'] is List ? cfg['inbounds'] as List : const []),
    ];
    String? httpTag;
    for (var i = 0; i < inbounds.length; i++) {
      final inb = inbounds[i];
      if (inb is! Map) continue;
      final p = inb['port'];
      if (p == httpPort) {
        final copy = Map<String, dynamic>.from(inb);
        var tag = '${copy['tag'] ?? ''}'.trim();
        if (tag.isEmpty) {
          tag = 'sg-http-in';
          copy['tag'] = tag;
        }
        // Гарантируем sniffing на HTTP-инбаунде, чтобы домены в HTTP/TLS всегда читались
        copy['sniffing'] ??= {
          'enabled': true,
          'destOverride': ['http', 'tls'],
        };
        inbounds[i] = copy;
        httpTag = tag;
        break;
      }
    }
    if (httpTag == null) return baseJson;

    final outbounds = <dynamic>[
      ...(cfg['outbounds'] is List ? cfg['outbounds'] as List : const []),
    ];
    final directTag = exitTagFor(kDpiBypassDirectKey);
    final fallbackTag = exitTagFor(kDpiBypassFallbackKey);

    if (directDomains.isNotEmpty && directPort != null && directPort > 0) {
      outbounds.add({
        'tag': directTag,
        'protocol': 'socks',
        'settings': {
          'servers': [
            {'address': '127.0.0.1', 'port': directPort},
          ],
        },
      });
    }
    if (fallbackDomains.isNotEmpty &&
        fallbackPort != null &&
        fallbackPort > 0) {
      outbounds.add({
        'tag': fallbackTag,
        'protocol': 'socks',
        'settings': {
          'servers': [
            {'address': '127.0.0.1', 'port': fallbackPort},
          ],
        },
      });
    }

    final routing = Map<String, dynamic>.from(
      cfg['routing'] is Map ? cfg['routing'] as Map : const {},
    );
    routing['domainStrategy'] ??= 'IPIfNonMatch';
    final rules = <dynamic>[
      ...(routing['rules'] is List ? routing['rules'] as List : const []),
    ];

    final dpiRules = <Map<String, dynamic>>[
      if (directDomains.isNotEmpty && directPort != null && directPort > 0)
        {
          'type': 'field',
          'inboundTag': [httpTag],
          'domain': [for (final d in directDomains) 'domain:$d'],
          'outboundTag': directTag,
        },
      if (fallbackDomains.isNotEmpty &&
          fallbackPort != null &&
          fallbackPort > 0)
        {
          'type': 'field',
          'inboundTag': [httpTag],
          'domain': [for (final d in fallbackDomains) 'domain:$d'],
          'outboundTag': fallbackTag,
        },
    ];

    var insertIdx = 0;
    while (insertIdx < rules.length) {
      final r = rules[insertIdx];
      if (r is Map && '${r['outboundTag'] ?? ''}' == 'api') {
        insertIdx++;
      } else {
        break;
      }
    }
    rules.insertAll(insertIdx, dpiRules);
    routing['rules'] = rules;
    cfg['inbounds'] = inbounds;
    cfg['outbounds'] = outbounds;
    cfg['routing'] = routing;
    return const JsonEncoder.withIndent('  ').convert(cfg);
  }
}
