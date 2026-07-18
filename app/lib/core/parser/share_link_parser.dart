import 'dart:convert';

import '../models/vpn_server.dart';
import '../util/b64.dart';

/// Парсер share-ссылок в [VpnServer].
///
/// Поддержаны основные схемы экосистемы Xray: vless://, vmess://, trojan://, ss://,
/// а также hysteria2:// (его поднимает не Xray, а sing-box — см. [VpnServer.core]).
/// Формат тот же, что парсит v2rayNG и генерирует Remnawave.
class ShareLinkParser {
  /// Возвращает null, если строка не распознана.
  static VpnServer? tryParse(String link) {
    final l = link.trim();
    try {
      if (l.startsWith('vless://')) return _parseVless(l);
      if (l.startsWith('vmess://')) return _parseVmess(l);
      if (l.startsWith('trojan://')) return _parseTrojan(l);
      if (l.startsWith('ss://')) return _parseShadowsocks(l);
      if (l.startsWith('hysteria2://') || l.startsWith('hy2://')) {
        return _parseHysteria2(l);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Разбор целого тела подписки (много строк) в список серверов.
  static List<VpnServer> parseSubscriptionBody(String body) {
    final text = _maybeBase64Body(body);
    final servers = <VpnServer>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final s = tryParse(line);
      if (s != null) servers.add(s);
    }
    return servers;
  }

  /// Если тело не содержит "://", пробуем как base64 всей подписки.
  static String _maybeBase64Body(String body) {
    if (body.contains('://')) return body;
    final decoded = B64.tryDecodeToString(body);
    if (decoded != null && decoded.contains('://')) return decoded;
    return body;
  }

  // ── vless ────────────────────────────────────────────────────────────────
  static VpnServer _parseVless(String link) {
    final uri = Uri.parse(link);
    final q = uri.queryParameters;
    final security = q['security'] ?? 'none';
    return VpnServer(
      protocol: 'vless',
      remark: _remark(uri),
      address: uri.host,
      port: uri.port,
      id: uri.userInfo,
      encryption: q['encryption'] ?? 'none',
      flow: _nz(q['flow']),
      network: q['type'] ?? 'tcp',
      security: security,
      sni: _nz(q['sni']),
      host: _nz(q['host']),
      path: _nz(q['path'] ?? q['serviceName']),
      fingerprint: _nz(q['fp']),
      publicKey: _nz(q['pbk']),
      shortId: _nz(q['sid']),
      spiderX: _nz(q['spx']),
      alpn: _nz(q['alpn']),
      headerType: _nz(q['headerType']),
      authority: _nz(q['authority']),
      xhttpMode: _nz(q['mode']),
      xPadding: _extractPadding(q['extra']),
      rawLink: link,
    );
  }

  /// Достаёт xPaddingBytes из параметра extra (JSON) xhttp-транспорта.
  static String? _extractPadding(String? extra) {
    if (extra == null || extra.isEmpty) return null;
    final m = RegExp(r'xPaddingBytes"?\s*:\s*"?([0-9\-]+)').firstMatch(extra);
    return m?.group(1);
  }

  // ── trojan ───────────────────────────────────────────────────────────────
  static VpnServer _parseTrojan(String link) {
    final uri = Uri.parse(link);
    final q = uri.queryParameters;
    return VpnServer(
      protocol: 'trojan',
      remark: _remark(uri),
      address: uri.host,
      port: uri.port,
      id: uri.userInfo,
      flow: _nz(q['flow']),
      network: q['type'] ?? 'tcp',
      security: q['security'] ?? 'tls',
      sni: _nz(q['sni']),
      host: _nz(q['host']),
      path: _nz(q['path'] ?? q['serviceName']),
      fingerprint: _nz(q['fp']),
      publicKey: _nz(q['pbk']),
      shortId: _nz(q['sid']),
      alpn: _nz(q['alpn']),
      headerType: _nz(q['headerType']),
      rawLink: link,
    );
  }

  // ── hysteria2 ─────────────────────────────────────────────────────────────
  // hysteria2://пароль@host:port?sni=…&insecure=1&obfs=salamander
  //             &obfs-password=…&alpn=h3&mport=1000-2000#имя
  // Короткая схема hy2:// — тот же формат. Транспорт всегда QUIC, TLS обязателен,
  // поэтому network/security фиксированы и в ссылке не передаются.
  static VpnServer _parseHysteria2(String link) {
    final uri = Uri.parse(link);
    final q = uri.queryParameters;
    // Пароль может содержать «:» (форма user:pass) и быть URL-кодированным.
    final password = Uri.decodeComponent(uri.userInfo);
    return VpnServer(
      protocol: 'hysteria2',
      remark: _remark(uri),
      address: uri.host,
      port: uri.hasPort ? uri.port : 443,
      id: password,
      network: 'quic',
      security: 'tls',
      sni: _nz(q['sni'] ?? q['peer']),
      alpn: _nz(q['alpn']),
      fingerprint: _nz(q['fp']),
      obfs: _nz(q['obfs']),
      obfsPassword: _nz(q['obfs-password'] ?? q['obfsParam']),
      allowInsecure: _bool(q['insecure'] ?? q['allowInsecure']),
      hopPorts: _nz(q['mport'] ?? q['ports']),
      rawLink: link,
    );
  }

  /// «1» / «true» — да; всё остальное (включая отсутствие) — нет.
  static bool _bool(String? v) {
    final s = (v ?? '').toLowerCase();
    return s == '1' || s == 'true';
  }

  // ── vmess (base64 JSON) ───────────────────────────────────────────────────
  static VpnServer _parseVmess(String link) {
    final payload = link.substring('vmess://'.length);
    final jsonStr = B64.decodeToString(payload);
    final m = jsonDecode(jsonStr) as Map<String, dynamic>;

    String s(String k) => (m[k] ?? '').toString();
    final tls = s('tls');
    return VpnServer(
      protocol: 'vmess',
      remark: s('ps'),
      address: s('add'),
      port: int.tryParse(s('port')) ?? 0,
      id: s('id'),
      alterId: int.tryParse(s('aid')) ?? 0,
      encryption: _nz(s('scy')) ?? 'auto',
      network: _nz(s('net')) ?? 'tcp',
      security: tls == 'tls' ? 'tls' : 'none',
      sni: _nz(s('sni')),
      host: _nz(s('host')),
      path: _nz(s('path')),
      alpn: _nz(s('alpn')),
      headerType: _nz(s('type')),
      rawLink: link,
    );
  }

  // ── shadowsocks ───────────────────────────────────────────────────────────
  // Форматы:
  //  ss://base64(method:password)@host:port#tag
  //  ss://base64(method:password@host:port)#tag
  static VpnServer _parseShadowsocks(String link) {
    var rest = link.substring('ss://'.length);
    String remark = '';
    final hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      remark = Uri.decodeComponent(rest.substring(hashIdx + 1));
      rest = rest.substring(0, hashIdx);
    }
    // Отбросить query, если есть (?plugin=…)
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) rest = rest.substring(0, qIdx);

    String method, password, host;
    int port;
    if (rest.contains('@')) {
      final at = rest.lastIndexOf('@');
      final creds = B64.decodeToString(rest.substring(0, at));
      final hostPart = rest.substring(at + 1);
      final ci = creds.indexOf(':');
      method = creds.substring(0, ci);
      password = creds.substring(ci + 1);
      final hi = hostPart.lastIndexOf(':');
      host = hostPart.substring(0, hi);
      port = int.tryParse(hostPart.substring(hi + 1)) ?? 0;
    } else {
      final decoded = B64.decodeToString(rest);
      final at = decoded.lastIndexOf('@');
      final creds = decoded.substring(0, at);
      final hostPart = decoded.substring(at + 1);
      final ci = creds.indexOf(':');
      method = creds.substring(0, ci);
      password = creds.substring(ci + 1);
      final hi = hostPart.lastIndexOf(':');
      host = hostPart.substring(0, hi);
      port = int.tryParse(hostPart.substring(hi + 1)) ?? 0;
    }

    return VpnServer(
      protocol: 'shadowsocks',
      remark: remark,
      address: host,
      port: port,
      id: password,
      encryption: method,
      network: 'tcp',
      security: 'none',
      rawLink: link,
    );
  }

  static String _remark(Uri uri) =>
      uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : '';

  /// null для пустых строк — чтобы не тянуть "" в конфиг.
  static String? _nz(String? v) => (v == null || v.isEmpty) ? null : v;
}
