import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../engine/vpn_engine.dart';
import '../settings/split_tunnel.dart';

/// Фактический маршрут живого соединения по данным Clash API ядра.
enum LiveRouteKind {
  vpn,
  blocked,
  direct,
}

/// Одно открытое соединение из `GET /connections` живого ядра.
class LiveConnectionEntry {
  final String id;
  final String host;
  final String destinationIp;
  final int destinationPort;
  final String network;
  final String process;
  final String processPath;
  final List<String> chains;
  final String rule;
  final int uploadBytes;
  final int downloadBytes;
  final DateTime? start;
  final LiveRouteKind route;

  const LiveConnectionEntry({
    required this.id,
    required this.host,
    required this.destinationIp,
    required this.destinationPort,
    required this.network,
    required this.process,
    this.processPath = '',
    required this.chains,
    required this.rule,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.start,
    required this.route,
  });

  /// Человекочитаемая цель соединения (`example.com:443` или `1.1.1.1:443`).
  String get targetLabel {
    final target = host.isNotEmpty ? host : destinationIp;
    if (target.isEmpty) return id;
    return destinationPort > 0 ? '$target:$destinationPort' : target;
  }

  /// Есть ли полный путь к исполняемому файлу на диске (Windows/десктоп).
  bool get hasExecutablePath =>
      processPath.contains(r'\') ||
      (processPath.contains('/') && !processPath.startsWith('package:'));

  /// Ключ программы для создания [AppRule] (`C:\...\app.exe`, `app.exe` или имя пакета Android).
  String get appRuleKey =>
      processPath.trim().isNotEmpty ? processPath.trim() : process.trim();
}

/// Секция списка открытых соединений.
class LiveConnectionsSection {
  final LiveRouteKind kind;
  final List<LiveConnectionEntry> items;

  const LiveConnectionsSection({
    required this.kind,
    required this.items,
  });
}

/// Снимок текущих открытых соединений, разложенный по маршрутам.
class LiveConnectionsSnapshot {
  final List<LiveConnectionEntry> vpn;
  final List<LiveConnectionEntry> blocked;
  final List<LiveConnectionEntry> direct;

  const LiveConnectionsSnapshot({
    this.vpn = const [],
    this.blocked = const [],
    this.direct = const [],
  });

  static const empty = LiveConnectionsSnapshot();

  int get totalCount => vpn.length + blocked.length + direct.length;

  /// Все соединения снимка в порядке секций ([vpn], [blocked], [direct]).
  List<LiveConnectionEntry> get allEntries => [...vpn, ...blocked, ...direct];

  /// Копия снимка без соединений из [closedIds] (удобно при замороженном списке).
  LiveConnectionsSnapshot withoutIds(Set<String> closedIds) {
    if (closedIds.isEmpty) return this;
    return LiveConnectionsSnapshot(
      vpn: vpn.where((e) => !closedIds.contains(e.id)).toList(),
      blocked: blocked.where((e) => !closedIds.contains(e.id)).toList(),
      direct: direct.where((e) => !closedIds.contains(e.id)).toList(),
    );
  }

  /// Секции строго в порядке требования:
  /// 1. Через VPN
  /// 2. Блокируются (ТОЛЬКО если есть хотя бы одно блокируемое соединение)
  /// 3. Прямые
  List<LiveConnectionsSection> get sections => [
        LiveConnectionsSection(kind: LiveRouteKind.vpn, items: vpn),
        if (blocked.isNotEmpty)
          LiveConnectionsSection(kind: LiveRouteKind.blocked, items: blocked),
        LiveConnectionsSection(kind: LiveRouteKind.direct, items: direct),
      ];

  /// Разбор ответа `GET /connections` Clash API.
  factory LiveConnectionsSnapshot.fromClashJson(
    Object? raw, {
    SplitTunnelConfig? split,
  }) {
    final list = raw is Map ? raw['connections'] : raw;
    if (list is! List) return empty;

    final vpn = <LiveConnectionEntry>[];
    final blocked = <LiveConnectionEntry>[];
    final direct = <LiveConnectionEntry>[];

    for (final item in list) {
      if (item is! Map) continue;
      final meta = item['metadata'];
      if (meta is! Map) continue;

      final rawHost = (meta['host'] ?? meta['sniffHost'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final host = _cleanHost(rawHost);
      final dstIp = (meta['destinationIP'] ?? '').toString().trim();
      final dstPort = _parseInt(meta['destinationPort']);
      final network = (meta['network'] ?? 'tcp').toString().trim().toLowerCase();
      final rawProcPath = (meta['processPath'] ?? '').toString().trim();
      final rawProcName = (meta['process'] ?? '').toString().trim();
      final rawProc = rawProcName.isNotEmpty ? rawProcName : rawProcPath;
      final process = _basename(rawProc);
      final processPath = rawProcPath.isNotEmpty
          ? rawProcPath
          : ((rawProcName.contains('\\') || rawProcName.contains('/'))
              ? rawProcName
              : '');

      // Отсекаем собственные служебные петли локального прокси/ядра.
      if (_isInternalLoopback(host: host, dstIp: dstIp, process: process)) {
        continue;
      }

      final chains = <String>[
        if (item['chains'] is List)
          for (final c in item['chains'] as List)
            if (c != null && c.toString().trim().isNotEmpty)
              c.toString().trim(),
      ];
      final rule = [
        (item['rule'] ?? '').toString().trim(),
        (item['rulePayload'] ?? '').toString().trim(),
      ].where((s) => s.isNotEmpty).join(' ');

      final route = classifyConnectionRoute(
        chains: chains,
        rule: rule,
        host: host,
        port: dstPort,
        split: split,
      );

      // Штатный сброс HTTP/3 (QUIC, UDP:443) ради возврата браузера на TCP
      // (`SingboxConfigBuilder._quicBlockDomains`) — техническая деталь
      // сниффинга, а не блокировка сайта пользователем.
      if (route == LiveRouteKind.blocked &&
          network == 'udp' &&
          dstPort == 443 &&
          split != null &&
          host.isNotEmpty) {
        final siteRule = mostSpecificSiteRule(split.sites, host, port: dstPort);
        if (siteRule != null && siteRule.action != AppAction.block) {
          continue;
        }
      }

      final entry = LiveConnectionEntry(
        id: (item['id'] ?? '').toString(),
        host: host,
        destinationIp: dstIp,
        destinationPort: dstPort,
        network: network,
        process: process,
        processPath: processPath,
        chains: chains,
        rule: rule,
        uploadBytes: _parseInt(item['upload']),
        downloadBytes: _parseInt(item['download']),
        start: DateTime.tryParse((item['start'] ?? '').toString()),
        route: route,
      );

      switch (route) {
        case LiveRouteKind.vpn:
          vpn.add(entry);
        case LiveRouteKind.blocked:
          blocked.add(entry);
        case LiveRouteKind.direct:
          direct.add(entry);
      }
    }

    int byRecent(LiveConnectionEntry a, LiveConnectionEntry b) {
      final sa = a.start;
      final sb = b.start;
      if (sa != null && sb != null) {
        final cmp = sb.compareTo(sa);
        if (cmp != 0) return cmp;
      }
      return (b.downloadBytes + b.uploadBytes)
          .compareTo(a.downloadBytes + a.uploadBytes);
    }

    vpn.sort(byRecent);
    blocked.sort(byRecent);
    direct.sort(byRecent);

    return LiveConnectionsSnapshot(
      vpn: vpn,
      blocked: blocked,
      direct: direct,
    );
  }
}

/// Определяет маршрут соединения по цепочке outbound-ов и правилу ядра.
LiveRouteKind classifyConnectionRoute({
  required List<String> chains,
  required String rule,
  required String host,
  required int port,
  SplitTunnelConfig? split,
}) {
  final lowerChains = [for (final c in chains) c.toLowerCase()];
  final lowerRule = rule.toLowerCase();

  for (final c in lowerChains) {
    if (c == 'block' ||
        c == 'blocked' ||
        c == 'reject' ||
        c == 'blackhole' ||
        c.startsWith('block-')) {
      return LiveRouteKind.blocked;
    }
  }
  if (lowerRule.contains('reject') || lowerRule.contains('action=block')) {
    return LiveRouteKind.blocked;
  }

  // В sing-box 1.11+ действие `action: reject` на правиле может давать пустой
  // `chains`: сверяем с наиболее конкретным доменным правилом.
  if (lowerChains.isEmpty && host.isNotEmpty && split != null) {
    final matched = mostSpecificSiteRule(split.sites, host, port: port);
    if (matched != null && matched.action == AppAction.block) {
      return LiveRouteKind.blocked;
    }
  }

  for (final c in lowerChains) {
    if (c == 'direct' ||
        c == 'bypass' ||
        c == 'dns-local' ||
        c.startsWith('direct-')) {
      return LiveRouteKind.direct;
    }
  }

  return LiveRouteKind.vpn;
}

/// Находит наиболее конкретное правило сайта для пары ([host], [port]).
SiteRule? mostSpecificSiteRule(
  List<SiteRule> sites,
  String host, {
  int port = 0,
}) {
  final h = _cleanHost(host);
  if (h.isEmpty) return null;
  SiteRule? best;
  for (final r in sites) {
    final d = r.domain.trim().toLowerCase();
    if (d.isEmpty) continue;
    if (h != d && !h.endsWith('.$d')) continue;
    if (r.port != null && port > 0 && r.port != port) continue;
    if (r.port != null && port <= 0) continue;
    if (best == null) {
      best = r;
      continue;
    }
    final bestLen = best.domain.trim().length;
    if (d.length > bestLen ||
        (d.length == bestLen && r.port != null && best.port == null)) {
      best = r;
    }
  }
  return best;
}

/// Отпечаток доменных правил маршрутизации, запечённых в конфиг туннеля.
///
/// Используется для сверки того, менял ли пользователь правила раздельного
/// туннелирования ПОСЛЕ подъёма текущего туннеля.
String splitRoutingSignature(
  SplitTunnelConfig split, {
  required bool noRealIp,
}) {
  final buf = StringBuffer('${split.mode.name}|$noRealIp');
  for (final s in split.sites) {
    buf.write(
      '|s:${s.domain.toLowerCase()}:${s.port ?? ''}:${s.action.name}:'
      '${s.allowRealIp}:${s.serverKey ?? ''}',
    );
  }
  for (final a in split.apps) {
    if (!a.enabled) continue;
    buf.write(
      '|a:${a.matchKey}:${a.action.name}:'
      '${a.allowRealIp}:${a.overrideSites}:${a.serverKey ?? ''}',
    );
  }
  return buf.toString();
}

/// Проверяет, есть ли среди открытых соединений домен, чей фактический маршрут
/// расходится с актуальным списком сайтов [split] (например, сайт добавили при
/// поднятом туннеле, а открытое соединение всё ещё идёт напрямую мимо VPN).
///
/// Возвращает имя домена правила, вызвавшего расхождение, либо `null`.
String? detectRoutingMismatch(
  LiveConnectionsSnapshot snapshot,
  SplitTunnelConfig split, {
  required bool noRealIp,
}) {
  if (split.mode == SplitMode.all || split.sites.isEmpty) return null;

  final overrideApps = <String>{
    for (final a in split.apps)
      if (a.enabled && (a.overrideSites || a.action == AppAction.block))
        a.name.toLowerCase(),
  };

  final all = <LiveConnectionEntry>[
    ...snapshot.direct,
    ...snapshot.vpn,
    ...snapshot.blocked,
  ];

  for (final conn in all) {
    if (conn.host.isEmpty) continue;
    if (conn.process.isNotEmpty &&
        overrideApps.contains(conn.process.toLowerCase())) {
      continue;
    }
    final rule =
        mostSpecificSiteRule(split.sites, conn.host, port: conn.destinationPort);
    if (rule == null) continue;

    final LiveRouteKind expected = switch (rule.action) {
      AppAction.tunnel => LiveRouteKind.vpn,
      AppAction.block => LiveRouteKind.blocked,
      AppAction.direct => (noRealIp && !rule.allowRealIp)
          ? LiveRouteKind.vpn
          : LiveRouteKind.direct,
    };

    // Служебные отказы по обходным протоколам (QUIC UDP:443, DoT/DoQ :853,
    // выключенный IPv6) намеренно переводят клиент на основной стек и не
    // означают устаревший список маршрутов.
    if (conn.route == LiveRouteKind.blocked &&
        expected != LiveRouteKind.blocked) {
      if ((conn.network == 'udp' && conn.destinationPort == 443) ||
          conn.destinationPort == 853 ||
          conn.destinationIp.contains(':')) {
        continue;
      }
    }

    if (conn.route != expected) {
      return rule.domain;
    }
  }
  return null;
}

/// Клиент Clash API (`GET /connections`) для опроса текущих открытых соединений.
class LiveConnectionsClient {
  const LiveConnectionsClient();

  Future<LiveConnectionsSnapshot?> fetch(
    LiveCoreApi api, {
    SplitTunnelConfig? split,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    if (api.port <= 0) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800)
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:${api.port}/connections'))
          .timeout(timeout);
      if (api.secret.isNotEmpty) {
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${api.secret}');
      }
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      return LiveConnectionsSnapshot.fromClashJson(decoded, split: split);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Принудительно закрывает одно соединение по [id] (`DELETE /connections/{id}`).
  Future<bool> closeConnection(
    LiveCoreApi api,
    String id, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final trimmed = id.trim();
    if (api.port <= 0 || trimmed.isEmpty) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800)
      ..findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri.parse(
        'http://127.0.0.1:${api.port}/connections/${Uri.encodeComponent(trimmed)}',
      );
      final req = await client.deleteUrl(uri).timeout(timeout);
      if (api.secret.isNotEmpty) {
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${api.secret}');
      }
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>().timeout(timeout);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Принудительно закрывает набор соединений и возвращает число закрытых сокетов.
  Future<int> closeConnections(
    LiveCoreApi api,
    Iterable<String> ids, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final unique = ids.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (api.port <= 0 || unique.isEmpty) return 0;
    var closed = 0;
    const chunkSize = 8;
    for (var i = 0; i < unique.length; i += chunkSize) {
      final end = (i + chunkSize < unique.length) ? i + chunkSize : unique.length;
      final results = await Future.wait(
        [for (final id in unique.sublist(i, end)) closeConnection(api, id, timeout: timeout)],
      );
      for (final ok in results) {
        if (ok) closed++;
      }
    }
    return closed;
  }
}

String _cleanHost(String raw) {
  var h = raw.trim().toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h;
}

int _parseInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

String _basename(String raw) {
  if (raw.isEmpty) return '';
  final norm = raw.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx >= 0 ? norm.substring(idx + 1) : norm;
}

bool _isInternalLoopback({
  required String host,
  required String dstIp,
  required String process,
}) {
  final procLower = process.toLowerCase();
  // Собственные процессы приложения и ядер уводятся в `direct` защитой от
  // петли (`SingboxConfigBuilder` эшелон 2): загрузка фавиконок, проверки
  // канала и транспорт обхода белых списков — служебный трафик, а не утечка.
  if (procLower == 'xray.exe' ||
      procLower == 'xray' ||
      procLower == 'sing-box.exe' ||
      procLower == 'sing-box' ||
      procLower == 'silentgate.exe' ||
      procLower == 'silentgate' ||
      procLower == 'silentgate-tun.exe' ||
      procLower == 'whitelist-bypass.exe' ||
      procLower == 'whitelist-bypass') {
    return true;
  }
  if (host.isEmpty && (dstIp == '127.0.0.1' || dstIp == '::1')) {
    return true;
  }
  return false;
}

