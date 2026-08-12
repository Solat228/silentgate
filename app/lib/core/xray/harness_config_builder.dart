import 'dart:convert';

import '../models/vpn_server.dart';
// Гейт «действуют ли пользовательские правила вообще» — ОБЩИЙ с боевыми
// построителями. Своя копия условия разъехалась бы с ними на первой же правке.
import '../singbox/api_exit_guard.dart';
import '../settings/split_tunnel.dart';
import 'outbound_variant.dart';
import 'xray_outbound_factory.dart';

/// Порты проброс-харнесса (отдельный экземпляр Xray для пинга/проб).
class HarnessPorts {
  final int base;
  const HarnessPorts({this.base = 21000});
}

/// Кусок боевых настроек, который влияет на ДОСТИЖИМОСТЬ мишени пробы.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ ЕСТЬ. Харнесс строился голым шаблоном: один
/// http-inbound на кандидата и его outbound, больше ничего. Проба через такой
/// конфиг проходила там, где боевое подключение не работает, — и плашка пинга
/// горела зелёным при полностью нерабочем канале, а сервис-чипы у кнопки
/// Connect (они ходят через ЖИВОЕ ядро) в тот же момент были красными.
/// Требование владельца: «настоящий пинг — как если бы юзер включил VPN, зашёл
/// на сайт, и у него загрузилось или нет».
///
/// Сюда попадает только то, что реально меняет судьбу запроса к мишени:
/// правила по САЙТАМ и DNS. Правила по ПРИЛОЖЕНИЯМ неприменимы по построению —
/// у соединения, пришедшего в локальный прокси, нет процесса-владельца, ядро
/// сопоставлять его не с чем (та же причина, по которой правила приложений не
/// работают у системного прокси Windows).
///
/// ⚠️ ЧЕСТНАЯ ГРАНИЦА: даже с этими правилами проба идёт через прокси-порт, а
/// не через TUN-адаптер. Если ломается именно TUN, харнесс этого не увидит —
/// увидит только проверка активного сервера через живое ядро.
class HarnessRealism {
  /// Сайты с действием «Блок»: в бою они не открываются вовсе.
  final List<SiteRule> blocked;

  /// Сайты с действием «Прямо»: в бою идут мимо VPN.
  final List<SiteRule> direct;

  /// Свой DNS-сервер пользователя (только режим «свой»); пусто — как в боевом
  /// конфиге по умолчанию.
  final String dnsServer;

  /// `queryStrategy` Xray (`UseIPv4`/`UseIPv6`); null — не задавать.
  final String? queryStrategy;

  const HarnessRealism({
    this.blocked = const [],
    this.direct = const [],
    this.dnsServer = '',
    this.queryStrategy,
  });

  /// Настроек, влияющих на пробу, нет — конфиг харнесса остаётся прежним.
  static const none = HarnessRealism();

  bool get isEmpty =>
      blocked.isEmpty &&
      direct.isEmpty &&
      dnsServer.isEmpty &&
      queryStrategy == null;

  /// Выжимка из боевых правил раздельного туннелирования.
  ///
  /// ⚠️ Режим «Всё через VPN» пользовательских правил НЕ применяет — ни блока,
  /// ни «Прямо» (они сохранены, но в боевой конфиг не входят). Гейт спрашиваем
  /// у [userRulesActive], того же, что решает это в боевых построителях:
  /// харнесс, блокирующий сайт там, где боевой конфиг его пропускает, врал бы
  /// в другую сторону — и это ничем не лучше.
  factory HarnessRealism.fromRules(
    SplitTunnelConfig split, {
    String dnsServer = '',
    String? queryStrategy,
  }) {
    final sites = userRulesActive(split) ? split.sites : const <SiteRule>[];
    return HarnessRealism(
      blocked: [
        for (final s in sites)
          if (s.action == AppAction.block) s,
      ],
      direct: [
        for (final s in sites)
          if (s.action == AppAction.direct) s,
      ],
      dnsServer: dnsServer,
      queryStrategy: queryStrategy,
    );
  }
}

/// Один кандидат в харнессе: сервер + вариация настроек.
class HarnessEntry {
  final String key; // стабильный ключ (обычно rawLink сервера + метка вариации)
  final VpnServer server;
  final OutboundVariant variant;

  /// Боевые настройки, влияющие на пробу (см. [HarnessRealism]).
  ///
  /// ⚠️ ЖИВЁТ ИМЕННО ЗДЕСЬ, А НЕ В ПОСТРОИТЕЛЕ, потому что построитель создаёт
  /// платформенный код харнесса (`XrayHarnessWindows`, `ProbeHarnessAndroid`),
  /// а настройки пользователя есть только у того, кто запускает прогон.
  /// Единственное, что доезжает от него до построителя, — список кандидатов.
  final HarnessRealism realism;

  const HarnessEntry({
    required this.key,
    required this.server,
    this.variant = OutboundVariant.none,
    this.realism = HarnessRealism.none,
  });
}

/// Настройки прогона: одни на весь харнесс, поэтому берём у первого кандидата,
/// который их принёс (остальные кандидаты того же прогона несут те же).
HarnessRealism realismOf(List<HarnessEntry> entries) {
  for (final e in entries) {
    if (!e.realism.isEmpty) return e.realism;
  }
  return HarnessRealism.none;
}

/// Строит конфиг проброс-харнесса: по одному http-inbound на кандидата,
/// маршрутизируемому на его outbound. Проба сервера i = HTTP-запрос через 127.0.0.1:(base+i).
///
/// Важно: харнесс НЕ содержит api/stats/policy и НЕ трогает системный прокси —
/// все inbound'ы слушают только 127.0.0.1. Dart HttpClient умеет ходить через http-прокси нативно.
class HarnessConfigBuilder {
  final HarnessPorts ports;

  /// Логин и пароль http-инбаундов харнесса.
  ///
  /// ⚠️ ЗАЧЕМ ОНИ ЗДЕСЬ. Инбаунд харнесса — это полноценный вход в туннель:
  /// кто к нему подключился, тот ходит через VPN-сервер кандидата. Живёт он
  /// недолго (только пока идёт прогон пинга или подбора), но всё это время был
  /// открыт ЛЮБОМУ процессу машины. Ровно такую дыру закрывали в 1.3.0 для
  /// портов 10808/10809 — про харнесс тогда забыли, потому что страж
  /// `local_ports_closed_test` знал два пути сборки конфига из четырёх.
  ///
  /// Пусто — инбаунд без пароля (так конфиг выглядел до 1.4.1). Оставлено
  /// возможным только ради тестов: боевой путь всегда выдаёт креды.
  final String user;
  final String password;

  const HarnessConfigBuilder({
    this.ports = const HarnessPorts(),
    this.user = '',
    this.password = '',
  });

  HarnessConfigBuilder withAuth(String user, String password) =>
      HarnessConfigBuilder(ports: ports, user: user, password: password);

  bool get _hasAuth => user.isNotEmpty && password.isNotEmpty;

  /// Секция `settings` http-инбаунда: с аккаунтами либо пустая.
  Map<String, dynamic> get _httpSettings => _hasAuth
      ? {
          'accounts': [
            {'user': user, 'pass': password}
          ],
        }
      : <String, dynamic>{};

  int portFor(int index) => ports.base + index;

  Map<String, dynamic> buildMap(List<HarnessEntry> entries) {
    // #8.2 — сервер с полным JSON-override: поднимаем его собственный конфиг
    // (со всеми outbounds/balancers/burstObservatory), но заменяем inbounds на
    // единственный http-inbound харнесса и роутим его на цель исходного конфига.
    if (entries.length == 1) {
      // Полный конфиг: правка пользователя либо профиль-автовыбор от панели.
      final s = entries.first.server;
      final raw = (s.rawJsonOverride ?? '').isNotEmpty
          ? s.rawJsonOverride
          : s.rawPanelConfig;
      if (raw != null && raw.isNotEmpty) {
        final map = _tryOverrideMap(raw, portFor(0));
        if (map != null) return map;
      }
    }

    final realism = realismOf(entries);
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final inTag = 'in-$i';
      final outTag = 'out-$i';
      inbounds.add({
        'tag': inTag,
        'listen': '127.0.0.1',
        'port': portFor(i),
        'protocol': 'http',
        'settings': _httpSettings,
      });
      outbounds.addAll(
        XrayOutboundFactory.build(e.server, tag: outTag, variant: e.variant),
      );
      rules.add({
        'type': 'field',
        'inboundTag': [inTag],
        'outboundTag': outTag,
      });
    }

    outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
    outbounds.add({'protocol': 'blackhole', 'tag': 'block'});

    final dns = _dns(realism);
    return {
      'log': {'loglevel': 'warning'},
      if (dns != null) 'dns': dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      // ⚠️ ПОРЯДОК ПРАВИЛ: сайты пользователя ВЫШЕ правил кандидатов. Правило
      // кандидата (`inboundTag: in-i`) совпадает с ЛЮБЫМ запросом из своего
      // входа, поэтому всё, что стоит ниже него, не срабатывает никогда.
      // Внутри — тот же порядок, что в боевом конфиге: блок, затем «Прямо».
      //
      // domainStrategy остаётся AsIs (а не боевой IPIfNonMatch) намеренно:
      // IPIfNonMatch заставляет ядро резолвить имя ЛОКАЛЬНО перед сверкой с
      // IP-правилами, и этот резолв попал бы в измеряемую задержку, испортив
      // саму цифру пинга. Доменные правила при AsIs работают: им резолв не нужен.
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          ..._siteRules(realism.blocked, 'block'),
          ..._siteRules(realism.direct, 'direct'),
          ...rules,
        ],
      },
    };
  }

  /// Правила по сайтам в терминах Xray. `domain:foo.com` — домен и его
  /// поддомены (аналог `domain_suffix` в боевом конфиге sing-box).
  List<Map<String, dynamic>> _siteRules(List<SiteRule> sites, String outbound) =>
      [
        for (final s in sites)
          {
            'type': 'field',
            'domain': ['domain:${s.domain}'],
            // Правило с портом действует только на него — иначе сайт,
            // заблокированный на 8443, оказался бы закрыт целиком.
            if (s.port != null) 'port': '${s.port}',
            'outboundTag': outbound,
          },
      ];

  /// DNS-секция под настройки пользователя. `null` — не писать её вовсе: при
  /// умолчаниях конфиг харнесса обязан остаться в точности прежним, иначе
  /// правка задевала бы всех, включая тех, у кого никаких настроек нет.
  Map<String, dynamic>? _dns(HarnessRealism realism) {
    if (realism.dnsServer.isEmpty && realism.queryStrategy == null) return null;
    return {
      if (realism.queryStrategy != null) 'queryStrategy': realism.queryStrategy,
      // Пустой список ядро не примет: без своего сервера берём тот же запасной
      // набор, что стоит в боевом конфиге автовыбора.
      'servers': realism.dnsServer.isNotEmpty
          ? [realism.dnsServer]
          : ['1.1.1.1', '8.8.8.8'],
    };
  }

  String buildJson(List<HarnessEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(entries));

  /// Строит harness-конфиг из полного пользовательского JSON. Возвращает null,
  /// если JSON нераспарсиваемый или без outbounds (тогда откат на обычный путь).
  ///
  /// ⚠️ Правила [HarnessRealism] сюда НЕ добавляются: теги `direct`/`block` в
  /// чужом конфиге есть не всегда, а правило с несуществующим тегом Xray молча
  /// уводит трафик в другой outbound (тот же класс дефекта, что и висячий тег в
  /// sing-box). Профили «Авто …» и правки JSON проверяются как раньше.
  Map<String, dynamic>? _tryOverrideMap(String raw, int port) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cfg = Map<String, dynamic>.from(decoded);
      final outbounds = cfg['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) return null;

      // Цель роутинга: balancerTag из исходных правил, иначе первый proxy-outbound.
      final routing = cfg['routing'] is Map
          ? Map<String, dynamic>.from(cfg['routing'] as Map)
          : <String, dynamic>{};
      String? balancerTag;
      final origRules = routing['rules'];
      if (origRules is List) {
        for (final r in origRules) {
          if (r is Map && r['balancerTag'] != null) {
            balancerTag = '${r['balancerTag']}';
            break;
          }
        }
      }
      String? outTag;
      if (balancerTag == null) {
        for (final o in outbounds) {
          if (o is! Map) continue;
          final proto = '${o['protocol']}';
          if (proto == 'freedom' || proto == 'blackhole' || proto == 'dns') {
            continue;
          }
          final tag = '${o['tag'] ?? ''}';
          if (tag.isNotEmpty) {
            outTag = tag;
            break;
          }
        }
        outTag ??= '${(outbounds.first as Map)['tag'] ?? ''}';
      }

      const inTag = 'in-0';
      routing['domainStrategy'] = routing['domainStrategy'] ?? 'AsIs';
      routing['rules'] = [
        {
          'type': 'field',
          'inboundTag': [inTag],
          if (balancerTag != null)
            'balancerTag': balancerTag
          else
            'outboundTag': outTag,
        },
      ];

      cfg['log'] = {'loglevel': 'warning'};
      cfg['inbounds'] = [
        {
          'tag': inTag,
          'listen': '127.0.0.1',
          'port': port,
          'protocol': 'http',
          'settings': _httpSettings,
        },
      ];
      cfg['routing'] = routing;
      cfg.remove('api');
      cfg.remove('stats');
      cfg.remove('policy');
      return cfg;
    } catch (_) {
      return null;
    }
  }
}
