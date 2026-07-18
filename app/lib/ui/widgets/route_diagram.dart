import 'package:flutter/material.dart';

import '../../core/settings/split_tunnel.dart';
import '../../core/i18n/enum_labels.dart';
import '../../l10n/gen/app_localizations.dart';
import 'app_icon.dart';

/// Наглядная схема: как пойдёт трафик при текущих настройках (#14.2).
///
/// Приложения и сайты группируются по действию: Туннель (через VPN), Прямо
/// (мимо VPN), Блок. «Остальное» показывается в той строке, куда его отправляет
/// базовый режим.
class RouteDiagram extends StatelessWidget {
  final SplitTunnelConfig split;
  const RouteDiagram({super.key, required this.split});

  List<AppRule> _apps(AppAction a) =>
      split.apps.where((r) => r.action == a).toList();
  int _sites(AppAction a) => split.sites.where((s) => s.action == a).length;

  bool get _baseViaVpn => split.mode != SplitMode.onlySelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Режим «Все — через VPN»: индивидуальные правила сохранены, но НЕ применяются
    // (весь трафик и так идёт в туннель), поэтому показываем простую схему
    // 💻 → 🔒 VPN → 🌐, без «прямых»/«блок» строк из ранее выбранных правил.
    if (split.mode == SplitMode.all) {
      return _card(context, [
        Text(splitModeLabel(l, split.mode),
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: scheme.primary)),
        const SizedBox(height: 10),
        _row(context, [
          _node(context, '💻', l.routeYourPc),
          _arrow(context),
          _node(context, '🔒', l.routeVpn),
          _arrow(context),
          _node(context, '🌐', l.routeInternet),
        ]),
      ]);
    }

    final blockApps = _apps(AppAction.block);
    final blockSites = _sites(AppAction.block);

    final directHasContent = _apps(AppAction.direct).isNotEmpty ||
        _sites(AppAction.direct) > 0 ||
        !_baseViaVpn;

    return _card(context, [
      Text(splitModeLabel(l, split.mode),
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: scheme.primary)),
      const SizedBox(height: 10),
      _row(context, _vpnChain(context)),
      if (directHasContent) ...[
        const SizedBox(height: 8),
        _row(context, _directChain(context), dim: true),
      ],
      if (blockApps.isNotEmpty || blockSites > 0) ...[
        const SizedBox(height: 8),
        _row(
            context,
            [
              _entriesNode(context, blockApps, blockSites, l.routeBlock),
              _arrow(context),
              _node(context, '🚫', l.routeBlocked),
            ],
            dim: true),
      ],
    ]);
  }

  /// Карточка-контейнер схемы (общий фон/отступы).
  Widget _card(BuildContext context, List<Widget> children) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  List<Widget> _vpnChain(BuildContext context) {
    final l = AppLocalizations.of(context);
    final apps = _apps(AppAction.tunnel);
    final sites = _sites(AppAction.tunnel);
    final hasMarked = apps.isNotEmpty || sites > 0;
    return [
      _node(context, '💻', l.routeYourPc),
      _arrow(context),
      if (hasMarked || !_baseViaVpn)
        _entriesNode(context, apps, sites, _baseViaVpn ? l.routeTunnel : l.routeViaVpn,
            includeRest: _baseViaVpn ? false : false),
      if (hasMarked || !_baseViaVpn) _arrow(context),
      _node(context, '🔒', l.routeVpn),
      _arrow(context),
      _node(context, '🌐', l.routeInternet),
    ];
  }

  List<Widget> _directChain(BuildContext context) {
    final l = AppLocalizations.of(context);
    final apps = _apps(AppAction.direct);
    final sites = _sites(AppAction.direct);
    // Если база — напрямую, «прямо» идёт всё остальное.
    if (!_baseViaVpn && apps.isEmpty && sites == 0) {
      return [
        _node(context, '💻', l.routeRest),
        _arrow(context),
        _node(context, '🌐', l.routeDirectly),
      ];
    }
    return [
      _entriesNode(context, apps, sites, !_baseViaVpn ? l.routeDirectPlusRest : l.routeDirect),
      _arrow(context),
      _node(context, '🌐', l.routeDirectly),
    ];
  }

  Widget _row(BuildContext context, List<Widget> children, {bool dim = false}) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Opacity(
      opacity: dim ? 0.65 : 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );
  }

  Widget _node(BuildContext context, String emoji, String label) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  /// Узел со списком приложений (иконки exe) и сайтов (🌍 с их числом).
  Widget _entriesNode(
      BuildContext context, List<AppRule> allApps, int siteCount, String label,
      {bool includeRest = false}) {
    final l = AppLocalizations.of(context);
    final apps = allApps.take(4).toList();
    final more = allApps.length - apps.length;
    if (apps.isEmpty && siteCount == 0) {
      return _node(context, '📄', l.routeEmptyList);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (final a in apps)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: a.byName ? a.name : a.path,
              child: AppIcon(path: a.path, size: 20),
            ),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text('+$more', style: Theme.of(context).textTheme.bodySmall),
          ),
        if (siteCount > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text('🌍$siteCount', style: const TextStyle(fontSize: 14)),
          ),
      ]),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _arrow(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.arrow_forward,
            size: 16, color: Theme.of(context).colorScheme.outline),
      );
}
