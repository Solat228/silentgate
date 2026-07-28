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

  /// Туннель создаёт платформа (Android `VpnService`), а не ядро.
  ///
  /// Меняет три вещи, каждая из которых иначе валит подключение:
  ///  * из TUN-инбаунда уходят `interface_name`, `auto_route`, `strict_route`
  ///    и `stack` — интерфейсом владеет система, ядро эти поля для
  ///    платформенного туннеля не принимает;
  ///  * появляются `include_package`/`exclude_package` — способ развести
  ///    приложения на Android (аналога process_name там нет);
  ///  * правила по именам процессов Windows не пишутся вовсе: `xray.exe` на
  ///    Android не совпадёт ни с чем.
  final bool platformTun;

  /// Пакет самого приложения — обязан идти мимо туннеля, иначе загрузка
  /// подписки и пинг уходят в собственный VPN (петля и ложные цифры).
  final String selfPackage;

  /// Файл, куда ядро пишет СВОЙ лог (`log.output`).
  ///
  /// ⚠️ Нужен на Android. Там ядро — библиотека в нашем же процессе, стандартный
  /// вывод перехватить нечем: `Libbox.redirectStderr` ловит ТОЛЬКО паники Go, а
  /// структурный лог sing-box туда не попадает. Живой запуск это подтвердил:
  /// при уровне `debug` файл оставался нулевого размера, и причину «туннель
  /// поднят, но трафика нет» посмотреть было негде.
  /// На Windows не нужен: там ядро — отдельный процесс, и его stdout читает
  /// `SingboxProcess`.
  final String? logOutput;

  /// Резолвер для доменов «Прямо» — ЯВНЫМ адресом (обычно DNS физического
  /// адаптера, снятый до подъёма туннеля).
  ///
  /// ⚠️ Почему нельзя оставлять `address: "local"`. На Windows это
  /// `getaddrinfo` → служба DNS-клиента → пакет уходит в TUN → попадает под
  /// `hijack-dns` → снова приходит в `dns-local`. Домен «Прямо» не резолвится
  /// вовсе: в логе `lookup <домен>: i/o timeout`, затем `name error`.
  /// Подтверждено живым тестом: сайт «Туннель» открывался, «Блок» блокировался,
  /// а «Прямо» — не открывался НИКАК. `detour: direct` тут не помогает:
  /// транспорт `local` вообще не дозванивается через outbound.
  /// Пусто → прежнее поведение (`local`).
  final String? directDnsUpstream;

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
    this.platformTun = false,
    this.selfPackage = 'lol.silentgate',
    this.directDnsUpstream,
    this.logOutput,
  });

  factory TunOptions.fromSettings(
    AppSettings s, {
    List<String> serverIps = const [],
    bool android = false,
    String? directDnsUpstream,
    String? logOutput,
  }) {
    return TunOptions(
      platformTun: android,
      directDnsUpstream: directDnsUpstream,
      logOutput: logOutput,
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
  ///
  /// ⚠️ Любое новое поле обязано попасть сюда. Автоподбор стека/MTU — это
  /// ДЕФОЛТ (`tunStack: auto`), и он пересоздаёт опции на каждой комбинации:
  /// забытое поле молча исчезает именно у большинства пользователей.
  /// Так уже терялись `platformTun` и `selfPackage` — на Android это ломало
  /// весь платформенный туннель при первом же переборе.
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
        platformTun: platformTun,
        selfPackage: selfPackage,
        directDnsUpstream: directDnsUpstream,
        logOutput: logOutput,
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
      // ⚠️ ПОРЯДОК: loop-protection стоит ВЫШЕ перехвата DNS.
      //
      // Раньше `hijack-dns` был первым, и под него попадал в том числе DNS
      // НАШИХ ЖЕ ядер. Отсюда два подтверждённых живым тестом отказа:
      //  * прокси-ядро (hysteria2) не могло отрезолвить адрес своего сервера —
      //    запрос уходил в туннель и возвращался в это же ядро (взаимный
      //    дедлок: `lookup <сервер>: i/o timeout` в одном логе и
      //    `dns: exchange failed … EOF` в другом, секунда в секунду);
      //  * домен, помеченный «Прямо», не резолвился вовсе — `dns-local`
      //    закольцовывался на системный резолвер через тот же перехват.
      // Ценой этого DNS самих ядер идёт мимо туннеля — но именно это и значит
      // «прямо», а системный DNS остальных приложений перехватывается как был.
      //
      // 1-й эшелон: сам VPN-сервер.
      if (o.serverIps.isNotEmpty)
        _route({'ip_cidr': [for (final ip in o.serverIps) _asCidr(ip)]}, 'direct'),
      // 2-й эшелон: процессы ядра. На Android имён процессов нет — там свой
      // пакет уже исключён из туннеля на уровне ОС (exclude_package), а
      // process_name со значением 'xray.exe' не совпал бы ни с чем.
      if (!o.platformTun)
        _route({
          'process_name': ['xray.exe', 'sing-box.exe', 'silentgate.exe'],
        }, 'direct'),
      if (o.dnsHijack && o.dnsMode != DnsMode.system)
        // Перехват UDP:53 — без него DNS уходит в final и «интернет пропадает»,
        // если UDP до сервера не проксируется.
        {'protocol': 'dns', 'action': 'hijack-dns'},
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
      'log': {
        'level': o.logLevel,
        'timestamp': true,
        if ((o.logOutput ?? '').isNotEmpty) 'output': o.logOutput,
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          // Имя интерфейса, автомаршруты, strict_route и выбор стека имеют смысл
          // только когда туннель создаёт САМО ядро. На Android его создаёт
          // VpnService, и эти поля ядро для платформенного туннеля не принимает.
          if (!o.platformTun) ...{
            'interface_name': 'silentgate-tun',
            'auto_route': true,
            'strict_route': o.strictRoute,
            if (o.stack != null) 'stack': o.stack,
          },
          // ⚠️ Стек указываем и на Android — он про ОБРАБОТКУ пакетов из
          // дескриптора, а не про то, кто создал интерфейс.
          //
          // По умолчанию ядро берёт стек, который на Android пытается привязать
          // форвардер к интерфейсу (`SO_BINDTODEVICE`), а это требует прав,
          // которых у приложения нет. В логе: «bind forwarder to interface:
          // operation not permitted», и TCP-соединения не форвардятся вовсе,
          // хотя DNS (UDP) при этом работает. gVisor обрабатывает всё в
          // пользовательском пространстве, привязка ему не нужна.
          if (o.platformTun) 'stack': o.stack ?? 'gvisor',
          'address': [
            '172.19.0.1/30',
            if (o.ipv6) 'fdfe:dcba:9876::1/126',
          ],
          'mtu': o.mtu,
          'endpoint_independent_nat': o.endpointIndependentNat,
          if (_validExcludeCidrs.isNotEmpty)
            'route_exclude_address': _validExcludeCidrs,
          // Разведение приложений на Android идёт пакетами, а не процессами.
          //
          // ⚠️ include_package и exclude_package ВЗАИМОИСКЛЮЧАЮЩИЕ. Раньше при
          // «только выбранные» отдавались ОБА: exclude всегда содержал хотя бы
          // свой пакет. `VpnService.Builder` такого не принимает —
          // addDisallowedApplication после addAllowedApplication бросает
          // UnsupportedOperationException, и туннель не поднимался вовсе.
          // Когда список include непуст, exclude не нужен по построению: в
          // туннель идут ТОЛЬКО перечисленные, всё прочее (включая нас) и так
          // мимо.
          if (o.platformTun) ..._packageLists(split, o),
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

    final dns = _buildDns(finalOutbound, split);
    if (dns != null) cfg['dns'] = dns;
    return cfg;
  }

  /// DNS-секция. Без неё запросы идут от svchost.exe в `final` и режут интернет,
  /// когда UDP до сервера не проксируется (частый случай VLESS+Vision).
  Map<String, dynamic>? _buildDns(String finalOutbound, SplitTunnelConfig split) {
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
      // Явный апстрим вместо `local`: см. TunOptions.directDnsUpstream —
      // системный резолвер под TUN закольцовывается на самого себя, и домены
      // «Прямо» не резолвятся вовсе.
      {
        'tag': 'dns-local',
        'address': (o.directDnsUpstream ?? '').isNotEmpty
            ? 'udp://${o.directDnsUpstream}'
            : 'local',
        'detour': 'direct',
      },
    ];

    // Доменные правила ЗЕРКАЛЯТСЯ из маршрутов. Без них весь DNS уходил в
    // dns-proxy (`final`), и сайт, помеченный «Прямо», резолвился резолвером
    // выходного узла: CDN отдавал адрес в стране VPN, а сам запрос всё равно
    // раскрывался провайдеру туннеля. Правило `outbound: direct` ниже в
    // TUN-режиме не срабатывает никогда (назначение из TUN — всегда IP, имя
    // берётся только из сниффинга), поэтому одного его недостаточно.
    final rules = <Map<String, dynamic>>[
      // Блок — выше остальных: заблокированный домен не должен даже резолвиться.
      ..._dnsSiteRules(split, AppAction.block, null),
      ..._dnsSiteRules(split, AppAction.direct, 'dns-local', allowRealIp: true),
      ..._dnsSiteRules(split, AppAction.tunnel, 'dns-proxy'),
      if (o.noRealIp)
        // Возвращённые под защиту — резолвим через туннель, иначе прямой
        // резолв выдал бы реальную геолокацию ещё до соединения.
        ..._dnsSiteRules(split, AppAction.direct, 'dns-proxy', allowRealIp: false),
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

  /// DNS-правила для сайтов с действием [action]: домены резолвит [server]
  /// (null → `action: reject`, домен не резолвится вовсе).
  ///
  /// ⚠️ Правила С ПОРТОМ в зеркало НЕ попадают. Резолв идёт ДО выбора порта, а
  /// `domain_suffix` в DNS-правиле про порт ничего не знает — правило вида
  /// «блокировать example.com:8443» убило бы резолв ВСЕГО домена, хотя маршрут
  /// блокирует только один порт (то же и для «Прямо»: резолв всего домена
  /// уехал бы к локальному резолверу). Маршрутизация таких правил по-прежнему
  /// точная, страдает только зеркалирование — и это верный размен.
  List<Map<String, dynamic>> _dnsSiteRules(
      SplitTunnelConfig split, AppAction action, String? server,
      {bool? allowRealIp}) {
    // Зеркало обязано повторять маршруты: в режиме «Всё через VPN» правил в
    // маршрутах нет, значит и в DNS их быть не должно (иначе домен «Прямо»
    // резолвился бы локально при затуннелированном трафике).
    if (!_userRulesActive(split)) return const [];
    var matched = split.sites.where((s) => s.action == action && s.port == null);
    if (allowRealIp != null && options.noRealIp) {
      matched = matched.where((s) => s.allowRealIp == allowRealIp);
    }
    // Пустой домен свалил бы весь конфиг: ядро отвергает его целиком.
    final domains =
        matched.map((s) => s.domain.trim()).where((d) => d.isNotEmpty).toSet().toList();
    if (domains.isEmpty) return const [];
    return [
      {
        'domain_suffix': domains,
        if (server == null) 'action': 'reject' else 'server': server,
      },
    ];
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
    if (!_userRulesActive(split)) return;
    _addActionRule(rules, split, AppAction.block, null);
    _addSiteRule(rules, split, AppAction.block, null);
  }

  /// В режиме «Всё через VPN» пользовательские правила НЕ применяются.
  ///
  /// Интерфейс в этом режиме прячет списки приложений и сайтов и обещает, что
  /// весь трафик идёт в туннель. Правила при этом сохраняются (переключение
  /// режима их не теряет), но в конфиг попадать не должны: иначе сохранённое
  /// «Прямо» продолжало бы прорезать дыру в туннеле — трафик и DNS уходили бы
  /// мимо VPN, а пользователь об этом не узнал бы, потому что правил не видно.
  /// Особенно остро после 1.0.1, где «Прямо» снова означает именно «прямо».
  bool _userRulesActive(SplitTunnelConfig split) =>
      split.mode != SplitMode.all;

  void _addAppRules(List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    if (!_userRulesActive(split)) return;
    // «Прямо» при включённом noRealIp расходится надвое: правила с поднятой
    // галочкой «разрешить реальный IP» идут действительно напрямую (пользователь
    // задал их явно), остальные возвращаются под защиту — через VPN.
    //
    // ⚠️ ИНВАРИАНТ: ВСЕ доменные правила стоят выше ВСЕХ правил приложений
    // (#3.5) — правило сайта конкретнее, чем «всё приложение целиком», а
    // sing-box берёт ПЕРВОЕ совпадение. Разделение «Прямо» надвое обязано его
    // сохранять: если дописать «возвращённые под защиту» в хвост, такой сайт
    // проиграет любому приложению с действием «Прямо» и уйдёт под реальным IP —
    // ровно то, от чего пользователь защищался, снимая галочку.
    // Внутри каждой группы порядок безразличен: наборы правил не пересекаются
    // (фильтр по allowRealIp разводит их по разным подмножествам).
    _addSiteRule(rules, split, AppAction.direct, 'direct', allowRealIp: true);
    if (options.noRealIp) {
      _addSiteRule(rules, split, AppAction.direct, 'proxy', allowRealIp: false);
    }
    _addSiteRule(rules, split, AppAction.tunnel, 'proxy');

    _addActionRule(rules, split, AppAction.direct, 'direct', allowRealIp: true);
    if (options.noRealIp) {
      _addActionRule(rules, split, AppAction.direct, 'proxy', allowRealIp: false);
    }
    _addActionRule(rules, split, AppAction.tunnel, 'proxy');
  }

  /// Домены с действием [action]. Сайты без порта — одним правилом; сайты с
  /// портом — отдельным правилом на каждый порт (domain_suffix + port вместе
  /// = совпадение по домену И порту). [outbound] == null → reject.
  ///
  /// [allowRealIp] отбирает подмножество правил «Прямо» при включённом
  /// `noRealIp`; при выключенном отбор не нужен — прямое правило и так прямое.
  void _addSiteRule(List<Map<String, dynamic>> rules, SplitTunnelConfig split,
      AppAction action, String? outbound, {bool? allowRealIp}) {
    var matched = split.sites.where((s) => s.action == action);
    if (allowRealIp != null && options.noRealIp) {
      matched = matched.where((s) => s.allowRealIp == allowRealIp);
    }
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
      AppAction action, String? outbound, {bool? allowRealIp}) {
    // Выключенные правила не применяются (галочка снята).
    var apps = split.apps.where((a) => a.enabled && a.action == action);
    if (allowRealIp != null && options.noRealIp) {
      apps = apps.where((a) => a.allowRealIp == allowRealIp);
    }
    // ⚠️ Android ищет приложение по ИМЕНИ ПАКЕТА: полей process_name и
    // process_path на нём нет вовсе (ядро получает от VpnService только uid и
    // отдаёт его как package_name). Раньше ветки по платформе не было, поэтому
    // в конфиг уезжали 'chrome.exe' и regex по путям Windows — они не совпадали
    // НИ С ЧЕМ. Правила приложений на Android не работали в принципе, а «Блок»
    // при этом молча пропускал трафик, хотя интерфейс показывал блокировку.
    if (options.platformTun) {
      final pkgs = apps
          .map((a) => a.path.trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
      if (pkgs.isNotEmpty) {
        rules.add(_action({'package_name': pkgs}, outbound));
      }
      return;
    }

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

  /// Пакеты, идущие МИМО туннеля (действие «Прямо»).
  ///
  /// ⚠️ При `noRealIp` пользовательские «Прямо»-приложения сюда НЕ попадают:
  /// исключённый на уровне ОС пакет ядро не увидит, и его трафик пойдёт под
  /// реальным IP — ровно та утечка, которую чинили на Windows (0.12.0).
  /// Там они остаются в туннеле, а правило `package_name → proxy` уводит их
  /// через VPN.
  List<String> _excludePackages(SplitTunnelConfig split, TunOptions o) {
    final out = <String>{o.selfPackage};
    // ⚠️ Режим «Всё через VPN» обязан быть здесь ТОЖЕ.
    //
    // Это была настоящая дыра: правила из маршрутов мы вырезали
    // (`_userRulesActive`), а из пакетных списков — нет. Сохранённое
    // «Прямо»-приложение продолжало уезжать в `exclude_package`, и
    // `VpnService` выводил его из туннеля НА УРОВНЕ ОС — трафик шёл под
    // реальным IP. Заметить было нельзя ничем: правил в конфиге нет, списки
    // в интерфейсе скрыты, схема маршрута рисует простую цепочку.
    if (!_userRulesActive(split)) return out.toList();
    if (o.noRealIp) return out.toList();
    if (split.mode == SplitMode.onlySelected) return out.toList();
    for (final a in split.apps) {
      if (!a.enabled || a.action != AppAction.direct) continue;
      if (a.path.trim().isEmpty) continue;
      out.add(a.path.trim());
    }
    return out.toList();
  }

  /// Пакеты, которые единственные идут В туннель (режим «только выбранные»).
  ///
  /// Списки include и exclude в `VpnService.Builder` несовместимы: наличие
  /// хотя бы одного include уводит всё остальное мимо VPN. Поэтому здесь
  /// либо один, либо другой.
  /// Пакетные списки для `VpnService.Builder` — ровно ОДИН из двух.
  ///
  /// Непустой include побеждает: в туннель идут только перечисленные, всё
  /// остальное (включая наш собственный пакет) остаётся снаружи само собой.
  /// Пустой include в режиме «только выбранные» означал бы «в туннель не идёт
  /// никто», а `VpnService` без allowed-списка тянет туда ВСЁ, — поэтому там
  /// возвращаемся к exclude, чтобы хотя бы себя из туннеля вынуть.
  Map<String, dynamic> _packageLists(SplitTunnelConfig split, TunOptions o) {
    final include = _includePackages(split, o);
    if (include.isNotEmpty) return {'include_package': include};
    return {'exclude_package': _excludePackages(split, o)};
  }

  List<String> _includePackages(SplitTunnelConfig split, TunOptions o) {
    if (split.mode != SplitMode.onlySelected) return const [];
    final out = <String>{};
    for (final a in split.apps) {
      if (!a.enabled) continue;
      // ⚠️ «Блок» обязан попасть в туннель. Раньше он тут пропускался — и
      // заблокированное приложение оказывалось ВНЕ туннеля: ядро его трафика
      // не видело, правило `package_name → reject` совпасть не могло, и блок
      // молча разрешал соединение. Ровно тот дефект, который чинили для
      // остальных режимов, только в «только выбранных».
      // Внутри туннеля его убивает reject-правило — оно стоит выше всего
      // пользовательского.
      final pkg = a.path.trim();
      if (pkg.isNotEmpty) out.add(pkg);
    }
    return out.toList();
  }

}
