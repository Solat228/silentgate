import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/util/server_search.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
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

    return Scaffold(
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
            tooltip: probe.running
                ? l.serversPinging
                : (_query.isEmpty ? l.serversPingAll : l.serversPingFound),
            icon: probe.running
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            onPressed: shown.isEmpty || probe.running
                ? null
                : () => probe.pingAll(
                    [for (final i in shown) servers[i]], settings),
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
                Expanded(
                  child: shown.isEmpty
                      ? Center(child: Text(l.serversNothingFound))
                      : ListView.separated(
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final idx = shown[i];
                            return ServerTile(
                              server: servers[idx],
                              selected: idx == state.selectedIndex,
                              onTap: () {
                                state.selectServer(idx);
                                Navigator.of(context).pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
