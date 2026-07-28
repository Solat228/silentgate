import 'dart:io' show InternetAddress;

import '../models/vpn_server.dart';

/// Строит outbound sing-box из [VpnServer].
///
/// **hysteria2** здесь обязателен: Xray этого протокола не умеет (QUIC +
/// собственный congestion control), поэтому такие серверы всегда поднимает
/// sing-box.
///
/// **vless/trojan/shadowsocks** sing-box тоже умеет, и это нужно на Android:
/// там оба ядра — gomobile-библиотеки, а две такие библиотеки в одном
/// приложении конфликтуют общим Go-рантаймом (`go.Seq`). Поэтому мобильная
/// сборка обходится одним ядром, и обычные серверы идут через него же.
/// На Windows ничего не меняется: там по-прежнему Xray, а sing-box отвечает за
/// TUN и hysteria2.
///
/// ⚠️ Чего sing-box заменить НЕ может — панельные профили «Авто»: это готовые
/// Xray-конфиги с `balancers`/`burstObservatory`, и разобрать их он не в
/// состоянии.
class SingboxOutboundFactory {
  /// Умеем ли мы построить outbound для этого сервера.
  static bool supports(VpnServer s) => const {
        'hysteria2',
        'vless',
        'trojan',
        'shadowsocks',
      }.contains(s.protocol);

  /// [resolvedIp] — адрес сервера, отрезолвленный ЗАРАНЕЕ (до подъёма TUN).
  ///
  /// Зачем: с доменным именем ядру приходится резолвить его самому уже в рантайме.
  /// В TUN-режиме этот запрос уходит в системный резолвер, перехватывается
  /// правилом `hijack-dns` (оно стоит выше защиты от петли, потому что запрос
  /// шлёт `svchost.exe`, а не наш процесс) и по `dns.final` возвращается
  /// В ЭТО ЖЕ прокси-ядро, которое как раз и ждёт ответа. Замкнутый круг:
  /// процесс жив, конфиг валиден, трафика нет.
  ///
  /// С подставленным IP резолвить нечего — петля невозможна по построению.
  /// Имя при этом НЕ теряется: оно остаётся в `server_name` (SNI) и в `Host`.
  static Map<String, dynamic> build(VpnServer s,
      {String tag = 'proxy', String? resolvedIp}) {
    switch (s.protocol) {
      case 'vless':
        return _vless(s, tag, resolvedIp);
      case 'trojan':
        return _trojan(s, tag, resolvedIp);
      case 'shadowsocks':
        return _shadowsocks(s, tag, resolvedIp);
      case 'hysteria2':
        break;
      default:
        throw ArgumentError('sing-box-outbound не умеет протокол ${s.protocol}');
    }

    final ports = _serverPorts(s.hopPorts);
    final obfs = _obfs(s);
    final out = <String, dynamic>{
      'type': 'hysteria2',
      'tag': tag,
      'server': _host(s, resolvedIp),
      // Порт-хоппинг: sing-box требует ЛИБО server_port, ЛИБО server_ports.
      // Подстановка IP его не касается — хоппинг меняет порт, не хост.
      if (ports == null) 'server_port': s.port else 'server_ports': ports,
      if (ports != null) 'hop_interval': '30s',
      if (s.id.isNotEmpty) 'password': s.id,
      if (obfs != null) 'obfs': obfs,
      // У hysteria2 транспорт — QUIC, TLS есть всегда и отключить его нельзя.
      'tls': {
        'enabled': true,
        if (_tlsName(s, resolvedIp) != null) 'server_name': _tlsName(s, resolvedIp),
        if (s.allowInsecure) 'insecure': true,
        if ((s.alpn ?? '').isNotEmpty)
          'alpn': s.alpn!.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
      },
    };
    return out;
  }

  /// Адрес для поля `server`: подставленный IP, иначе исходный адрес.
  static String _host(VpnServer s, String? resolvedIp) =>
      (resolvedIp != null && resolvedIp.isNotEmpty) ? resolvedIp : s.address;

  /// Имя сервера, если исходный адрес — доменное имя (а не IP-литерал).
  static String? _domainOf(VpnServer s) {
    final a = s.address.trim();
    if (a.isEmpty) return null;
    // IPv6 в конфиге может приехать в скобках.
    final bare = a.startsWith('[') && a.endsWith(']')
        ? a.substring(1, a.length - 1)
        : a;
    return InternetAddress.tryParse(bare) == null ? a : null;
  }

  /// Имя для TLS/SNI.
  ///
  /// ⚠️ Когда в `server` подставлен IP, `server_name` ОБЯЗАН остаться доменом:
  /// иначе сертификат не пройдёт проверку, а sing-box вовсе отвергнет конфиг
  /// («missing server_name or insecure=true») — и вместо починки пользователь
  /// получит «Ядро завершилось при запуске».
  static String? _tlsName(VpnServer s, String? resolvedIp) {
    final sni = (s.sni ?? '').trim();
    if (sni.isNotEmpty) return sni;
    if (resolvedIp != null && resolvedIp.isNotEmpty) return _domainOf(s);
    return null;
  }

  // ── VLESS / Trojan / Shadowsocks ────────────────────────────────────────────

  static Map<String, dynamic> _vless(
          VpnServer s, String tag, String? resolvedIp) =>
      {
        'type': 'vless',
        'tag': tag,
        'server': _host(s, resolvedIp),
        'server_port': s.port,
        'uuid': s.id,
        if ((s.flow ?? '').isNotEmpty) 'flow': s.flow,
        if ((s.encryption ?? '').isNotEmpty && s.encryption != 'none')
          'packet_encoding': s.encryption,
        ..._tlsBlock(s, resolvedIp),
        ..._transportBlock(s, resolvedIp),
      };

  static Map<String, dynamic> _trojan(
          VpnServer s, String tag, String? resolvedIp) =>
      {
        'type': 'trojan',
        'tag': tag,
        'server': _host(s, resolvedIp),
        'server_port': s.port,
        'password': s.id,
        ..._tlsBlock(s, resolvedIp),
        ..._transportBlock(s, resolvedIp),
      };

  static Map<String, dynamic> _shadowsocks(
          VpnServer s, String tag, String? resolvedIp) =>
      {
        'type': 'shadowsocks',
        'tag': tag,
        'server': _host(s, resolvedIp),
        'server_port': s.port,
        'method': (s.encryption ?? '').isEmpty ? 'aes-128-gcm' : s.encryption,
        'password': s.id,
      };

  /// TLS-блок: обычный TLS, Reality и подмена отпечатка через uTLS.
  ///
  /// Пустые строки НЕ пишем: Go отвергает `alpn: [""]` («invalid NextProtos»),
  /// и ровно на этом уже спотыкались в редакторе сервера.
  static Map<String, dynamic> _tlsBlock(VpnServer s, String? resolvedIp) {
    final security = s.security.toLowerCase();
    if (security != 'tls' && security != 'reality') return const {};

    final alpn = (s.alpn ?? '')
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();

    return {
      'tls': {
        'enabled': true,
        if (_tlsName(s, resolvedIp) != null) 'server_name': _tlsName(s, resolvedIp),
        if (s.allowInsecure) 'insecure': true,
        if (alpn.isNotEmpty) 'alpn': alpn,
        if ((s.fingerprint ?? '').isNotEmpty)
          'utls': {'enabled': true, 'fingerprint': s.fingerprint},
        if (security == 'reality')
          'reality': {
            'enabled': true,
            if ((s.publicKey ?? '').isNotEmpty) 'public_key': s.publicKey,
            if ((s.shortId ?? '').isNotEmpty) 'short_id': s.shortId,
          },
      },
    };
  }

  /// Транспорт. `tcp` — это отсутствие секции: у sing-box нет такого типа,
  /// и явное указание валит конфиг целиком.
  static Map<String, dynamic> _transportBlock(VpnServer s, String? resolvedIp) {
    final path = (s.path ?? '');
    // ⚠️ При подставленном IP заголовок Host обязан остаться доменом: без него
    // CDN/Nginx на той стороне не найдёт нужный виртуальный хост и вернёт 404
    // вместо апгрейда соединения.
    final host = (s.host ?? '').isNotEmpty
        ? s.host!
        : (resolvedIp != null ? (_domainOf(s) ?? '') : '');
    switch (s.network) {
      case 'ws':
        return {
          'transport': {
            'type': 'ws',
            if (path.isNotEmpty) 'path': path,
            if (host.isNotEmpty) 'headers': {'Host': host},
          },
        };
      case 'grpc':
        return {
          'transport': {
            'type': 'grpc',
            // В share-ссылке имя grpc-сервиса приезжает в поле path.
            if (path.isNotEmpty) 'service_name': path.replaceFirst('/', ''),
          },
        };
      case 'http':
      case 'h2':
        return {
          'transport': {
            'type': 'http',
            if (path.isNotEmpty) 'path': path,
            if (host.isNotEmpty) 'host': [host],
          },
        };
      case 'httpupgrade':
        return {
          'transport': {
            'type': 'httpupgrade',
            if (path.isNotEmpty) 'path': path,
            if (host.isNotEmpty) 'host': host,
          },
        };
      default:
        return const {};
    }
  }

  /// Блок обфускации — или null, если её нет.
  ///
  /// Проверять обязательно: sing-box валит **весь конфиг**, а не один outbound,
  /// если тип не `salamander` или пароль пуст (`FATAL initialize outbound[0]:
  /// missing obfs password` / `unknown obfs type: none`). А написать `obfs=none`
  /// в ссылке — обычный способ сказать «без обфускации», и такая ссылка не должна
  /// убивать подключение ко всем остальным серверам сразу.
  static Map<String, dynamic>? _obfs(VpnServer s) {
    final type = (s.obfs ?? '').trim().toLowerCase();
    final password = (s.obfsPassword ?? '').trim();
    if (type != 'salamander' || password.isEmpty) return null;
    return {'type': 'salamander', 'password': password};
  }

  /// `mport=1000-2000,3000` → `["1000:2000", "3000:3000"]` (формат sing-box).
  /// null — хоппинг не задан или задан мусором, тогда используется обычный
  /// server_port: это лучше, чем `bad port range` и мёртвый конфиг целиком.
  static List<String>? _serverPorts(String? mport) {
    final raw = (mport ?? '').trim();
    if (raw.isEmpty) return null;
    final ranges = <String>[];
    for (final part in raw.split(RegExp(r'[,\s]+'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final m = RegExp(r'^(\d+)\s*[-:]\s*(\d+)$').firstMatch(p);
      if (m != null) {
        final a = int.tryParse(m.group(1)!);
        final b = int.tryParse(m.group(2)!);
        final range = _range(a, b);
        if (range != null) ranges.add(range);
        continue;
      }
      final single = int.tryParse(p);
      final one = _range(single, single);
      if (one != null) ranges.add(one);
    }
    return ranges.isEmpty ? null : ranges;
  }

  /// Диапазон портов в границах uint16; перевёрнутый разворачиваем, а не
  /// отдаём как есть — иначе хоппинг молча не работает.
  static String? _range(int? a, int? b) {
    if (a == null || b == null) return null;
    final lo = a <= b ? a : b;
    final hi = a <= b ? b : a;
    if (lo < 1 || hi > 65535) return null;
    return '$lo:$hi';
  }
}
