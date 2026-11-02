import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/net/live_connections.dart';
import '../../core/settings/split_tunnel.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../layout/adaptive.dart';
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

  String _rulesSignature(SplitTunnelConfig split, bool noRealIp) {
    final buf = StringBuffer('${split.mode.name}|$noRealIp');
    for (final s in split.sites) {
      buf.write('|${s.domain.toLowerCase()}:${s.port ?? ''}:${s.action.name}:${s.allowRealIp}');
    }
    return buf.toString();
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
    final mismatchDomain = detectRoutingMismatch(
      snap,
      settings.splitTunnel,
      noRealIp: settings.noRealIp,
    );
    if (mismatchDomain == null) return;

    final sig = _rulesSignature(settings.splitTunnel, settings.noRealIp);
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
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
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
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: _LiveConnectionsView(
          client: client,
          initial: initial,
          isDialog: true,
        ),
      ),
    ),
  );
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
  String _query = '';
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    _busy = true;
    try {
      final snap = await widget.client.fetch(
        api,
        split: settingsCtrl.settings.splitTunnel,
      );
      if (mounted && snap != null) {
        setState(() => _snapshot = snap);
      }
    } finally {
      _busy = false;
      if (mounted &&
          context.read<AppState>().status.isConnected &&
          context.read<AppState>().connectionsCoreApi != null) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 1), _tick);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final api = state.connectionsCoreApi;
    final snap = _snapshot ?? LiveConnectionsSnapshot.empty;

    // Секции в строгом порядке: Через VPN → Блокируются (если > 0) → Прямые.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.liveConnsTitle,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      l.liveConnsSubtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
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
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
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
                  : ListView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final section in filteredSections) ...[
                          _SectionHeader(
                            kind: section.kind,
                            count: section.items.length,
                          ),
                          for (final item in section.items)
                            ListTile(
                              dense: true,
                              leading: _routeIcon(scheme, section.kind),
                              title: Text(
                                item.targetLabel,
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                [
                                  item.network.toUpperCase(),
                                  if (item.process.isNotEmpty) item.process,
                                  if (item.host.isNotEmpty &&
                                      item.destinationIp.isNotEmpty)
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
                            ),
                        ],
                      ],
                    ),
        ),
      ],
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

