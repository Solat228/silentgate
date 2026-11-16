import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_server.dart';
import '../../core/settings/app_settings.dart';
import '../../core/util/auto_groups.dart';
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

/// Ширина шеврона у шапки группы «Авто». На эту же ширину сдвинуты серверы
/// группы — их флаги встают ровно под флагом профиля.
const double kAutoGroupToggleWidth = 34;

/// Строки списка серверов для [shown] (исходные индексы после поиска).
///
/// ⚠️ ПРИ ПОИСКЕ ГРУППЫ НЕ СТРОЯТСЯ. Человек ищет конкретный сервер, и найденный
/// внутри свёрнутой группы оказался бы спрятан. Общая точка для правой панели
/// главного экрана, экрана «Серверы» и диалога «Через сервер».
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
  // Закреплённые к профилю не привязываются: они наверху ради того, чтобы
  // быть под рукой, а не прятаться в свёрнутой группе.
  final auto = AutoGroups.bind(servers, skip: pinned);
  final ordered = ServerGroups.order(servers, shown,
      sortByCountry: settings.sortServersByCountry, pinned: pinned, auto: auto);
  return ServerGroups.build(servers, ordered,
      collapsed: settings.collapsedCountries.toSet(),
      selected: selected,
      pinned: pinned,
      auto: auto,
      expandedAuto: settings.expandedAutoGroups.toSet());
}

/// Строка сервера в списке с учётом группы: отступ внутри группы и шеврон у
/// шапки группы «Авто». Общая для обоих списков — как и [serverListEntries].
///
/// ⚠️ Высоту строки обёртка не меняет: прокрутка к выбранному серверу
/// считает её по строке без групп ([serverEntryTop]).
Widget serverListRow(ServerRowEntry row, Widget tile) {
  if (row.auto case final info?) {
    return Row(children: [
      AutoGroupToggle(info: info),
      Expanded(child: tile),
    ]);
  }
  if (row.autoMember || row.grouped) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
          start: row.autoMember ? kAutoGroupToggleWidth : kServerGroupIndent),
      child: tile,
    );
  }
  return tile;
}

/// Свернуть или развернуть группу профиля «Авто» [key]. Хранятся раскрытые:
/// по умолчанию группа свёрнута.
Future<void> toggleAutoGroup(BuildContext context, String key) {
  return context.read<SettingsController>().update((s) {
    final set = s.expandedAutoGroups.toSet();
    if (!set.remove(key)) set.add(key);
    return s.copyWith(expandedAutoGroups: set.toList()..sort());
  });
}

/// Шеврон и число серверов слева от строки профиля «Авто».
class AutoGroupToggle extends StatelessWidget {
  final AutoGroupInfo info;
  const AutoGroupToggle({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: info.collapsed ? l.serverGroupExpand : l.serverGroupCollapse,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => toggleAutoGroup(context, info.key),
        child: SizedBox(
          width: kAutoGroupToggleWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(info.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 20),
              Text('${info.count}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
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
/// переживает перезапуск. Папка «🌉 Мосты» по умолчанию свёрнута и хранит
/// признак раскрытия в `expandedAutoGroups`.
Future<void> toggleServerGroup(BuildContext context, String country) {
  if (country == ServerGroups.bridgesCountryKey) {
    return toggleAutoGroup(context, ServerGroups.bridgesGroupKey);
  }
  return context.read<SettingsController>().update((s) {
    final set = s.collapsedCountries.toSet();
    if (!set.remove(country)) set.add(country);
    return s.copyWith(collapsedCountries: set.toList()..sort());
  });
}

/// Заголовок сворачиваемой группы серверов одной страны (когда у страны нет
/// собственного автосервера от панели) либо папки «🌉 Мосты».
///
/// Шёлк по шеврону или числу сворачивает/разворачивает группу, а нажатие по
/// самой строке (флаг и название) выбирает группу целиком как виртуальный
/// автосервер по всем её узлам.
class ServerGroupHeaderTile extends StatelessWidget {
  final ServerGroupHeader group;

  /// Имя любого сервера группы — из него [FlagCell] берёт флаг.
  final String flagSource;

  /// Переопределение действия при выборе заголовка (например, в пикере
  /// «Через сервер» или на экране `ServersScreen`). По умолчанию выбирает
  /// виртуальный автосервер группы в [AppState].
  final VoidCallback? onSelect;

  /// Переопределение признака «выбрана вся группа» (для пикера правил).
  final bool? selectedOverride;

  const ServerGroupHeaderTile({
    super.key,
    required this.group,
    required this.flagSource,
    this.onSelect,
    this.selectedOverride,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isBridges = group.country == ServerGroups.bridgesCountryKey;
    final selectedGroup = selectedOverride ??
        (context.select<AppState, String?>((s) => s.selectedGroupCountry) ==
            group.country);
    final selectedInside = selectedGroup ||
        group.indices.contains(
            context.select<AppState, int>((s) => s.selectedIndex));
    final titleText = isBridges ? '🌉 ${group.label}' : group.label;

    return ColoredBox(
      color: selectedGroup
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
          : Colors.transparent,
      child: SizedBox(
        height: kServerGroupHeaderExtent,
        child: Row(children: [
          Tooltip(
            message:
                group.collapsed ? l.serverGroupExpand : l.serverGroupCollapse,
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              key: ValueKey('groupToggle:${group.country}'),
              onTap: () => toggleServerGroup(context, group.country),
              child: SizedBox(
                width: kAutoGroupToggleWidth,
                height: kServerGroupHeaderExtent,
                child: Icon(
                  group.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 20,
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              key: ValueKey('groupSelect:${group.country}'),
              onTap: onSelect ??
                  () => context.read<AppState>().selectServerGroup(group),
              child: SizedBox(
                height: kServerGroupHeaderExtent,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Row(children: [
                    FlagCell(
                      isBridges ? '' : flagSource,
                      auto: isBridges,
                      width: 24,
                      height: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: selectedInside
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: selectedGroup
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                    if (selectedGroup) ...[
                      Icon(Icons.check,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          Tooltip(
            message:
                group.collapsed ? l.serverGroupExpand : l.serverGroupCollapse,
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              onTap: () => toggleServerGroup(context, group.country),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 4, end: 12, top: 8, bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Text('${group.count}', style: theme.textTheme.labelSmall),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
