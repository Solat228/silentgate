import 'dart:convert';

import '../models/vpn_server.dart';

/// Разбор подписки в формате **XRAY_JSON** — том, что Remnawave отдаёт Happ/v2rayNG.
///
/// Тело — массив ПОЛНЫХ конфигов Xray, по одному на сервер:
/// `[{dns, routing, inbounds, outbounds:[{tag:"proxy",…},direct,block], remarks:"Имя"}, …]`
///
/// Ценность формата в том, что панель отдаёт **готовый outbound**: точные
/// streamSettings, flow, reality-поля. Пересборка их из share-ссылок теряет детали —
/// именно из-за этого автовыбор (burstObservatory) получал нерабочие outbound'ы.
/// Поэтому сохраняем исходный outbound целиком в [VpnServer.rawOutboundJson].
class XrayJsonSubscription {
  /// Похоже ли тело на JSON-подписку (а не на base64-список ссылок).
  static bool looksLikeJson(String body) {
    final t = body.trimLeft();
    return t.startsWith('[') || t.startsWith('{');
  }

  /// Разобрать тело. Возвращает пустой список, если формат не наш.
  static List<VpnServer> parse(String body) {
    try {
      final decoded = jsonDecode(body);
      final configs = decoded is List ? decoded : [decoded];
      final servers = <VpnServer>[];
      for (final cfg in configs) {
        if (cfg is! Map) continue;
        final s = _fromConfig(cfg.cast<String, dynamic>());
        if (s != null) servers.add(s);
      }
      return servers;
    } catch (_) {
      return const [];
    }
  }

  /// Восстановить сервер из сохранённого полного конфига профиля (после перезапуска:
  /// на диске лежат только ссылки, а `panel://…` обычным парсером не разбирается).
  static VpnServer? fromPanelConfig(String configJson) {
    try {
      final m = jsonDecode(configJson);
      if (m is! Map) return null;
      return _fromConfig(m.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static VpnServer? _fromConfig(Map<String, dynamic> cfg) {
    final outbounds = cfg['outbounds'];
    if (outbounds is! List) return null;

    final proxies = <Map<String, dynamic>>[];
    for (final o in outbounds) {
      if (o is! Map) continue;
      final proto = '${o['protocol']}';
      if (proto == 'freedom' || proto == 'blackhole' || proto == 'dns') continue;
      proxies.add(o.cast<String, dynamic>());
    }
    if (proxies.isEmpty) return null;

    // Первый по тегу 'proxy', иначе просто первый — он даёт поля для отображения.
    final proxy = proxies.firstWhere((o) => '${o['tag']}' == 'proxy',
        orElse: () => proxies.first);
    final remark = '${cfg['remarks'] ?? proxy['tag'] ?? 'Сервер'}';

    final base = fromOutbound(proxy, remark: remark);
    if (base == null) return null;
    if (!isComplexProfile(cfg, proxyCount: proxies.length)) return base;

    // «Авто …»: конфиг применяется целиком, иначе теряются десятки серверов
    // и весь балансировщик. Ключ — по имени профиля: состав outbound'ов меняется
    // при каждом обновлении подписки, и ключ по первому серверу «уезжал» бы.
    return base.copyWith(
      rawPanelConfig: jsonEncode(cfg),
      rawLink: panelKey(remark),
    );
  }

  /// Профиль-автовыбор: несколько прокси-outbound'ов и/или готовый балансировщик.
  static bool isComplexProfile(Map<String, dynamic> cfg, {required int proxyCount}) {
    if (cfg.containsKey('burstObservatory') || cfg.containsKey('observatory')) {
      return true;
    }
    final balancers = (cfg['routing'] as Map?)?['balancers'];
    if (balancers is List && balancers.isNotEmpty) return true;
    return proxyCount > 1;
  }

  /// Стабильный ключ профиля панели (не зависит от состава серверов внутри).
  static String panelKey(String remark) =>
      'panel://${Uri.encodeComponent(remark.trim())}';

  /// Собрать [VpnServer] из одного outbound'а Xray.
  static VpnServer? fromOutbound(Map<String, dynamic> out, {required String remark}) {
    final protocol = '${out['protocol']}';
    final settings = (out['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final stream =
        (out['streamSettings'] as Map?)?.cast<String, dynamic>() ?? const {};

    // Hysteria2: Remnawave отдаёт его в XRAY_JSON как protocol "hysteria" (version 2),
    // адрес/порт — прямо в settings, а не в vnext/servers. Без этой ветки узел
    // проваливал проверку address.isEmpty ниже и МОЛЧА выбрасывался (у панели их 7).
    // Ядро для него — sing-box (Xray hysteria не умеет), поэтому собираем из полей,
    // а не сохраняем Xray-outbound как есть.
    if (protocol == 'hysteria2' ||
        (protocol == 'hysteria' && (settings['version'] == 2 ||
            ((stream['hysteriaSettings'] as Map?)?['version'] == 2)))) {
      return _fromHysteria(settings, stream, remark);
    }

    String address = '';
    int port = 0;
    String id = '';
    String? encryption, flow;
    int alterId = 0;

    final vnext = settings['vnext'];
    final serversList = settings['servers'];
    if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
      final v = (vnext.first as Map).cast<String, dynamic>();
      address = '${v['address'] ?? ''}';
      port = (v['port'] as num?)?.toInt() ?? 0;
      final users = v['users'];
      if (users is List && users.isNotEmpty && users.first is Map) {
        final u = (users.first as Map).cast<String, dynamic>();
        id = '${u['id'] ?? ''}';
        alterId = (u['alterId'] as num?)?.toInt() ?? 0;
        final f = '${u['flow'] ?? ''}';
        if (f.isNotEmpty) flow = f;
        final enc = '${u['encryption'] ?? u['security'] ?? ''}';
        if (enc.isNotEmpty) encryption = enc;
      }
    } else if (serversList is List &&
        serversList.isNotEmpty &&
        serversList.first is Map) {
      // trojan / shadowsocks
      final v = (serversList.first as Map).cast<String, dynamic>();
      address = '${v['address'] ?? ''}';
      port = (v['port'] as num?)?.toInt() ?? 0;
      id = '${v['password'] ?? ''}';
      final method = '${v['method'] ?? ''}';
      if (method.isNotEmpty) encryption = method;
      final f = '${v['flow'] ?? ''}';
      if (f.isNotEmpty) flow = f;
    }
    if (address.isEmpty || port == 0) return null;

    final network = '${stream['network'] ?? 'tcp'}';
    final security = '${stream['security'] ?? 'none'}';

    String? sni, fingerprint, publicKey, shortId, spiderX, alpn;
    final reality = (stream['realitySettings'] as Map?)?.cast<String, dynamic>();
    final tls = (stream['tlsSettings'] as Map?)?.cast<String, dynamic>();
    if (reality != null) {
      sni = _str(reality['serverName']);
      fingerprint = _str(reality['fingerprint']);
      publicKey = _str(reality['publicKey']);
      shortId = _str(reality['shortId']);
      spiderX = _str(reality['spiderX']);
    } else if (tls != null) {
      sni = _str(tls['serverName']);
      fingerprint = _str(tls['fingerprint']);
      final a = tls['alpn'];
      if (a is List && a.isNotEmpty) alpn = a.join(',');
    }

    String? host, path, headerType, authority, xhttpMode, xPadding;
    switch (network) {
      case 'ws':
        final ws = (stream['wsSettings'] as Map?)?.cast<String, dynamic>();
        path = _str(ws?['path']);
        host = _str((ws?['headers'] as Map?)?['Host']);
        break;
      case 'grpc':
        final g = (stream['grpcSettings'] as Map?)?.cast<String, dynamic>();
        path = _str(g?['serviceName']);
        authority = _str(g?['authority']);
        break;
      case 'xhttp':
        final x = (stream['xhttpSettings'] as Map?)?.cast<String, dynamic>();
        path = _str(x?['path']);
        host = _str(x?['host']);
        xhttpMode = _str(x?['mode']);
        xPadding = _str((x?['extra'] as Map?)?['xPaddingBytes']);
        break;
      case 'http':
      case 'h2':
        final h = (stream['httpSettings'] as Map?)?.cast<String, dynamic>();
        path = _str(h?['path']);
        final hosts = h?['host'];
        if (hosts is List && hosts.isNotEmpty) host = '${hosts.first}';
        break;
      default:
        final tcp = (stream['tcpSettings'] as Map?)?.cast<String, dynamic>();
        final header = (tcp?['header'] as Map?)?.cast<String, dynamic>();
        headerType = _str(header?['type']);
        final req = (header?['request'] as Map?)?.cast<String, dynamic>();
        final paths = req?['path'];
        if (paths is List && paths.isNotEmpty) path = '${paths.first}';
        final hh = (req?['headers'] as Map?)?['Host'];
        if (hh is List && hh.isNotEmpty) host = '${hh.first}';
        break;
    }

    final base = VpnServer(
      protocol: protocol,
      remark: remark,
      address: address,
      port: port,
      id: id,
      encryption: encryption,
      alterId: alterId,
      flow: flow,
      network: network,
      security: security,
      sni: sni,
      host: host,
      path: path,
      fingerprint: fingerprint,
      publicKey: publicKey,
      shortId: shortId,
      spiderX: spiderX,
      alpn: alpn,
      headerType: headerType,
      authority: authority,
      xhttpMode: xhttpMode,
      xPadding: xPadding,
      rawLink: '', // подставим стабильный ключ ниже
      rawOutboundJson: jsonEncode(out),
    );
    // Ключ — восстановленная share-ссылка: стабильна между запусками и совместима
    // с пинами/override, сохранёнными до перехода на JSON-формат.
    return base.copyWith(rawLink: base.buildShareLink());
  }

  /// Hysteria2-узел из Xray-outbound панели (protocol "hysteria", version 2).
  /// Поля лежат в `settings` (address/port) и `streamSettings.hysteriaSettings`
  /// (auth/obfs) + `tlsSettings` (sni/alpn). Ядро — sing-box (`VpnServer.core`).
  static VpnServer? _fromHysteria(
    Map<String, dynamic> settings,
    Map<String, dynamic> stream,
    String remark,
  ) {
    final address = '${settings['address'] ?? ''}';
    final port = (settings['port'] as num?)?.toInt() ?? 0;
    if (address.isEmpty || port == 0) return null;

    final hy = (stream['hysteriaSettings'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final tls = (stream['tlsSettings'] as Map?)?.cast<String, dynamic>() ?? const {};

    // Пароль/токен: hysteriaSettings.auth (у Remnawave), иначе settings.auth/password.
    final auth = _str(hy['auth']) ??
        _str(hy['auth_str']) ??
        _str(settings['auth']) ??
        _str(settings['password']) ??
        '';

    final alpnRaw = tls['alpn'];
    final alpn = alpnRaw is List && alpnRaw.isNotEmpty
        ? alpnRaw.join(',')
        : _str(alpnRaw);

    final insecure = tls['allowInsecure'] == true ||
        settings['insecure'] == true ||
        hy['insecure'] == true;

    final base = VpnServer(
      protocol: 'hysteria2',
      remark: remark,
      address: address,
      port: port,
      id: auth,
      network: 'quic',
      security: 'tls',
      sni: _str(tls['serverName']) ?? _str(hy['server_name']),
      alpn: alpn,
      fingerprint: _str(tls['fingerprint']),
      obfs: _str((hy['obfs'] as Map?)?['type']) ?? _str(hy['obfs']),
      obfsPassword:
          _str((hy['obfs'] as Map?)?['password']) ?? _str(hy['obfsPassword']),
      allowInsecure: insecure,
      hopPorts: _str(hy['hopPorts']) ?? _str(hy['ports']),
      rawLink: '',
    );
    // Стабильный ключ — восстановленная hysteria2://-ссылка (переживает перезапуск,
    // совместима с пинами/override).
    return base.copyWith(rawLink: base.buildShareLink());
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = '$v';
    return s.isEmpty ? null : s;
  }
}
