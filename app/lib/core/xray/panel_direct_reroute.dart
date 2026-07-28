import 'dart:convert';
import 'private_networks.dart';

/// Переписывает Xray-конфиг (профиль панели «Авто …» или JSON-override) так, чтобы
/// весь `direct`-трафик шёл ЧЕРЕЗ VPN, а не под реальным IP пользователя.
///
/// Зачем: панельные профили несут свою маршрутизацию (RU-routing и т.п.) —
/// правила с `outboundTag:"direct"` выпускают часть трафика напрямую. Kill switch
/// и раздельное туннелирование работают на слое sing-box TUN и этот внутренний
/// direct Xray не видят → утечка реального IP при «Всё через VPN»/kill switch.
///
/// Что делает:
///  - правила `outboundTag:"direct"` переводит на балансер/прокси (VPN);
///  - **LAN (приватные адреса) оставляет direct** — иначе ломается локальная сеть
///    и туннель может не подняться;
///  - **смешанные** правила (публичная сеть + приватная в одном `ip`, напр.
///    `["geoip:ru","geoip:private"]`) РАЗБИВАЕТ: приватную часть оставляет direct,
///    публичную уводит в VPN (иначе `geoip:ru` утекал бы под реальным IP);
///  - добавляет сверху страховку «приватные → direct», а снизу — catch-all «всё
///    остальное → VPN», чтобы непокрытый трафик не ушёл на дефолтный (первый)
///    outbound, если тот `freedom`;
///  - `block` не трогает (он не течёт). Идемпотентна: повторное применение не
///    плодит дубли. Если структуру не распознал или уводить некуда — возвращает
///    исходный JSON без изменений.
String rerouteDirectThroughVpn(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return rawJson;
    final cfg = Map<String, dynamic>.from(decoded);

    final routing = cfg['routing'];
    if (routing is! Map) return rawJson;
    final rules = routing['rules'];
    if (rules is! List) return rawJson;

    final target = _proxyTarget(cfg);
    if (target == null) return rawJson; // некуда уводить — не рискуем

    final outs = cfg['outbounds'] is List ? cfg['outbounds'] as List : const [];
    final hasDirect = outs.any((o) => o is Map && '${o['tag']}' == 'direct');

    final newRules = <dynamic>[];
    for (final r in rules) {
      if (r is! Map || '${r['outboundTag']}' != 'direct') {
        newRules.add(r);
        continue;
      }
      final ip = r['ip'];
      if (ip is List) {
        final priv = ip.where(_isPrivateEntry).toList();
        final pub = ip.where((e) => !_isPrivateEntry(e)).toList();
        if (pub.isEmpty) {
          newRules.add(r); // всё приватное → оставляем direct
          continue;
        }
        if (priv.isEmpty) {
          newRules.add(_toTarget(Map<String, dynamic>.from(r), target));
          continue;
        }
        // Смешанное правило: приватную часть — direct, публичную — в VPN.
        newRules.add(Map<String, dynamic>.from(r)..['ip'] = priv);
        newRules.add(
            _toTarget(Map<String, dynamic>.from(r)..['ip'] = pub, target));
      } else {
        // Без ip (домен/протокол/порт). Приватный домен оставляем direct.
        if (_ruleHasPrivateDomain(r)) {
          newRules.add(r);
          continue;
        }
        newRules.add(_toTarget(Map<String, dynamic>.from(r), target));
      }
    }

    // Страховка сверху: LAN всегда direct (первое совпадение выигрывает). Только
    // если есть куда (outbound с тегом direct) и такого правила ещё нет.
    if (hasDirect && !_isPrivateSafetyRule(newRules.isEmpty ? null : newRules.first)) {
      newRules.insert(0, {
        'type': 'field',
        'ip': kPrivateNetworks,
        'outboundTag': 'direct',
      });
    }

    // Catch-all снизу: непокрытый трафик → VPN, а не на дефолтный (первый)
    // outbound. Не добавляем, если хвостом уже стоит безусловный увод в target.
    if (!newRules.any((r) => _isCatchAllTo(r, target))) {
      newRules.add({'type': 'field', 'network': 'tcp,udp', ...target});
    }

    routing['rules'] = newRules;
    return jsonEncode(cfg);
  } catch (_) {
    return rawJson;
  }
}

/// Убирает у правила прежний тег и ставит целевой (balancer/proxy). Возвращает его же.
Map<String, dynamic> _toTarget(Map<String, dynamic> r, Map<String, String> target) {
  r.remove('outboundTag');
  r.remove('balancerTag');
  r.addAll(target);
  return r;
}

/// Куда уводить direct: балансер (если есть), иначе первый «прокси»-outbound.
Map<String, String>? _proxyTarget(Map cfg) {
  final routing = cfg['routing'];
  if (routing is Map && routing['balancers'] is List) {
    final bs = routing['balancers'] as List;
    if (bs.isNotEmpty && bs.first is Map) {
      final tag = '${(bs.first as Map)['tag'] ?? ''}';
      if (tag.isNotEmpty) return {'balancerTag': tag};
    }
  }
  final outs = cfg['outbounds'];
  if (outs is List) {
    for (final o in outs) {
      if (o is! Map) continue;
      final proto = '${o['protocol']}';
      final tag = '${o['tag'] ?? ''}';
      if (tag.isEmpty) continue;
      if (proto == 'freedom' || proto == 'blackhole' || proto == 'dns') continue;
      return {'outboundTag': tag};
    }
  }
  return null;
}

/// Одна запись `ip` нацелена на приватную сеть (LAN)?
///
/// ⚠️ Сначала — точное совпадение с нашим списком, и только потом эвристика.
/// Иначе повторный проход уводил бы в VPN половину собственной же страховки:
/// эвристика по префиксам не знает ни CGNAT (`100.64.0.0/10`), ни
/// `224.0.0.0/4`, ни IPv6-записей вроде `2001:db8::/32` — они уехали бы в
/// «публичную» часть, то есть LAN частично пошёл бы через туннель.
/// Эвристика остаётся для значений, которые приходят ИЗ ПАНЕЛИ и в наш список
/// не входят.
bool _isPrivateEntry(dynamic e) {
  final raw = '$e';
  if (kPrivateNetworks.contains(raw)) return true;
  final s = raw.toLowerCase();
  return s.contains('private') ||
      s.startsWith('10.') ||
      s.startsWith('192.168.') ||
      s.startsWith('127.') ||
      s.startsWith('172.16.') ||
      s.startsWith('169.254.') ||
      s.startsWith('fc') ||
      s.startsWith('fd') ||
      s.startsWith('fe80');
}

/// Правило без `ip`, но с приватным доменом (`geosite:private`)?
bool _ruleHasPrivateDomain(Map r) {
  final d = r['domain'];
  return d is List && d.any((e) => '$e'.toLowerCase().contains('private'));
}

/// Это уже наша страховка «приватные → direct» (для идемпотентности)?
///
/// Опознаём ОБА вида: старый (`geoip:private` одной записью — так писали до
/// отказа от гео-файлов и так приходит из панели) и новый (явный список
/// подсетей). Иначе повторный проход дописывал бы вторую страховку поверх
/// первой при каждом переподключении.
bool _isPrivateSafetyRule(dynamic r) {
  if (r is! Map) return false;
  if (r['outboundTag'] != 'direct') return false;
  final ip = r['ip'];
  if (ip is! List || ip.isEmpty) return false;
  if (ip.length == 1 && '${ip.first}' == 'geoip:private') return true;
  // Список считаем нашим, если он целиком состоит из приватных подсетей.
  return ip.every((e) => kPrivateNetworks.contains('$e'));
}

/// Правило — безусловный увод всего трафика в [target] (catch-all)?
/// Считаем таким, если оно ведёт в target и не сужено по ip/domain (network/port
/// допустимы — типовой хвост панельного профиля `{network:"tcp,udp",balancerTag}`).
bool _isCatchAllTo(dynamic r, Map<String, String> target) {
  if (r is! Map) return false;
  for (final e in target.entries) {
    if ('${r[e.key]}' != e.value) return false;
  }
  return r['ip'] == null && r['domain'] == null;
}
