import '../core/models/vpn_server.dart';
import '../core/util/country_flag.dart';
import 'package:country_flags/country_flags.dart';
import '../state/app_state.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'layout/adaptive.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/singbox/exit_outbounds.dart';
import '../core/settings/split_service_presets.dart';
import '../core/settings/split_tunnel.dart';
import '../core/settings/split_tunnel_counts.dart';
import '../core/settings/split_tunnel_text.dart';
import '../core/settings/split_rule_layout.dart';
import '../core/platform/platform_services.dart';
import '../state/settings_controller.dart';
import '../core/util/server_search.dart';
import 'widgets/app_icon.dart';
import 'widgets/dead_path_badge.dart';
import 'widgets/flag_text.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';
import 'widgets/app_label.dart';
import 'widgets/route_diagram.dart';
import 'widgets/site_favicon.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/rule_counts_text.dart';
import 'widgets/rule_import_dialog.dart';
import 'widgets/sel_text.dart';
import 'widgets/app_toast.dart';
import 'widgets/drag_select_region.dart';
import 'widgets/extended_clipboard.dart';
import 'widgets/vpn_reload_prompt_dialog.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';

enum _SplitRuleMenuAction {
  toggleSelect,
  selectSubdomains,
  configure,
  routeTunnel,
  routeViaServer,
  routeDirect,
  routeBlock,
  toggleEnabled,
  copyValue,
  deleteRule,
}

/// Можно ли редактировать правила при таком способе захвата.
///
/// ⚠️ НЕ ТО ЖЕ САМОЕ, ЧТО «ПРАВИЛА ДЕЙСТВУЮТ ДЛЯ ВСЕЙ МАШИНЫ».
///
/// * `tun` — действуют полностью;
/// * `proxyOnly` — не действуют ни для одной программы машины (перехватывать
///   нечего), но список «Блок» применяется к локальным портам API при
///   включённом `AppSettings.applyRulesInProxyOnly`. Значит редактировать его
///   надо ЗДЕСЬ — а экран был заблокирован, и тумблер в настройках вёл в
///   никуда (находка финального ревью 8);
/// * `systemProxy` — не действуют вовсе: приложения сами решают, ходить ли
///   через прокси, и принудить их нечем.
bool splitRulesEditableIn(CaptureMode mode) => mode != CaptureMode.systemProxy;

/// Оговорки, которые интерфейс ОБЯЗАН произнести вслух при текущих настройках.
///
/// ⚠️ ЭТО РАЗБОР ЖАЛОБЫ, А НЕ УКРАШЕНИЕ. 19.08.2026 владелец написал: «kill
/// switch включён, а меня выбивает под реальным IP». Настройки при этом были
/// выставлены верно — врал интерфейс:
///
///  * в режиме «Только отмеченные» база маршрута — `direct`
///    (`SingboxConfigBuilder`: `finalOutbound = onlySelected ? 'direct' :
///    'proxy'`), то есть ВСЁ НЕОТМЕЧЕННОЕ выходит под настоящим адресом. Нигде
///    об этом не говорилось ни слова;
///  * галочка «Не выходить под реальным IP» обещала «весь „прямой“ трафик идёт
///    через VPN», хотя переписывает ТОЛЬКО явные правила «Прямо» и панельный
///    `direct` — базу она не трогает и в этом режиме не спасает;
///  * kill switch разбирает трафик по программам: пока ядро восстанавливается,
///    доменных правил не существует — некому разбирать имена.
///
/// Функция ЧИСТАЯ и живёт отдельно от вёрстки специально: проверять надо
/// условие, а не расположение плашки (`test/split_honesty_test.dart`).
enum SplitHonesty {
  /// «Только отмеченные»: неотмеченный трафик идёт под реальным IP.
  realIpByDefault,

  /// Правила по САЙТАМ kill switch не удерживает — он работает по программам.
  killSwitchIsPerApp,

  /// Kill switch в режиме системного прокси — не блокировка.
  killSwitchWeakInSystemProxy,
}

/// Какие оговорки нужны при этих настройках.
///
/// Гейт по способу захвата не формальность:
///  * `systemProxy` — правила раздельного туннелирования не применяются вовсе
///    (об этом экран говорит своей плашкой), и база маршрута ни на что не
///    влияет: через VPN идёт всё, что уважает прокси, независимо от режима;
///  * `proxyOnly` — машина целиком мимо туннеля, и это сказано отдельно;
///  * `tun` — единственный случай, где `finalOutbound` действительно решает
///    судьбу неотмеченного трафика.
Set<SplitHonesty> splitHonestyWarnings(AppSettings s) {
  final out = <SplitHonesty>{};
  final tun = s.captureMode == CaptureMode.tun;
  final only = s.splitTunnel.mode == SplitMode.onlySelected;
  if (tun && only) out.add(SplitHonesty.realIpByDefault);
  // Про сайты говорим там, где сайты есть: пустому списку оговорка не нужна.
  if (tun && only && s.killSwitch && s.splitTunnel.sites.isNotEmpty) {
    out.add(SplitHonesty.killSwitchIsPerApp);
  }
  // ⚠️ В режиме системного прокси kill switch держит трафик ОДНИМ способом —
  // оставляет прокси прописанным в реестре. Никаких фильтров и никаких прав
  // администратора: программа, которая прокси игнорирует, и весь UDP уходят
  // напрямую. Молчать об этом — обещать герметичность, которой нет.
  //
  // ⚠️ УСЛОВИЕ ПОЛНОЕ, А НЕ УРЕЗАННОЕ. Kill switch без автопереподключения
  // инертен (так задумано с 0.8.2), а в режиме «Только прокси» неприменим
  // вовсе (`killSwitchApplies`). Предупреждать о слабости того, что и так не
  // работает, — значит пугать на ровном месте.
  //
  // ⚠️ И ЭТО ЕДИНСТВЕННОЕ МЕСТО, ГДЕ УСЛОВИЕ ЖИВЁТ. Раньше экран настроек
  // разбирал его СВОИМ кодом, и два разбора уже разошлись: здесь было
  // `killSwitch && systemProxy`, там — плюс `killSwitchApplies` и
  // `autoReconnect`. Значение при этом вычислялось, покрывалось тремя тестами
  // и НИКЕМ не читалось: поправь кто-нибудь эту функцию — на экране не
  // изменилось бы ничего, а тесты остались бы зелёными.
  if (s.killSwitchApplies &&
      s.killSwitch &&
      s.autoReconnect &&
      s.captureMode == CaptureMode.systemProxy) {
    out.add(SplitHonesty.killSwitchWeakInSystemProxy);
  }
  return out;
}

class _SplitSitesScope extends InheritedWidget {
  final void Function(String query) onQueryChanged;
  final void Function(
    BuildContext context, {
    required String domain,
    required int? port,
    required bool alreadyExisted,
  }) onSiteSubmitted;

  const _SplitSitesScope({
    required this.onQueryChanged,
    required this.onSiteSubmitted,
    required super.child,
  });

  static _SplitSitesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitSitesScope>();

  @override
  bool updateShouldNotify(_SplitSitesScope oldWidget) => false;
}

class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key, this.openRulePath});

  /// Путь правила, к которому нужно сразу открыть диалог настройки.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО ЗДЕСЬ. Уведомление о мёртвом пути ([EngineNoticeKind.deadAppRule])
  /// ведёт «к этому правилу», а не просто на экран: открывать список и
  /// заставлять искать нужную строку среди остальных значило бы заново
  /// прятать то, что уведомление уже нашло. Диалог правила (`_appDialog`) и
  /// есть место починки — там же переключатель «по имени».
  final String? openRulePath;

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  String _siteQuery = '';
  String? _primaryHighlightNodeKey;
  String? _highlightFamilyDomain;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _siteRowKeys = <String, GlobalKey>{};
  final ScrollController _listScrollCtrl = ScrollController();
  final DragSelectController<String> _dragCtrl = DragSelectController<String>();
  bool _explicitSelectMode = false;
  final Set<String> _selectedRuleIds = <String>{};

  bool get _selectionMode =>
      _explicitSelectMode || _selectedRuleIds.isNotEmpty;

  static String _appSelId(AppRule r) => 'app:${r.matchKey}';
  static String _siteSelId(SiteRule s) =>
      'site:${s.domain.toLowerCase()}|${s.port ?? ''}';

  GlobalKey _keyForSiteNode(String nodeKey) =>
      _siteRowKeys.putIfAbsent(nodeKey, GlobalKey.new);

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _dragCtrl.dispose();
    _listScrollCtrl.dispose();
    super.dispose();
  }

  void _clearSelection() {
    if (!_selectionMode) return;
    setState(() {
      _selectedRuleIds.clear();
      _explicitSelectMode = false;
    });
  }

  void _toggleRuleSelection(String id) {
    setState(() {
      if (!_selectedRuleIds.remove(id)) {
        _selectedRuleIds.add(id);
      }
    });
  }

  void _toggleSelectAllVisible(List<String> visibleIds) {
    if (visibleIds.isEmpty) return;
    setState(() {
      final allSelected = visibleIds.every(_selectedRuleIds.contains);
      if (allSelected) {
        _selectedRuleIds.removeAll(visibleIds);
      } else {
        _selectedRuleIds.addAll(visibleIds);
      }
    });
  }

  Set<String> _validSelectedIds(SplitTunnelConfig st) {
    if (_selectedRuleIds.isEmpty) return const <String>{};
    final valid = <String>{
      for (final a in st.apps) _appSelId(a),
      for (final s in st.sites) _siteSelId(s),
    };
    return _selectedRuleIds.intersection(valid);
  }

  List<String> _computeVisibleRuleIds(
    SettingsController controller,
    SplitTunnelConfig st,
    bool editable,
  ) {
    if (!editable || st.mode == SplitMode.all) return const [];
    final out = <String>[];
    if (!controller.settings.splitAppsCollapsed) {
      for (final g in groupRulesByAction(st.apps, (r) => r.action)) {
        if (controller.settings.splitCollapsed
            .contains(splitGroupKey('apps', g.action))) {
          continue;
        }
        for (final r in g.rules) {
          out.add(_appSelId(r));
        }
      }
    }
    if (!controller.settings.splitSitesCollapsed) {
      final filtered = filterSiteRules(st.sites, _siteQuery);
      final collapsedSet = _siteQuery.trim().isNotEmpty
          ? const <String>{}
          : controller.settings.splitCollapsed.toSet();
      for (final g in groupRulesByAction(filtered, (x) => x.action)) {
        if (_siteQuery.trim().isEmpty &&
            controller.settings.splitCollapsed
                .contains(splitGroupKey('sites', g.action))) {
          continue;
        }
        final rows = siteTreeRows(
          [
            for (final x in filtered)
              if (x.action == g.action) x,
          ],
          collapsed: collapsedSet,
        );
        for (final row in rows) {
          if (!row.isVirtualGroup) {
            out.add(_siteSelId(row.site));
          }
        }
      }
    }
    return out;
  }

  void _promptReloadAfterBatchIfConnected(
    BuildContext context,
    SettingsController controller,
    AppState state,
    String? primarySubject,
  ) {
    if (!state.status.isConnected ||
        !splitRulesEditableIn(controller.settings.captureMode)) {
      return;
    }
    if (controller.settings.alwaysReloadVpnOnNewSite) {
      unawaited(state.reconnect(controller.settings));
    } else if (primarySubject != null && primarySubject.isNotEmpty) {
      unawaited(
        showVpnReloadPromptDialog(
          context,
          domain: primarySubject,
          settingsController: controller,
          appState: state,
          isLiveMismatch: false,
        ),
      );
    }
  }

  Future<void> _applyBatchRoute(
    BuildContext context,
    SettingsController controller,
    AppState state,
    Set<String> targetIds, {
    required AppAction action,
    bool pickServer = false,
  }) async {
    if (targetIds.isEmpty) return;
    final l = AppLocalizations.of(context);
    String? serverKey;
    if (pickServer) {
      final choice = await showDialog<RuleServerChoice>(
        context: context,
        builder: (_) => RuleServerPickerDialog(
          servers: state.servers,
          currentServer: state.selectedServer,
          serverKey: null,
        ),
      );
      if (choice == null || !context.mounted) return;
      serverKey = choice.key;
    }

    final effectiveServer = action == AppAction.tunnel ? serverKey : null;
    var touched = 0;
    var touchedApps = false;
    var touchedSites = false;
    String? subject;

    controller.update((cur) {
      final st = cur.splitTunnel;
      final nextApps = <AppRule>[
        for (final a in st.apps)
          if (targetIds.contains(_appSelId(a)))
            (() {
              touched++;
              touchedApps = true;
              subject ??= a.name;
              return a.copyWith(
                action: action,
                serverKey: effectiveServer,
                clearServer: effectiveServer == null,
              );
            })()
          else
            a,
      ];
      final nextSites = <SiteRule>[
        for (final x in st.sites)
          if (targetIds.contains(_siteSelId(x)))
            (() {
              touched++;
              touchedSites = true;
              subject ??= x.domain;
              return x.copyWith(
                action: action,
                serverKey: effectiveServer,
                clearServer: effectiveServer == null,
              );
            })()
          else
            x,
      ];
      final uncollapseKeys = <String>{
        if (touchedApps) splitGroupKey('apps', action),
        if (touchedSites) splitGroupKey('sites', action),
      };
      return cur.copyWith(
        splitCollapsed: cur.splitCollapsed
            .where((k) => !uncollapseKeys.contains(k))
            .toList(),
        splitTunnel: st.copyWith(apps: nextApps, sites: nextSites),
      );
    });

    _clearSelection();
    if (!context.mounted || touched == 0) return;
    AppToast.show(context, l.splitBatchUpdatedToast(touched));
    _promptReloadAfterBatchIfConnected(context, controller, state, subject);
  }

  void _toggleBatchAppsEnabled(
    BuildContext context,
    SettingsController controller,
    AppState state,
    Set<String> targetIds,
  ) {
    final st = controller.settings.splitTunnel;
    final selectedApps =
        st.apps.where((a) => targetIds.contains(_appSelId(a))).toList();
    if (selectedApps.isEmpty) return;
    final l = AppLocalizations.of(context);
    final enableNext = selectedApps.every((a) => !a.enabled);
    String? subject;
    controller.update((cur) {
      final nextApps = <AppRule>[
        for (final a in cur.splitTunnel.apps)
          if (targetIds.contains(_appSelId(a)))
            (() {
              subject ??= a.name;
              return a.copyWith(enabled: enableNext);
            })()
          else
            a,
      ];
      return cur.copyWith(
        splitTunnel: cur.splitTunnel.copyWith(apps: nextApps),
      );
    });
    _clearSelection();
    AppToast.show(context, l.splitBatchUpdatedToast(selectedApps.length));
    _promptReloadAfterBatchIfConnected(context, controller, state, subject);
  }

  void _deleteBatchRules(
    BuildContext context,
    SettingsController controller,
    AppState state,
    Set<String> targetIds,
  ) {
    if (targetIds.isEmpty) return;
    final l = AppLocalizations.of(context);
    var removed = 0;
    String? subject;
    final removedNodeKeys = <String>{};

    controller.update((cur) {
      final st = cur.splitTunnel;
      final nextApps = <AppRule>[];
      for (final a in st.apps) {
        if (targetIds.contains(_appSelId(a))) {
          removed++;
          subject ??= a.name;
        } else {
          nextApps.add(a);
        }
      }
      final nextSites = <SiteRule>[];
      for (final x in st.sites) {
        if (targetIds.contains(_siteSelId(x))) {
          removed++;
          subject ??= x.domain;
          removedNodeKeys.add(siteNodeKey(x));
        } else {
          nextSites.add(x);
        }
      }
      return cur.copyWith(
        splitCollapsed: cur.splitCollapsed
            .where((k) => !removedNodeKeys.contains(k))
            .toList(),
        splitTunnel: st.copyWith(apps: nextApps, sites: nextSites),
      );
    });

    _clearSelection();
    if (removed == 0) return;
    AppToast.show(context, l.splitBatchRemovedToast(removed));
    _promptReloadAfterBatchIfConnected(context, controller, state, subject);
  }

  Future<void> _openRuleContextMenu(
    BuildContext context,
    Offset globalPos,
    SettingsController controller,
    AppState state, {
    AppRule? appRule,
    SiteRule? siteRule,
    bool isVirtualGroup = false,
  }) async {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final st = controller.settings.splitTunnel;
    final activeSelected = _validSelectedIds(st);

    if (isVirtualGroup && siteRule != null) {
      final familyIds = <String>{
        for (final x in st.sites)
          if (x.action == siteRule.action &&
              isSameDomainFamily(x.domain, siteRule.domain))
            _siteSelId(x),
      };
      if (familyIds.isEmpty) return;
      final chosen = await showMenu<_SplitRuleMenuAction>(
        context: context,
        position: RelativeRect.fromRect(
          globalPos & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem(
            value: _SplitRuleMenuAction.selectSubdomains,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist_rtl_rounded, size: 18),
              title: Text(l.splitMenuSelectSubdomains(siteRule.domain)),
            ),
          ),
        ],
      );
      if (chosen == _SplitRuleMenuAction.selectSubdomains && mounted) {
        setState(() => _selectedRuleIds.addAll(familyIds));
      }
      return;
    }

    final itemId = appRule != null
        ? _appSelId(appRule)
        : (siteRule != null ? _siteSelId(siteRule) : '');
    if (itemId.isEmpty) return;

    final isItemSelected = activeSelected.contains(itemId);
    final targetIds = (isItemSelected && activeSelected.length > 1)
        ? activeSelected
        : <String>{itemId};
    final hasAnyAppInTarget =
        st.apps.any((a) => targetIds.contains(_appSelId(a)));
    final allTargetAppsDisabled = hasAnyAppInTarget &&
        st.apps
            .where((a) => targetIds.contains(_appSelId(a)))
            .every((a) => !a.enabled);

    final chosen = await showMenu<_SplitRuleMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _SplitRuleMenuAction.toggleSelect,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              isItemSelected ? Icons.check_box_outline_blank : Icons.check_box,
              size: 18,
            ),
            title: Text(
              isItemSelected ? l.liveConnsMenuDeselect : l.liveConnsMenuSelect,
            ),
          ),
        ),
        if (targetIds.length == 1)
          PopupMenuItem(
            value: _SplitRuleMenuAction.configure,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune, size: 18),
              title: Text(l.splitMenuConfigure),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _SplitRuleMenuAction.routeTunnel,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vpn_lock, size: 18, color: scheme.primary),
            title: Text(appActionLabel(l, AppAction.tunnel)),
          ),
        ),
        PopupMenuItem(
          value: _SplitRuleMenuAction.routeViaServer,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.public, size: 18, color: scheme.primary),
            title: Text(l.splitBatchViaServer),
          ),
        ),
        PopupMenuItem(
          value: _SplitRuleMenuAction.routeDirect,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.arrow_outward,
              size: 18,
              color: Colors.blueGrey,
            ),
            title: Text(appActionLabel(l, AppAction.direct)),
          ),
        ),
        PopupMenuItem(
          value: _SplitRuleMenuAction.routeBlock,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block, size: 18, color: scheme.error),
            title: Text(appActionLabel(l, AppAction.block)),
          ),
        ),
        if (hasAnyAppInTarget)
          PopupMenuItem(
            value: _SplitRuleMenuAction.toggleEnabled,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                allTargetAppsDisabled
                    ? Icons.toggle_on_outlined
                    : Icons.toggle_off_outlined,
                size: 18,
              ),
              title: Text(
                allTargetAppsDisabled ? l.splitBatchEnable : l.splitBatchDisable,
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _SplitRuleMenuAction.copyValue,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.copy, size: 18),
            title: Text(appRule != null ? l.splitCopyPath : l.splitCopyDomain),
          ),
        ),
        PopupMenuItem(
          value: _SplitRuleMenuAction.deleteRule,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, size: 18, color: scheme.error),
            title: Text(
              l.splitRemove,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
      ],
    );

    if (chosen == null || !context.mounted) return;
    switch (chosen) {
      case _SplitRuleMenuAction.toggleSelect:
        _toggleRuleSelection(itemId);
      case _SplitRuleMenuAction.selectSubdomains:
        break;
      case _SplitRuleMenuAction.configure:
        if (appRule != null) {
          await _appDialog(context, controller, appRule);
        } else if (siteRule != null) {
          await _siteDialog(context, controller, siteRule);
        }
      case _SplitRuleMenuAction.routeTunnel:
        await _applyBatchRoute(
          context,
          controller,
          state,
          targetIds,
          action: AppAction.tunnel,
        );
      case _SplitRuleMenuAction.routeViaServer:
        await _applyBatchRoute(
          context,
          controller,
          state,
          targetIds,
          action: AppAction.tunnel,
          pickServer: true,
        );
      case _SplitRuleMenuAction.routeDirect:
        await _applyBatchRoute(
          context,
          controller,
          state,
          targetIds,
          action: AppAction.direct,
        );
      case _SplitRuleMenuAction.routeBlock:
        await _applyBatchRoute(
          context,
          controller,
          state,
          targetIds,
          action: AppAction.block,
        );
      case _SplitRuleMenuAction.toggleEnabled:
        _toggleBatchAppsEnabled(context, controller, state, targetIds);
      case _SplitRuleMenuAction.copyValue:
        final text = appRule != null ? appRule.path : (siteRule?.label ?? '');
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) AppToast.copied(context);
      case _SplitRuleMenuAction.deleteRule:
        _deleteBatchRules(context, controller, state, targetIds);
    }
  }

  Widget _buildBatchActionBar(
    BuildContext context,
    SettingsController controller,
    AppState state,
    AppLocalizations l,
    Set<String> activeSelectedIds,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final st = controller.settings.splitTunnel;
    final selectedApps =
        st.apps.where((a) => activeSelectedIds.contains(_appSelId(a))).toList();
    final hasApps = selectedApps.isNotEmpty;
    final enableNext = hasApps && selectedApps.every((a) => !a.enabled);

    return SafeArea(
      top: false,
      child: Container(
        key: const Key('splitBatchActionBar'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              key: const Key('splitBatchTunnel'),
              onPressed: () => _applyBatchRoute(
                context,
                controller,
                state,
                activeSelectedIds,
                action: AppAction.tunnel,
              ),
              icon: const Icon(Icons.vpn_lock, size: 17),
              label: Text(appActionLabel(l, AppAction.tunnel)),
            ),
            FilledButton.tonalIcon(
              key: const Key('splitBatchViaServer'),
              onPressed: () => _applyBatchRoute(
                context,
                controller,
                state,
                activeSelectedIds,
                action: AppAction.tunnel,
                pickServer: true,
              ),
              icon: const Icon(Icons.public, size: 17),
              label: Text(l.splitBatchViaServer),
            ),
            OutlinedButton.icon(
              key: const Key('splitBatchDirect'),
              onPressed: () => _applyBatchRoute(
                context,
                controller,
                state,
                activeSelectedIds,
                action: AppAction.direct,
              ),
              icon: const Icon(Icons.arrow_outward, size: 17),
              label: Text(appActionLabel(l, AppAction.direct)),
            ),
            OutlinedButton.icon(
              key: const Key('splitBatchBlock'),
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => _applyBatchRoute(
                context,
                controller,
                state,
                activeSelectedIds,
                action: AppAction.block,
              ),
              icon: const Icon(Icons.block, size: 17),
              label: Text(appActionLabel(l, AppAction.block)),
            ),
            if (hasApps)
              OutlinedButton.icon(
                key: const Key('splitBatchToggleEnabled'),
                onPressed: () => _toggleBatchAppsEnabled(
                  context,
                  controller,
                  state,
                  activeSelectedIds,
                ),
                icon: Icon(
                  enableNext
                      ? Icons.toggle_on_outlined
                      : Icons.toggle_off_outlined,
                  size: 18,
                ),
                label: Text(
                  enableNext ? l.splitBatchEnable : l.splitBatchDisable,
                ),
              ),
            IconButton(
              key: const Key('splitBatchDelete'),
              tooltip: l.splitRemove,
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: () => _deleteBatchRules(
                context,
                controller,
                state,
                activeSelectedIds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSiteQueryChanged(String query) {
    if (_siteQuery == query) return;
    setState(() => _siteQuery = query);
    if (query.trim().isNotEmpty) {
      final controller = context.read<SettingsController>();
      if (controller.settings.splitSitesCollapsed) {
        controller.update((s) => s.copyWith(splitSitesCollapsed: false));
      }
    }
  }

  void _onSiteSubmitted(
    BuildContext submitContext, {
    required String domain,
    required int? port,
    required bool alreadyExisted,
  }) {
    final controller = context.read<SettingsController>();
    final state = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final targetKey =
        siteNodeKey(SiteRule(domain, port: port, action: AppAction.tunnel));

    _highlightTimer?.cancel();
    setState(() {
      _siteQuery = '';
      _primaryHighlightNodeKey = targetKey;
      _highlightFamilyDomain = domain;
    });
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _primaryHighlightNodeKey = null;
        _highlightFamilyDomain = null;
      });
    });

    if (alreadyExisted) {
      AppToast.show(context, l.splitSiteAlreadyExists);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowCtx = _siteRowKeys[targetKey]?.currentContext ??
          _siteRowKeys[virtualGroupNodeKey(baseDomain(domain))]?.currentContext;
      if (rowCtx != null) {
        Scrollable.ensureVisible(
          rowCtx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.28,
        );
      }
    });

    if (!alreadyExisted &&
        state.status.isConnected &&
        splitRulesEditableIn(controller.settings.captureMode)) {
      if (controller.settings.alwaysReloadVpnOnNewSite) {
        unawaited(state.reconnect(controller.settings));
      } else {
        unawaited(showVpnReloadPromptDialog(
          context,
          domain: domain,
          settingsController: controller,
          appState: state,
          isLiveMismatch: false,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    // Серверы и текущий выбор — из состояния приложения: правило указывает на
    // сервер напрямую, поэтому список нужен и строкам, и диалогам.
    final state = context.watch<AppState>();
    final st = controller.settings.splitTunnel;
    // #2 — при системном прокси раздельное туннелирование не работает
    // (приложения сами решают, ходить ли через прокси): контролы серые.
    final mode = controller.settings.captureMode;
    final tunActive = mode == CaptureMode.tun;
    // ⚠️ В «Только прокси» ЭКРАН РЕДАКТИРУЕМ, ХОТЬ TUN И НЕ ВКЛЮЧЁН —
    // см. [splitRulesEditableIn], там же почему.
    final editable = splitRulesEditableIn(mode);
    final l = AppLocalizations.of(context);
    final visibleRuleIds = _computeVisibleRuleIds(controller, st, editable);
    _dragCtrl.orderedIds = visibleRuleIds;
    final activeSelectedIds = _validSelectedIds(st);
    final inSelectMode =
        editable && st.mode != SplitMode.all && (_explicitSelectMode || activeSelectedIds.isNotEmpty);

    final scaffold = PopScope(
      canPop: !inSelectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inSelectMode) _clearSelection();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          if (inSelectMode)
            const SingleActivator(LogicalKeyboardKey.escape): _clearSelection,
        },
        child: Scaffold(
          appBar: inSelectMode
              ? AppBar(
                  leading: IconButton(
                    key: const Key('splitCancelSelectionBtn'),
                    tooltip: l.splitBatchCancel,
                    icon: const Icon(Icons.close),
                    onPressed: _clearSelection,
                  ),
                  title: Text(l.splitSelectedCount(activeSelectedIds.length)),
                  actions: [
                    IconButton(
                      key: const Key('splitSelectAllBtn'),
                      tooltip: l.splitSelectAllVisible,
                      icon: const Icon(Icons.select_all_rounded),
                      onPressed: visibleRuleIds.isEmpty
                          ? null
                          : () => _toggleSelectAllVisible(visibleRuleIds),
                    ),
                  ],
                )
              : AppBar(title: Text(l.splitTitle)),
          bottomNavigationBar: (inSelectMode && activeSelectedIds.isNotEmpty)
              ? _buildBatchActionBar(
                  context,
                  controller,
                  state,
                  l,
                  activeSelectedIds,
                )
              : null,
          body: DragSelectRegion<String>(
            controller: _dragCtrl,
            scrollController: _listScrollCtrl,
            enabled: editable && st.mode != SplitMode.all,
            isSelectionMode: inSelectMode,
            selectedIds: activeSelectedIds,
            onSelectionChanged: (next, {required enteredSelectionMode}) {
              setState(() {
                _selectedRuleIds
                  ..clear()
                  ..addAll(next);
              });
            },
            child: ListView(
              controller: _listScrollCtrl,
              children: [
          if (!tunActive)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: SelText(mode == CaptureMode.proxyOnly
                      ? l.splitProxyOnlyBanner
                      : l.splitTunOnlyBanner),
                ),
                // Кнопка «Включить TUN» — только там, где менять режим и
                // правда нужно. В «Только прокси» её нет: режим выбран
                // осознанно (ради портов API), и предлагать выйти из него
                // ради правил, которые тут и так частично работают, — совет
                // против намерения пользователя.
                if (mode != CaptureMode.proxyOnly)
                  TextButton(
                    onPressed: () => controller.update(
                        (s) => s.copyWith(captureMode: CaptureMode.tun)),
                    child: Text(l.splitEnableTun),
                  ),
              ]),
            ),
          // #2 — при системном прокси всё серое и неактивное.
          IgnorePointer(
            ignoring: !editable,
            child: Opacity(
              opacity: editable ? 1 : 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ⚠️ Пока «Не выходить под реальным IP» включено, часть
                  // правил «Прямо» работает не так, как написано в строке.
                  // Молчать об этом нельзя: человек видит «Прямо» и считает,
                  // что трафик идёт прямо.
                  if (controller.settings.noRealIp)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.shield_outlined, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelText(l.splitNoRealIpBanner,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ]),
                    ),
                  _header(context, l.splitModeHeader, l.infoSplitMode),
                  ...SplitMode.values.map((m) => RadioListTile<SplitMode>(
                        value: m,
                        groupValue: st.mode,
                        onChanged: (v) => controller.update((s) => s.copyWith(
                            splitTunnel: s.splitTunnel.copyWith(mode: v))),
                        title: Text(splitModeLabel(l, m)),
                      )),
                  // ⚠️ КРАСНАЯ ПЛАШКА УБРАНА ПО ПРЯМОМУ ТРЕБОВАНИЮ ВЛАДЕЛЬЦА
                  // (02.09.2026, повторное). Она занимала треть экрана над
                  // списками и висела постоянно, а не по событию.
                  //
                  // ⚠️ САМ ФАКТ НИКУДА НЕ ДЕЛСЯ И ОСТАЁТСЯ ВЕРНЫМ: в режиме
                  // «Только отмеченные» всё неотмеченное идёт под реальным
                  // адресом (`singbox_config_builder.dart`, finalOutbound =
                  // direct), и галочка «Не выходить под реальным IP» этого не
                  // меняет. Текст жив в `splitHonestyWarnings` и в переводах —
                  // если решите вернуть предупреждение в другом виде
                  // (подсказка «!», строка под переключателем), брать оттуда,
                  // а не писать заново.
                  // #14.2 — наглядно, как пойдёт трафик при текущем режиме.
                  RouteDiagram(split: st),
                  const Divider(),
                  // ⚠️ ВЫШЕ блока «списки при не-all режиме» намеренно: выходы
                  // действуют и в режиме «Всё через VPN». Там нет ни «Прямо»,
                  // ни «Блока», но вопрос «в какой туннель» остаётся.
                  // «Все через VPN» — исключений нет, списки приложений/сайтов не
                  // показываем: и так понятно, что весь трафик идёт через VPN.
                  if (st.mode != SplitMode.all) ...[
                  const Divider(),
                  // ⚠️ ЗАГОЛОВОК, ИНСТРУМЕНТЫ, ПОТОМ СПИСОК — именно в таком
                  // порядке и внутри КАЖДОГО блока. У человека с сотнями
                  // правил добавление, лежащее под списком, недостижимо без
                  // прокрутки через весь список (прямое требование владельца).
                  _listHeader(
                    context,
                    l,
                    title: l.splitAppsHeader,
                    info: l.infoSplitApps,
                    counts: countAppRules(st.apps),
                    collapsed: controller.settings.splitAppsCollapsed,
                    onToggle: () => controller.update((s) => s.copyWith(
                        splitAppsCollapsed: !s.splitAppsCollapsed)),
                  ),
                  _appTools(context, controller, state, l),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SelText(
                      l.splitAppsHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  // Подгруппы по действию (Туннель → Прямо → Блок), внутри
                  // новые сверху — решение владельца 11.10.2026. Раскладка в
                  // `split_rule_layout.dart`; порядок на диске не меняется.
                  if (!controller.settings.splitAppsCollapsed)
                  ...groupRulesByAction(st.apps, (r) => r.action).expand((g) => [
                  _groupHeader(context, controller, l,
                      list: 'apps', action: g.action, count: g.rules.length),
                  if (!controller.settings.splitCollapsed
                      .contains(splitGroupKey('apps', g.action)))
                  ...g.rules.map((rule) {
                    final selId = _appSelId(rule);
                    final isRuleSelected = activeSelectedIds.contains(selId);
                    return DragSelectItem<String>(
                      key: ValueKey('dragApp:${rule.matchKey}'),
                      id: selId,
                      controller: _dragCtrl,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapUp: (d) => _openRuleContextMenu(
                          context,
                          d.globalPosition,
                          controller,
                          state,
                          appRule: rule,
                        ),
                        onLongPressStart: (d) => _openRuleContextMenu(
                          context,
                          d.globalPosition,
                          controller,
                          state,
                          appRule: rule,
                        ),
                        child: Opacity(
                          opacity: rule.enabled ? 1 : 0.45,
                          child: ListTile(
                            key: ValueKey('app:${rule.path}'),
                            selected: inSelectMode && isRuleSelected,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.11),
                            leading:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Checkbox(
                                value:
                                    inSelectMode ? isRuleSelected : rule.enabled,
                                onChanged: inSelectMode
                                    ? (_) => _toggleRuleSelection(selId)
                                    : (v) => _updateApp(controller, rule,
                                        enabled: v ?? true),
                              ),
                              AppIcon(
                                  path: rule.path), // #1 — реальная иконка exe
                            ]),
                          dense: context.sg.isCompact,
                          // Человеческое имя приложения, а не ключ правила. На
                          // Windows ключ и есть имя файла, на Android — имя
                          // пакета, и без этого в строке стояло
                          // «com.google.android.youtube» при верной иконке.
                          title: AppLabel(
                              path: rule.path, fallback: rule.name),
                          subtitle: _ruleSubtitle(
                            context,
                            rule.enabled
                                // На Android сопоставления «по имени/по пути»
                                // нет — там имя пакета, и подпись «По имени ·
                                // com.android.chrome» только путала.
                                // ⚠️ Показываем ТО, ПО ЧЕМУ РЕАЛЬНО СРАВНИВАЕМ.
                                // Раньше подпись гласила «По имени · <полный
                                // путь>» — то есть называла способ, а
                                // показывала поле, к сопоставлению отношения не
                                // имеющее. Четыре записи одной программы, все
                                // с разными путями, выглядели разными
                                // правилами, хотя правило было одно.
                                ? (Platform.isAndroid || Platform.isIOS
                                    ? rule.path
                                    : '${rule.byName ? l.splitByName : l.splitByPath}'
                                        ' · ${rule.byName ? rule.name : rule.path}')
                                : l.splitRuleDisabled,
                            action: rule.action,
                            allowRealIp: rule.allowRealIp,
                            noRealIp: rule.enabled && controller.settings.noRealIp,
                          ),
                          // ⚠️ НА ТЕЛЕФОНЕ КНОПКИ УДАЛЕНИЯ ЗДЕСЬ НЕТ, И ЭТО НЕ ПОТЕРЯ.
                          //
                          // Считано на 360 dp: слева 104 dp занимают отступ,
                          // галочка и иконка, справа чип с кнопкой — ещё 120.
                          // Названию приложения оставалось около 120 dp, то
                          // есть примерно двенадцать символов. Удаление и так
                          // доступно в диалоге, который открывается по тапу на
                          // строку, поэтому на компактном экране кнопка уходит
                          // и освобождает 48 dp. На десктопе она остаётся: там
                          // мышь, hover и подсказка работают, а места хватает.
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            // Правило по пути на исчезнувший файл: молчать о нём
                            // нельзя — оно выглядит здоровым и не совпадает ни с
                            // чем (воспроизведено опытом, см. DeadPathBadge).
                            DeadPathBadge(
                              rule: rule,
                              onSwitchToName: () =>
                                  _updateApp(controller, rule, byName: true),
                            ),
                            ServerBadge(
                                servers: state.servers,
                                serverKey: rule.serverKey,
                                action: rule.action),
                            _ActionChip(action: rule.action),
                            if (!context.sg.isCompact)
                              IconButton(
                                tooltip: l.splitRemove,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeApp(controller, rule),
                              ),
                          ]),
                            onTap: () {
                              if (_dragCtrl.consumeTapSuppression()) return;
                              if (inSelectMode) {
                                _toggleRuleSelection(selId);
                              } else {
                                _appDialog(context, controller, rule);
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  }),
                  ]),
                  const Divider(),
                  _listHeader(
                    context,
                    l,
                    title: l.splitSitesHeader,
                    info: l.infoSplitDomains,
                    counts: countSiteRules(st.sites),
                    collapsed: controller.settings.splitSitesCollapsed,
                    onToggle: () => controller.update((s) => s.copyWith(
                        splitSitesCollapsed: !s.splitSitesCollapsed)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: _AddSiteField(controller: controller),
                  ),
                  _siteTools(context, controller, state, l),
                  _quickServiceChips(context, controller, state, l),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SelText(
                      l.splitSitesHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  // Уведомление о блокировке — рядом со списком, который его
                  // и порождает, но ВЫШЕ самого списка: иначе до галочки
                  // пришлось бы прокручивать все правила.
                  SwitchListTile(
                    secondary: const Icon(Icons.sync_outlined),
                    value: controller.settings.alwaysReloadVpnOnNewSite,
                    onChanged: (v) => controller.update(
                        (s) => s.copyWith(alwaysReloadVpnOnNewSite: v)),
                    title: Text(l.splitAlwaysReloadOnNewSite),
                  ),
                  if (st.sites.any((x) => x.action == AppAction.block))
                    SwitchListTile(
                      secondary:
                          const Icon(Icons.notifications_active_outlined),
                      value: controller.settings.blockNoticeEnabled,
                      onChanged: (v) => controller
                          .update((s) => s.copyWith(blockNoticeEnabled: v)),
                      title: Text(l.blockNoticeTitle),
                      subtitle: SelText(l.blockNoticeSub,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (!controller.settings.splitSitesCollapsed) ...[
                  if (_siteQuery.trim().isNotEmpty &&
                      filterSiteRules(st.sites, _siteQuery).isEmpty)
                    Padding(
                      key: const Key('splitSiteSearchEmpty'),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: SelText(
                        l.splitSiteSearchEmpty(_siteQuery.trim()),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ),
                  ...groupRulesByAction(
                          filterSiteRules(st.sites, _siteQuery), (x) => x.action)
                      .expand((g) => [
                  _groupHeader(context, controller, l,
                      list: 'sites', action: g.action, count: g.rules.length),
                  if (_siteQuery.trim().isNotEmpty ||
                      !controller.settings.splitCollapsed
                          .contains(splitGroupKey('sites', g.action)))
                  ...siteTreeRows(
                    [
                      for (final x in filterSiteRules(st.sites, _siteQuery))
                        if (x.action == g.action) x
                    ],
                    collapsed: _siteQuery.trim().isNotEmpty
                        ? const <String>{}
                        : controller.settings.splitCollapsed.toSet(),
                  ).expand((e) => [
                        if (e.newGroup)
                          const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
                        _siteTile(context, controller, e),
                      ]),
                  ]),
                  ],
                  // ⚠️ Побочный эффект правил по сайтам, о котором нельзя
                  // молчать: приложение глушит HTTP/3 для ВСЕГО трафика, а не
                  // только для перечисленных доменов. Иначе правило по сайту
                  // молча не срабатывает — браузер на HTTP/3 имени не
                  // оставляет. Пользователь имеет право знать, почему у него
                  // пропал HTTP/3, хотя он такого не просил.
                  if (st.sites.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).hintColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelText(
                              l.splitQuicNote,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context).hintColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // ⚠️ Уведомление о блокировке («Сообщать о заблокированных
                  // сайтах») переехало НАВЕРХ, в `_topTools`, по просьбе
                  // владельца — вместе с полем добавления сайта. Гейт там тот
                  // же: показываем, лишь когда есть правило «Блок».
                  //
                  // ⚠️ ЗДЕСЬ БЫЛА СТРАНИЦА-ЗАГЛУШКА. Она подменяла ответ по
                  // http и до пользователя почти никогда не доходила: браузеры
                  // идут в https сразу, HSTS переписывает адрес ДО отправки
                  // запроса, и человек видел `ERR_CONNECTION_RESET` вместо
                  // объяснения. Подменить https без своего корневого
                  // сертификата нельзя, а ставить такой сертификат — значит
                  // получить возможность читать весь TLS пользователя. Поэтому
                  // объяснение переехало туда, где оно работает всегда, —
                  // в само приложение.
                  ], // конец блока «списки при не-all режиме»
                ],
              ),
            ),
          ),
        ],
            ),
          ),
        ),
      ),
    );

    final scoped = _SplitSitesScope(
      onQueryChanged: _onSiteQueryChanged,
      onSiteSubmitted: _onSiteSubmitted,
      child: scaffold,
    );
    final path = widget.openRulePath;
    if (path == null) return scoped;
    final matches = st.apps.where((r) => r.path == path).toList();
    if (matches.isEmpty) return scoped;
    return _OpenRuleOnce(
      key: ValueKey('openRuleOnce:$path'),
      onShow: () => _appDialog(context, controller, matches.first),
      child: scoped,
    );
  }

  Widget _header(BuildContext context, String title, String info) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          SelText(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
          InfoTooltip(info, title: title),
        ]),
      );

  /// Заголовок блока: название, «!», сводка числами и сворачивание.
  ///
  /// ⚠️ СВОДКА — ЧАСТЬ СВОРАЧИВАНИЯ, А НЕ УКРАШЕНИЕ. Свёрнутый список не
  /// показывает ничего, и без чисел человек не видит даже того, остались ли
  /// там правила. Строится в [formatRuleCounts].
  ///
  /// ⚠️ Внутри заголовка `Text`, а не `SelText`: строка кликабельна целиком, а
  /// жест выделения выигрывает арену у `InkWell` — заголовок перестал бы
  /// сворачиваться (тот же случай, что с `SelText` в строках списков).
  Widget _listHeader(
    BuildContext context,
    AppLocalizations l, {
    required String title,
    required String info,
    required RuleCounts counts,
    required bool collapsed,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 4, 2),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                  InfoTooltip(info, title: title),
                ]),
                Text(formatRuleCounts(l, counts),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          IconButton(
            tooltip: collapsed ? l.splitExpandList : l.splitCollapseList,
            icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
            onPressed: onToggle,
          ),
        ]),
      ),
    );
  }

  Widget _appTools(BuildContext context, SettingsController controller,
          AppState state, AppLocalizations l) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: OverflowBar(
          alignment: MainAxisAlignment.start,
          spacing: 4,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.list),
              // Формулировка зависит от платформы: на Windows каталог
              // строится из ЗАПУЩЕННЫХ процессов, на Android система отдаёт
              // список УСТАНОВЛЕННЫХ приложений. Назвать их «запущенными»
              // значило бы обмануть — человек стал бы искать в списке то,
              // что сейчас открыто.
              label: Text(platform.appCatalog.supportsManualPick
                  ? l.splitFromRunning
                  : l.splitPickInstalled),
              onPressed: () => _pickRunning(context, controller),
            ),
            // Выбор файла вручную осмыслен там, где правило адресует
            // исполняемый файл (Windows). На Android правило — это
            // packageName, и весь список даёт сама система.
            if (platform.appCatalog.supportsManualPick)
              TextButton.icon(
                icon: const Icon(Icons.folder_open),
                label: Text(l.splitPickExe),
                onPressed: () => _pickExe(context, controller),
              ),
            TextButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(l.splitExport),
              onPressed: () => _exportApps(context, controller, state),
            ),
            TextButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: Text(l.splitImport),
              onPressed: () => _importApps(context, controller, state),
            ),
            if (controller.settings.splitTunnel.apps.isNotEmpty)
              TextButton.icon(
                key: const Key('splitSelectAppsBtn'),
                icon: Icon(_selectionMode
                    ? Icons.deselect_rounded
                    : Icons.checklist_rtl_rounded),
                label: Text(
                    _selectionMode ? l.splitBatchCancel : l.splitSelectRules),
                onPressed: () {
                  if (_selectionMode) {
                    _clearSelection();
                  } else {
                    setState(() => _explicitSelectMode = true);
                  }
                },
              ),
          ],
        ),
      );

  Widget _siteTools(BuildContext context, SettingsController controller,
          AppState state, AppLocalizations l) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: OverflowBar(
          alignment: MainAxisAlignment.start,
          spacing: 4,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(l.splitExport),
              onPressed: () => _exportSites(context, controller, state),
            ),
            TextButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: Text(l.splitImport),
              onPressed: () => _importSites(context, controller, state),
            ),
            if (controller.settings.splitTunnel.sites.isNotEmpty)
              TextButton.icon(
                key: const Key('splitSelectSitesBtn'),
                icon: Icon(_selectionMode
                    ? Icons.deselect_rounded
                    : Icons.checklist_rtl_rounded),
                label: Text(
                    _selectionMode ? l.splitBatchCancel : l.splitSelectRules),
                onPressed: () {
                  if (_selectionMode) {
                    _clearSelection();
                  } else {
                    setState(() => _explicitSelectMode = true);
                  }
                },
              ),
          ],
        ),
      );

  /// Имя сервера для записи в текстовый список.
  ///
  /// ⚠️ НЕ `displayName`. При пустом названии он вырождается в `адрес:порт`, и
  /// экспорт, который человек потом кому-то перешлёт, унёс бы адрес сервера
  /// наружу — ровно та утечка, что разбиралась в 1.4.3. Безымянный сервер
  /// просто не называется: правило уедет в общий туннель, и это видно.
  Widget _quickServiceChips(BuildContext context, SettingsController controller,
      AppState state, AppLocalizations l) {
    final st = controller.settings.splitTunnel;
    final defaultAction = st.defaultAction;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.splitQuickServicesTitle, style: theme.textTheme.titleSmall),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              l.splitQuickServicesSub,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: SplitServicePresets.catalog.map((preset) {
              final svc = preset.service;
              final active = SplitServicePresets.isPresetActive(
                  st.sites, svc, defaultAction);
              return FilterChip(
                key: Key('splitPreset-${svc.name}'),
                avatar:
                    SiteFavicon(domain: svc.domain, size: 18, builtIn: true),
                label: Text(svc.label),
                selected: active,
                onSelected: (_) {
                  final action = controller.settings.splitTunnel.defaultAction;
                  final toggled = SplitServicePresets.togglePreset(
                    controller.settings.splitTunnel.sites,
                    svc,
                    action: action,
                  );
                  controller.update((s) {
                    final groupKey = splitGroupKey('sites', action);
                    final nextCollapsed = toggled.added
                        ? s.splitCollapsed
                            .where((k) => k != groupKey)
                            .toList()
                        : s.splitCollapsed;
                    return s.copyWith(
                      splitSitesCollapsed:
                          toggled.added ? false : s.splitSitesCollapsed,
                      splitCollapsed: nextCollapsed,
                      splitTunnel:
                          s.splitTunnel.copyWith(sites: toggled.sites),
                    );
                  });
                  if (toggled.added &&
                      preset.needsAppRuleHint &&
                      context.mounted) {
                    AppToast.show(context, l.splitServiceAppHint(svc.label));
                  }
                  if (state.status.isConnected &&
                      splitRulesEditableIn(controller.settings.captureMode)) {
                    if (controller.settings.alwaysReloadVpnOnNewSite) {
                      unawaited(state.reconnect(controller.settings));
                    } else {
                      unawaited(showVpnReloadPromptDialog(
                        context,
                        domain: svc.domain,
                        settingsController: controller,
                        appState: state,
                        isLiveMismatch: false,
                      ));
                    }
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  static String? _exitName(AppState state, String key) {
    for (final s in state.servers) {
      if (s.key != key) continue;
      final name = s.remark.trim();
      return name.isEmpty ? null : name;
    }
    return null;
  }

  /// Обратный поиск: имя из текста → ключ сервера. Имени не нашлось — `null`,
  /// то есть общий туннель (висячая ссылка на выход опаснее: ядро её не ловит).
  static String? _exitKey(AppState state, String name) {
    final want = name.trim();
    if (want.isEmpty) return null;
    for (final s in state.servers) {
      if (s.remark.trim() == want) return s.key;
    }
    return null;
  }

  /// Экспорт в буфер обмена. Через буфер, а не файлом: на телефоне сохранение
  /// файла ненадёжно, а буфер работает везде.
  Future<void> _exportSites(
      BuildContext context, SettingsController c, AppState state) async {
    final l = AppLocalizations.of(context);
    final sites = c.settings.splitTunnel.sites;
    if (sites.isEmpty) {
      AppToast.show(context, l.splitExportEmpty);
      return;
    }
    await Clipboard.setData(ClipboardData(
        text: encodeSiteRules(sites,
            exitNameOf: (k) => _exitName(state, k))));
    if (context.mounted) AppToast.copied(context);
  }

  Future<void> _exportApps(
      BuildContext context, SettingsController c, AppState state) async {
    final l = AppLocalizations.of(context);
    final apps = c.settings.splitTunnel.apps;
    if (apps.isEmpty) {
      AppToast.show(context, l.splitExportEmpty);
      return;
    }
    await Clipboard.setData(ClipboardData(
        text: encodeAppRules(apps, exitNameOf: (k) => _exitName(state, k))));
    if (context.mounted) AppToast.copied(context);
  }

  Future<void> _importSites(
      BuildContext context, SettingsController c, AppState state) async {
    final l = AppLocalizations.of(context);
    final current = c.settings.splitTunnel.sites;
    final defaultAction = c.settings.splitTunnel.defaultAction;
    final res = await showDialog<RuleImportResult<SiteRule>>(
      context: context,
      builder: (ctx) => RuleImportDialog<SiteRule>(
        title: l.splitImportTitleSites,
        parse: (t) => parseSiteRules(t,
            defaultAction: defaultAction,
            exitKeyOf: (n) => _exitKey(state, n)),
        plan: (incoming) => planSiteMerge(current, incoming),
        apply: (p, {required overwrite}) =>
            applySiteMerge(current, p, overwriteConflicts: overwrite),
        label: (s) => s.label,
        describe: (s) => appActionLabel(l, s.action),
      ),
    );
    if (res == null || !context.mounted) return;
    c.update((s) =>
        s.copyWith(splitTunnel: s.splitTunnel.copyWith(sites: res.rules)));
    _importToast(context, l, res.replaced, res.rules.length, res.added,
        res.overwritten);
  }

  Future<void> _importApps(
      BuildContext context, SettingsController c, AppState state) async {
    final l = AppLocalizations.of(context);
    final current = c.settings.splitTunnel.apps;
    final defaultAction = c.settings.splitTunnel.defaultAction;
    final res = await showDialog<RuleImportResult<AppRule>>(
      context: context,
      builder: (ctx) => RuleImportDialog<AppRule>(
        title: l.splitImportTitleApps,
        parse: (t) => parseAppRules(t,
            defaultAction: defaultAction,
            exitKeyOf: (n) => _exitKey(state, n)),
        plan: (incoming) => planAppMerge(current, incoming),
        apply: (p, {required overwrite}) =>
            applyAppMerge(current, p, overwriteConflicts: overwrite),
        label: (a) => a.byName ? a.name : a.path,
        describe: (a) => a.enabled
            ? appActionLabel(l, a.action)
            : '${appActionLabel(l, a.action)} · ${l.splitRuleDisabled}',
      ),
    );
    if (res == null || !context.mounted) return;
    c.update((s) =>
        s.copyWith(splitTunnel: s.splitTunnel.copyWith(apps: res.rules)));
    _importToast(context, l, res.replaced, res.rules.length, res.added,
        res.overwritten);
  }

  static void _importToast(BuildContext context, AppLocalizations l,
      bool replaced, int total, int added, int overwritten) {
    AppToast.show(
        context,
        replaced
            ? l.splitImportReplaced(total)
            : l.splitImportAdded(added, overwritten));
  }

  /// Добавить СРАЗУ НЕСКОЛЬКО приложений одним изменением настроек.
  ///
  /// ⚠️ Не циклом по [_addApp]: каждый вызов пишет настройки на диск и дёргает
  /// перерисовку, а при выборе десятка приложений это десяток сохранений
  /// подряд. Плюс промежуточные состояния успевают уехать в конфиг.
  void _addApps(SettingsController c, List<String> paths) {
    if (paths.isEmpty) return;
    c.update((s) {
      final apps = [...s.splitTunnel.apps];
      for (final path in paths) {
        // ⚠️ Спрашиваем у правил, покрывают ли они эту программу, а НЕ сравниваем
        // пути. Правило «по имени» ловит процесс по имени файла, поэтому запись
        // с прежним путём (до обновления программы) — это та же самая запись.
        if (apps.any((a) => a.matches(path))) continue;
        apps.add(AppRule(path,
            byName: true, action: s.splitTunnel.defaultAction));
      }
      return s.copyWith(splitTunnel: s.splitTunnel.copyWith(apps: apps));
    });
  }

  /// `false` — правило на эту программу уже есть (вызывающий скажет об этом).
  bool _addApp(SettingsController c, String path) {
    if (c.settings.splitTunnel.containsApp(path)) return false;
    c.update((s) {
      if (s.splitTunnel.containsApp(path)) return s;
      // #3 — по умолчанию сопоставляем ПО ИМЕНИ: sing-box сравнивает process_path
      // побайтово (регистр/короткие пути Windows), из-за чего правило «по пути»
      // может молча не срабатывать. По имени — надёжно; меняется в диалоге.
      // Действие — «то, что выделено» текущим режимом (см. defaultAction).
      final rule = AppRule(path,
          byName: true, action: s.splitTunnel.defaultAction);
      return s.copyWith(
          splitTunnel: s.splitTunnel
              .copyWith(apps: [...s.splitTunnel.apps, rule]));
    });
    return true;
  }

  void _removeApp(SettingsController c, AppRule rule) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            apps: s.splitTunnel.apps
                // По ключу сопоставления, а не по пути: у правила «по имени»
                // путь — это лишь путь, по которому его когда-то завели, и он
                // устаревает при первом же обновлении программы.
                .where((a) => a.matchKey != rule.matchKey)
                .toList())));
  }

  void _updateApp(SettingsController c, AppRule rule,
      {AppAction? action,
      bool? byName,
      bool? enabled,
      bool? allowRealIp,
      bool? overrideSites}) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            apps: s.splitTunnel.apps
                // `rule` — состояние ДО правки, поэтому его ключ совпадает с
                // ключом искомого элемента даже когда правка меняет `byName`.
                .map((a) => a.matchKey == rule.matchKey
                    ? a.copyWith(
                        action: action,
                        byName: byName,
                        enabled: enabled,
                        allowRealIp: allowRealIp,
                        overrideSites: overrideSites)
                    : a)
                .toList())));
  }

  // ── Сайты ────────────────────────────────────────────────────────────────
  // Запись уникальна по паре (домен, порт): один домен может быть добавлен
  // и без порта, и с портом — это разные правила.
  static bool _sameSite(SiteRule a, SiteRule b) =>
      a.domain == b.domain && a.port == b.port;

  void _removeSite(SettingsController c, SiteRule site) {
    c.update((s) => s.copyWith(
        // Пометка «свёрнут» удалённого узла больше ни к чему не относится.
        splitCollapsed:
            s.splitCollapsed.where((k) => k != siteNodeKey(site)).toList(),
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .where((x) => !_sameSite(x, site))
                .toList())));
  }

  void _updateSite(SettingsController c, SiteRule site, AppAction action) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .map((x) => _sameSite(x, site) ? x.copyWith(action: action) : x)
                .toList())));
  }

  void _setSitePort(SettingsController c, SiteRule site, int? port) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                // copyWith, а не новый SiteRule: пересборка теряла бы галочку
                // «разрешить реальный IP» при каждой правке порта.
                .map((x) => _sameSite(x, site)
                    ? x.copyWith(port: port, clearPort: port == null)
                    : x)
                .toList())));
  }

  /// Назначить сайту сервер. `null` — основной туннель.
  void _setSiteServer(SettingsController c, SiteRule site, String? key) {
    c.update((s) => s.copyWith(
          splitTunnel: s.splitTunnel.copyWith(
            sites: [
              for (final x in s.splitTunnel.sites)
                (x.domain == site.domain && x.port == site.port)
                    ? x.copyWith(serverKey: key, clearServer: key == null)
                    : x
            ],
          ),
        ));
  }

  /// Назначить приложению сервер. `null` — основной туннель.
  void _setAppServer(SettingsController c, AppRule rule, String? key) {
    c.update((s) => s.copyWith(
          splitTunnel: s.splitTunnel.copyWith(
            apps: [
              for (final a in s.splitTunnel.apps)
                // Тот же ключ сопоставления, что и в _updateApp/_removeApp:
                // четыре точки сравнения обязаны согласоваться, иначе выбор
                // сервера уедет не на то правило.
                a.matchKey == rule.matchKey
                    ? a.copyWith(serverKey: key, clearServer: key == null)
                    : a
            ],
          ),
        ));
  }

  void _setSiteAllowRealIp(SettingsController c, SiteRule site, bool value) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .map((x) => _sameSite(x, site) ? x.copyWith(allowRealIp: value) : x)
                .toList())));
  }

  /// Заголовок подгруппы «Туннель / Прямо / Блок» со счётчиком и шевроном.
  Widget _groupHeader(BuildContext context, SettingsController controller,
      AppLocalizations l,
      {required String list, required AppAction action, required int count}) {
    final key = splitGroupKey(list, action);
    final collapsed = controller.settings.splitCollapsed.contains(key);
    void toggle() => controller.update((s) => s.copyWith(
        splitCollapsed: toggleCollapsedKey(s.splitCollapsed, key)));
    return InkWell(
      key: ValueKey('group:$key'),
      onTap: toggle,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 4, 0),
        child: Row(children: [
          _ActionChip(action: action),
          const SizedBox(width: 8),
          Text('$count',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor)),
          const Spacer(),
          IconButton(
            tooltip: collapsed ? l.splitExpandGroup : l.splitCollapseGroup,
            icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
            onPressed: toggle,
          ),
        ]),
      ),
    );
  }

  Widget _siteTile(
      BuildContext context, SettingsController controller, SiteTreeRow row) {
    final state = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final site = row.site;
    final depth = row.depth;
    final indent = 16.0 + depth * 22.0;
    final nodeKey = row.nodeKey;

    final isPrimary = !row.isVirtualGroup && _primaryHighlightNodeKey == nodeKey;
    final inSubmittedFamily = _highlightFamilyDomain != null &&
        isSameDomainFamily(site.domain, _highlightFamilyDomain!);
    final liveNorm = normalizeDomain(_siteQuery);
    final inLiveFamily = liveNorm.contains('.') &&
        isSameDomainFamily(site.domain, liveNorm);
    final highlighted = isPrimary || inSubmittedFamily || inLiveFamily;

    void toggleNode() => controller.update((s) => s.copyWith(
        splitCollapsed: toggleCollapsedKey(s.splitCollapsed, nodeKey)));

    final st = controller.settings.splitTunnel;
    final activeSelected = _validSelectedIds(st);
    final inSelectMode = splitRulesEditableIn(controller.settings.captureMode) &&
        st.mode != SplitMode.all &&
        (_explicitSelectMode || activeSelected.isNotEmpty);
    final selId = _siteSelId(site);
    final isRuleSelected = !row.isVirtualGroup && activeSelected.contains(selId);

    Widget tile;
    if (row.isVirtualGroup) {
      tile = ListTile(
        key: ValueKey('vgroup:${site.domain}'),
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: indent, end: 16),
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            key: ValueKey('toggle:$nodeKey'),
            borderRadius: BorderRadius.circular(12),
            onTap: toggleNode,
            child: Tooltip(
              message: row.collapsed
                  ? l.splitExpandSubdomains
                  : l.splitCollapseSubdomains,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(row.collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 20),
                  if (row.collapsed)
                    Text('+${row.descendants}',
                        style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ),
          SiteFavicon(domain: site.domain),
        ]),
        title: Row(children: [
          Flexible(
            child: Text(
              site.domain,
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l.splitVirtualGroupBadge,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
        onTap: toggleNode,
      );
      tile = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => _openRuleContextMenu(
          context,
          d.globalPosition,
          controller,
          state,
          siteRule: site,
          isVirtualGroup: true,
        ),
        onLongPressStart: (d) => _openRuleContextMenu(
          context,
          d.globalPosition,
          controller,
          state,
          siteRule: site,
          isVirtualGroup: true,
        ),
        child: tile,
      );
    } else {
      tile = ListTile(
        key: ValueKey('site:${site.domain}|${site.port ?? ''}'),
        selected: inSelectMode && isRuleSelected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.11),
        contentPadding: EdgeInsetsDirectional.only(start: indent, end: 16),
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          if (inSelectMode) ...[
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: isRuleSelected,
                onChanged: (_) => _toggleRuleSelection(selId),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (depth > 0)
            Icon(Icons.subdirectory_arrow_right,
                size: 18, color: Theme.of(context).disabledColor),
          if (row.descendants > 0)
            InkWell(
              key: ValueKey('toggle:$nodeKey'),
              borderRadius: BorderRadius.circular(12),
              onTap: toggleNode,
              child: Tooltip(
                message: row.collapsed
                    ? l.splitExpandSubdomains
                    : l.splitCollapseSubdomains,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(row.collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 20),
                    if (row.collapsed)
                      Text('+${row.descendants}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
            ),
          if (site.insecureScheme)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Tooltip(
                message: l.siteInsecureScheme,
                child: Icon(Icons.no_encryption_gmailerrorred_outlined,
                    size: 18, color: Theme.of(context).colorScheme.error),
              ),
            ),
          SiteFavicon(domain: site.domain),
        ]),
        title: depth > 0
            ? _SubdomainLabel(site: site)
            : Text(site.label,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: _ruleSubtitle(
            context,
            site.port != null ? l.splitOnlyPort(site.port!) : null,
            action: site.action,
            allowRealIp: site.allowRealIp,
            noRealIp: controller.settings.noRealIp),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ServerBadge(
              servers: state.servers,
              serverKey: site.serverKey,
              action: site.action),
          _ActionChip(action: site.action),
          IconButton(
            tooltip: l.splitRemove,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _removeSite(controller, site),
          ),
        ]),
        onTap: () {
          if (_dragCtrl.consumeTapSuppression()) return;
          if (inSelectMode) {
            _toggleRuleSelection(selId);
          } else {
            _siteDialog(context, controller, site);
          }
        },
      );
      tile = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => _openRuleContextMenu(
          context,
          d.globalPosition,
          controller,
          state,
          siteRule: site,
        ),
        onLongPressStart: (d) => _openRuleContextMenu(
          context,
          d.globalPosition,
          controller,
          state,
          siteRule: site,
        ),
        child: tile,
      );
    }

    final wrapped = AnimatedContainer(
      key: _keyForSiteNode(nodeKey),
      duration: const Duration(milliseconds: 220),
      margin: highlighted
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : EdgeInsets.zero,
      decoration: highlighted
          ? BoxDecoration(
              color: scheme.primary.withValues(alpha: isPrimary ? 0.14 : 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isPrimary
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.7),
                width: isPrimary ? 2.0 : 1.3,
              ),
            )
          : null,
      child: tile,
    );
    if (row.isVirtualGroup) return wrapped;
    return DragSelectItem<String>(
      key: ValueKey('dragSite:$selId'),
      id: selId,
      controller: _dragCtrl,
      child: wrapped,
    );
  }

  /// Подпись правила. При включённом «Не выходить под реальным IP» правило
  /// «Прямо» обязано честно сообщать, куда оно на самом деле пойдёт: раньше чип
  /// показывал «Прямо», а трафик молча уходил в туннель.
  Widget? _ruleSubtitle(BuildContext context, String? base,
      {required AppAction action,
      required bool allowRealIp,
      required bool noRealIp}) {
    final l = AppLocalizations.of(context);
    // Длинный путь к exe обязан обрезаться, а не ломать вёрстку строки.
    Widget baseText() =>
        Text(base!, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!noRealIp || action != AppAction.direct) {
      return base == null ? null : baseText();
    }
    final scheme = Theme.of(context).colorScheme;
    final warn = allowRealIp;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (base != null) ...[Flexible(child: baseText()), const SizedBox(width: 8)],
      Icon(warn ? Icons.warning_amber_rounded : Icons.shield_outlined,
          size: 14, color: warn ? Colors.orange : scheme.primary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          warn ? l.splitRealIpExposed : l.splitRealIpProtected,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: warn ? Colors.orange : scheme.primary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }

  /// Диалог настройки приложения: действие + способ сопоставления.
  Future<void> _appDialog(
      BuildContext context, SettingsController c, AppRule rule) async {
    final state = context.read<AppState>();
    // ⚠️ Смена «по имени / по пути» меняет ключ правила ([AppRule.matchKey]).
    // Правки, сделанные в том же диалоге ПОСЛЕ неё, искали старый ключ и
    // терялись (аудит 25.10.2026, I) — ведём актуальное правило, как у сайта.
    var current = rule;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RuleDialog(
        servers: state.servers,
        currentServer: state.selectedServer,
        serverKey: rule.serverKey,
        onServer: (key) {
          _setAppServer(c, current, key);
          current =
              current.copyWith(serverKey: key, clearServer: key == null);
        },
        // Строка списка уже прогрела кэш меток — берём готовую.
        title: (hasPlatformServices
                ? platform.appCatalog.cachedLabel(rule.path)
                : null) ??
            rule.name,
        copySource: rule.path,
        action: rule.action,
        byName: rule.byName,
        allowRealIp: c.settings.noRealIp ? rule.allowRealIp : null,
        // Только у приложений: у сайта переопределять нечего.
        overrideSites: rule.overrideSites,
        onAction: (a) {
          _updateApp(c, current, action: a);
          current = current.copyWith(action: a);
        },
        onByName: (b) {
          _updateApp(c, current, byName: b);
          current = current.copyWith(byName: b);
        },
        onAllowRealIp: (v) {
          _updateApp(c, current, allowRealIp: v);
          current = current.copyWith(allowRealIp: v);
        },
        onOverrideSites: (v) {
          _updateApp(c, current, overrideSites: v);
          current = current.copyWith(overrideSites: v);
        },
      ),
    );
  }

  /// Диалог настройки сайта: действие + необязательный порт.
  Future<void> _siteDialog(
      BuildContext context, SettingsController c, SiteRule site) async {
    final state = context.read<AppState>();
    // Порт правится «на месте»: находим актуальную запись после смены порта,
    // чтобы последующие изменения действия попадали в неё же.
    var current = site;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RuleDialog(
        title: site.domain,
        copySource: site.label,
        action: site.action,
        initialPort: site.port,
        allowRealIp: c.settings.noRealIp ? site.allowRealIp : null,
        servers: state.servers,
        currentServer: state.selectedServer,
        serverKey: site.serverKey,
        onServer: (key) {
          _setSiteServer(c, current, key);
          current = current.copyWith(serverKey: key, clearServer: key == null);
        },
        onAction: (a) => _updateSite(c, current, a),
        onAllowRealIp: (v) => _setSiteAllowRealIp(c, current, v),
        onPort: (p) {
          _setSitePort(c, current, p);
          current = current.copyWith(port: p, clearPort: p == null);
        },
      ),
    );
  }

  Future<void> _pickExe(BuildContext context, SettingsController c) async {
    final l = AppLocalizations.of(context);
    final group = XTypeGroup(label: l.splitProgramsFileType, extensions: const ['exe']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    // Молчаливое «ничего не произошло» читается как поломка: пользователь выбрал
    // файл, а список не изменился. Говорим, почему.
    final added = _addApp(c, file.path);
    if (!added && context.mounted) {
      AppToast.show(context, l.splitAppAlreadyAdded);
    }
  }

  Future<void> _pickRunning(BuildContext context, SettingsController c) async {
    final all = await platform.appCatalog.list();
    final added = c.settings.splitTunnel;
    // #6.3 — исключаем уже добавленные
    final procs = all.where((p) => !added.containsApp(p.key)).toList();
    if (!context.mounted) return;
    // ⚠️ Диалог отдаёт СПИСОК. Раньше он возвращал одну строку и закрывался на
    // первом же тапе: пользователь отмечал несколько приложений, а добавлялось
    // одно. Из-за этого в правилах владельца не оказалось браузера — и в режиме
    // «только отмеченные» весь веб уходил мимо VPN, что выглядело как «ничего
    // не работает».
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _RunningPickerDialog(procs: procs),
    );
    if (selected != null) _addApps(c, selected);
  }
}

/// Запускает [onShow] РОВНО ОДИН РАЗ — в `initState`, а не в `build`.
///
/// ⚠️ ЗАЧЕМ ЭТО ОТДЕЛЬНЫЙ ВИДЖЕТ. [SplitTunnelScreen] — `StatelessWidget`, и
/// его `build` перевызывается на каждое изменение `AppState`/`SettingsController`
/// (например, раз в секунду при живом VPN — тикают счётчики трафика). Если бы
/// диалог открывался прямо из `build`, он открывался бы заново на каждый такой
/// тик. `initState` вызывается один раз за жизнь `State` — а она переживает
/// эти перерисовки, пока сам экран не будет закрыт и открыт заново.
class _OpenRuleOnce extends StatefulWidget {
  const _OpenRuleOnce(
      {super.key, required this.onShow, required this.child});

  final VoidCallback onShow;
  final Widget child;

  @override
  State<_OpenRuleOnce> createState() => _OpenRuleOnceState();
}

class _OpenRuleOnceState extends State<_OpenRuleOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShow();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Плашка честности под выбором режима.
///
/// ⚠️ ЗАМЕТНАЯ, А НЕ МЕЛКОЙ ПОДПИСЬЮ — И ЭТО ТРЕБОВАНИЕ, А НЕ ВКУС. Владелец
/// пользовался режимом «Только отмеченные», был уверен, что kill switch держит
/// его целиком, и получил свой настоящий адрес наружу. Сказать это шрифтом
/// подписи значило бы сказать это никому.
///
/// Рядом — кнопка «Все — через VPN»: оговорка без выхода из положения читается
/// как «сам виноват».
///
/// Класс ПУБЛИЧНЫЙ намеренно: тест поднимает его отдельно от экрана — целиком
/// экран тянет за собой каталог программ, иконки и загрузку фавиконов, то есть
/// проверял бы что угодно, кроме условия показа.
class SplitHonestyBanner extends StatelessWidget {
  const SplitHonestyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final warnings = splitHonestyWarnings(controller.settings);
    // Про системный прокси говорит экран настроек — там же, где живёт тумблер
    // kill switch. Здесь показываем только то, что относится к правилам.
    if (!warnings.contains(SplitHonesty.realIpByDefault)) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const Key('splitHonesty'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: scheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: SelText(
                l.splitOnlySelectedWarnTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, start: 30),
            child: SelText(l.splitOnlySelectedWarnBody,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          // Галочка «Не выходить под реальным IP» на базу маршрута не влияет —
          // а выглядит как «теперь точно ничего не утечёт».
          if (controller.settings.noRealIp)
            Padding(
              key: const Key('splitHonesty-noRealIp'),
              padding: const EdgeInsetsDirectional.only(top: 6, start: 30),
              child: SelText(l.splitOnlySelectedNoRealIp,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          if (warnings.contains(SplitHonesty.killSwitchIsPerApp))
            Padding(
              key: const Key('splitHonesty-killSwitch'),
              padding: const EdgeInsetsDirectional.only(top: 6, start: 30),
              child: SelText(l.splitKillSwitchIsPerApp,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('splitHonesty-toAll'),
              onPressed: () => controller.update((s) => s.copyWith(
                  splitTunnel: s.splitTunnel.copyWith(mode: SplitMode.all))),
              child: Text(splitModeLabel(l, SplitMode.all)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог выбора из запущенных с поиском (#6.1).
class _RunningPickerDialog extends StatefulWidget {
  final List<CatalogApp> procs;
  const _RunningPickerDialog({required this.procs});
  @override
  State<_RunningPickerDialog> createState() => _RunningPickerDialogState();
}

class _RunningPickerDialogState extends State<_RunningPickerDialog> {
  String _q = '';

  /// Отмеченные приложения. Раньше диалог закрывался на первом тапе и отдавал
  /// ровно одно — отсюда и жалоба «правила не работают при мультивыделении».
  final Set<String> _picked = {};

  /// Имя → сколько приложений его носят (для подписи у тёзок).
  final Map<String, int> _dupes = {};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Сколько приложений носят каждое имя: подпись нужна только тёзкам.
    if (_dupes.isEmpty) {
      for (final p in widget.procs) {
        _dupes[p.label] = (_dupes[p.label] ?? 0) + 1;
      }
    }
    final filtered = _q.isEmpty
        ? widget.procs
        : widget.procs
            .where((p) => p.label.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return AlertDialog(
      // См. кнопку открытия: на Android это установленные приложения.
      title: Row(children: [
        Expanded(
          child: Text(platform.appCatalog.supportsManualPick
              ? l.splitRunningApps
              : l.splitInstalledApps),
        ),
        // На компактном экране третья кнопка живёт здесь — см. комментарий у
        // `actions`.
        if (filtered.isNotEmpty && context.sg.isCompact)
          IconButton(
            tooltip: l.splitSelectAllFound,
            icon: const Icon(Icons.done_all),
            onPressed: () => setState(() {
              final keys = filtered.map((p) => p.key);
              if (keys.every(_picked.contains)) {
                _picked.removeAll(keys);
              } else {
                _picked.addAll(keys);
              }
            }),
          ),
      ]),
      content: adaptiveDialogBody(
        context,
        width: 440,
        height: 480,
        child: Column(
          children: [
            TextField(
              // ⚠️ НЕ автофокус на телефоне: клавиатура поднимается В МОМЕНТ
                // открытия и съедает ~280 dp — человек видит список из одной
                // строки раньше, чем успевает что-то выбрать.
                autofocus: !context.sg.isCompact,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.splitSearchByName,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(l.splitNothingFound))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final on = _picked.contains(p.key);
                        // ⚠️ Подпись показываем ТОЛЬКО у тёзок. Она и есть та
                        // вторая строка, из-за которой каждая позиция занимала
                        // 64 dp вместо 56: на десяти видимых строках это целая
                        // потерянная позиция. А смысл у неё ровно один —
                        // различить два приложения с одинаковым названием; в
                        // остальных случаях на Android там просто имя пакета,
                        // которое ничего не добавляет.
                        final ambiguous = (_dupes[p.label] ?? 0) > 1;
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          controlAffinity: ListTileControlAffinity.leading,
                          // ⚠️ ИКОНКА В `title`, А НЕ В `secondary`. У
                          // CheckboxListTile `secondary` — это слот на
                          // ПРОТИВОПОЛОЖНОЙ от галочки стороне: с галочкой
                          // слева иконка уезжала к правому краю, отрываясь от
                          // имени, которому принадлежит. Порядок, который
                          // просил владелец: галочка, отступ, иконка, имя.
                          title: Row(children: [
                            AppIcon(
                                path: p.key, size: context.sg.listIconSize),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                          subtitle: ambiguous
                              ? Text(p.key,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                          onChanged: (v) => setState(() =>
                              v == true ? _picked.add(p.key) : _picked.remove(p.key)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // ⚠️ ТРИ КНОПКИ НА ТЕЛЕФОНЕ НЕ ВЛЕЗАЮТ В СТРОКУ.
      //
      // Диалог на экране 360 dp получает 280 dp ширины, а «Отметить всё
      // найденное» + «Закрыть» + «Добавить (N)» требуют заметно больше.
      // `OverflowBar` в этом случае раскладывает их СТОЛБИКОМ и съедает ~170 dp
      // высоты — при 300 dp, уже отданных клавиатуре, списку не оставалось
      // ничего. Поэтому на компактном экране «Отметить всё найденное»
      // переезжает из ряда кнопок в шапку диалога, где место есть.
      actions: [
        // «Отметить всё найденное» — по отфильтрованному списку, а не по всему:
        // иначе поиск теряет смысл, а случайное нажатие добавляет сотню правил.
        if (filtered.isNotEmpty && !context.sg.isCompact)
          TextButton(
            onPressed: () => setState(() {
              final keys = filtered.map((p) => p.key);
              if (keys.every(_picked.contains)) {
                _picked.removeAll(keys);
              } else {
                _picked.addAll(keys);
              }
            }),
            child: Text(l.splitSelectAllFound),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.splitClose)),
        // Счётчик прямо на кнопке: видно, сколько уйдёт в правила, и заметно,
        // если отметилось не то.
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop(_picked.toList()),
          child: Text(l.splitAddSelected(_picked.length)),
        ),
      ],
    );
  }
}

/// Метка действия приложения (Туннель / Прямо / Блок) — цвет + иконка + текст.
/// Сервер, через который идёт правило, — плашкой рядом с чипом действия.
///
/// Ничего не рисует, когда сервер не задан или действие не «Туннель»: правило
/// без явного сервера идёт через основной, и плашка «как у всех» у каждой
/// строки только съедала бы ширину, которой на телефоне и так впритык.
///
/// ⚠️ ШИРИНА РЕШАЕТ, ЧТО ПОКАЗАТЬ. Просьба владельца — «старайся вписать полное
/// название сервера, или оставляй только флаг». Поэтому здесь не фиксированная
/// ширина, а [LayoutBuilder]: пока имя влезает — показываем имя целиком, стало
/// тесно — остаётся один флаг, а если флага у сервера нет, имя обрезается.
/// Числом это не задать: на телефоне и в широком окне «влезает» разное.
///
/// ⚠️ Класс публичный только ради стража (`test/rule_server_picker_test.dart`):
/// подсказка налезала на соседнюю строку, и проверять это надо на настоящей
/// плашке, а не на её копии в тесте.
class ServerBadge extends StatelessWidget {
  final List<VpnServer> servers;
  final String? serverKey;
  final AppAction action;

  const ServerBadge(
      {super.key,
      required this.servers,
      required this.serverKey,
      required this.action});

  @override
  Widget build(BuildContext context) {
    if (action != AppAction.tunnel || serverKey == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    VpnServer? server;
    for (final s in servers) {
      if (s.key == serverKey) {
        server = s;
        break;
      }
    }
    // Сервер исчез из подписки, пока правило лежало. Показываем это явно:
    // трафик пойдёт основным туннелем, а молчащая строка выглядела бы
    // настроенной — человек искал бы поломку не там.
    if (server == null) {
      return Tooltip(
        message: l.exitServerGone,
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.link_off, size: 13, color: scheme.onErrorContainer),
        ),
      );
    }
    final name = server.displayName;
    final iso = FlagUtil.isoFromName(name);
    // ⚠️ СЕРВЕР МОЖЕТ БЫТЬ ВЫБРАН И ПРИ ЭТОМ НЕ РАБОТАТЬ ОТДЕЛЬНЫМ ВЫХОДОМ.
    //
    // Панельный профиль «Авто» — это готовый конфиг Xray целиком, а вторым
    // выходом трафик разводит sing-box: собрать из такого профиля outbound он
    // не может. Правило остаётся валидным и молча идёт основным туннелем —
    // ровно тот класс дефектов, за который в этом проекте платили дороже всего:
    // «настройка видна, выглядит рабочей и ничего не делает».
    // Владелец решил (07.08.2026) выбор разрешать, но предупреждать.
    //
    // ⚠️ И ДО ЭТОЙ ПРАВКИ КОММЕНТАРИЙ ВРАЛ. Спрашивали
    // `SingboxOutboundFactory.supports`, а он смотрит ТОЛЬКО на `protocol` —
    // у панельного профиля тот берётся с первого outbound'а конфига и равен
    // `vless`, то есть предупреждение про «Авто» не показывалось ни разу с
    // версии 1.2.0. Теперь вопрос задаётся единственному ответчику
    // (`canBeExitServer`), общему с `/v1/exits` и `ExitOutbounds.build`.
    final unsupported = !canBeExitServer(server);
    return LayoutBuilder(builder: (context, box) {
      final tight = box.maxWidth < 132;
      final flagOnly = tight && iso != null;
      final badge = Tooltip(
        // ⚠️ В ПОДСКАЗКЕ — ТОЛЬКО ИМЯ СЕРВЕРА, АБЗАЦ УЕХАЛ В «!».
        //
        // Здесь стоял `exitServerUnsupported(name)` — 230 символов одной
        // всплывающей подсказкой. Подсказка не ограничена по ширине и рисуется
        // ПОД плашкой (`preferBelow` по умолчанию `true`), поэтому накрывала
        // следующее правило списка: владелец прислал скриншот. Длинный текст
        // теперь показывает `InfoTooltip` диалогом (см. ниже), а ширина
        // подсказок вдобавок ограничена темой (`buildAppTheme` в `app.dart`).
        //
        // Имя оставляем: плашка на узком экране показывает один флаг, и без
        // подсказки не узнать, через какой сервер идёт правило. Значка
        // FlagCell тут нет (значок плашки — один флаг по [iso]) — флаги в
        // имени остаются картинками, ни один не срезается.
        richMessage: flagTextSpan(name),
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: EdgeInsets.symmetric(
              horizontal: flagOnly ? 5 : 8, vertical: 3),
          decoration: BoxDecoration(
            // Непригодный сервер красим предупреждением, а не основным цветом:
            // одинаковая плашка означала бы «настроено и работает».
            color: unsupported
                ? scheme.tertiaryContainer
                : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (unsupported)
              Icon(Icons.warning_amber_rounded,
                  size: 13, color: scheme.onTertiaryContainer)
            else if (iso != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: CountryFlag.fromCountryCode(iso, width: 16, height: 12),
              )
            else
              Icon(Icons.alt_route, size: 13, color: scheme.onPrimaryContainer),
            // Тесно и флаг есть — он и опознаёт сервер, текст только мешает.
            if (!flagOnly) ...[
              const SizedBox(width: 5),
              Flexible(
                child: FlagText(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: unsupported
                          ? scheme.onTertiaryContainer
                          : scheme.onPrimaryContainer),
                ),
              ),
            ],
          ]),
        ),
      );
      if (!unsupported) return badge;
      // «!» рядом с плашкой: абзац о том, почему сервер не поднимется
      // отдельным выходом, показывается ДИАЛОГОМ. Он же работает на тач-экране,
      // где наведения нет вовсе, — прежняя подсказка там была недостижима.
      return Row(mainAxisSize: MainAxisSize.min, children: [
        badge,
        InfoTooltip(l.exitServerUnsupportedInfo, title: name),
      ]);
    });
  }
}

/// Итог выбора сервера в пикере.
///
/// ⚠️ ОБЁРТКА, А НЕ ГОЛЫЙ `String?`, И ЭТО НЕ ФОРМАЛЬНОСТЬ. `showDialog`
/// возвращает `null` при ОТМЕНЕ (кнопка «Закрыть», Esc, тап мимо диалога), а
/// `null` внутри выбора — законное значение «как основной сервер». Без обёртки
/// закрытие пикера крестиком стирало бы уже выбранный сервер, и правило молча
/// уезжало бы в общий туннель — ровно тот класс дефектов, который в этом
/// проекте стоит дороже всего.
class RuleServerChoice {
  /// Ключ сервера; `null` — «как основной».
  final String? key;
  const RuleServerChoice(this.key);
}

/// Строка «через какой сервер идёт правило» + вход в пикер.
///
/// Текущий выбор показывается ТОЙ ЖЕ строкой [ServerTile], что и на главном
/// экране: флаг, имя, подписка, теги, пинг и скорость. Данные она берёт из тех
/// же провайдеров, поэтому разойтись с главным экраном физически не может —
/// в отличие от прежнего `Text(displayName)`, который показывал только имя.
class RuleServerField extends StatelessWidget {
  final List<VpnServer> servers;

  /// Сервер, выбранный на главном экране, — для подписи «Как основной (…)».
  final VpnServer? currentServer;
  final String? serverKey;
  final ValueChanged<String?> onChanged;

  const RuleServerField({
    super.key,
    required this.servers,
    required this.currentServer,
    required this.serverKey,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final choice = await showDialog<RuleServerChoice>(
      context: context,
      builder: (_) => RuleServerPickerDialog(
        servers: servers,
        currentServer: currentServer,
        serverKey: serverKey,
      ),
    );
    // Отмена (`null`) выбор НЕ трогает — см. [RuleServerChoice].
    if (choice != null) onChanged(choice.key);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    VpnServer? picked;
    for (final s in servers) {
      if (s.key == serverKey) {
        picked = s;
        break;
      }
    }
    // ⚠️ Сервер мог пропасть из подписки, пока правило лежало. Прежний
    // `DropdownButtonFormField` в этом случае молча показывал «Как основной» —
    // то есть врал: правило по-прежнему ссылается на исчезнувший сервер.
    // Говорим прямо, той же строкой, что и плашка в списке правил.
    final gone = serverKey != null && picked == null;

    final Widget inner;
    if (picked != null) {
      inner = ServerTile(
        server: picked,
        selected: false,
        // Тап по строке открывает пикер: строка здесь — не выбор, а показ
        // текущего значения.
        onTap: () => _open(context),
        // Ни меню, ни правки: диалог правила поверх себя ничего не переживёт.
        showActions: false,
        unavailableNote:
            canBeExitServer(picked) ? null : l.exitServerUnsupportedInfo,
      );
    } else {
      inner = ListTile(
        dense: true,
        leading: Icon(gone ? Icons.link_off : Icons.hub_outlined,
            color: gone ? scheme.error : null),
        title: FlagText(
          gone
              ? l.exitServerGone
              // ⚠️ Умолчание — «тот, что включён сейчас», и оно НЕ фиксируется
              // ключом. Запиши мы сюда текущий сервер, правило застряло бы на
              // нём навсегда: пользователь сменил бы сервер на главном экране, а
              // правило продолжало ходить через прежнюю страну — молча, при том
              // что в строке написано «Туннель».
              : (currentServer == null
                  ? l.ruleServerCurrent
                  : l.ruleServerCurrentNamed(currentServer!.displayName)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _open(context),
      );
    }

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(child: inner),
          // Стрелка вместо шеврона: поле должно читаться как выпадающий
          // список, которым оно и было, — иначе неочевидно, что по нему жмут.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

/// Пикер сервера для правила — по образцу диалога выбора приложений.
///
/// ⚠️ ВНУТРИ — НАСТОЯЩИЙ [ServerTile], А НЕ ЕГО УПРОЩЁННАЯ КОПИЯ. Копия
/// разошлась бы с главным экраном на первой же правке (так уже было с плашкой
/// пригодности сервера, которая полтора релиза не показывалась), а здесь
/// строка сама берёт пинг и скорость из `ProbeController`.
///
/// ⚠️ Строки-уведомления подписки (`0.0.0.0:1` с текстом вместо имени) в список
/// не попадают: выход из них собирается синтаксически верным и ведёт в никуда —
/// так решает `exitServerRejection`, единственный ответчик на вопрос
/// пригодности. Предлагать заведомо нерабочий выбор нельзя.
class RuleServerPickerDialog extends StatefulWidget {
  final List<VpnServer> servers;
  final VpnServer? currentServer;
  final String? serverKey;

  const RuleServerPickerDialog({
    super.key,
    required this.servers,
    required this.currentServer,
    required this.serverKey,
  });

  @override
  State<RuleServerPickerDialog> createState() => _RuleServerPickerDialogState();
}

class _RuleServerPickerDialogState extends State<RuleServerPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final all = widget.servers.where((s) => !s.isNotice).toList();
    // Поиск — общий с главным экраном (`ServerSearch`): у владельца в подписке
    // больше сотни серверов, и без поиска список пришлось бы листать.
    // ⚠️ Он отдаёт ИСХОДНЫЕ индексы, поэтому берём сервер по ним, а не по
    // порядку в отфильтрованном списке.
    final found = ServerSearch.matchIndices(all, _q);

    return AlertDialog(
      title: Text(l.ruleServer),
      content: adaptiveDialogBody(
        context,
        width: 440,
        height: 480,
        child: Column(
          children: [
            ServerSearchField(
              value: _q,
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            // «Как основной» — ОТДЕЛЬНОЙ строкой над списком: у этого выбора
            // сервера нет, и строкой сервера его не изобразить.
            ListTile(
              dense: true,
              leading: const Icon(Icons.hub_outlined),
              selected: widget.serverKey == null,
              title: FlagText(
                widget.currentServer == null
                    ? l.ruleServerCurrent
                    : l.ruleServerCurrentNamed(
                        widget.currentServer!.displayName),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  widget.serverKey == null ? const Icon(Icons.check) : null,
              onTap: () =>
                  Navigator.of(context).pop(const RuleServerChoice(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: found.isEmpty
                  ? Center(child: Text(l.splitNothingFound))
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (_, i) {
                        final s = all[found[i]];
                        final supported = canBeExitServer(s);
                        return ServerTile(
                          server: s,
                          selected: supported && s.key == widget.serverKey,
                          // Непригодные серверы («Авто», обходы БС, Xray-only)
                          // заблокированы от выбора: тап не закрывает пикер
                          // ложным успехом, а объясняет причину диалогом ошибки.
                          onTap: supported
                              ? () => Navigator.of(context)
                                  .pop(RuleServerChoice(s.key))
                              : () => showUnsupportedExitServerDialog(
                                    context,
                                    s,
                                  ),
                          // Меню строки уводит с диалога (информация,
                          // автонастройка) и умеет удалять сервер — в пикере
                          // это чужие действия.
                          showActions: false,
                          // Пригодность спрашиваем у единственного ответчика,
                          // общего с построителем конфига и `/v1/exits`:
                          // разойдись мы с ним — интерфейс пообещал бы то,
                          // чего конфиг не сделает.
                          unavailableNote:
                              supported ? null : l.exitServerBlockedNote,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.splitClose),
        ),
      ],
    );
  }
}

/// Показывает блокирующее сообщение об ошибке при попытке выбрать сервер,
/// который сейчас нельзя поднять отдельным выходом (`!canBeExitServer`).
Future<void> showUnsupportedExitServerDialog(
  BuildContext context,
  VpnServer server,
) {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('unsupportedExitServerDialog'),
      title: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(l.exitServerBlockedTitle)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SelText(l.exitServerBlockedBody(server.displayName)),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.splitClose),
        ),
      ],
    ),
  );
}

class _ActionChip extends StatelessWidget {
  final AppAction action;
  const _ActionChip({required this.action});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (action) {
      AppAction.tunnel => (Icons.vpn_lock, scheme.primary),
      AppAction.direct => (Icons.arrow_outward, Colors.blueGrey),
      AppAction.block => (Icons.block, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(appActionLabel(l, action),
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Диалог настройки записи (приложения или сайта): действие + (для приложений)
/// способ сопоставления. Изменения применяются сразу через колбэки.
class _RuleDialog extends StatefulWidget {
  final String title;

  /// Что кладём в буфер: у приложения — полный путь, а не короткое имя из
  /// заголовка; у сайта — адрес с портом.
  final String? copySource;
  String get copyText => copySource ?? title;

  final AppAction action;
  final bool? byName; // null = запись без сопоставления (сайт)
  final ValueChanged<AppAction> onAction;
  final ValueChanged<bool>? onByName;
  final int? initialPort; // задан для сайтов (может быть null = любой порт)
  final ValueChanged<int?>? onPort; // задан для сайтов

  /// Галочка «разрешить реальный IP». null = не показывать (настройка
  /// «Не выходить под реальным IP» выключена — тогда «Прямо» и так прямое).
  final bool? allowRealIp;
  final ValueChanged<bool>? onAllowRealIp;

  /// Приложение важнее правил по сайтам. null — запись без этой опции (сайт).
  final bool? overrideSites;
  final ValueChanged<bool>? onOverrideSites;

  /// Серверы подписки и текущий выбор правила.
  ///
  /// ⚠️ Показываем ТОЛЬКО при действии «Туннель». «Прямо через Германию» —
  /// противоречие: прямое правило идёт мимо всех туннелей, и такой выбор был бы
  /// контролом, который видно и который ничего не делает.
  final List<VpnServer> servers;

  /// Сервер, выбранный на главном экране: он и стоит по умолчанию.
  final VpnServer? currentServer;
  final String? serverKey;
  final ValueChanged<String?>? onServer;

  const _RuleDialog({
    required this.title,
    required this.action,
    this.copySource,
    required this.onAction,
    this.byName,
    this.onByName,
    this.initialPort,
    this.onPort,
    this.allowRealIp,
    this.onAllowRealIp,
    this.overrideSites,
    this.onOverrideSites,
    this.servers = const [],
    this.currentServer,
    this.serverKey,
    this.onServer,
  });

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late AppAction _action = widget.action;
  late bool _byName = widget.byName ?? true;
  late bool _allowRealIp = widget.allowRealIp ?? true;

  late bool _overrideSites = widget.overrideSites ?? false;
  late String? _serverKey = widget.serverKey;
  late final TextEditingController _port =
      TextEditingController(text: widget.initialPort?.toString() ?? '');
  String? _portError;

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  void _applyPort() {
    final l = AppLocalizations.of(context);
    final raw = _port.text.trim();
    if (raw.isEmpty) {
      setState(() => _portError = null);
      widget.onPort?.call(null);
      return;
    }
    final p = int.tryParse(raw);
    if (p == null || p < 1 || p > 65535) {
      setState(() => _portError = l.splitPortRange);
      return;
    }
    setState(() => _portError = null);
    widget.onPort?.call(p);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      // ⚠️ Внутри поле «Порт»: без прокрутки диалог рвётся при клавиатуре.
      // У пикера выше scrollable НЕ ставим — там свой ListView в Expanded,
      // и внешняя прокрутка отняла бы у него высоту.
      scrollable: true,
      // Заголовок — сам адрес сайта (или имя exe): делаем его выделяемым и
      // даём кнопку копирования. Раньше адрес нельзя было ни выделить, ни
      // скопировать: нажатие по строке лишь открывало этот диалог.
      title: Row(children: [
        Expanded(
          child: SelText.technical(widget.title,
              maxLines: 1, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(
          tooltip: widget.onPort != null ? l.splitCopyDomain : l.splitCopyPath,
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.copyText));
            if (context.mounted) AppToast.copied(context);
          },
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.splitAction),
          for (final a in AppAction.values)
            RadioListTile<AppAction>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: a,
              groupValue: _action,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _action = v);
                widget.onAction(v);
              },
              title: Text(appActionLabel(l, a)),
              secondary: _actionIcon(context, a),
            ),
          // Сервер — только у «Туннеля»: см. оговорку у поля servers.
          if (widget.onServer != null &&
              widget.servers.isNotEmpty &&
              _action == AppAction.tunnel) ...[
            const Divider(),
            Text(l.ruleServer),
            const SizedBox(height: 6),
            // ⚠️ ЗДЕСЬ БЫЛ ВЫПАДАЮЩИЙ СПИСОК С ГОЛЫМ ИМЕНЕМ СЕРВЕРА: ни флага,
            // ни пинга, ни скорости, ни пометки «этот сервер отдельным выходом
            // не поднимается». Человек выбирал вслепую, хотя рядом, на главном
            // экране, всё это уже показано. Требование владельца (18.08.2026):
            // «в выборе сервера, через что пойдёт трафик, отображай инфу о
            // сервере как на главной».
            RuleServerField(
              servers: widget.servers,
              currentServer: widget.currentServer,
              serverKey: _serverKey,
              onChanged: (v) {
                setState(() => _serverKey = v);
                widget.onServer?.call(v);
              },
            ),
          ],
          // Видно только у «Прямо» и только когда включено «Не выходить под
          // реальным IP»: в остальных случаях выбора нет — прямое правило и так
          // идёт мимо VPN.
          if (widget.allowRealIp != null && _action == AppAction.direct) ...[
            const Divider(),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _allowRealIp,
              onChanged: (v) {
                setState(() => _allowRealIp = v);
                widget.onAllowRealIp?.call(v);
              },
              title: Text(l.splitAllowRealIp),
              subtitle: Text(_allowRealIp
                  ? l.splitAllowRealIpOn
                  : l.splitAllowRealIpOff),
            ),
          ],
          // Переопределение приоритета: по умолчанию правило сайта конкретнее и
          // потому сильнее. Здесь это можно перевернуть для конкретного
          // приложения — когда оно обязано ходить одним путём целиком.
          if (widget.overrideSites != null) ...[
            const Divider(),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _overrideSites,
              onChanged: (v) {
                setState(() => _overrideSites = v);
                widget.onOverrideSites?.call(v);
              },
              title: Text(l.splitAppOverrideSites),
              subtitle: Text(l.splitAppOverrideSitesSub),
            ),
          ],
          if (widget.onPort != null) ...[
            const Divider(),
            Text(l.splitPortOptional),
            const SizedBox(height: 6),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              contentInsertionConfiguration: buildExtendedContentInsertion(
                _port,
                onInserted: (_) => _applyPort(),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: l.splitAnyPort,
                errorText: _portError,
                helperText: l.splitPortHelper,
              ),
              onChanged: (_) => _applyPort(),
            ),
          ],
          // Способ сопоставления — понятие Windows: там правило матчится либо по
          // имени exe, либо по полному пути. На Android ядро получает от
          // VpnService только uid и знает приложение по ИМЕНИ ПАКЕТА — выбор
          // ничего не менял, но правил настройки и звал переподключиться зря.
          if (widget.byName != null && !Platform.isAndroid && !Platform.isIOS) ...[
            const Divider(),
            Text(l.splitMatching),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: _byName,
              onChanged: (v) {
                setState(() => _byName = v!);
                widget.onByName?.call(v!);
              },
              title: Text(l.splitByName),
              subtitle: Text(l.splitByNameSubtitle),
            ),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: _byName,
              onChanged: (v) {
                setState(() => _byName = v!);
                widget.onByName?.call(v!);
              },
              title: Text(l.splitByPath),
              subtitle: Text(l.splitByPathSubtitle),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.splitDone)),
      ],
    );
  }

  Widget _actionIcon(BuildContext context, AppAction a) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (a) {
      AppAction.tunnel => (Icons.vpn_lock, scheme.primary),
      AppAction.direct => (Icons.arrow_outward, Colors.blueGrey),
      AppAction.block => (Icons.block, scheme.error),
    };
    return Icon(icon, color: color, size: 20);
  }
}

class _AddSiteField extends StatefulWidget {
  final SettingsController controller;
  const _AddSiteField({required this.controller});
  @override
  State<_AddSiteField> createState() => _AddSiteFieldState();
}

class _AddSiteFieldState extends State<_AddSiteField> {
  final _controller = TextEditingController();
  final _portController = TextEditingController();
  String? _error;

  void _notifyQuery() {
    final dom = _controller.text;
    final p = _portController.text.trim();
    final combined =
        (p.isNotEmpty && dom.isNotEmpty && !dom.contains(':')) ? '$dom:$p' : dom;
    _SplitSitesScope.maybeOf(context)?.onQueryChanged(combined);
    setState(() {
      if (_error != null && dom.trim().isNotEmpty) _error = null;
    });
  }

  void _clearSearch() {
    _controller.clear();
    _portController.clear();
    setState(() => _error = null);
    _SplitSitesScope.maybeOf(context)?.onQueryChanged('');
  }

  void _add() {
    final l = AppLocalizations.of(context);
    final rawInput = _controller.text;
    final domain = normalizeDomain(rawInput);
    if (domain.isEmpty) {
      setState(() => _error = l.splitEnterDomain);
      return;
    }
    int? port;
    final rawPort = _portController.text.trim();
    if (rawPort.isNotEmpty) {
      port = int.tryParse(rawPort);
      if (port == null || port < 1 || port > 65535) {
        setState(() => _error = l.splitPortRange);
        return;
      }
    } else {
      port = extractPort(rawInput);
    }

    final existed =
        widget.controller.settings.splitTunnel.containsSite(domain, port: port);
    widget.controller.update((s) {
      final existingRule = s.splitTunnel.sites
          .where(
              (x) => x.domain.toLowerCase() == domain.toLowerCase() && x.port == port)
          .firstOrNull;
      final effectiveAction = existingRule?.action ?? s.splitTunnel.defaultAction;
      final nextSites = existingRule != null
          ? s.splitTunnel.sites
          : [
              ...s.splitTunnel.sites,
              SiteRule(domain,
                  port: port,
                  action: effectiveAction,
                  insecureScheme: hasInsecureScheme(rawInput)),
            ];
      return s.copyWith(
        splitSitesCollapsed: false,
        splitCollapsed: expandCollapsedForSite(
          currentCollapsed: s.splitCollapsed,
          allSites: nextSites,
          domain: domain,
          action: effectiveAction,
        ),
        splitTunnel: s.splitTunnel.copyWith(sites: nextSites),
      );
    });
    _controller.clear();
    _portController.clear();
    setState(() => _error = null);
    _SplitSitesScope.maybeOf(context)?.onSiteSubmitted(
      context,
      domain: domain,
      port: port,
      alreadyExisted: existed,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasQuery =
        _controller.text.isNotEmpty || _portController.text.isNotEmpty;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 3,
        child: TextField(
          controller: _controller,
          contentInsertionConfiguration: buildExtendedContentInsertion(
            _controller,
            onInserted: (_) => _notifyQuery(),
          ),
          decoration: InputDecoration(
            hintText: 'youtube.com',
            labelText: l.splitAddSite,
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: hasQuery
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _clearSearch,
                  )
                : null,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
          ),
          onChanged: (_) => _notifyQuery(),
          onSubmitted: (_) => _add(),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 92,
        child: TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          contentInsertionConfiguration: buildExtendedContentInsertion(
            _portController,
            onInserted: (_) => _notifyQuery(),
          ),
          decoration: InputDecoration(
            hintText: l.splitAnyPort,
            labelText: l.splitPort,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => _notifyQuery(),
          onSubmitted: (_) => _add(),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FilledButton(onPressed: _add, child: Text(l.splitAdd)),
      ),
    ]);
  }
}

/// Подпись поддомена: своя часть — обычным цветом, общий хвост — приглушённым.
///
/// ⚠️ Зачем не просто `Text(domain)`. В дереве подряд стоят `github.io` и
/// `xtls.github.io`; читаются они почти одинаково, а ведут себя по-разному —
/// от того, какой из них совпал, зависит и маршрут, и резолвер. Выделяя ту
/// часть, которой строки ОТЛИЧАЮТСЯ, мы делаем разницу видимой без лишних
/// пояснений.
class _SubdomainLabel extends StatelessWidget {
  final SiteRule site;

  const _SubdomainLabel({required this.site});

  @override
  Widget build(BuildContext context) {
    final base = baseDomain(site.domain);
    final d = site.domain;
    // Хвост совпал — значит есть своя часть; иначе рисуем как есть.
    final own = d.toLowerCase().endsWith('.${base.toLowerCase()}')
        ? d.substring(0, d.length - base.length - 1)
        : '';
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.55);
    final port = site.port == null ? '' : ':${site.port}';
    if (own.isEmpty) {
      return Text('$d$port', textDirection: TextDirection.ltr);
    }
    return RichText(
      textDirection: TextDirection.ltr,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(
              text: own, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: '.$base$port', style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}
