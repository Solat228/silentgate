import 'dart:convert';
import 'dart:io';

import '../settings/app_settings.dart';
import '../settings/split_tunnel.dart';

/// Параметры TUN-туннеля (всё, что настраивается пользователем + вычисляемое движком).
class TunOptions {
  /// Стек sing-box: 'system' | 'gvisor' | 'mixed'; null — дефолт ядра.
  final String? stack;
  final int mtu;
  final bool strictRoute;
  final bool ipv6;
  final bool endpointIndependentNat;
  final bool bypassLan;
  final List<String> excludeCidrs;

  final DnsMode dnsMode;
  final String dnsServer;
  final bool dnsHijack;
  final DnsStrategy dnsStrategy;
  final String logLevel;

  /// IP-адреса VPN-серверов: жёстко уводятся мимо туннеля, иначе трафик самого
  /// Xray к серверу вернётся в Xray — петля и мгновенная смерть сети.
  final List<String> serverIps;

  /// Пользователь выбрал стек «авто» — подбирать стек и MTU перебором,
  /// пока туннель не поднимется (см. [TunAutotune]).
  final bool autotune;

  /// «Не выходить под реальным IP»: пользовательские правила «Прямо» (direct)
  /// уводятся ЧЕРЕЗ VPN (proxy). Инфраструктурный direct (IP серверов, процессы
  /// ядра, приватная сеть) остаётся direct — иначе туннель не поднимется.
  final bool noRealIp;

  const TunOptions({
    this.stack,
    this.mtu = 1500,
    this.strictRoute = true,
    this.ipv6 = true,
    this.endpointIndependentNat = true,
    this.bypassLan = true,
    this.excludeCidrs = const [],
    this.dnsMode = DnsMode.vpn,
    this.dnsServer = '1.1.1.1',
    this.dnsHijack = true,
    this.dnsStrategy = DnsStrategy.preferIpv4,
    this.logLevel = 'warn',
    this.serverIps = const [],
    this.autotune = false,
    this.noRealIp = false,
  });

  factory TunOptions.fromSettings(AppSettings s, {List<String> serverIps = const []}) {
    return TunOptions(
      stack: s.tunStack.singboxValue,
      mtu: s.tunMtu,
      strictRoute: s.tunStrictRoute,
      ipv6: s.tunIpv6,
      endpointIndependentNat: s.tunEndpointIndependentNat,
      bypassLan: s.tunBypassLan,
      excludeCidrs: s.tunExcludeCidrs,
      dnsMode: s.dnsMode,
      dnsServer: s.dnsMode == DnsMode.custom ? s.dnsCustomServer : '1.1.1.1',
      dnsHijack: s.dnsHijack,
      dnsStrategy: s.dnsStrategy,
      logLevel: s.singboxLogLevel.name,
      serverIps: serverIps,
      // «Авто» = подбирать стек/MTU перебором; явный выбор пользователя уважаем.
      autotune: s.tunStack == TunStack.auto,
      noRealIp: s.noRealIp,
    );
  }

  /// Копия с другими стеком/MTU — для перебора в автоподборе.
  TunOptions copyWith({String? stack, int? mtu}) => TunOptions(
        stack: stack ?? this.stack,
        mtu: mtu ?? this.mtu,
        strictRoute: strictRoute,
        ipv6: ipv6,
        endpointIndependentNat: endpointIndependentNat,
        bypassLan: bypassLan,
        excludeCidrs: excludeCidrs,
        dnsMode: dnsMode,
        dnsServer: dnsServer,
        dnsHijack: dnsHijack,
        dnsStrategy: dnsStrategy,
        logLevel: logLevel,
        serverIps: serverIps,
        autotune: autotune,
        noRealIp: noRealIp,
      );
}

/// Строит конфиг sing-box для TUN-режима: sing-box держит TUN (wintun) и маршрутизацию
/// (по приложениям через process_*, по доменам через domain_suffix), а прокси-трафик
/// уходит в Xray через socks-outbound на локальный SOCKS Xray. Модель Happ.
///
/// Защита от петли — в три эшелона (по убыванию надёжности):
///   1. IP VPN-серверов → direct (не зависит от матчинга процессов);
///   2. собственные процессы ядра (xray/sing-box/silentgate) → direct;
///   3. приватные адреса → direct.
class SingboxConfigBuilder {
  final int xraySocksPort;
  final TunOptions options;

  /// Готовый прокси-outbound вместо перехода в локальный SOCKS.
  ///
  /// Windows: `null` — туннель заворачивает трафик в SOCKS, где его принимает
  /// отдельный процесс Xray (или sing-box для hysteria2).
  /// Android: сюда кладётся outbound сервера, и ядро одно — оно держит и
  /// туннель, и само соединение. Причина в том, что две gomobile-библиотеки
  /// в одном приложении конфликтуют общим Go-рантаймом.
  final Map<String, dynamic>? proxyOutbound;

  const SingboxConfigBuilder({
    this.xraySocksPort = 10808,
    this.options = const TunOptions(),
    this.proxyOutbound,
  });

  String buildJson(SplitTunnelConfig split) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(split));

  Map<String, dynamic> buildMap(SplitTunnelConfig split) {
    final o = options;

    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      if (o.dnsHijack && o.dnsMode != DnsMode.system)
        // Перехват UDP:53 — без него DNS уходит в final и «интернет пропадает»,
        // если UDP до сервера не проксируется.
        {'protocol': 'dns', 'action': 'hijack-dns'},
      // Loop-protection (выше даже блокировки): сам VPN-сервер и процессы ядра
      // ВСЕГДА мимо туннеля — их нельзя ни блокировать, ни заворачивать.
      // 1-й эшелон: сам VPN-сервер.
      if (o.serverIps.isNotEmpty)
        _route({'ip_cidr': [for (final ip in o.serverIps) _asCidr(ip)]}, 'direct'),
      // 2-й эшелон: процессы ядра.
      _route({
        'process_name': ['xray.exe', 'sing-box.exe', 'silentgate.exe'],
      }, 'direct'),
    ];

    // #3 — явный БЛОК ставим ВЫШЕ bypassLan/excludeCidr: блокировка домена должна
    // побеждать удобные direct-исключения (иначе заблокированный домен, чей IP
    // попал в приватный диапазон или в excludeCidr, молча уходил бы напрямую).
    _addBlockRules(rules, split);
    if (o.bypassLan) rules.add(_route({'ip_is_private': true}, 'direct'));
    // Только ВАЛИДНЫЕ CIDR: один битый префикс (напр. «10.0.0.0/33») заставляет
    // sing-box отвергнуть ВЕСЬ конфиг, и туннель молча не поднимается.
    if (_validExcludeCidrs.isNotEmpty) {
      rules.add(_route({'ip_cidr': _validExcludeCidrs}, 'direct'));
    }

    // База: куда идёт всё, чему не задано действие вручную.
    //  all / exceptSelected → через VPN (proxy); onlySelected → напрямую.
    final finalOutbound =
        split.mode == SplitMode.onlySelected ? 'direct' : 'proxy';
    _addAppRules(rules, split);

    final cfg = <String, dynamic>{
      'log': {'level': o.logLevel, 'timestamp': true},
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'silentgate-tun',
          'address': [
            '172.19.0.1/30',
            if (o.ipv6) 'fdfe:dcba:9876::1/126',
          ],
          'mtu': o.mtu,
          'auto_route': true,
          'strict_route': o.strictRoute,
          if (o.stack != null) 'stack': o.stack,
          'endpoint_independent_nat': o.endpointIndependentNat,
          if (_validExcludeCidrs.isNotEmpty)
            'route_exclude_address': _validExcludeCidrs,
        },
      ],
      'outbounds': [
        // Тег 'proxy' обязан сохраниться: на него ссылаются ВСЕ правила
        // маршрутизации ниже, включая noRealIp и реврайт direct→VPN.
        proxyOutbound != null
            ? {...proxyOutbound!, 'tag': 'proxy'}
            : {
                'type': 'socks',
                'tag': 'proxy',
                'server': '127.0.0.1',
                'server_port': xraySocksPort,
                'version': '5',
              },
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': finalOutbound,
        'rules': rules,
      },
    };

    final dns = _buildDns(finalOutbound);
    if (dns != null) cfg['dns'] = dns;
    return cfg;
  }

  /// DNS-секция. Без неё запросы идут от svchost.exe в `final` и режут интернет,
  /// когда UDP до сервера не проксируется (частый случай VLESS+Vision).
  Map<String, dynamic>? _buildDns(String finalOutbound) {
    final o = options;
    if (o.dnsMode == DnsMode.system) return null;

    // Резолвер туннеля: по TCP через прокси — работает даже там, где UDP не ходит.
    // Хост чистим: пустой/битый `dnsServer` дал бы `tcp://` и отказ всего конфига.
    final servers = <Map<String, dynamic>>[
      {
        'tag': 'dns-proxy',
        'address': 'tcp://${_dnsHost(o.dnsServer)}',
        'address_resolver': 'dns-local',
        'strategy': o.dnsStrategy.singboxValue,
        'detour': 'proxy',
      },
      {'tag': 'dns-local', 'address': 'local', 'detour': 'direct'},
    ];

    // Что уходит мимо VPN (direct-outbound) — резолвим локально; ВСЁ остальное,
    // включая явно затуннелированные приложения/сайты, — через прокси (dns-proxy).
    final rules = <Map<String, dynamic>>[
      {
        'outbound': ['direct'],
        'server': 'dns-local',
      },
    ];

    return {
      'servers': servers,
      'rules': rules,
      // ВСЕГДА dns-proxy по умолчанию: DNS через зашифрованный туннель не течёт
      // мимо VPN. Раньше в режиме onlySelected (finalOutbound=='direct') final
      // был dns-local, и DNS затуннелированных приложений резолвился локальным
      // (ISP) резолвером — утечка + отравление censorship. direct-домены всё так
      // же уходят в dns-local по правилу выше.
      'final': 'dns-proxy',
      'strategy': o.dnsStrategy.singboxValue,
      'independent_cache': true,
    };
  }

  /// Валидные CIDR из настроек (битые отбрасываем — иначе sing-box рвёт весь конфиг).
  List<String> get _validExcludeCidrs =>
      options.excludeCidrs.where(_isValidCidr).toList();

  /// Проверка «ip/префикс»: IPv4 (0..32) или IPv6 (0..128), адрес разбирается.
  static bool _isValidCidr(String cidr) {
    final parts = cidr.trim().split('/');
    if (parts.length != 2) return false;
    final addr = InternetAddress.tryParse(parts[0]);
    if (addr == null) return false;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0) return false;
    final max = addr.type == InternetAddressType.IPv6 ? 128 : 32;
    return prefix <= max;
  }

  /// Хост для DNS-резолвера. Пустой/битый → фолбэк 1.1.1.1; из URL/схемы берём хост.
  static String _dnsHost(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '1.1.1.1';
    // Пользователь мог вписать 'https://dns.google/...' или 'tcp://1.1.1.1'.
    s = s.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    s = s.split('/').first.split(RegExp(r'\s')).first;
    if (s.isEmpty) return '1.1.1.1';
    return s;
  }

  /// Правила по действиям приложений и сайтов. ПОРЯДОК = приоритет (первое
  /// совпадение выигрывает):
  ///  1) БЛОК (и приложения, и сайты) — всегда важнее всего. Иначе
  ///     «Туннель»-приложение перекрывало бы блок сайта: заблокированный сайт,
  ///     открытый в туннель-приложении, не блокировался (#3.5).
  ///  2) доменные правила (конкретнее, чем «всё приложение целиком»);
  ///  3) правила приложений; дальше — база (final).
  /// «Прямо» (direct): при [TunOptions.noRealIp] уводится ЧЕРЕЗ VPN (proxy),
  /// чтобы ничего не уходило под реальным IP; иначе — direct.
  /// БЛОК-правила (reject) — отдельно от остальных, чтобы поставить их выше
  /// bypassLan/excludeCidr (#3). Блок — через action: reject (в 1.11 outbound
  /// «block» устарел). Порядок: приложения, затем сайты.
  void _addBlockRules(List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    _addActionRule(rules, split, AppAction.block, null);
    _addSiteRule(rules, split, AppAction.block, null);
  }

  void _addAppRules(List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    final directOut = options.noRealIp ? 'proxy' : 'direct';
    _addSiteRule(rules, split, AppAction.direct, directOut);
    _addSiteRule(rules, split, AppAction.tunnel, 'proxy');
    _addActionRule(rules, split, AppAction.direct, directOut);
    _addActionRule(rules, split, AppAction.tunnel, 'proxy');
  }

  /// Домены с действием [action]. Сайты без порта — одним правилом; сайты с
  /// портом — отдельным правилом на каждый порт (domain_suffix + port вместе
  /// = совпадение по домену И порту). [outbound] == null → reject.
  void _addSiteRule(List<Map<String, dynamic>> rules, SplitTunnelConfig split,
      AppAction action, String? outbound) {
    final matched = split.sites.where((s) => s.action == action);
    final noPort = matched.where((s) => s.port == null).map((s) => s.domain).toList();
    if (noPort.isNotEmpty) {
      rules.add(_action({'domain_suffix': noPort}, outbound));
    }
    // Группируем по порту: один порт — одно правило с его доменами.
    final byPort = <int, List<String>>{};
    for (final s in matched.where((s) => s.port != null)) {
      byPort.putIfAbsent(s.port!, () => []).add(s.domain);
    }
    byPort.forEach((port, domains) {
      rules.add(_action({'domain_suffix': domains, 'port': [port]}, outbound));
    });
  }

  /// Одно правило для всех приложений с действием [action]. [outbound] == null →
  /// reject (блок). Приложения «по имени» и «по пути» — разными матчерами.
  void _addActionRule(List<Map<String, dynamic>> rules, SplitTunnelConfig split,
      AppAction action, String? outbound) {
    // Выключенные правила не применяются (галочка снята).
    final apps = split.apps.where((a) => a.enabled && a.action == action);
    final byName = apps.where((a) => a.byName).map((a) => a.name).toList();
    final byPath = apps.where((a) => !a.byName).map((a) => a.path).toList();
    if (byName.isNotEmpty) {
      rules.add(_action({'process_name': byName}, outbound));
    }
    if (byPath.isNotEmpty) {
      // process_path сравнивается ядром побайтово (регистр, короткие пути Windows) —
      // правило могло молча не срабатывать. process_path_regex с (?i) — надёжно.
      rules.add(_action({
        'process_path_regex': [for (final p in byPath) '(?i)^${_reEscape(p)}\$'],
      }, outbound));
    }
  }

  /// Правило маршрутизации в синтаксисе sing-box 1.11+ (`outbound` в правиле — deprecated).
  static Map<String, dynamic> _route(Map<String, dynamic> match, String outbound) =>
      {...match, 'action': 'route', 'outbound': outbound};

  /// route на [outbound], либо reject, если [outbound] == null (блокировка).
  static Map<String, dynamic> _action(
          Map<String, dynamic> match, String? outbound) =>
      outbound == null
          ? {...match, 'action': 'reject'}
          : _route(match, outbound);

  /// Одиночный IP → /32 или /128 (sing-box ждёт CIDR).
  static String _asCidr(String ip) {
    if (ip.contains('/')) return ip;
    return ip.contains(':') ? '$ip/128' : '$ip/32';
  }

  /// Экранирование пути для RE2 (Go regexp в sing-box): только реальные
  /// метасимволы — экранирование пробела и пр. RE2 считает ошибкой.
  static String _reEscape(String s) =>
      s.replaceAllMapped(RegExp(r'[.*+?^${}()|\[\]\\]'), (m) => '\\${m[0]}');
}
