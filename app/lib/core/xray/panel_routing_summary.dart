import 'dart:convert';

/// Краткий разбор внутренней маршрутизации панельного «Авто»-профиля — чтобы
/// показать пользователю, что этот сервер делает со split-туннелированием (#3.2).
class PanelRoutingInfo {
  /// Сколько прокси-серверов в профиле (для автовыбора лучшего).
  final int serverCount;

  /// Часть трафика профиль пускает НАПРЯМУЮ (RU-routing и т.п.).
  final bool routesSomeDirect;

  /// Часть трафика профиль БЛОКИРУЕТ (реклама/торренты).
  final bool routesSomeBlock;

  const PanelRoutingInfo({
    required this.serverCount,
    required this.routesSomeDirect,
    required this.routesSomeBlock,
  });

  static const empty =
      PanelRoutingInfo(serverCount: 0, routesSomeDirect: false, routesSomeBlock: false);
}

// Кэш разбора: server_tile зовёт analyzePanelRouting в build НА КАЖДУЮ перерисовку
// (а конфиг профиля — до ~38 КБ JSON, jsonDecode на кадр — дорого). Ключ — сам
// конфиг; панельных профилей немного (по одному на сервер). Размер ограничен.
final Map<String, PanelRoutingInfo> _summaryCache = {};

/// Разбирает Xray-JSON панельного профиля: считает прокси-outbound'ы (не
/// freedom/blackhole/dns/api) и наличие direct/block в правилах роутинга.
/// Результат кэшируется по строке конфига (разбор в build — на каждую перерисовку).
PanelRoutingInfo analyzePanelRouting(String rawJson) {
  final cached = _summaryCache[rawJson];
  if (cached != null) return cached;
  final info = _analyzePanelRouting(rawJson);
  if (_summaryCache.length > 64) _summaryCache.clear();
  _summaryCache[rawJson] = info;
  return info;
}

PanelRoutingInfo _analyzePanelRouting(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return PanelRoutingInfo.empty;

    var servers = 0;
    final outs = decoded['outbounds'];
    if (outs is List) {
      for (final o in outs) {
        if (o is! Map) continue;
        final proto = '${o['protocol']}';
        if (proto == 'freedom' ||
            proto == 'blackhole' ||
            proto == 'dns' ||
            '${o['tag']}' == 'api') {
          continue;
        }
        servers++;
      }
    }

    var direct = false, block = false;
    final routing = decoded['routing'];
    if (routing is Map && routing['rules'] is List) {
      for (final r in (routing['rules'] as List)) {
        if (r is! Map) continue;
        final tag = '${r['outboundTag']}';
        if (tag == 'direct') direct = true;
        if (tag == 'block') block = true;
      }
    }

    return PanelRoutingInfo(
      serverCount: servers,
      routesSomeDirect: direct,
      routesSomeBlock: block,
    );
  } catch (_) {
    return PanelRoutingInfo.empty;
  }
}
