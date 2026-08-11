import 'package:flutter/material.dart';

import '../../core/settings/split_tunnel.dart';
import '../../core/i18n/enum_labels.dart';
import '../../l10n/gen/app_localizations.dart';
import 'app_icon.dart';
import 'app_label.dart';

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
  List<SiteRule> _sites(AppAction a) =>
      split.sites.where((s) => s.action == a).toList();

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
        _sites(AppAction.direct).isNotEmpty ||
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
      if (blockApps.isNotEmpty || blockSites.isNotEmpty) ...[
        const SizedBox(height: 8),
        _row(
            context,
            [
              _entriesNode(context, blockApps, blockSites),
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
    final hasMarked = apps.isNotEmpty || sites.isNotEmpty;
    return [
      _node(context, '💻', l.routeYourPc),
      _arrow(context),
      if (hasMarked || !_baseViaVpn)
        _entriesNode(context, apps, sites),
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
    //
    // ⚠️ ЗДЕСЬ БЫЛО `sites == 0`. Когда `_sites` сменил тип с `int` на
    // `List<SiteRule>`, три соседних сравнения обновили, а это — нет. Список
    // никогда не равен числу, поэтому условие давало `false` ВСЕГДА, и в
    // режиме «только отмеченные» схема рисовала лишнюю ветку вместо честного
    // «остальное — напрямую». Анализатор такое видит, но лишь как подсказку
    // уровня info (`unrelated_type_equality_checks`), и она тонет среди
    // семидесяти других.
    if (!_baseViaVpn && apps.isEmpty && sites.isEmpty) {
      return [
        _node(context, '💻', l.routeRest),
        _arrow(context),
        _node(context, '🌐', l.routeDirectly),
      ];
    }
    return [
      _entriesNode(context, apps, sites),
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
  ///
  /// ⚠️ ПОКАЗАННОЕ ЗДЕСЬ — ВСЕГДА ВЫЖИМКА. Иконок помещается четыре, сайты
  /// сворачиваются в одно число, и по такой схеме нельзя ответить на простой
  /// вопрос «а *_что_* именно у меня идёт через VPN». Поэтому весь узел
  /// целиком — и иконки, и «+N», и глобус — открывает всплывающий список со
  /// ВСЕМИ записями. Наведение на компьютере показывает то же самое подсказкой:
  /// на телефоне наведения нет, поэтому нажатие обязано работать всюду.
  /// ⚠️ ПОДПИСЬ ЛЕВОГО УЗЛА НАЗЫВАЕТ «ЧТО», А НЕ «КУДА».
  ///
  /// Раньше здесь стояло «Через VPN» и «Блок» — то есть ДЕЙСТВИЕ, при том что
  /// действие уже написано справа («VPN», «Заблокировано»). Схема читалась как
  /// «Через VPN → VPN → Интернет»: стрелка вела из действия в то же действие, а
  /// подлежащее — сами приложения и сайты — не называлось вовсе. Теперь слева
  /// стоит подлежащее, и строка читается как предложение:
  /// «Ваши приложения → VPN → Интернет».
  ///
  /// Текст выбирается по СОСТАВУ: пусто говорить «приложения», когда в правиле
  /// одни сайты.
  String _subjectLabel(AppLocalizations l, int appCount, int siteCount) {
    if (appCount > 0 && siteCount > 0) return l.routeAppsAndSites;
    return appCount > 0 ? l.routeYourApps : l.routeYourSites;
  }

  Widget _entriesNode(
      BuildContext context, List<AppRule> allApps, List<SiteRule> allSites) {
    final l = AppLocalizations.of(context);
    final apps = allApps.take(4).toList();
    final more = allApps.length - apps.length;
    final siteCount = allSites.length;
    if (apps.isEmpty && siteCount == 0) {
      return _node(context, '📄', l.routeEmptyList);
    }
    final label = _subjectLabel(l, allApps.length, siteCount);
    final content = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (final a in apps)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AppIcon(path: a.path, size: 20),
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

    final full = _fullList(allApps, allSites);
    return Tooltip(
      message: full,
      // Подсказка длинная — стандартная задержка заставляла бы ждать.
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showFullList(context, label, allApps, allSites),
        child: Padding(padding: const EdgeInsets.all(4), child: content),
      ),
    );
  }

  /// Полный список одной строкой — для подсказки при наведении.
  String _fullList(List<AppRule> apps, List<SiteRule> sites) => [
        for (final a in apps) a.byName ? a.name : a.path,
        for (final s in sites) s.label,
      ].join('\n');

  /// Полный список окном: он может не поместиться на экран, поэтому прокрутка.
  void _showFullList(BuildContext context, String label, List<AppRule> apps,
      List<SiteRule> sites) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final a in apps)
                ListTile(
                  dense: true,
                  leading: AppIcon(path: a.path, size: 22),
                  // Человеческое имя: на Android `name` — это имя пакета.
                  title: AppLabel(path: a.path, fallback: a.name),
                  // Путь нужен, чтобы отличить два одноимённых exe. У правила
                  // «по имени» путь не участвует в сопоставлении — и об этом
                  // честнее сказать прямо здесь, иначе человек добавляет одно и
                  // то же приложение по каждому новому пути после обновления.
                  subtitle: Text(
                    a.byName ? l.routeMatchByName : a.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final s in sites)
                ListTile(
                  dense: true,
                  leading: const Text('🌍', style: TextStyle(fontSize: 18)),
                  title: Text(s.label),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.commonClose),
          ),
        ],
      ),
    );
  }

  Widget _arrow(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.arrow_forward,
            size: 16, color: Theme.of(context).colorScheme.outline),
      );
}
