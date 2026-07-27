import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_server.dart';
import '../../core/util/country_flag.dart';
import '../../core/i18n/enum_labels.dart';
import '../../core/i18n/text_direction.dart';
import '../../core/xray/panel_routing_summary.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/auto_config_controller.dart';
import '../../state/probe_controller.dart';
import '../../state/settings_controller.dart';
import '../auto_config_screen.dart';
import '../server_editor_dialog.dart';
import 'app_toast.dart';
import '../server_info_screen.dart';
import '../server_json_dialog.dart';
import 'flag_cell.dart';
import 'info_tooltip.dart';
import 'ping_chip.dart';

/// Краткая сводка туннелирования панельного профиля для «!»-подсказки (#3.2).
String _panelSummary(AppLocalizations l, PanelRoutingInfo p) {
  final lines = <String>[l.panelInfoServers(p.serverCount)];
  if (p.routesSomeDirect) lines.add(l.panelInfoDirect);
  if (p.routesSomeBlock) lines.add(l.panelInfoBlock);
  return lines.join('\n');
}

/// Единая строка сервера: флаг-ячейка · имя + теги конфига · пинг · шеврон, с контекст-меню (ПКМ).
class ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;
  final VoidCallback onTap;
  const ServerTile({
    super.key,
    required this.server,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final probe = context.watch<ProbeController>();
    final state = context.watch<AppState>();
    // Служебный «сервер»-уведомление от панели (истёкшая подписка): не пингуем,
    // не подключаемся — показываем сообщение и кнопку «Обновить».
    if (server.isNotice) return _noticeTile(context, state);
    final l = AppLocalizations.of(context);
    final name = FlagUtil.strip(server.remark);
    final pinned = state.isPinned(server);
    final scheme = Theme.of(context).colorScheme;
    // #3.2 — у сервера с автовыбором/панельного профиля своя маршрутизация:
    // помечаем и даём «!» с краткой сводкой (разбор внутреннего конфига).
    final panelInfo = server.isPanelProfile
        ? analyzePanelRouting(server.rawPanelConfig ?? '')
        : null;

    // Правой кнопки на тач-экране нет, а меню — единственный вход к пяти из
    // семи действий (инфо, пинг, пин, JSON, удаление). Поэтому там долгое
    // нажатие и видимая кнопка ⫶ вместо шеврона.
    final touch = _isTouchLayout(context);

    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      onLongPressStart:
          touch ? (d) => _menu(context, d.globalPosition) : null,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.08),
        leading: FlagCell(server.remark, auto: server.isPanelProfile),
        title: Row(children: [
          if (pinned)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 4),
              child: Icon(Icons.push_pin, size: 13),
            ),
          Flexible(
            child: Text(name.isEmpty ? server.address : name,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr),
          ),
          if (panelInfo != null)
            InfoTooltip(_panelSummary(l, panelInfo), title: l.panelTunnelMarker),
        ]),
        subtitle: Text(
            panelInfo != null
                ? l.panelTunnelMarker
                : configTagLabels(l, server.configTags).join(' / '),
            style: Theme.of(context).textTheme.bodySmall,
            textDirection: panelInfo != null ? null : TextDirection.ltr),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PingChip(result: probe.resultFor(server)),
            // На десктопе шеврон ведёт в редактор, а меню — по правой кнопке.
            // На тач-экране правой кнопки нет, поэтому здесь ⫶: без неё
            // большинство действий над сервером были бы недостижимы.
            touch
                ? Builder(
                    builder: (btnContext) => IconButton(
                      tooltip: l.srvTileMenu,
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        final box = btnContext.findRenderObject() as RenderBox?;
                        final pos = box == null
                            ? Offset.zero
                            : box.localToGlobal(box.size.center(Offset.zero));
                        _menu(context, pos);
                      },
                    ),
                  )
                : IconButton(
                    tooltip: l.srvTileEdit,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _edit(context),
                  ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  /// Строка-уведомление панели: сообщение + «Скопировать» и (для «После оплаты
  /// нажмите…») кнопка «Обновить», которая перезапрашивает подписку — как раз то,
  /// что нужно нажать после оплаты, чтобы появились настоящие серверы.
  Widget _noticeTile(BuildContext context, AppState state) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = FlagUtil.strip(server.remark).trim();
    final low = text.toLowerCase();
    final actionable = low.contains('нажмите') ||
        low.contains('обнов') ||
        server.remark.contains('🔄') ||
        server.remark.contains('🔗');
    return ListTile(
      dense: true,
      leading: Icon(Icons.campaign_outlined, color: scheme.tertiary),
      title: Text(text.isEmpty ? l.srvTileNotice : text,
          // Notice-сообщение провайдера — направление по содержимому
          // (пустое → локализованный фолбэк, наследует локаль).
          textDirection: text.isEmpty ? null : autoTextDirection(text),
          style: TextStyle(color: scheme.onSurface)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        // «Обновить» — раньше «Скопировать» (после оплаты жмут именно её).
        if (actionable)
          FilledButton.tonalIcon(
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.srvTileRefresh),
            onPressed: () async {
              await state.refreshSubscription();
              if (context.mounted) {
                AppToast.show(context, l.srvTileSubscriptionUpdated,
                    kind: ToastKind.success);
              }
            },
          ),
        IconButton(
          tooltip: l.srvTileCopy,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            AppToast.copied(context);
          },
        ),
      ]),
    );
  }

  Future<void> _menu(BuildContext context, Offset pos) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final probe = context.read<ProbeController>();
    final autoCfg = context.read<AutoConfigController>();
    final settings = context.read<SettingsController>().settings;
    final navigator = Navigator.of(context);
    final pinned = state.isPinned(server);

    PopupMenuItem<String> item(String value, IconData icon, String text) =>
        PopupMenuItem(
          value: value,
          child: Row(children: [
            Icon(icon, size: 18),
            const SizedBox(width: 12),
            Text(text),
          ]),
        );

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        item('info', Icons.info_outline, l.srvTileInfo),
        item('ping', Icons.network_check, l.srvTilePing),
        item('pin', pinned ? Icons.push_pin_outlined : Icons.push_pin,
            pinned ? l.srvTileUnpin : l.srvTilePin),
        item('json', Icons.data_object, l.srvTileJsonConfig),
        item('smart', Icons.auto_fix_high, l.srvTileSmart),
        item('edit', Icons.edit, l.srvTileEdit),
        item('delete', Icons.delete_outline, l.srvTileDelete),
      ],
    );

    switch (action) {
      case 'info':
        navigator.push(MaterialPageRoute(
            builder: (_) => ServerInfoScreen(server: server)));
        break;
      case 'ping':
        if (!probe.running) probe.pingOne(server, settings);
        break;
      case 'pin':
        await state.togglePin(server);
        break;
      case 'json':
        if (context.mounted) await _json(context);
        break;
      case 'smart':
        autoCfg.startForKey(server.rawLink, settings);
        navigator.push(MaterialPageRoute(builder: (_) => const AutoConfigScreen()));
        break;
      case 'edit':
        await _edit(context);
        break;
      case 'delete':
        await state.removeServer(server);
        if (context.mounted) {
          AppToast.show(context, l.srvTileServerDeleted, kind: ToastKind.success);
        }
        break;
    }
  }

  Future<void> _edit(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final edited = await showDialog<VpnServer>(
      context: context,
      builder: (_) => ServerEditorDialog(server: server),
    );
    if (edited != null) {
      await state.saveEditedServer(server, edited);
      if (context.mounted) {
        AppToast.show(context, l.srvTileSaved, kind: ToastKind.success);
      }
    }
  }

  Future<void> _json(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ServerJsonDialog(server: server),
    );
    // «Редактор полей» из JSON-диалога → открыть редактор.
    if (result == 'edit' && context.mounted) await _edit(context);
  }
}

/// Тач-раскладка: правой кнопки мыши нет, значит контекст-меню обязано иметь
/// видимую точку входа.
///
/// Мобильные платформы определяем прямо: правая кнопка там недоступна в
/// принципе. Подключённая к телефону мышь роли не играет — рассчитывать на неё
/// в основном сценарии нельзя, а лишняя кнопка ⫶ ничего не ломает.
bool _isTouchLayout(BuildContext context) => Platform.isAndroid || Platform.isIOS;
