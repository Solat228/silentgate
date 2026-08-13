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
  ///
  /// ⚠️ ССЫЛКА ПРИВОДИТСЯ К КАНОНИЧЕСКОМУ ВИДУ, И ЭТО НЕ КОСМЕТИКА. Ссылка —
  /// это КЛЮЧ сервера (`VpnServer.key`), а по ключу лежат пин, ручная правка и
  /// результат пинга. Одни и те же данные приходят в разных написаниях: у gRPC
  /// имя сервиса встречается и как `serviceName=`, и как `path=` — разбор
  /// понимает оба (см. ниже), а сборка пишет одно. Пока ключом была ИСХОДНАЯ
  /// строка, один и тот же сервер получал разные ключи в зависимости от
  /// формата ответа панели (Remnawave выбирает его по `User-Agent`).
  ///
  /// Чем это обошлось на живых данных владельца 13.08.2026: из 374 сохранённых
  /// результатов пинга **273 осиротели**, из них 190 — gRPC. Вместе с ключом
  /// терялись пин и ручная правка, а баннер обновления подписки каждый раз
  /// показывал «+1 · −1» на неизменившемся сервере.
  ///
  /// Поэтому ключ строится ОДНИМ кодом из разобранных полей, а не берётся из
  /// входной строки. Протоколы, которые [VpnServer.buildShareLink] не
  /// пересобирает (vmess, ss), остаются как есть — там `buildShareLink`
  /// возвращает `rawLink` без изменений.
  static VpnServer? tryParse(String link) {
    final s = _tryParseRaw(link);
    if (s == null) return null;
    // ⚠️ КАНОНИЗИРУЕМ ТОЛЬКО ОСМЫСЛЕННО РАЗОБРАННОЕ. Разбор снисходителен: он
    // проглотит огрызок вроде `vless://a` и отдаст сервер с пустым адресом и
    // портом 0, а сборка превратит это в `vless://@a:0?type=tcp&…` — то есть
    // придумает ключ, которого никогда не было. Для настоящего сервера адрес и
    // порт заполнены всегда, поэтому проверка ничего не стоит; а вот битой или
    // чужой строке она сохраняет её собственный вид, и данные по ней не
    // осиротеют. Правило то же, что у `canonicalKey`: чужое не выбрасываем.
    if (s.address.trim().isEmpty || s.port <= 0) return s;
    final canonical = s.buildShareLink();
    return canonical == s.rawLink ? s : s.copyWith(rawLink: canonical);
  }

  /// Разбор без приведения ключа — только для самой канонизации и тестов на
  /// идемпотентность.
  static VpnServer? tryParseRaw(String link) => _tryParseRaw(link);

  static VpnServer? _tryParseRaw(String link) {
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

  /// Канонический вид ссылки: та же ссылка, приведённая к одному написанию.
  ///
  /// Не разобралась — возвращаем как есть: выбрасывать чужие данные нельзя,
  /// а незнакомый протокол это ещё не повод считать ключ мусором.
  static String canonicalKey(String link) => tryParse(link)?.key ?? link.trim();

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
