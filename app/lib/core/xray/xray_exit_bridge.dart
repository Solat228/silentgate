import 'dart:convert';
import 'dart:io' show InternetAddress;

import '../models/vpn_server.dart';
import '../singbox/exit_tags.dart';
import '../singbox/singbox_outbound_factory.dart';
import 'outbound_variant.dart';
import 'private_networks.dart';
import 'xray_keys.dart';
import 'xray_outbound_factory.dart';

/// Базовый порт локальных SOCKS5-мостов Xray для дополнительных выходов
/// («Через сервер»), которые не может поднять напрямую `sing-box`
/// (панельные профили «🎬 Авто (YouTube)», «⚡ Авто …», транспорт `XHTTP` и
/// пользовательские JSON-правки Xray).
///
/// Диапазон `10910+` не пересекается ни с основными портами ядра
/// (`10808`/`10809`/`10085`), ни со служебными Clash API (`10811`..`10813`),
/// ни с локальными портами API (`10819`..`10859`, `10870`), ни с релеем БС
/// (`10855`).
const int kXrayExitBridgeBasePort = 10910;

const _builtinXrayOutbounds = {'freedom', 'blackhole', 'dns', 'loopback'};
const _xrayBridgeableSingleProtocols = {'vless', 'trojan', 'shadowsocks'};

/// Причина, по которой полный JSON-конфиг Xray (профиль «Авто» от панели или
/// пользовательский `rawJsonOverride`) НЕЛЬЗЯ поднять мостом второго выхода.
/// `null` — конфиг валиден и содержит хотя бы один рабочий прокси-outbound.
String? fullConfigExitRejection(VpnServer s) {
  final full = s.effectiveFullConfig.trim();
  if (full.isEmpty) {
    return 'панельный профиль «Авто» пуст: ${s.displayName}';
  }
  try {
    final decoded = jsonDecode(canonicalXrayJson(full));
    if (decoded is! Map) {
      return 'повреждён конфиг профиля «Авто»: ${s.displayName}';
    }
    final outbounds = decoded['outbounds'];
    if (outbounds is! List || outbounds.isEmpty) {
      return 'панельный профиль «Авто» не содержит узлов: ${s.displayName}';
    }
    var proxyTotal = 0;
    var usableWithoutRelay = 0;
    for (final ob in outbounds) {
      if (ob is! Map) continue;
      final proto = '${ob['protocol'] ?? ''}'.trim().toLowerCase();
      if (proto.isEmpty || _builtinXrayOutbounds.contains(proto)) continue;
      proxyTotal++;
      if (!_isWhitelistRelayOutbound(ob)) {
        usableWithoutRelay++;
      }
    }
    if (proxyTotal == 0) {
      return 'панельный профиль «Авто» не содержит прокси-узлов: '
          '${s.displayName}';
    }
    if (usableWithoutRelay == 0) {
      return 'профиль «Авто» требует собственного WebRTC-звонка БС и вторым '
          'туннелем не поднимается: ${s.displayName}';
    }
    return null;
  } catch (_) {
    return 'повреждён JSON профиля «Авто»: ${s.displayName}';
  }
}

/// Требуется ли серверу [s] локальный SOCKS5-мост через Xray, чтобы работать
/// отдельным выходом (`exit-…`) в `sing-box`.
bool needsXrayExitBridge(VpnServer s) {
  if (s.address.trim().isEmpty ||
      s.isNotice ||
      s.isUnsupported ||
      s.usesWhitelistRelay) {
    return false;
  }
  if (s.core != ProxyCore.xray) return false;
  if (s.isPanelProfile || (s.rawJsonOverride ?? '').trim().isNotEmpty) {
    return fullConfigExitRejection(s) == null;
  }
  if (!SingboxOutboundFactory.supports(s) &&
      _xrayBridgeableSingleProtocols.contains(s.protocol)) {
    return true;
  }
  return false;
}

/// Детерминированно назначает локальные порты `127.0.0.1:<basePort + i>` всем
/// серверам из [exitServers], которым нужен Xray-мост ([needsXrayExitBridge]).
///
/// Ключи сортируются лексикографически — так же, как в `ExitOutbounds.build` и
/// `ApiPorts`: одна и та же карта серверов всегда даёт побайтно тот же конфиг
/// и те же номера портов (важно для сверки живого TUN при бесшовной смене).
Map<String, int> assignXrayExitBridgePorts(
  Map<String, VpnServer> exitServers, {
  int basePort = kXrayExitBridgeBasePort,
}) {
  if (exitServers.isEmpty) return const {};
  final keys = exitServers.keys.toList()..sort();
  final out = <String, int>{};
  var offset = 0;
  for (final k in keys) {
    final s = exitServers[k];
    if (s != null && needsXrayExitBridge(s)) {
      out[k] = basePort + offset;
      offset++;
    }
  }
  return out;
}

/// Собирает outbound `socks` для `sing-box`, смотрящий в локальный мост Xray.
Map<String, dynamic> buildSingboxBridgeSocksOutbound({
  required String tag,
  required int port,
  String user = '',
  String password = '',
}) =>
    {
      'type': 'socks',
      'tag': tag,
      'server': '127.0.0.1',
      'server_port': port,
      'version': '5',
      if (user.isNotEmpty && password.isNotEmpty) ...{
        'username': user,
        'password': password,
      },
    };

/// Встраивает изолированные SOCKS5-инбаунды (`in-exit-<hash>`), префиксованные
/// outbound'ы (`exit-<hash>-…`), балансировщики и `burstObservatory` в
/// Xray-конфиг [baseXrayJson].
///
/// Если [baseXrayJson] равен `null` (например, основной сервер сессии —
/// `Hysteria2` на `sing-box`, но в правиле «Через сервер» выбран
/// «🎬 Авто (YouTube)» или `XHTTP`-узел), строит минимальный автономный
/// Xray-конфиг, обслуживающий только мосты выходов.
///
/// ### Почему внутренний `direct` шаблона «Авто (YouTube)» НЕ переносится
/// Шаблон панели «Авто (YouTube)» устроен для работы основным профилем: он
/// отправляет домены YouTube/Telegram в `balancerTag: "yt_auto"`, а всё
/// остальное (`.ru` и финальное `network: "tcp,udp"`) — в `direct`. Когда же
/// пользователь в самом SilentGate назначает «Через сервер → 🎬 Авто (YouTube)»
/// конкретному сайту или программе (например, `discord.com` или `2ip.ru`),
/// отбор трафика УЖЕ выполнил `sing-box`. Оставь мы финальный `direct` внутри
/// моста — любой не-YouTube сайт на этом выходе молча утёк бы под реальным IP
/// пользователя. Поэтому мост сохраняет блок QUIC (`UDP:443 -> block`, если он
/// был в профиле) и направляет весь трафик своего `in-exit-<hash>` строго в
/// целевой балансировщик (`exit-<hash>-yt_auto`) или первый прокси-outbound.
String injectXrayExitBridges(
  String? baseXrayJson, {
  required Map<String, VpnServer> exitServers,
  required Map<String, int> bridgePorts,
  Map<String, String> resolvedIps = const {},
  String socksUser = '',
  String socksPassword = '',
  OutboundVariant variant = OutboundVariant.none,
}) {
  if (bridgePorts.isEmpty) return baseXrayJson ?? '';

  Map<String, dynamic> cfg;
  if (baseXrayJson != null && baseXrayJson.trim().isNotEmpty) {
    final decoded = jsonDecode(canonicalXrayJson(baseXrayJson));
    cfg = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : _emptyAuxiliaryXrayConfig();
  } else {
    cfg = _emptyAuxiliaryXrayConfig();
  }

  final inbounds = <dynamic>[
    ...(cfg['inbounds'] is List ? cfg['inbounds'] as List : const []),
  ];
  final outbounds = <dynamic>[
    ...(cfg['outbounds'] is List ? cfg['outbounds'] as List : const []),
  ];
  final routing = Map<String, dynamic>.from(
    (cfg['routing'] is Map ? cfg['routing'] as Map : const {}),
  );
  routing['domainStrategy'] ??= 'IPIfNonMatch';
  final existingRules = <dynamic>[
    ...(routing['rules'] is List ? routing['rules'] as List : const []),
  ];
  final balancers = <dynamic>[
    ...(routing['balancers'] is List ? routing['balancers'] as List : const []),
  ];

  final extraBurstSelectors = <String>[];
  Map<String, dynamic>? borrowedPingConfig;
  final bridgeRules = <Map<String, dynamic>>[];

  final sortedKeys = bridgePorts.keys.toList()..sort();
  var fullConfigCount = 0;
  for (final key in sortedKeys) {
    final srv = exitServers[key];
    if (srv != null &&
        needsXrayExitBridge(srv) &&
        srv.effectiveFullConfig.trim().isNotEmpty) {
      fullConfigCount++;
    }
  }
  // Когда одновременно поднимается >= 2 панельных профилей «Авто» (например,
  // кнопка «Все Авто» в API), они содержат одни и те же 20–40 прокси-узлов.
  // Дедуплицируем идентичные outbound'ы по каноническому хэшу без `tag`:
  // Xray держит один общий набор `exit-sh-<16hex>`, а балансировщик каждого
  // профиля «Авто» ссылается ровно на свои узлы без умножения пингов на N.
  final sharedOutboundTagsByFp =
      fullConfigCount >= 2 ? <String, String>{} : null;

  for (final key in sortedKeys) {
    final server = exitServers[key];
    final port = bridgePorts[key];
    if (server == null || port == null || !needsXrayExitBridge(server)) {
      continue;
    }

    final exitTag = exitTagFor(key); // exit-<8 hex>
    final prefix = '$exitTag-';
    final inboundTag = 'in-$exitTag';

    final hasAuth = socksUser.isNotEmpty && socksPassword.isNotEmpty;
    inbounds.add({
      'tag': inboundTag,
      'listen': '127.0.0.1',
      'port': port,
      'protocol': 'socks',
      'settings': hasAuth
          ? {
              'udp': true,
              'auth': 'password',
              'accounts': [
                {'user': socksUser, 'pass': socksPassword},
              ],
            }
          : {'udp': true, 'auth': 'noauth'},
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls', 'quic'],
      },
    });

    final full = server.effectiveFullConfig.trim();
    if (full.isNotEmpty) {
      final parsed = _extractBridgedFullConfig(
        fullJson: full,
        prefix: prefix,
        inboundTag: inboundTag,
        resolvedIps: resolvedIps,
        sharedOutboundTagsByFp: sharedOutboundTagsByFp,
      );
      if (parsed == null) continue;
      outbounds.addAll(parsed.outbounds);
      balancers.addAll(parsed.balancers);
      for (final sel in parsed.burstSelectors) {
        if (!extraBurstSelectors.contains(sel)) {
          extraBurstSelectors.add(sel);
        }
      }
      borrowedPingConfig ??= parsed.pingConfig;
      bridgeRules.addAll(parsed.rules);
    } else {
      final resolvedServer = _withResolvedAddress(server, resolvedIps);
      final nodeTag = '${prefix}node';
      final built = XrayOutboundFactory.build(
        resolvedServer,
        tag: nodeTag,
        variant: variant,
      );
      outbounds.addAll(built);
      bridgeRules.addAll([
        {
          'type': 'field',
          'inboundTag': [inboundTag],
          'ip': List<String>.from(kPrivateNetworks),
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'inboundTag': [inboundTag],
          'port': '443',
          'network': 'udp',
          'outboundTag': 'block',
        },
        {
          'type': 'field',
          'inboundTag': [inboundTag],
          'network': 'tcp,udp',
          'outboundTag': nodeTag,
        },
      ]);
    }
  }

  // Гарантируем наличие служебных direct и block в outbounds (в конце списка,
  // чтобы не сместить outbounds[0] основного одиночного конфига Xray!).
  final knownOutboundTags = {
    for (final o in outbounds)
      if (o is Map && o['tag'] is String) o['tag'] as String,
  };
  if (!knownOutboundTags.contains('direct')) {
    outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
  }
  if (!knownOutboundTags.contains('block')) {
    outbounds.add({'protocol': 'blackhole', 'tag': 'block'});
  }

  // Вставляем правила мостов сразу после служебного правила api (если есть),
  // СТРОГО выше любых общих правил основного профиля. Так трафик `in-exit-*`
  // никогда не проваливается в чужой балансировщик или чужой `direct`, а
  // трафик основных `socks`/`http` не задевает правила `in-exit-*`.
  var insertIdx = 0;
  while (insertIdx < existingRules.length) {
    final r = existingRules[insertIdx];
    if (r is Map && '${r['outboundTag'] ?? ''}' == 'api') {
      insertIdx++;
    } else {
      break;
    }
  }
  existingRules.insertAll(insertIdx, bridgeRules);
  routing['rules'] = existingRules;
  if (balancers.isNotEmpty) {
    routing['balancers'] = balancers;
  }

  if (extraBurstSelectors.isNotEmpty) {
    _mergeBurstObservatory(
      cfg,
      extraSelectors: extraBurstSelectors,
      fallbackPingConfig: borrowedPingConfig,
    );
  }

  cfg['inbounds'] = inbounds;
  cfg['outbounds'] = outbounds;
  cfg['routing'] = routing;
  stripMasterKeyLog(cfg);

  return const JsonEncoder.withIndent('  ').convert(cfg);
}

Map<String, dynamic> _emptyAuxiliaryXrayConfig() => {
      'log': {'loglevel': 'warning'},
      'dns': {
        'queryStrategy': 'UseIP',
        'servers': ['1.1.1.1', '8.8.8.8'],
      },
      'inbounds': <dynamic>[],
      'outbounds': <dynamic>[],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': <dynamic>[],
      },
    };

VpnServer _withResolvedAddress(
  VpnServer server,
  Map<String, String> resolvedIps,
) {
  final orig = server.address.trim();
  final ip = resolvedIps[orig];
  if (ip == null || ip.isEmpty || ip == orig) return server;
  final wasDomain = InternetAddress.tryParse(orig) == null;
  return server.copyWith(
    address: ip,
    sni: (wasDomain && (server.sni ?? '').trim().isEmpty) ? orig : server.sni,
    host: (wasDomain &&
            (server.host ?? '').trim().isEmpty &&
            const {'ws', 'http', 'h2', 'httpupgrade', 'xhttp', 'splithttp'}
                .contains(server.network))
        ? orig
        : server.host,
  );
}

class _BridgedFullConfig {
  final List<Map<String, dynamic>> outbounds;
  final List<Map<String, dynamic>> balancers;
  final List<String> burstSelectors;
  final Map<String, dynamic>? pingConfig;
  final List<Map<String, dynamic>> rules;

  const _BridgedFullConfig({
    required this.outbounds,
    required this.balancers,
    required this.burstSelectors,
    required this.pingConfig,
    required this.rules,
  });
}

_BridgedFullConfig? _extractBridgedFullConfig({
  required String fullJson,
  required String prefix,
  required String inboundTag,
  required Map<String, String> resolvedIps,
  Map<String, String>? sharedOutboundTagsByFp,
}) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(canonicalXrayJson(fullJson));
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final extCfg = Map<String, dynamic>.from(decoded);
  stripMasterKeyLog(extCfg);

  final rawOutbounds = extCfg['outbounds'];
  if (rawOutbounds is! List) return null;

  final outbounds = <Map<String, dynamic>>[];
  final origToNewTag = <String, String>{};
  final newOutboundTags = <String>[];
  final profileNodes = <({String origTag, String actualTag})>[];
  var idx = 0;

  for (final rawOb in rawOutbounds) {
    if (rawOb is! Map) continue;
    final proto = '${rawOb['protocol'] ?? ''}'.trim().toLowerCase();
    if (proto.isEmpty || _builtinXrayOutbounds.contains(proto)) continue;
    if (_isWhitelistRelayOutbound(rawOb)) continue;

    final cloned =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(rawOb)) as Map);
    final origTag = '${cloned['tag'] ?? ''}'.trim();
    final safeOrig = origTag.isEmpty ? 'node-$idx' : origTag;
    idx++;
    _applyResolvedIpsToXrayOutbound(cloned, resolvedIps);

    String actualTag;
    if (sharedOutboundTagsByFp != null) {
      final fp = _outboundFingerprint(cloned);
      final existing = sharedOutboundTagsByFp[fp];
      if (existing != null) {
        actualTag = existing;
      } else {
        actualTag = 'exit-sh-$fp';
        cloned['tag'] = actualTag;
        sharedOutboundTagsByFp[fp] = actualTag;
        outbounds.add(cloned);
      }
    } else {
      var newTag = '$prefix$safeOrig';
      while (newOutboundTags.contains(newTag)) {
        idx++;
        newTag = '$prefix$safeOrig-$idx';
      }
      cloned['tag'] = newTag;
      actualTag = newTag;
      outbounds.add(cloned);
    }

    if (origTag.isNotEmpty) {
      origToNewTag.putIfAbsent(origTag, () => actualTag);
    }
    newOutboundTags.add(actualTag);
    profileNodes.add((origTag: safeOrig, actualTag: actualTag));
  }

  if (profileNodes.isEmpty) return null;

  final extRouting = extCfg['routing'] is Map
      ? Map<String, dynamic>.from(extCfg['routing'] as Map)
      : const <String, dynamic>{};

  // Переносим и префиксуем балансировщики профиля (например, `yt_auto`).
  final balancers = <Map<String, dynamic>>[];
  final origToNewBalancer = <String, String>{};
  final neededObservatoryPrefixes = <String>[];
  final rawBalancers = extRouting['balancers'];
  if (rawBalancers is List) {
    var bIdx = 0;
    for (final rawB in rawBalancers) {
      if (rawB is! Map) continue;
      final clonedB =
          Map<String, dynamic>.from(jsonDecode(jsonEncode(rawB)) as Map);
      final origBTag = '${clonedB['tag'] ?? ''}'.trim();
      final safeB = origBTag.isEmpty ? 'bal-$bIdx' : origBTag;
      final newBTag = '$prefix$safeB';
      bIdx++;
      clonedB['tag'] = newBTag;
      if (origBTag.isNotEmpty) {
        origToNewBalancer[origBTag] = newBTag;
      }

      // Префиксуем selector и проверяем, что хотя бы один узел под него попал.
      final rawSel = clonedB['selector'];
      final prefixedSel = <String>[];
      if (sharedOutboundTagsByFp != null) {
        if (rawSel is List) {
          for (final s in rawSel) {
            final sv = '$s'.trim();
            if (sv.isEmpty) continue;
            for (final n in profileNodes) {
              if (n.origTag.startsWith(sv) &&
                  !prefixedSel.contains(n.actualTag)) {
                prefixedSel.add(n.actualTag);
              }
            }
          }
        }
        if (prefixedSel.isEmpty) {
          for (final n in profileNodes) {
            if (!prefixedSel.contains(n.actualTag)) {
              prefixedSel.add(n.actualTag);
            }
          }
        }
      } else {
        if (rawSel is List) {
          for (final s in rawSel) {
            final sv = '$s'.trim();
            if (sv.isEmpty) continue;
            final cand = '$prefix$sv';
            if (newOutboundTags.any((t) => t.startsWith(cand))) {
              prefixedSel.add(cand);
            }
          }
        }
        if (prefixedSel.isEmpty) {
          prefixedSel.add(prefix);
        }
      }
      clonedB['selector'] = prefixedSel;

      // Разрешаем fallbackTag: в шаблонах Remnawave (`ytjson.txt`) `zslow` —
      // это префикс инжектируемых запасных нод (`zslow`, `zslow-1`, …), либо
      // точный тег. Если ни одного `zslow`-узла в профиле нет, убираем висячий
      // `fallbackTag`, чтобы Xray не отверг конфиг на старте.
      final rawFb = '${clonedB['fallbackTag'] ?? ''}'.trim();
      if (rawFb.isNotEmpty) {
        String? resolvedFb = origToNewTag[rawFb];
        if (resolvedFb == null) {
          for (final n in profileNodes) {
            if (n.origTag.startsWith(rawFb)) {
              resolvedFb = n.actualTag;
              break;
            }
          }
        }
        if (resolvedFb != null) {
          clonedB['fallbackTag'] = resolvedFb;
        } else {
          clonedB.remove('fallbackTag');
        }
      }

      final stratType = clonedB['strategy'] is Map
          ? '${(clonedB['strategy'] as Map)['type'] ?? ''}'.trim()
          : '';
      if (stratType == 'leastPing' || stratType == 'leastLoad') {
        for (final s in prefixedSel) {
          if (!neededObservatoryPrefixes.contains(s)) {
            neededObservatoryPrefixes.add(s);
          }
        }
      }

      balancers.add(clonedB);
    }
  }

  // Извлекаем subjectSelector и pingConfig из burstObservatory / observatory.
  final burstSelectors = <String>[...neededObservatoryPrefixes];
  Map<String, dynamic>? pingConfig;
  for (final obsKey in const ['burstObservatory', 'observatory']) {
    final obs = extCfg[obsKey];
    if (obs is! Map) continue;
    final rawSubj = obs['subjectSelector'];
    if (rawSubj is List) {
      for (final s in rawSubj) {
        final sv = '$s'.trim();
        if (sv.isEmpty) continue;
        if (sharedOutboundTagsByFp != null) {
          for (final n in profileNodes) {
            if (n.origTag.startsWith(sv) &&
                !burstSelectors.contains(n.actualTag)) {
              burstSelectors.add(n.actualTag);
            }
          }
        } else {
          final cand = '$prefix$sv';
          if (newOutboundTags.any((t) => t.startsWith(cand)) &&
              !burstSelectors.contains(cand)) {
            burstSelectors.add(cand);
          }
        }
      }
    }
    if (pingConfig == null && obs['pingConfig'] is Map) {
      pingConfig = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(obs['pingConfig'])) as Map,
      );
    }
  }

  // Определяем, блокировал ли профиль QUIC (UDP:443 -> block) и какой
  // балансировщик / outbound в нём основной для целевого трафика.
  var blocksQuic = false;
  String? primaryBalancerTag;
  String? primaryOutboundTag;
  final rawRules = extRouting['rules'];
  if (rawRules is List) {
    for (final r in rawRules) {
      if (r is! Map) continue;
      final outTag = '${r['outboundTag'] ?? ''}'.trim();
      final balTag = '${r['balancerTag'] ?? ''}'.trim();
      final net = '${r['network'] ?? ''}'.toLowerCase();
      final port = '${r['port'] ?? ''}'.trim();
      if ((outTag == 'block' || '${r['ruleTag'] ?? ''}' == 'block-quic') &&
          net.contains('udp') &&
          port == '443') {
        blocksQuic = true;
      }
      if (primaryBalancerTag == null &&
          balTag.isNotEmpty &&
          origToNewBalancer.containsKey(balTag)) {
        primaryBalancerTag = origToNewBalancer[balTag];
      }
      if (primaryOutboundTag == null &&
          outTag.isNotEmpty &&
          origToNewTag.containsKey(outTag)) {
        primaryOutboundTag = origToNewTag[outTag];
      }
    }
  }

  primaryBalancerTag ??=
      balancers.isNotEmpty ? '${balancers.first['tag']}' : null;
  primaryOutboundTag ??= profileNodes.first.actualTag;

  final rules = <Map<String, dynamic>>[
    {
      'type': 'field',
      'inboundTag': [inboundTag],
      'ip': List<String>.from(kPrivateNetworks),
      'outboundTag': 'direct',
    },
    if (blocksQuic)
      {
        'type': 'field',
        'inboundTag': [inboundTag],
        'port': '443',
        'network': 'udp',
        'outboundTag': 'block',
      },
    {
      'type': 'field',
      'inboundTag': [inboundTag],
      'network': 'tcp,udp',
      if (primaryBalancerTag != null)
        'balancerTag': primaryBalancerTag
      else
        'outboundTag': primaryOutboundTag,
    },
  ];

  return _BridgedFullConfig(
    outbounds: outbounds,
    balancers: balancers,
    burstSelectors: burstSelectors,
    pingConfig: pingConfig,
    rules: rules,
  );
}

void _mergeBurstObservatory(
  Map<String, dynamic> cfg, {
  required List<String> extraSelectors,
  Map<String, dynamic>? fallbackPingConfig,
}) {
  // Если в основном конфиге уже живёт обычный `observatory` (без burst),
  // расширяем его `subjectSelector`: одновременные `observatory` и
  // `burstObservatory` Xray 26.3.27 не любит. Иначе используем `burstObservatory`.
  final usePlainObservatory =
      cfg['observatory'] is Map && cfg['burstObservatory'] == null;
  final key = usePlainObservatory ? 'observatory' : 'burstObservatory';

  final existing = cfg[key] is Map
      ? Map<String, dynamic>.from(cfg[key] as Map)
      : <String, dynamic>{};

  final selectors = <String>[
    if (existing['subjectSelector'] is List)
      for (final s in existing['subjectSelector'] as List)
        if ('$s'.trim().isNotEmpty) '$s'.trim(),
  ];
  for (final s in extraSelectors) {
    if (!selectors.contains(s)) selectors.add(s);
  }
  existing['subjectSelector'] = selectors;

  if (!usePlainObservatory && existing['pingConfig'] is! Map) {
    existing['pingConfig'] = fallbackPingConfig ??
        {
          'destination': 'https://cp.cloudflare.com/generate_204',
          'interval': '30s',
          'sampling': 3,
          'timeout': '5s',
        };
  }
  cfg[key] = existing;
}

void _applyResolvedIpsToXrayOutbound(
  Map<String, dynamic> ob,
  Map<String, String> resolvedIps,
) {
  if (resolvedIps.isEmpty) return;
  final settings = ob['settings'];
  if (settings is! Map) return;

  String? replacedDomain;
  void patchMapAddress(Map target) {
    final raw = target['address'];
    if (raw is! String) return;
    final orig = raw.trim();
    final ip = resolvedIps[orig];
    if (ip == null || ip.isEmpty || ip == orig) return;
    if (InternetAddress.tryParse(orig) == null) {
      replacedDomain ??= orig;
    }
    target['address'] = ip;
  }

  patchMapAddress(settings);
  final vnext = settings['vnext'];
  if (vnext is List) {
    for (final v in vnext) {
      if (v is Map) patchMapAddress(v);
    }
  }
  final servers = settings['servers'];
  if (servers is List) {
    for (final s in servers) {
      if (s is Map) patchMapAddress(s);
    }
  }

  // Если домен заменили на IP, убеждаемся, что SNI не потерян у TLS-стрима.
  if (replacedDomain != null && ob['streamSettings'] is Map) {
    final ss = ob['streamSettings'] as Map;
    final sec = '${ss['security'] ?? ''}'.toLowerCase();
    if (sec == 'tls') {
      final tls = ss['tlsSettings'] is Map
          ? Map<String, dynamic>.from(ss['tlsSettings'] as Map)
          : <String, dynamic>{};
      if ('${tls['serverName'] ?? ''}'.trim().isEmpty) {
        tls['serverName'] = replacedDomain;
        ss['tlsSettings'] = tls;
      }
    }
  }
}

bool _isWhitelistRelayOutbound(Map ob) {
  final ss = ob['streamSettings'];
  if (ss is! Map) return false;
  if ('${ss['network'] ?? ''}'.toLowerCase() != 'ws') return false;
  final ws = ss['wsSettings'];
  if (ws is! Map) return false;
  final path = '${ws['path'] ?? ''}'.trim();
  return path == '/sgbs' || path.startsWith('/sgbs?');
}

Object? _canonicalizeJsonValue(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return <String, Object?>{
      for (final k in keys) k: _canonicalizeJsonValue(v[k]),
    };
  }
  if (v is List) {
    return [for (final item in v) _canonicalizeJsonValue(item)];
  }
  return v;
}

/// Двухпроходный 64-битный (16 hex символов, фиксированной длины!) отпечаток
/// прокси-outbound без поля `tag`: два тега `exit-sh-<16hex>` одинаковой длины
/// никогда не являются префиксом друг друга в `strings.HasPrefix` Xray.
String _outboundFingerprint(Map<String, dynamic> ob) {
  final copy = Map<String, dynamic>.from(ob)..remove('tag');
  final canonical = jsonEncode(_canonicalizeJsonValue(copy));
  final bytes = utf8.encode(canonical);
  var h1 = 0x811c9dc5;
  var h2 = 0x9e3779b9;
  for (final b in bytes) {
    h1 ^= b;
    h1 = (h1 * 0x01000193) & 0xffffffff;
    h2 ^= (b + 0x55) & 0xff;
    h2 = (h2 * 0x85ebca6b) & 0xffffffff;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}'
      '${h2.toRadixString(16).padLeft(8, '0')}';
}
