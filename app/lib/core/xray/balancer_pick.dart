import 'dart:convert';

/// Узел, через который балансировщик Xray ведёт трафик прямо сейчас.
///
/// ⚠️ АДРЕС, А НЕ ИМЯ. Ядро знает только тег outbound-а (`proxy-2`): у
/// профилей «Авто» от панели теги безымянные, имени узла в конфиге нет вовсе.
/// Имя находит состояние приложения — по адресу и порту среди серверов
/// подписки, где тот же узел лежит обычной строкой с названием.
class ActiveNode {
  final String tag;
  final String address;
  final int port;

  const ActiveNode({
    required this.tag,
    required this.address,
    required this.port,
  });

  @override
  bool operator ==(Object other) =>
      other is ActiveNode &&
      other.tag == tag &&
      other.address == address &&
      other.port == port;

  @override
  int get hashCode => Object.hash(tag, address, port);
}

/// Разбор конфига и ответа `xray api bi` для показа выбранного узла «Авто».
///
/// ⚠️ ЗАЧЕМ. «Авто (лучший)» и панельные «Авто …» — это балансировщик внутри
/// ядра: он сам выбирает узел по задержке и переключается на лету. Человек
/// видел только «Подключено» и не знал, в какой он стране. Решение владельца
/// 24.09.2026 — показывать узел, который выбран сейчас.
///
/// Чистые функции: ядро не нужно, тестируются на строках.
abstract final class BalancerPick {
  /// Есть ли в конфиге балансировщик вообще.
  static bool hasBalancer(Map<String, dynamic> cfg) =>
      _balancers(cfg).isNotEmpty;

  /// Тег балансировщика, который несёт ОСНОВНОЙ трафик.
  ///
  /// Балансировщиков у панели бывает несколько (свой на YouTube, свой на
  /// остальное). Основной — тот, на который указывает ПОСЛЕДНЕЕ правило с
  /// `balancerTag`: правила идут сверху вниз, и общее «всё остальное» стоит
  /// ниже частных. Правил нет — первый балансировщик.
  static String? mainBalancerTag(Map<String, dynamic> cfg) {
    final balancers = _balancers(cfg);
    if (balancers.isEmpty) return null;
    final routing = cfg['routing'];
    final rules = routing is Map && routing['rules'] is List
        ? routing['rules'] as List
        : const [];
    final known = {for (final b in balancers) b['tag']};
    for (final r in rules.reversed) {
      if (r is Map && known.contains(r['balancerTag'])) {
        return '${r['balancerTag']}';
      }
    }
    final first = balancers.first['tag'];
    return first is String && first.isNotEmpty ? first : null;
  }

  /// Выбранный тег из ответа `xray api bi -json <тег>`.
  ///
  /// Ответ ядра 26.3.27 (снят живьём):
  /// `{"balancer":{"override":{},"principleTarget":{"tag":["proxy-a"]}}}`.
  /// Ручная подмена (`override.target`) важнее выбора стратегии — так ядро и
  /// маршрутизирует. Пустой тег (`[""]`) бывает на холодном старте, когда
  /// замеров ещё нет: тогда `null`, а не пустая строка — трафик в этот момент
  /// идёт через `fallbackTag`, и выдать его за выбранный было бы неправдой.
  static String? parseBi(String stdout, String balancerTag) {
    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) return null;
      final b = decoded[balancerTag];
      if (b is! Map) return null;
      final override = b['override'];
      if (override is Map) {
        final t = override['target'];
        if (t is String && t.isNotEmpty) return t;
      }
      final principle = b['principleTarget'];
      if (principle is Map && principle['tag'] is List) {
        for (final t in principle['tag'] as List) {
          if (t is String && t.isNotEmpty) return t;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Адрес и порт outbound-а с тегом [tag] (vless/vmess — `vnext`,
  /// trojan/shadowsocks — `servers`).
  static ActiveNode? nodeOf(Map<String, dynamic> cfg, String tag) {
    final outbounds = cfg['outbounds'];
    if (outbounds is! List) return null;
    for (final o in outbounds) {
      if (o is! Map || o['tag'] != tag) continue;
      final settings = o['settings'];
      if (settings is! Map) return null;
      final list = settings['vnext'] is List
          ? settings['vnext'] as List
          : settings['servers'] is List
              ? settings['servers'] as List
              : const [];
      if (list.isEmpty || list.first is! Map) return null;
      final first = list.first as Map;
      final address = first['address'];
      final port = first['port'];
      final p = port is int ? port : int.tryParse('${port ?? ''}');
      if (address is! String || address.isEmpty || p == null) return null;
      return ActiveNode(tag: tag, address: address, port: p);
    }
    return null;
  }

  static List<Map> _balancers(Map<String, dynamic> cfg) {
    final routing = cfg['routing'];
    if (routing is! Map || routing['balancers'] is! List) return const [];
    return [
      for (final b in routing['balancers'] as List)
        if (b is Map && b['tag'] is String && (b['tag'] as String).isNotEmpty)
          b,
    ];
  }
}
