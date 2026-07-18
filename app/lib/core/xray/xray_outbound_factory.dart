import 'dart:convert';

import '../models/vpn_server.dart';
import 'outbound_variant.dart';

/// Строит outbound(ы) Xray из [VpnServer]. Общая фабрика для основного конфига,
/// проброс-харнесса и вариаций автонастройки.
///
/// Возвращает список: сам proxy-outbound (с тегом [tag]) плюс вспомогательные
/// (например, freedom-outbound `frag-<tag>` при включённой фрагментации).
class XrayOutboundFactory {
  static List<Map<String, dynamic>> build(
    VpnServer server, {
    String tag = 'proxy',
    OutboundVariant variant = OutboundVariant.none,
  }) {
    // Панель (Remnawave, формат XRAY_JSON) отдаёт готовый outbound — берём его как есть.
    // Пересборка из share-ссылки теряет детали streamSettings, из-за чего автовыбор
    // (burstObservatory) пинговал нерабочие outbound'ы.
    final authoritative = _fromPanel(server, tag, variant);
    if (authoritative != null) return authoritative;

    final result = <Map<String, dynamic>>[];
    final stream = _streamSettings(server, variant);

    // Фрагментация: proxy-outbound дозванивается через freedom-outbound с fragment.
    if (variant.fragment) {
      final fragTag = 'frag-$tag';
      final sockopt = (stream['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      sockopt['dialerProxy'] = fragTag;
      stream['sockopt'] = sockopt;
      result.add({
        'tag': fragTag,
        'protocol': 'freedom',
        'settings': {
          'domainStrategy': 'AsIs',
          'fragment': variant.params.toJson(),
        },
      });
    }

    result.insert(0, _protocolOutbound(server, tag, stream));
    return result;
  }

  /// Outbound из [VpnServer.rawOutboundJson] (как прислала панель): перетегируем под
  /// нужный tag и, если запрошена вариация, накладываем fingerprint/fragment поверх.
  /// null — если авторитетного JSON нет или он не разобрался.
  static List<Map<String, dynamic>>? _fromPanel(
      VpnServer server, String tag, OutboundVariant variant) {
    final raw = server.rawOutboundJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final out = Map<String, dynamic>.from(decoded);
      out['tag'] = tag;

      final stream = out['streamSettings'] is Map
          ? Map<String, dynamic>.from(out['streamSettings'] as Map)
          : <String, dynamic>{};

      // Вариация автонастройки: подменяем отпечаток TLS/Reality.
      final fp = variant.fingerprint;
      if (fp != null) {
        for (final key in const ['realitySettings', 'tlsSettings']) {
          if (stream[key] is Map) {
            final m = Map<String, dynamic>.from(stream[key] as Map);
            m['fingerprint'] = fp;
            stream[key] = m;
          }
        }
      }

      final result = <Map<String, dynamic>>[];
      if (variant.fragment) {
        final fragTag = 'frag-$tag';
        final sockopt = stream['sockopt'] is Map
            ? Map<String, dynamic>.from(stream['sockopt'] as Map)
            : <String, dynamic>{};
        sockopt['dialerProxy'] = fragTag;
        stream['sockopt'] = sockopt;
        result.add({
          'tag': fragTag,
          'protocol': 'freedom',
          'settings': {
            'domainStrategy': 'AsIs',
            'fragment': variant.params.toJson(),
          },
        });
      }

      if (stream.isNotEmpty) out['streamSettings'] = stream;
      result.insert(0, out);
      return result;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _protocolOutbound(
      VpnServer s, String tag, Map<String, dynamic> stream) {
    switch (s.protocol) {
      case 'vless':
        return {
          'protocol': 'vless',
          'tag': tag,
          'settings': {
            'vnext': [
              {
                'address': s.address,
                'port': s.port,
                'users': [
                  {
                    'id': s.id,
                    'encryption': s.encryption ?? 'none',
                    if (s.flow != null) 'flow': s.flow,
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'vmess':
        return {
          'protocol': 'vmess',
          'tag': tag,
          'settings': {
            'vnext': [
              {
                'address': s.address,
                'port': s.port,
                'users': [
                  {
                    'id': s.id,
                    'alterId': s.alterId,
                    'security': s.encryption ?? 'auto',
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'trojan':
        return {
          'protocol': 'trojan',
          'tag': tag,
          'settings': {
            'servers': [
              {
                'address': s.address,
                'port': s.port,
                'password': s.id,
                if (s.flow != null) 'flow': s.flow,
              },
            ],
          },
          'streamSettings': stream,
        };
      case 'shadowsocks':
        return {
          'protocol': 'shadowsocks',
          'tag': tag,
          'settings': {
            'servers': [
              {
                'address': s.address,
                'port': s.port,
                'method': s.encryption ?? 'aes-256-gcm',
                'password': s.id,
              },
            ],
          },
          'streamSettings': stream,
        };
      default:
        throw UnsupportedError('Неизвестный протокол: ${s.protocol}');
    }
  }

  static Map<String, dynamic> _streamSettings(VpnServer s, OutboundVariant variant) {
    final fp = variant.fingerprint ?? s.fingerprint;
    final stream = <String, dynamic>{
      'network': s.network,
      'security': s.security,
    };

    if (s.security == 'reality') {
      stream['realitySettings'] = {
        'serverName': s.sni ?? '',
        'fingerprint': fp ?? 'chrome',
        'publicKey': s.publicKey ?? '',
        'shortId': s.shortId ?? '',
        'spiderX': s.spiderX ?? '',
      };
    } else if (s.security == 'tls') {
      stream['tlsSettings'] = {
        'serverName': s.sni ?? s.host ?? s.address,
        'allowInsecure': false,
        if (fp != null) 'fingerprint': fp,
        // Пустой alpn нельзя писать в конфиг: [""] Go отвергает целиком
        // («tls: invalid NextProtos value»), и сервер молча перестаёт работать.
        if ((s.alpn ?? '').isNotEmpty) 'alpn': s.alpn!.split(','),
      };
    }

    switch (s.network) {
      case 'ws':
        stream['wsSettings'] = {
          'path': (s.path ?? '').isEmpty ? '/' : s.path,
          if ((s.host ?? '').isNotEmpty) 'headers': {'Host': s.host},
        };
        break;
      case 'grpc':
        stream['grpcSettings'] = {
          'serviceName': s.path ?? '',
          'multiMode': false,
          if ((s.authority ?? '').isNotEmpty) 'authority': s.authority,
        };
        break;
      case 'xhttp':
        stream['xhttpSettings'] = {
          'path': (s.path ?? '').isEmpty ? '/' : s.path,
          if ((s.host ?? '').isNotEmpty) 'host': s.host,
          'mode': s.xhttpMode ?? 'auto',
          'extra': {'xPaddingBytes': s.xPadding ?? '100-1000'},
        };
        break;
      case 'http':
      case 'h2':
        stream['httpSettings'] = {
          'path': s.path ?? '/',
          if (s.host != null) 'host': [s.host],
        };
        break;
      case 'tcp':
      default:
        if (s.headerType == 'http') {
          stream['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': [s.path ?? '/'],
                if (s.host != null)
                  'headers': {
                    'Host': [s.host],
                  },
              },
            },
          };
        }
        break;
    }

    return stream;
  }
}
