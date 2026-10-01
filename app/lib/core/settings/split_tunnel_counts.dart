/// Счётчики для заголовков свёрнутых списков раздельного туннелирования.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Свёрнутый список не показывает ничего, и заголовок
/// остаётся единственным, что о нём говорит. «Сайты» без чисел превращают
/// сворачивание в способ потерять список из виду, поэтому счётчики — часть
/// самой возможности, а не украшение.
///
/// ⚠️ ДЕЙСТВИЯ СЧИТАЮТСЯ ТОЛЬКО У ВКЛЮЧЁННЫХ ПРАВИЛ. Выключенное правило в
/// конфиг ядра не попадает (`_addActionRule` фильтрует по `enabled`), и
/// посчитать его в графе «блок» значило бы обещать блокировку, которой нет.
library;

import 'split_tunnel.dart';

/// Разбивка списка правил по состоянию и действию.
class RuleCounts {
  final int total;

  /// Включённые/выключенные. У сайтов выключения нет вовсе
  /// ([SiteRule] не имеет такого поля), поэтому там `disabled == 0`.
  final int enabled;
  final int disabled;

  /// Среди ВКЛЮЧЁННЫХ: сколько уходит в туннель, мимо и в отказ.
  final int tunnel;
  final int direct;
  final int block;

  const RuleCounts({
    required this.total,
    required this.enabled,
    required this.disabled,
    required this.tunnel,
    required this.direct,
    required this.block,
  });

  static const empty = RuleCounts(
      total: 0, enabled: 0, disabled: 0, tunnel: 0, direct: 0, block: 0);

  bool get isEmpty => total == 0;

  @override
  bool operator ==(Object other) =>
      other is RuleCounts &&
      other.total == total &&
      other.enabled == enabled &&
      other.disabled == disabled &&
      other.tunnel == tunnel &&
      other.direct == direct &&
      other.block == block;

  @override
  int get hashCode =>
      Object.hash(total, enabled, disabled, tunnel, direct, block);

  @override
  String toString() => 'RuleCounts(total: $total, enabled: $enabled, '
      'disabled: $disabled, tunnel: $tunnel, direct: $direct, block: $block)';
}

RuleCounts _count(Iterable<({bool enabled, AppAction action})> rules) {
  var total = 0, on = 0, off = 0, tunnel = 0, direct = 0, block = 0;
  for (final r in rules) {
    total++;
    if (!r.enabled) {
      off++;
      continue;
    }
    on++;
    switch (r.action) {
      case AppAction.tunnel:
        tunnel++;
      case AppAction.direct:
        direct++;
      case AppAction.block:
        block++;
    }
  }
  return RuleCounts(
      total: total,
      enabled: on,
      disabled: off,
      tunnel: tunnel,
      direct: direct,
      block: block);
}

RuleCounts countAppRules(Iterable<AppRule> apps) =>
    _count(apps.map((a) => (enabled: a.enabled, action: a.action)));

RuleCounts countSiteRules(Iterable<SiteRule> sites) =>
    _count(sites.map((s) => (enabled: true, action: s.action)));
