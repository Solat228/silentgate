import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/util/server_groups.dart';
import '../core/util/server_search.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
import 'home_screen.dart' show CopyServerKeyShortcut;
import 'widgets/auto_pick_button.dart';
import 'widgets/ping_gate.dart';
import 'widgets/server_group_header.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final probe = context.watch<ProbeController>();
    final settings = context.read<SettingsController>().settings;
    final servers = state.servers;
    // Исходные индексы: выбор идёт по позиции в AppState.servers.
    final shown = ServerSearch.matchIndices(servers, _query);
    // Строки с заголовками групп стран — та же функция, что у правой панели
    // главного экрана.
    final entries = serverListEntries(
      servers: servers,
      shown: shown,
      searching: _query.isNotEmpty,
      settings: context.watch<SettingsController>().settings,
      selected: state.selectedIndex,
      isPinned: state.isPinned,
    );
    final gate = PingGate.of(probe, hasTargets: shown.isNotEmpty);
    final nothingToPing =
        servers.isEmpty ? l.serversEmpty : l.serversNothingFound;

    return CopyServerKeyShortcut(
        child: Scaffold(
      appBar: AppBar(
        title: Text(_query.isEmpty
            ? l.serversTitle
            : l.serversFound(shown.length, servers.length)),
        actions: [
          IconButton(
            tooltip: l.serversRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: state.subscriptionUrl == null || state.loading
                ? null
                : state.refreshSubscription,
          ),
          IconButton(
            tooltip: gate.label(
                l, _query.isEmpty ? l.serversPingAll : l.serversPingFound,
                noTargets: nothingToPing),
            icon: probe.running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            onPressed: gate.allowed
                ? () => probe.pingAll(
                    [for (final i in shown) servers[i]], settings)
                : null,
          ),
        ],
      ),
      body: servers.isEmpty
          ? Center(child: Text(l.serversEmpty))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: ServerSearchField(
                    value: _query,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: AutoPickServerButton(wide: true),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(child: Text(l.serversNothingFound))
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            if (entry is ServerGroupHeader) {
                              return ServerGroupHeaderTile(
                                group: entry,
                                flagSource:
                                    servers[entry.indices.first].remark,
                                onSelect: () {
                                  state.selectServerGroup(entry);
                                  Navigator.of(context).pop();
                                },
                              );
                            }
                            final row = entry as ServerRowEntry;
                            final idx = row.index;
                            final tile = ServerTile(
                              server: servers[idx],
                              selected: idx == state.selectedIndex,
                              onTap: () {
                                state.selectServer(idx);
                                Navigator.of(context).pop();
                              },
                            );
                            return serverListRow(row, tile);
                          },
                        ),
                ),
              ],
            ),
    ));
  }
}
