import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/enum_labels.dart';
import '../../core/net/live_connection_rules_planner.dart';
import '../../core/net/live_connections.dart';
import '../../core/settings/split_tunnel.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../layout/adaptive.dart';
import '../split_tunnel_screen.dart';
import 'app_toast.dart';
import 'drag_select_region.dart';
import 'extended_clipboard.dart';
import 'sel_text.dart';
import 'vpn_reload_prompt_dialog.dart';

/// Компактная плашка открытых соединений в левом нижнем углу главного экрана
/// при активном VPN. Одновременно отслеживает в реальном времени соответствие
/// открытых соединений обновлённому списку сайтов раздельного туннелирования.
class LiveConnectionsBadge extends StatefulWidget {
  const LiveConnectionsBadge({
    super.key,
    this.client = const LiveConnectionsClient(),
  });

  final LiveConnectionsClient client;

  @override
  State<LiveConnectionsBadge> createState() => _LiveConnectionsBadgeState();
}

class _LiveConnectionsBadgeState extends State<LiveConnectionsBadge> {
  LiveConnectionsSnapshot? _snapshot;
  Timer? _nextPoll;
  bool _polling = false;
  bool _dialogOpen = false;
  DateTime? _lastAutoReloadAt;
  final Set<String> _promptedMismatches = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePolling());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePolling();
  }

  @override
  void dispose() {
    _nextPoll?.cancel();
    super.dispose();
  }

  void _ensurePolling() {
    if (!mounted) return;
    final state = context.read<AppState>();
    final api = state.connectionsCoreApi;
    if (!state.status.isConnected || api == null || api.port <= 0) {
      _nextPoll?.cancel();
      _nextPoll = null;
      if (_snapshot != null) {
        setState(() => _snapshot = null);
      }
      return;
    }
    if (!_polling && _nextPoll == null) {
      unawaited(_pollOnce());
    }
  }

  Future<void> _pollOnce() async {
    if (!mounted || _polling) return;
    final state = context.read<AppState>();
    final settingsCtrl = context.read<SettingsController>();
    final api = state.connectionsCoreApi;
    if (!state.status.isConnected || api == null || api.port <= 0) {
      return;
    }

    _polling = true;
    try {
      final split = settingsCtrl.settings.splitTunnel;
      final snap = await widget.client.fetch(api, split: split);
      if (!mounted) return;
      if (snap != null) {
        final prev = _snapshot;
        final changed = prev == null ||
            prev.vpn.length != snap.vpn.length ||
            prev.blocked.length != snap.blocked.length ||
            prev.direct.length != snap.direct.length;
        _snapshot = snap;
        if (changed) setState(() {});
        _checkLiveRoutingMismatch(snap, state, settingsCtrl);
      }
    } finally {
      _polling = false;
      if (mounted &&
          context.read<AppState>().status.isConnected &&
          context.read<AppState>().connectionsCoreApi != null) {
        _nextPoll?.cancel();
        _nextPoll = Timer(const Duration(seconds: 1), () {
          _nextPoll = null;
          unawaited(_pollOnce());
        });
      }
    }
  }

  void _checkLiveRoutingMismatch(
    LiveConnectionsSnapshot snap,
    AppState state,
    SettingsController settingsCtrl,
  ) {
    if (!mounted || _dialogOpen || !state.status.isConnected) return;
    final settings = settingsCtrl.settings;
    final sig = splitRoutingSignature(
      settings.splitTunnel,
      noRealIp: settings.noRealIp,
    );
    // Диалог «Маршруты обновились» уместен ТОЛЬКО если правила менялись после
    // подъёма текущего туннеля. Пока отпечаток совпадает с тем, с которым
    // поднят активный туннель, «прежнего списка» не существует.
    final activeSig = state.connectedSplitSignature;
    if (activeSig != null && activeSig == sig) return;

    final mismatchDomain = detectRoutingMismatch(
      snap,
      settings.splitTunnel,
      noRealIp: settings.noRealIp,
    );
    if (mismatchDomain == null) return;

    final promptKey = '${mismatchDomain.toLowerCase()}@$sig';
    if (_promptedMismatches.contains(promptKey)) return;

    if (settings.alwaysReloadVpnOnNewSite) {
      final now = DateTime.now();
      if (_lastAutoReloadAt != null &&
          now.difference(_lastAutoReloadAt!) < const Duration(seconds: 8)) {
        return;
      }
      _lastAutoReloadAt = now;
      _promptedMismatches.add(promptKey);
      unawaited(state.reconnect(settings));
      return;
    }

    _promptedMismatches.add(promptKey);
    _dialogOpen = true;
    unawaited(
      showVpnReloadPromptDialog(
        context,
        domain: mismatchDomain,
        settingsController: settingsCtrl,
        appState: state,
        isLiveMismatch: true,
      ).whenComplete(() {
        _dialogOpen = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.status.isConnected) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final snap = _snapshot;
    final count = snap?.totalCount ?? 0;

    return Material(
      key: const Key('liveConnectionsBadge'),
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
      elevation: 1,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showLiveConnectionsSheet(
          context,
          client: widget.client,
          initial: snap,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l.liveConnsBadge(count),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (snap != null && count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '${snap.vpn.length}/${snap.direct.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Открывает панель текущих открытых соединений в реальном времени.
Future<void> showLiveConnectionsSheet(
  BuildContext context, {
  LiveConnectionsClient client = const LiveConnectionsClient(),
  LiveConnectionsSnapshot? initial,
}) {
  if (context.sg.isCompact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.80,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (ctx, scrollController) => _LiveConnectionsView(
          client: client,
          initial: initial,
          scrollController: scrollController,
          isDialog: false,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: _LiveConnectionsView(
          client: client,
          initial: initial,
          isDialog: true,
        ),
      ),
    ),
  );
}

enum _ConnMenuAction {
  toggleSelect,
  selectProcess,
  selectDomain,
  routeTunnel,
  routeViaServer,
  routeDirect,
  routeBlock,
  closeConn,
  filterProcess,
  filterDomain,
  copyDomain,
  copyIpPort,
  copyProcess,
  copyExePath,
  showInExplorer,
}

class _LiveConnectionsView extends StatefulWidget {
  const _LiveConnectionsView({
    required this.client,
    required this.isDialog,
    this.initial,
    this.scrollController,
  });

  final LiveConnectionsClient client;
  final LiveConnectionsSnapshot? initial;
  final ScrollController? scrollController;
  final bool isDialog;

  @override
  State<_LiveConnectionsView> createState() => _LiveConnectionsViewState();
}

class _LiveConnectionsViewState extends State<_LiveConnectionsView> {
  late LiveConnectionsSnapshot? _snapshot = widget.initial;
  final _searchCtrl = TextEditingController();
  late final ScrollController _ownScrollCtrl = ScrollController();
  final DragSelectController<String> _dragCtrl = DragSelectController<String>();

  String _query = '';
  Timer? _timer;
  bool _busy = false;

  bool _manualPaused = false;
  bool _explicitSelectMode = false;
  final Set<String> _selectedIds = <String>{};
  LiveRuleTargetMode _targetMode = LiveRuleTargetMode.auto;

  ScrollController get _scrollCtrl => widget.scrollController ?? _ownScrollCtrl;
  bool get _selectionMode => _explicitSelectMode || _selectedIds.isNotEmpty;
  bool get _effectivePaused => _manualPaused || _selectionMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dragCtrl.dispose();
    _ownScrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted || _busy) return;
    final state = context.read<AppState>();
    final settingsCtrl = context.read<SettingsController>();
    final api = state.connectionsCoreApi;
    if (!state.status.isConnected || api == null || api.port <= 0) {
      return;
    }

    if (_effectivePaused) {
      _scheduleNextTick();
      return;
    }

    _busy = true;
    try {
      final snap = await widget.client.fetch(
        api,
        split: settingsCtrl.settings.splitTunnel,
      );
      if (mounted && snap != null && !_effectivePaused) {
        setState(() => _snapshot = snap);
      }
    } finally {
      _busy = false;
      _scheduleNextTick();
    }
  }

  void _scheduleNextTick() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.status.isConnected && state.connectionsCoreApi != null) {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _tick);
    }
  }

  void _toggleManualPause() {
    setState(() => _manualPaused = !_manualPaused);
    if (!_effectivePaused) {
      unawaited(_tick());
    }
  }

  void _clearSelection() {
    if (!_selectionMode) return;
    setState(() {
      _selectedIds.clear();
      _explicitSelectMode = false;
    });
    if (!_effectivePaused) {
      unawaited(_tick());
    }
  }

  void _toggleSingleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
    if (!_effectivePaused) {
      unawaited(_tick());
    }
  }

  void _toggleSelectAllVisible(List<String> visibleIds) {
    if (visibleIds.isEmpty) return;
    setState(() {
      final allSelected = visibleIds.every(_selectedIds.contains);
      if (allSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  void _setFilterQuery(String q) {
    _searchCtrl.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    setState(() => _query = q);
  }

  bool _matches(LiveConnectionEntry e) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.host.contains(q) ||
        e.destinationIp.toLowerCase().contains(q) ||
        e.process.toLowerCase().contains(q) ||
        '${e.destinationPort}'.contains(q);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _previewNames(Iterable<String> items, {int maxCount = 2}) {
    final list = items.toList();
    if (list.length <= maxCount) return list.join(', ');
    final head = list.take(maxCount).join(', ');
    return '$head +${list.length - maxCount}';
  }

  Future<void> _closeConnectionsById(Set<String> ids) async {
    if (ids.isEmpty) return;
    final state = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final api = state.connectionsCoreApi;
    if (api == null || api.port <= 0) return;

    final closed = await widget.client.closeConnections(api, ids);
    if (!mounted) return;
    if (closed > 0) {
      setState(() {
        _snapshot = (_snapshot ?? LiveConnectionsSnapshot.empty).withoutIds(ids);
        _selectedIds.removeAll(ids);
      });
      AppToast.show(context, l.liveConnsClosedToast(closed));
    } else {
      AppToast.show(context, l.liveConnsCloseFailedToast);
    }
  }

  Future<void> _copySelectedTargets(List<LiveConnectionEntry> entries) async {
    if (entries.isEmpty) return;
    final lines = <String>[];
    final seen = <String>{};
    for (final e in entries) {
      final line = e.process.isNotEmpty
          ? '${e.targetLabel} (${e.process})'
          : e.targetLabel;
      if (seen.add(line)) lines.add(line);
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) AppToast.copied(context);
  }

  Future<void> _applyRulesForEntries(
    List<LiveConnectionEntry> entries, {
    required LiveRuleTargetMode mode,
    required AppAction action,
    bool pickServer = false,
  }) async {
    if (entries.isEmpty) return;
    final state = context.read<AppState>();
    final settingsCtrl = context.read<SettingsController>();
    final l = AppLocalizations.of(context);

    final plan = LiveConnectionRulesPlanner.plan(entries, mode: mode);
    if (plan.isEmpty) {
      AppToast.show(context, l.liveConnsPlanEmpty);
      return;
    }

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
      if (choice == null || !mounted) return;
      serverKey = choice.key;
    }

    late AppliedLiveRulesResult applied;
    settingsCtrl.update((cur) {
      applied = LiveConnectionRulesPlanner.applyToSettings(
        cur,
        plan,
        action: action,
        serverKey: serverKey,
      );
      return applied.settings;
    });

    // Сразу сбрасываем текущие открытые сокеты этих соединений, чтобы браузер /
    // мессенджер открыл их заново уже по новому правилу.
    final api = state.connectionsCoreApi;
    final idsToClose = entries.map((e) => e.id).toSet();
    if (api != null && api.port > 0) {
      unawaited(widget.client.closeConnections(api, idsToClose));
    }

    setState(() {
      _selectedIds.clear();
      _explicitSelectMode = false;
    });
    if (!_effectivePaused) {
      unawaited(_tick());
    }

    if (!mounted) return;
    AppToast.show(context, l.liveConnsRulesAppliedToast(applied.totalTouched));

    if (state.status.isConnected &&
        splitRulesEditableIn(settingsCtrl.settings.captureMode)) {
      if (settingsCtrl.settings.alwaysReloadVpnOnNewSite) {
        unawaited(state.reconnect(settingsCtrl.settings));
      } else if (applied.primarySubject.isNotEmpty) {
        unawaited(
          showVpnReloadPromptDialog(
            context,
            domain: applied.primarySubject,
            settingsController: settingsCtrl,
            appState: state,
            isLiveMismatch: false,
          ),
        );
      }
    }
  }

  Future<void> _showInExplorer(String processPath) async {
    if (!Platform.isWindows || processPath.trim().isEmpty) return;
    final winPath = processPath.trim().replaceAll('/', r'\');
    try {
      await Process.run('explorer.exe', ['/select,$winPath']);
    } catch (_) {}
  }

  Future<void> _openRowContextMenu(
    BuildContext context,
    Offset globalPos,
    LiveConnectionEntry item,
    LiveConnectionsSnapshot snap,
  ) async {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final all = snap.allEntries;
    final sameProcIds = item.process.isEmpty
        ? const <String>{}
        : {
            for (final e in all)
              if (e.process.toLowerCase() == item.process.toLowerCase()) e.id,
          };
    final validDomain = LiveConnectionRulesPlanner.extractValidDomain(item);
    final sameDomainIds = validDomain.isEmpty
        ? const <String>{}
        : {
            for (final e in all)
              if (LiveConnectionRulesPlanner.extractValidDomain(e) == validDomain)
                e.id,
          };

    final isItemSelected = _selectedIds.contains(item.id);
    // Если ПКМ вызван по строке внутри активного мультивыбора (> 1), быстрые
    // маршруты применяются ко всему выделению; иначе - к этой строке.
    final routeEntries = (isItemSelected && _selectedIds.length > 1)
        ? all.where((e) => _selectedIds.contains(e.id)).toList()
        : <LiveConnectionEntry>[item];
    final routeMode = (isItemSelected && _selectedIds.length > 1)
        ? _targetMode
        : LiveRuleTargetMode.auto;

    final action = await showMenu<_ConnMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _ConnMenuAction.toggleSelect,
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
        if (item.process.isNotEmpty && sameProcIds.length > 1)
          PopupMenuItem(
            value: _ConnMenuAction.selectProcess,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.apps, size: 18),
              title: Text(
                l.liveConnsMenuSelectProcess(item.process, sameProcIds.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (validDomain.isNotEmpty && sameDomainIds.length > 1)
          PopupMenuItem(
            value: _ConnMenuAction.selectDomain,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language, size: 18),
              title: Text(
                l.liveConnsMenuSelectDomain(validDomain, sameDomainIds.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ConnMenuAction.routeTunnel,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vpn_lock, size: 18, color: scheme.primary),
            title: Text(appActionLabel(l, AppAction.tunnel)),
          ),
        ),
        PopupMenuItem(
          value: _ConnMenuAction.routeViaServer,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.public, size: 18, color: scheme.primary),
            title: Text(l.liveConnsMenuRouteViaServer),
          ),
        ),
        PopupMenuItem(
          value: _ConnMenuAction.routeDirect,
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
          value: _ConnMenuAction.routeBlock,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block, size: 18, color: scheme.error),
            title: Text(appActionLabel(l, AppAction.block)),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ConnMenuAction.closeConn,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link_off, size: 18, color: scheme.error),
            title: Text(
              l.liveConnsMenuCloseConn,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
        if (item.process.isNotEmpty)
          PopupMenuItem(
            value: _ConnMenuAction.filterProcess,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.filter_alt_outlined, size: 18),
              title: Text(
                l.liveConnsMenuFilterProcess(item.process),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (validDomain.isNotEmpty)
          PopupMenuItem(
            value: _ConnMenuAction.filterDomain,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.travel_explore, size: 18),
              title: Text(
                l.liveConnsMenuFilterDomain(validDomain),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        const PopupMenuDivider(),
        if (item.host.isNotEmpty)
          PopupMenuItem(
            value: _ConnMenuAction.copyDomain,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy, size: 18),
              title: Text(l.liveConnsMenuCopyDomain),
            ),
          ),
        if (item.destinationIp.isNotEmpty)
          PopupMenuItem(
            value: _ConnMenuAction.copyIpPort,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pin_drop_outlined, size: 18),
              title: Text(l.liveConnsMenuCopyIpPort),
            ),
          ),
        if (item.process.isNotEmpty)
          PopupMenuItem(
            value: _ConnMenuAction.copyProcess,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.terminal, size: 18),
              title: Text(l.liveConnsMenuCopyProcess),
            ),
          ),
        if (item.hasExecutablePath)
          PopupMenuItem(
            value: _ConnMenuAction.copyExePath,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, size: 18),
              title: Text(l.liveConnsMenuCopyExePath),
            ),
          ),
        if (Platform.isWindows && item.hasExecutablePath)
          PopupMenuItem(
            value: _ConnMenuAction.showInExplorer,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open, size: 18),
              title: Text(l.liveConnsMenuShowInExplorer),
            ),
          ),
      ],
    );

    if (action == null || !mounted) return;
    switch (action) {
      case _ConnMenuAction.toggleSelect:
        _toggleSingleSelection(item.id);
      case _ConnMenuAction.selectProcess:
        setState(() => _selectedIds.addAll(sameProcIds));
      case _ConnMenuAction.selectDomain:
        setState(() => _selectedIds.addAll(sameDomainIds));
      case _ConnMenuAction.routeTunnel:
        await _applyRulesForEntries(
          routeEntries,
          mode: routeMode,
          action: AppAction.tunnel,
        );
      case _ConnMenuAction.routeViaServer:
        await _applyRulesForEntries(
          routeEntries,
          mode: routeMode,
          action: AppAction.tunnel,
          pickServer: true,
        );
      case _ConnMenuAction.routeDirect:
        await _applyRulesForEntries(
          routeEntries,
          mode: routeMode,
          action: AppAction.direct,
        );
      case _ConnMenuAction.routeBlock:
        await _applyRulesForEntries(
          routeEntries,
          mode: routeMode,
          action: AppAction.block,
        );
      case _ConnMenuAction.closeConn:
        final targetIds = (isItemSelected && _selectedIds.length > 1)
            ? Set<String>.of(_selectedIds)
            : <String>{item.id};
        await _closeConnectionsById(targetIds);
      case _ConnMenuAction.filterProcess:
        _setFilterQuery(item.process);
      case _ConnMenuAction.filterDomain:
        _setFilterQuery(validDomain);
      case _ConnMenuAction.copyDomain:
        await Clipboard.setData(ClipboardData(text: item.host));
        if (context.mounted) AppToast.copied(context);
      case _ConnMenuAction.copyIpPort:
        final ipPort = item.destinationPort > 0
            ? '${item.destinationIp}:${item.destinationPort}'
            : item.destinationIp;
        await Clipboard.setData(ClipboardData(text: ipPort));
        if (context.mounted) AppToast.copied(context);
      case _ConnMenuAction.copyProcess:
        await Clipboard.setData(ClipboardData(text: item.process));
        if (context.mounted) AppToast.copied(context);
      case _ConnMenuAction.copyExePath:
        await Clipboard.setData(ClipboardData(text: item.processPath));
        if (context.mounted) AppToast.copied(context);
      case _ConnMenuAction.showInExplorer:
        await _showInExplorer(item.processPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final api = state.connectionsCoreApi;
    final snap = _snapshot ?? LiveConnectionsSnapshot.empty;

    // Секции в строгом порядке: Через VPN -> Блокируются (если > 0) -> Прямые.
    final rawSections = snap.sections;
    final filteredSections = <LiveConnectionsSection>[
      for (final s in rawSections)
        if (s.kind != LiveRouteKind.blocked ||
            s.items.where(_matches).isNotEmpty)
          LiveConnectionsSection(
            kind: s.kind,
            items: s.items.where(_matches).toList(),
          ),
    ];

    final visibleOrderedIds = <String>[
      for (final s in filteredSections)
        for (final e in s.items) e.id,
    ];
    _dragCtrl.orderedIds = visibleOrderedIds;

    final allEntries = snap.allEntries;
    final selectedEntries =
        allEntries.where((e) => _selectedIds.contains(e.id)).toList();

    final (subtitleText, subtitleColor) = _manualPaused
        ? (l.liveConnsPausedSubtitle, scheme.tertiary)
        : (_selectionMode
            ? (l.liveConnsFrozenSelectingSubtitle, scheme.primary)
            : (l.liveConnsSubtitle, scheme.onSurfaceVariant));

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (_selectionMode)
          const SingleActivator(LogicalKeyboardKey.escape): _clearSelection,
      },
      child: Focus(
        autofocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectionMode && _selectedIds.isNotEmpty
                              ? l.liveConnsSelectedCount(_selectedIds.length)
                              : l.liveConnsTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Row(
                          children: [
                            if (_effectivePaused) ...[
                              Icon(
                                Icons.ac_unit_rounded,
                                size: 12,
                                color: subtitleColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                subtitleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: subtitleColor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('liveConnsPauseBtn'),
                    tooltip:
                        _manualPaused ? l.liveConnsResume : l.liveConnsPause,
                    icon: Icon(
                      _manualPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: _manualPaused ? scheme.tertiary : null,
                    ),
                    onPressed: _toggleManualPause,
                  ),
                  if (!_selectionMode)
                    IconButton(
                      key: const Key('liveConnsSelectModeBtn'),
                      tooltip: l.liveConnsSelectMode,
                      icon: const Icon(Icons.checklist_rtl_rounded),
                      onPressed: () =>
                          setState(() => _explicitSelectMode = true),
                    )
                  else ...[
                    IconButton(
                      key: const Key('liveConnsSelectAllBtn'),
                      tooltip: l.liveConnsSelectAll,
                      icon: const Icon(Icons.select_all_rounded),
                      onPressed: visibleOrderedIds.isEmpty
                          ? null
                          : () => _toggleSelectAllVisible(visibleOrderedIds),
                    ),
                    IconButton(
                      key: const Key('liveConnsClearSelectBtn'),
                      tooltip: l.liveConnsClearSelection,
                      icon: const Icon(Icons.deselect_rounded),
                      onPressed: _clearSelection,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                contentInsertionConfiguration: buildExtendedContentInsertion(
                  _searchCtrl,
                  onInserted: (v) => setState(() => _query = v),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _setFilterQuery(''),
                        )
                      : null,
                  hintText: 'youtube.com / chrome.exe',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: api == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SelText(
                          l.liveConnsUnavailable,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : snap.totalCount == 0
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(l.liveConnsEmpty),
                          ),
                        )
                      : DragSelectRegion<String>(
                          controller: _dragCtrl,
                          scrollController: _scrollCtrl,
                          isSelectionMode: _selectionMode,
                          selectedIds: _selectedIds,
                          onSelectionChanged:
                              (next, {required enteredSelectionMode}) {
                            setState(() {
                              _selectedIds
                                ..clear()
                                ..addAll(next);
                            });
                          },
                          child: ListView(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.only(bottom: 16),
                            children: [
                              for (final section in filteredSections) ...[
                                _SectionHeader(
                                  kind: section.kind,
                                  count: section.items.length,
                                ),
                                for (final item in section.items)
                                  _buildConnectionRow(
                                    context,
                                    scheme,
                                    section.kind,
                                    item,
                                    snap,
                                  ),
                              ],
                            ],
                          ),
                        ),
            ),
            if (selectedEntries.isNotEmpty)
              _buildBatchActionPanel(context, l, scheme, selectedEntries),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionRow(
    BuildContext context,
    ColorScheme scheme,
    LiveRouteKind kind,
    LiveConnectionEntry item,
    LiveConnectionsSnapshot snap,
  ) {
    final isSelected = _selectedIds.contains(item.id);
    return DragSelectItem<String>(
      key: ValueKey('liveConn:${item.id}'),
      id: item.id,
      controller: _dragCtrl,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) =>
            _openRowContextMenu(context, d.globalPosition, item, snap),
        onLongPressStart: (d) =>
            _openRowContextMenu(context, d.globalPosition, item, snap),
        child: ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: scheme.primary.withValues(alpha: 0.11),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectionMode) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: isSelected,
                    onChanged: (_) => _toggleSingleSelection(item.id),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _routeIcon(scheme, kind),
            ],
          ),
          title: Text(
            item.targetLabel,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            [
              item.network.toUpperCase(),
              if (item.process.isNotEmpty) item.process,
              if (item.host.isNotEmpty && item.destinationIp.isNotEmpty)
                item.destinationIp,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '↓ ${_formatBytes(item.downloadBytes)}\n'
            '↑ ${_formatBytes(item.uploadBytes)}',
            textAlign: TextAlign.end,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          onTap: () {
            if (_dragCtrl.consumeTapSuppression()) return;
            _toggleSingleSelection(item.id);
          },
        ),
      ),
    );
  }

  Widget _buildBatchActionPanel(
    BuildContext context,
    AppLocalizations l,
    ColorScheme scheme,
    List<LiveConnectionEntry> selectedEntries,
  ) {
    final plan = LiveConnectionRulesPlanner.plan(
      selectedEntries,
      mode: _targetMode,
    );

    final summaryParts = <String>[
      if (plan.domains.isNotEmpty)
        l.liveConnsPlanSummarySites(
          plan.domains.length,
          _previewNames(plan.domains),
        ),
      if (plan.apps.isNotEmpty)
        l.liveConnsPlanSummaryApps(
          plan.apps.length,
          _previewNames(plan.apps.map((a) => a.displayName)),
        ),
    ];
    final summaryText =
        summaryParts.isEmpty ? l.liveConnsPlanEmpty : summaryParts.join('  ·  ');

    Widget modeChip(LiveRuleTargetMode mode, String label) {
      final active = _targetMode == mode;
      return ChoiceChip(
        key: ValueKey('liveTargetMode:${mode.name}'),
        label: Text(label),
        selected: active,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => setState(() => _targetMode = mode),
      );
    }

    return Container(
      key: const Key('liveConnsBatchPanel'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    modeChip(LiveRuleTargetMode.auto, l.liveConnsModeAuto),
                    modeChip(LiveRuleTargetMode.sites, l.liveConnsModeSites),
                    modeChip(LiveRuleTargetMode.apps, l.liveConnsModeApps),
                    modeChip(LiveRuleTargetMode.both, l.liveConnsModeBoth),
                  ],
                ),
              ),
              IconButton(
                key: const Key('liveConnsBatchCopyBtn'),
                visualDensity: VisualDensity.compact,
                tooltip: l.liveConnsCopySelectedTargets,
                icon: const Icon(Icons.copy_all_outlined, size: 20),
                onPressed: () => _copySelectedTargets(selectedEntries),
              ),
              IconButton(
                key: const Key('liveConnsBatchCloseSockBtn'),
                visualDensity: VisualDensity.compact,
                tooltip: l.liveConnsMenuCloseSelected(selectedEntries.length),
                icon: Icon(Icons.link_off, size: 20, color: scheme.error),
                onPressed: () => _closeConnectionsById(
                  selectedEntries.map((e) => e.id).toSet(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summaryText,
            key: const Key('liveConnsPlanPreview'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: plan.isEmpty
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
          ),
          if (plan.skippedSharedBareIpProcesses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l.liveConnsPlanSkippedSharedIp(
                  plan.skippedSharedBareIpProcesses.join(', '),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.tertiary),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                key: const Key('liveConnsBatchTunnel'),
                onPressed: plan.isEmpty
                    ? null
                    : () => _applyRulesForEntries(
                          selectedEntries,
                          mode: _targetMode,
                          action: AppAction.tunnel,
                        ),
                icon: const Icon(Icons.vpn_lock, size: 17),
                label: Text(appActionLabel(l, AppAction.tunnel)),
              ),
              FilledButton.tonalIcon(
                key: const Key('liveConnsBatchViaServer'),
                onPressed: plan.isEmpty
                    ? null
                    : () => _applyRulesForEntries(
                          selectedEntries,
                          mode: _targetMode,
                          action: AppAction.tunnel,
                          pickServer: true,
                        ),
                icon: const Icon(Icons.public, size: 17),
                label: Text(l.liveConnsMenuRouteViaServer),
              ),
              OutlinedButton.icon(
                key: const Key('liveConnsBatchDirect'),
                onPressed: plan.isEmpty
                    ? null
                    : () => _applyRulesForEntries(
                          selectedEntries,
                          mode: _targetMode,
                          action: AppAction.direct,
                        ),
                icon: const Icon(Icons.arrow_outward, size: 17),
                label: Text(appActionLabel(l, AppAction.direct)),
              ),
              OutlinedButton.icon(
                key: const Key('liveConnsBatchBlock'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                ),
                onPressed: plan.isEmpty
                    ? null
                    : () => _applyRulesForEntries(
                          selectedEntries,
                          mode: _targetMode,
                          action: AppAction.block,
                        ),
                icon: const Icon(Icons.block, size: 17),
                label: Text(appActionLabel(l, AppAction.block)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _routeIcon(ColorScheme scheme, LiveRouteKind kind) {
    return switch (kind) {
      LiveRouteKind.vpn =>
        Icon(Icons.vpn_lock, size: 18, color: scheme.primary),
      LiveRouteKind.blocked =>
        Icon(Icons.block, size: 18, color: scheme.error),
      LiveRouteKind.direct =>
        const Icon(Icons.arrow_outward, size: 18, color: Colors.blueGrey),
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.kind, required this.count});

  final LiveRouteKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (kind) {
      LiveRouteKind.vpn => (l.liveConnsSectionVpn, scheme.primary),
      LiveRouteKind.blocked => (l.liveConnsSectionBlocked, scheme.error),
      LiveRouteKind.direct => (l.liveConnsSectionDirect, Colors.blueGrey),
    };
    return Container(
      key: ValueKey('liveSection:${kind.name}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
