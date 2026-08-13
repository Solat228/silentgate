import 'dart:convert';

import '../models/vpn_server.dart';
import '../util/key_migration.dart';

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
    final proxies = _proxyOutbounds(cfg);
    if (proxies.isEmpty) return null;

    // Первый по тегу 'proxy', иначе просто первый — он даёт поля для отображения.
    final proxy = proxies.firstWhere((o) => '${o['tag']}' == 'proxy',
        orElse: () => proxies.first);
    final remark = _remarkOf(cfg, proxies);

    final base = fromOutbound(proxy, remark: remark);
    if (base == null) return null;
    if (!isComplexProfile(cfg, proxyCount: proxies.length)) return base;

    // «Авто …»: конфиг применяется целиком, иначе теряются десятки серверов
    // и весь балансировщик. Ключ — имя профиля ПЛЮС отпечаток подписки
    // (см. [panelKey]); состав outbound'ов в него не входит, потому что панель
    // тасует его при каждом обновлении.
    final key = panelKeyOf(cfg);
    // Данные, записанные до 1.4.2, лежат по ключу из ОДНОГО имени. Чтобы они не
    // осиротели, каждое построение ключа заодно объявляет старое написание
    // псевдонимом нового — переносом занимается KeyMigration при загрузке.
    KeyMigration.registerPanelKey(panelKey(remark), key);
    return base.copyWith(
      rawPanelConfig: jsonEncode(cfg),
      rawLink: key,
    );
  }

  /// Прокси-outbound'ы конфига (служебные freedom/blackhole/dns — не в счёт).
  static List<Map<String, dynamic>> _proxyOutbounds(Map<String, dynamic> cfg) {
    final outbounds = cfg['outbounds'];
    if (outbounds is! List) return const [];
    final proxies = <Map<String, dynamic>>[];
    for (final o in outbounds) {
      if (o is! Map) continue;
      final proto = '${o['protocol']}';
      if (proto == 'freedom' || proto == 'blackhole' || proto == 'dns') continue;
      proxies.add(o.cast<String, dynamic>());
    }
    return proxies;
  }

  /// Имя профиля. ⚠️ Считается ОДНИМ кодом для сервера и для ключа: разъедься
  /// они хоть в запасной ветке (`remarks` нет — берётся тег outbound'а), и
  /// профиль после перезапуска искал бы свои пинги не по тому ключу.
  static String _remarkOf(
      Map<String, dynamic> cfg, List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) return '${cfg['remarks'] ?? 'Сервер'}';
    final proxy = proxies.firstWhere((o) => '${o['tag']}' == 'proxy',
        orElse: () => proxies.first);
    return '${cfg['remarks'] ?? proxy['tag'] ?? 'Сервер'}';
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
  ///
  /// ⚠️ ПОЧЕМУ ОДНОГО ИМЕНИ НЕ ХВАТИЛО. Панель называет профили одинаково во
  /// ВСЕХ подписках («Авто (YouTube)» и т. п.), а подписок у человека бывает
  /// несколько. Ключ из одного имени означал, что профиль второй подписки и
  /// профиль первой — это ОДИН сервер: результат пинга, ручная правка и
  /// сохранённый конфиг панели писались друг поверх друга, пинг профиля B мог
  /// уйти конфигом A, и зелёная плашка появлялась на профиле, который никто не
  /// проверял. У обычного сервера такого не бывает — его ключ это share-ссылка,
  /// а в ней лежат учётные данные подписки; профиль «Авто» терял их целиком.
  /// [scope] возвращает ровно эту различающую часть (см. [panelScope]).
  ///
  /// Пустой [scope] даёт СТАРОЕ написание `panel://<имя>` — по нему лежат данные,
  /// записанные до 1.4.2, и оно остаётся действующим (перенос — [KeyMigration]).
  static String panelKey(String remark, {String? scope}) {
    final base = 'panel://${Uri.encodeComponent(remark.trim())}';
    final s = (scope ?? '').trim();
    return s.isEmpty ? base : '$base?sub=$s';
  }

  /// Ключ профиля по его полному конфигу — ЕДИНСТВЕННАЯ точка вычисления и для
  /// разбора свежей подписки, и для восстановления с диска ([fromPanelConfig]),
  /// и для переноса старых ключей ([registerLegacyPanelKeys]).
  static String panelKeyOf(Map<String, dynamic> cfg) {
    final proxies = _proxyOutbounds(cfg);
    return panelKey(_remarkOf(cfg, proxies), scope: panelScope(cfg));
  }

  /// Отпечаток подписки, которой принадлежит конфиг: 8 hex от учётных данных.
  ///
  /// Учётные данные (uuid VLESS/VMess, пароль trojan/ss, auth hysteria2) у
  /// Remnawave выдаются ПОЛЬЗОВАТЕЛЮ, а не узлу: во всех outbound'ах подписки
  /// они одни и те же и переживают обновление списка серверов.
  ///
  /// ⚠️ БЕРЁТСЯ НАИМЕНЬШЕЕ ПО АЛФАВИТУ ИЗ РАЗЛИЧНЫХ ЗНАЧЕНИЙ, А НЕ САМОЕ ЧАСТОЕ.
  /// «Самое частое» держалось ровно до первой перетасовки состава. Учётное
  /// значение в профиле не обязано быть одно: uuid у vless/vmess и пароль у
  /// trojan/ss — разные строки, а профиль автовыбора собирает узлы разных
  /// протоколов. Стоило панели прислать одних узлов больше, чем других, как
  /// побеждало другое значение, отпечаток менялся и ключ профиля «уезжал»
  /// целиком — ровно та болезнь, которую этот ключ лечит. От количеств минимум
  /// не зависит вовсе, от порядка outbound'ов — тоже.
  ///
  /// ⚠️ Разбор учётных данных ниже понимает и hysteria2, но в профиле панели
  /// такой узел не наблюдался и наблюдаться не должен: профиль всегда поднимает
  /// Xray (`VpnServer.core`), а Xray hysteria2 не умеет. Ветка оставлена как
  /// страховка для чужих конфигов, а не как описание поведения Remnawave.
  ///
  /// ⚠️ И ЧЕГО ЭТО НЕ ДАЁТ: полной неизменности. Исчезни из профиля протокол,
  /// чей секрет был наименьшим, — отпечаток сменится, и данные профиля осиротеют
  /// (спасёт только псевдоним, а его завести будет не из чего). Устойчивость к
  /// ПЕРЕТАСОВКЕ состава доказана тестом; большего здесь не обещается.
  ///
  /// ⚠️ ХЭШ, А НЕ САМИ ДАННЫЕ: ключ сервера попадает в правила раздельного
  /// туннелирования, в ответы локального API и в отчёты — пароль подписки там
  /// не место.
  static String panelScope(Map<String, dynamic> cfg) {
    String? best;
    for (final out in _proxyOutbounds(cfg)) {
      for (final c in _credentialsOf(out)) {
        final cur = best;
        if (cur == null || c.compareTo(cur) < 0) best = c;
      }
    }
    final min = best;
    return min == null ? '' : _fnv32(min);
  }

  /// Учётные данные из одного outbound'а — всё, чем подписка отличается от
  /// чужой. Форм несколько, потому что протоколы кладут секрет в разные места.
  static List<String> _credentialsOf(Map<String, dynamic> out) {
    final settings =
        (out['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final creds = <String>[];
    void add(Object? v) {
      final s = v == null ? '' : '$v';
      if (s.isNotEmpty) creds.add(s);
    }

    final vnext = settings['vnext'];
    if (vnext is List) {
      for (final v in vnext) {
        final users = v is Map ? v['users'] : null;
        if (users is! List) continue;
        for (final u in users) {
          if (u is Map) add(u['id'] ?? u['password']);
        }
      }
    }
    final servers = settings['servers'];
    if (servers is List) {
      for (final v in servers) {
        if (v is Map) add(v['password']);
      }
    }
    // hysteria2 от Remnawave: пароль лежит не в vnext/servers, а рядом.
    final hy = ((out['streamSettings'] as Map?)?['hysteriaSettings'] as Map?)
        ?.cast<String, dynamic>();
    add(hy?['auth']);
    add(hy?['auth_str']);
    add(settings['auth']);
    add(settings['password']);
    return creds;
  }

  /// FNV-1a 32 бит, восемь hex — та же схема, что у тегов выходов
  /// (`core/singbox/exit_tags.dart`). ⚠️ Маска обязательна: в Dart int
  /// 64-битный, без неё хэш разъедется с любой другой реализацией.
  static String _fnv32(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Объявить псевдонимами ключи профилей, записанные до 1.4.2, по снимку
  /// сохранённых конфигов панели (содержимое `panel_outbounds.json`).
  ///
  /// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ВХОД, ЕСЛИ ПСЕВДОНИМ ОБЪЯВЛЯЕТСЯ И ПРИ РАЗБОРЕ. Разбор
  /// свежей подписки — это поход в сеть, и до него старые данные с диска уже
  /// прочитаны и мигрированы. Зовёт этот вход `PanelOutboundsStore.load()` —
  /// прямо на сыром содержимом файла, ДО переноса ключей и до того, как
  /// `AppState` прочитает правки серверов, список серверов подписки и пины.
  /// Порядок задан явно (`AppState.init`), а не сложился сам.
  /// Возвращает число объявленных псевдонимов.
  static int registerLegacyPanelKeys(Map<String, dynamic> stored) {
    var found = 0;
    stored.forEach((key, value) {
      if (!key.startsWith('panel://')) return;
      final raw = value is Map ? value['config'] : null;
      if (raw is! String || raw.isEmpty) return;
      try {
        final cfg = jsonDecode(raw);
        if (cfg is! Map) return;
        final canonical = panelKeyOf(cfg.cast<String, dynamic>());
        if (canonical == key) return;
        KeyMigration.registerPanelKey(key, canonical);
        found++;
      } catch (_) {
        // Битый конфиг — не повод ронять загрузку: ключ просто останется старым.
      }
    });
    return found;
  }

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
