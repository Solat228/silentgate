import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_server.dart';
import '../../core/probe/ping_result.dart';
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
import 'selection_outline.dart';
import 'subscription_avatar.dart';

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
    // Подписка, из которой пришёл сервер, если сейчас выбрана другая. Свои
    // серверы значком не помечаются — иначе он был бы у каждой строки и
    // перестал бы что-либо значить.
    final foreign = state.foreignSubscriptionOf(server);
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

    final tile = GestureDetector(
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      onLongPressStart:
          touch ? (d) => _menu(context, d.globalPosition) : null,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        // Кнопка правки/меню уезжает ВПЛОТНУЮ к краю строки — просьба владельца
        // («можно увести гораздо правее»). Штатные 16 dp справа отодвигали её от
        // края почти на ширину самой иконки.
        contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 2),
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.08),
        leading: FlagCell(server.remark, auto: server.isPanelProfile),
        title: Row(children: [
          if (pinned)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 4),
              child: Icon(Icons.push_pin, size: 13),
            ),
          // Мини-профиль чужой подписки. Пины общие и переживают переключение,
          // поэтому в одном списке оказываются серверы из разных подписок —
          // без значка они выглядят одинаково, и человек не понимает, куда
          // подключается.
          if (foreign != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 5),
              child: Tooltip(
                message: foreign.safeTitle,
                child: SubscriptionAvatar(
                    path: foreign.logoPath, label: foreign.safeTitle, size: 15),
              ),
            ),
          Flexible(
            child: Text(name.isEmpty ? server.address : name,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr),
          ),
          if (panelInfo != null)
            InfoTooltip(_panelSummary(l, panelInfo), title: l.panelTunnelMarker),
        ]),
        // Имя чужой подписки — текстом, а не только подсказкой к значку: на
        // тач-экране подсказка вызывается долгим нажатием, а оно уже занято
        // контекстным меню, и имя оказалось бы недостижимо.
        subtitle: Text(
            [
              // ⚠️ ИМЕННО `safeTitle`, А НЕ `title`. Запасное имя профиля — это
              // кусок URL подписки, а последний его сегмент у Remnawave и есть
              // СЕКРЕТ. В меню переключателя это ещё полбеды, а здесь оно
              // попало бы на главный экран, который люди шлют в поддержку
              // скриншотом.
              if (foreign != null) foreign.safeTitle,
              panelInfo != null
                  ? l.panelTunnelMarker
                  : configTagLabels(l, server.configTags).join(' / '),
            ].where((s) => s.isNotEmpty).join('  ·  '),
            style: Theme.of(context).textTheme.bodySmall,
            // Одна строка с многоточием: имя подписки панель отдаёт произвольной
            // длины, и без ограничения строка раздувалась бы на пол-экрана,
            // ломая ровный список.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection:
                (panelInfo != null || foreign != null) ? null : TextDirection.ltr),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PingSpeedColumn(
              ping: probe.resultFor(server),
              speed: probe.speedFor(server),
            ),
            // На десктопе шеврон ведёт в редактор, а меню — по правой кнопке.
            // На тач-экране правой кнопки нет, поэтому здесь ⫶: без неё
            // большинство действий над сервером были бы недостижимы.
            //
            // Кнопка ужата (`compact` + нулевой padding): рядом с ней теперь
            // стоит столбик из двух плашек, и штатные 48 dp иконки съедали
            // ширину у имени сервера.
            touch
                ? Builder(
                    builder: (btnContext) => IconButton(
                      tooltip: l.srvTileMenu,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
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
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _edit(context),
                  ),
          ],
        ),
        onTap: onTap,
      ),
    );

    // Обводка выбранного сервера — просьба владельца: «сделай такую же обводку
    // для выбранного сервера», как у раздела настроек. Заливка строки (8 %
    // primary) выделяет слабо: на светлой теме её почти не видно, и после
    // перезапуска непонятно, какой сервер запомнился.
    //
    // ⚠️ Обёртка НЕ меняет высоту строки: линия рисуется поверх той же коробки
    // с отступом внутрь. Высота здесь — не косметика, по ней считается
    // прокрутка к выбранному серверу в home_screen.
    return SelectionOutline(selected: selected, inset: 2, child: tile);
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
        item('speed', Icons.speed, l.srvTileMeasureSpeed),
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
      case 'speed':
        // ⚠️ Гейт по проверке канала — решение владельца: сервер, через который
        // не прошёл GET, скорость мерить не нужно. Молча ничего не делать здесь
        // нельзя: человек нажал пункт меню и обязан узнать, почему пусто.
        if (probe.running || probe.speedRunning) break;
        if (!probe.resultFor(server).speedMeasurable) {
          if (context.mounted) {
            AppToast.show(context, l.speedNotVerified, kind: ToastKind.warning);
          }
          break;
        }
        probe.measureSpeedOne(server, settings);
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

/// Пинг и скорость — столбиком у края строки (решение владельца).
///
/// Раскладка ровно та, что он описал:
///   • есть скорость — пинг ПРИЖАТ К ВЕРХУ, скорость к низу, между ними пусто;
///   • нет скорости — пинг ОДИН и встаёт по центру строки;
///   • сервер не прошёл проверку канала — на месте скорости прочерк.
///
/// ⚠️ ВЫСОТА СТОЛБИКА ЗАДАНА ЧИСЛОМ, И ЭТО ГЛАВНОЕ ЗДЕСЬ. `ListTile`
/// (dense + `VisualDensity(vertical: -2)`) отводит `trailing` ровно **40 dp** и
/// строку под него НЕ растягивает. Столбик из двух прежних плашек занимал
/// 52 dp, вылезал за пределы строки на 11 px и рисовался поверх соседних —
/// владелец описал это как «из-за скорости всё поплыло». Отладочная сборка при
/// этом ещё и ругалась `RenderFlex overflowed`. [PingChip.columnHeight] = 38 dp
/// влезает с запасом, а поскольку оно фиксировано, появление и пропажа замера
/// скорости строку не двигают вовсе.
///
/// ⚠️ Строка живёт и на телефоне. Ширину столбика НЕ ограничиваем жёстко:
/// `ConstrainedBox` не режет содержимое, а роняет отладочную сборку по
/// переполнению, стоит плашке «123.4 Мбит/с» не влезть в потолок. Место для
/// имени сервера отдаёт `ListTile` (`trailing` берёт свою ширину, остаток —
/// заголовку), а заголовок у нас `Flexible` с многоточием, поэтому лишний
/// десяток пикселей здесь ничего не ломает.
class PingSpeedColumn extends StatelessWidget {
  final PingResult ping;
  final ServerSpeed? speed;
  const PingSpeedColumn({super.key, required this.ping, required this.speed});

  @override
  Widget build(BuildContext context) {
    final chip = PingChip(result: ping);
    if (!SpeedChip.visible(speed: speed, ping: ping)) return chip;
    return SizedBox(
      height: PingChip.columnHeight,
      child: Column(
        // Пинг сверху, скорость снизу, просвет — сам собой между ними.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          chip,
          SpeedChip(speed: speed, ping: ping),
        ],
      ),
    );
  }
}

/// Тач-раскладка: правой кнопки мыши нет, значит контекст-меню обязано иметь
/// видимую точку входа.
///
/// Мобильные платформы определяем прямо: правая кнопка там недоступна в
/// принципе. Подключённая к телефону мышь роли не играет — рассчитывать на неё
/// в основном сценарии нельзя, а лишняя кнопка ⫶ ничего не ломает.
bool _isTouchLayout(BuildContext context) => Platform.isAndroid || Platform.isIOS;
