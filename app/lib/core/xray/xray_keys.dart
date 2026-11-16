import 'dart:convert';

/// Ключи чужого Xray-конфига в том написании, в котором их читает наш код.
///
/// ⚠️ XRAY ЧИТАЕТ JSON СТАНДАРТНЫМ `encoding/json` Go: имя ключа сверяется с
/// полем БЕЗ УЧЁТА РЕГИСТРА. А нормализаторы (`override_normalizer.dart`,
/// `panel_direct_reroute.dart`, харнесс пинга) смотрят точное написание. До
/// ревью 29.10.2026 (H3) это давало обход каждой их проверки:
/// - `"Log":{"access":…}` — журнал ядра писался в любой путь, например в
///   «Автозагрузку»;
/// - `"Listen":"0.0.0.0"` у inbound — socks-порт приложения открывался всей сети;
/// - `"Routing"`/`"OutboundTag":"direct"` — трафик уходил под реальным IP мимо
///   реврайта;
/// - `"Api":{"services":["HandlerService"]}` — мимо белого списка служб.
///
/// Лечение — на входе: ключи, совпадающие с известными полями без учёта
/// регистра, переписываются в каноническое написание. Смысл для ядра тот же
/// (оно и так сверяет без регистра), а нормализаторы видят то, что увидит ядро.
/// Имена не из списка не трогаются: среди них ключи-данные (`headers.Host`,
/// домены в `dns.hosts`), и их написание значимо.
///
/// ⚠️ ДВА КЛЮЧА, РАВНЫХ БЕЗ УЧЁТА РЕГИСТРА, В ОДНОМ ОБЪЕКТЕ — ОТКАЗ. Go
/// разбирает их в одно поле и для вложенных объектов СЛИВАЕТ содержимое:
/// `{"log":{"access":"x"},"Log":{"loglevel":"warning"}}` даёт журнал в `x`.
/// Повторить это слияние точно нельзя, а честный конфиг так не пишут.
const _canonicalKeys = [
  // Разделы верхнего уровня.
  'log', 'api', 'dns', 'routing', 'policy', 'inbounds', 'outbounds',
  'transport', 'stats', 'reverse', 'fakedns', 'metrics', 'observatory',
  'burstObservatory',
  // log
  'access', 'error', 'loglevel', 'dnsLog', 'maskAddress',
  // api / metrics / inbound / outbound
  'tag', 'services', 'listen', 'port', 'protocol', 'settings', 'sniffing',
  'streamSettings', 'proxySettings', 'mux', 'sendThrough', 'allocate',
  // settings
  'auth', 'accounts', 'udp', 'user', 'pass', 'address', 'allowTransparent',
  // routing
  'domainStrategy', 'rules', 'balancers', 'type', 'outboundTag', 'balancerTag',
  'inboundTag', 'ip', 'domain', 'network', 'selector', 'fallbackTag',
  'strategy',
  // streamSettings
  'security', 'tlsSettings', 'realitySettings', 'sockopt', 'masterKeyLog',
  // policy
  'system', 'levels', 'statsInboundUplink', 'statsInboundDownlink',
  'statsOutboundUplink', 'statsOutboundDownlink',
];

final _byLower = {for (final k in _canonicalKeys) k.toLowerCase(): k};

/// Ключи двух записей в одном объекте совпали без учёта регистра.
class XrayDuplicateKeyException extends FormatException {
  XrayDuplicateKeyException(String path)
      : super('Xray-JSON: ключ «$path» повторяется в разном написании');
}

/// Копия [value] с каноническими ключами (см. [_canonicalKeys]).
///
/// Бросает [XrayDuplicateKeyException], если в объекте два ключа равны без
/// учёта регистра.
Object? canonicalXrayValue(Object? value, [String path = r'$']) {
  if (value is Map) {
    final out = <String, dynamic>{};
    final seen = <String>{};
    for (final e in value.entries) {
      final key = '${e.key}';
      final low = key.toLowerCase();
      final known = _byLower[low];
      // Только для известных полей: ключи-данные (`headers`, `dns.hosts`) Go
      // разбирает в map, где `Host` и `host` — разные записи.
      if (known != null && !seen.add(low)) {
        throw XrayDuplicateKeyException('$path.$key');
      }
      final name = known ?? key;
      out[name] = canonicalXrayValue(e.value, '$path.$name');
    }
    return out;
  } else if (value is List) {
    return [
      for (var i = 0; i < value.length; i++)
        canonicalXrayValue(value[i], '$path[$i]'),
    ];
  }
  return value;
}

/// Убрать `masterKeyLog` на любой глубине, в любом написании.
///
/// ⚠️ ПОЛЕ ПИШЕТ ФАЙЛ. В `tlsSettings`/`realitySettings` оно задаёт путь, куда
/// ядро дописывает ключи TLS-сессий: чужой конфиг или outbound панели получал
/// запись в любой путь пользователя (и расшифровку его трафика тем, кто файл
/// прочтёт). Нам это поле не нужно нигде (ревью 29.10.2026, L15).
void stripMasterKeyLog(Object? node) {
  if (node is Map) {
    node.removeWhere((k, _) => '$k'.toLowerCase() == 'masterkeylog');
    for (final v in node.values) {
      stripMasterKeyLog(v);
    }
  } else if (node is List) {
    for (final v in node) {
      stripMasterKeyLog(v);
    }
  }
}

/// [canonicalXrayValue] для строки JSON.
///
/// Не JSON — строка возвращается как есть: ядро само откажется её принять, и
/// причина в его журнале будет точнее нашей.
String canonicalXrayJson(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return raw;
  }
  return jsonEncode(canonicalXrayValue(decoded));
}
