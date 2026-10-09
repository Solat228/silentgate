import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_server.dart';
import '../../core/settings/app_settings.dart';
import '../../core/util/server_groups.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'flag_cell.dart';

/// Высота заголовка группы. Фиксированная: прокрутка к выбранному серверу
/// считает смещение по строкам ([serverEntryTop]), и плавающая высота
/// заголовка увела бы её мимо цели.
const double kServerGroupHeaderExtent = 40;

/// Отступ строки сервера внутри группы.
const double kServerGroupIndent = 12;

/// Строки списка серверов для [shown] (исходные индексы после поиска).
///
/// ⚠️ ПРИ ПОИСКЕ ГРУППЫ НЕ СТРОЯТСЯ. Человек ищет конкретный сервер, и найденный
/// внутри свёрнутой группы оказался бы спрятан. Общая точка для правой панели
/// главного экрана и экрана «Серверы» — два своих варианта разошлись бы.
List<ServerListEntry> serverListEntries({
  required List<VpnServer> servers,
  required List<int> shown,
  required bool searching,
  required AppSettings settings,
  required int selected,
  required bool Function(VpnServer) isPinned,
}) {
  if (searching) return [for (final i in shown) ServerRowEntry(i)];
  final pinned = {
    for (var i = 0; i < servers.length; i++)
      if (isPinned(servers[i])) i
  };
  final ordered = ServerGroups.order(servers, shown,
      sortByCountry: settings.sortServersByCountry, pinned: pinned);
  return ServerGroups.build(servers, ordered,
      collapsed: settings.collapsedCountries.toSet(),
      selected: selected,
      pinned: pinned);
}

/// Верх строки сервера [index] в списке [entries] или `null`, если её нет.
///
/// Строки и заголовки разной высоты, поэтому «номер × высота» для списка с
/// группами врал бы на высоту каждого заголовка выше цели.
double? serverEntryTop(
  List<ServerListEntry> entries,
  int index, {
  required double rowExtent,
  double headerExtent = kServerGroupHeaderExtent + 1,
}) {
  var top = 0.0;
  for (final e in entries) {
    switch (e) {
      case ServerRowEntry(index: final i):
        if (i == index) return top;
        top += rowExtent;
      case ServerGroupHeader():
        top += headerExtent;
    }
  }
  return null;
}

/// Свернуть или развернуть группу [country] — состояние живёт в настройках и
/// переживает перезапуск.
Future<void> toggleServerGroup(BuildContext context, String country) {
  return context.read<SettingsController>().update((s) {
    final set = s.collapsedCountries.toSet();
    if (!set.remove(country)) set.add(country);
    return s.copyWith(collapsedCountries: set.toList()..sort());
  });
}

/// Заголовок группы серверов одной страны: флаг, подпись, число, шеврон.
class ServerGroupHeaderTile extends StatelessWidget {
  final ServerGroupHeader group;

  /// Имя любого сервера группы — из него [FlagCell] берёт флаг.
  final String flagSource;

  const ServerGroupHeaderTile(
      {super.key, required this.group, required this.flagSource});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selectedInside =
        group.indices.contains(context.select<AppState, int>((s) => s.selectedIndex));
    return Tooltip(
      message: group.collapsed ? l.serverGroupExpand : l.serverGroupCollapse,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => toggleServerGroup(context, group.country),
        child: SizedBox(
          height: kServerGroupHeaderExtent,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
            child: Row(children: [
              Icon(group.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 20),
              const SizedBox(width: 6),
              FlagCell(flagSource, width: 24, height: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          selectedInside ? FontWeight.w700 : FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${group.count}',
                    style: theme.textTheme.labelSmall),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
