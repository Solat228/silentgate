import 'package:flutter/material.dart';
import 'app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/text_direction.dart';
import '../../core/models/subscription_info.dart';
import '../../core/models/subscription_sync.dart';
import '../../core/util/country_flag.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../import_screen.dart';
import '../settings_screen.dart';
import 'flag_cell.dart';
import 'subscription_avatar.dart';
import '../../core/i18n/enum_labels.dart';

/// Карточка подписки сверху: название, трафик (использовано/всего), срок, поддержка.
/// Меню (кнопка ⋮ и ПКМ): обновить, копировать URL, поддержка, удалить.
class SubscriptionBar extends StatelessWidget {
  const SubscriptionBar({super.key});

  static String _gb(int? bytes, String gb) =>
      bytes == null ? '—' : '${(bytes / (1 << 30)).toStringAsFixed(1)} $gb';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final info = state.info;
    if (state.subscriptionUrl == null && info.title == null) {
      return const SizedBox.shrink();
    }

    final frac = info.usedFraction;
    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SubscriptionAvatar(path: state.logoPath, label: info.title, size: 22),
                const SizedBox(width: 8),
                // Имя/переключатель занимает всё свободное место — длинное название
                // больше не срезается кнопкой «Обновить» и треугольником.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: state.subscriptions.length > 1
                        ? _SubscriptionSwitcher(
                            title: info.title ?? l.subBarSubscription)
                        : Text(info.title ?? l.subBarSubscription,
                            // Название подписки — провайдерское: направление по
                            // содержимому (латиница не зеркалится, арабский — RTL).
                            textDirection: autoTextDirection(info.title),
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis),
                  ),
                ),
                // «Обновить» — компактной иконкой у самого края, рядом с ⋮.
                IconButton(
                  tooltip: state.refreshing
                      ? l.subBarRefreshing
                      : l.subBarRefreshSubscription,
                  visualDensity: VisualDensity.compact,
                  icon: state.refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  onPressed: state.subscriptionUrl == null || state.refreshing
                      ? null
                      : () => context.read<AppState>().refreshSubscription(),
                ),
                _MenuButton(offset: (pos) => _menu(context, pos)),
              ]),
              if (info.totalBytes != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: frac, minHeight: 6),
                ),
                const SizedBox(height: 4),
                Text(
                    l.subBarUsage(_gb(info.usedBytes, l.subBarGbUnit),
                        _gb(info.totalBytes, l.subBarGbUnit)),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 4),
              _ExpiryLine(info: info),
              // Объявление провайдера (announce) — как в Happ. Панель может
              // прислать очень длинный текст, поэтому ограничиваем высоту и даём
              // прокрутку внутри — иначе карточка растянулась бы на весь экран.
              if ((info.announce ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(info.announce!,
                          // Объявление провайдера — направление по содержимому.
                          textDirection: autoTextDirection(info.announce),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6)),
                  icon: const Icon(Icons.support_agent, size: 16),
                  label: Text(l.subBarSupport),
                  // Кнопка «Поддержка» ВЕЗДЕ ведёт в настройки → раздел поддержки,
                  // где объяснено, что будет сделано, и дана ссылка из конфига.
                  onPressed: () => _openSupport(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// «Поддержка» ведёт в настройки → раздел поддержки (везде одинаково).
  void _openSupport(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const SettingsScreen(scrollToSupport: true)));
  }

  Future<void> _menu(BuildContext context, Offset pos) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        _item('refresh', Icons.refresh, l.subBarRefresh),
        _item('add', Icons.add_link, l.subBarAddSubscription),
        _item('copy', Icons.copy, l.subBarCopyLink),
        _item('support', Icons.support_agent, l.subBarSupport),
        _item('delete', Icons.delete_outline, l.subBarDeleteSubscription),
      ],
    );
    switch (action) {
      case 'refresh':
        if (state.subscriptionUrl != null) state.refreshSubscription();
        break;
      case 'add':
        if (!context.mounted) return;
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ImportScreen()));
        break;
      case 'copy':
        if (state.subscriptionUrl != null) {
          await Clipboard.setData(ClipboardData(text: state.subscriptionUrl!));
          if (context.mounted) {
            AppToast.copied(context, message: l.subBarLinkCopied);
          }
        }
        break;
      case 'support':
        if (context.mounted) _openSupport(context);
        break;
      case 'delete':
        if (!context.mounted) return;
        await _confirmDelete(context, state);
        break;
    }
  }

  /// #5 — закреплённые серверы переживают подписку, поэтому спрашиваем про них явно:
  /// иначе после удаления список не пустеет и это выглядит как баг.
  Future<void> _confirmDelete(BuildContext context, AppState state) async {
    final l = AppLocalizations.of(context);
    var alsoPinned = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setState) => AlertDialog(
          title: Text(l.subBarDeleteConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.subBarDeleteConfirmBody),
              if (state.hasPinned)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alsoPinned,
                  onChanged: (v) => setState(() => alsoPinned = v ?? false),
                  title: Text(l.subBarDeletePinned(state.pinnedCount)),
                  subtitle: Text(l.subBarDeletePinnedHint),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: Text(l.subBarCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: Text(l.subBarDelete)),
          ],
        ),
      ),
    );
    if (ok == true) {
      await state.deleteSubscription(removePinned: alsoPinned);
      if (context.mounted) {
        AppToast.show(context, l.subBarSubscriptionDeleted,
            kind: ToastKind.success);
      }
    }
  }

  static PopupMenuItem<String> _item(String v, IconData icon, String text) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(text)]),
      );
}

class _MenuButton extends StatelessWidget {
  final void Function(Offset pos) offset;
  const _MenuButton({required this.offset});

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (ctx) {
      return IconButton(
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: () {
          final box = ctx.findRenderObject() as RenderBox?;
          final pos = box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero;
          offset(pos);
        },
      );
    });
  }
}

/// Сводка последнего обновления подписки (#1.1): сколько всего, что добавилось
/// и что удалилось — как в NekoBox. Списки имён раскрываются по клику.
class _SyncSummary extends StatefulWidget {
  final SubscriptionSyncResult result;
  const _SyncSummary({required this.result});

  @override
  State<_SyncSummary> createState() => _SyncSummaryState();
}

class _SyncSummaryState extends State<_SyncSummary> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = widget.result;
    final scheme = Theme.of(context).colorScheme;
    final color = r.hasChanges ? scheme.primary : scheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(r.hasChanges ? Icons.sync : Icons.check_circle_outline,
            size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(l.subBarSubscriptionUpdated(syncSummary(l, r)),
              style: TextStyle(fontSize: 14, color: color)),
        ),
        if (r.hasChanges)
          // Список показываем ПОВЕРХ интерфейса: раскрытие внутри карточки
          // раздвигало её и сдвигало кнопку Connect вниз.
          Builder(builder: (ctx) {
            return TextButton(
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact),
              onPressed: () => _showChanges(ctx, r),
              child: Text(l.subBarMore,
                  style: TextStyle(fontSize: 13, color: color)),
            );
          }),
        InkWell(
          onTap: () => context.read<AppState>().clearSyncResult(),
          child: Icon(Icons.close, size: 18, color: color),
        ),
      ]),
    );
  }

  /// Всплывающий список изменений — как контекстное меню, поверх содержимого.
  Future<void> _showChanges(BuildContext ctx, SubscriptionSyncResult r) async {
    final l = AppLocalizations.of(ctx);
    final box = ctx.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final scheme = Theme.of(ctx).colorScheme;

    await showMenu<void>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy + 24, 16, 0),
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.added.isNotEmpty) ...[
                    _header(ctx, l.subBarAdded(r.added.length), scheme.primary),
                    ...r.added.map((n) => _line(ctx, n, '+', scheme.primary)),
                  ],
                  if (r.removed.isNotEmpty) ...[
                    if (r.added.isNotEmpty) const SizedBox(height: 8),
                    _header(ctx, l.subBarRemoved(r.removed.length), scheme.error),
                    ...r.removed.map((n) => _line(ctx, n, '−', scheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext ctx, String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, color: color, fontWeight: FontWeight.bold)),
      );

  /// Строка с флагом страны — имя сервера без флаг-эмодзи (они не рендерятся на Windows).
  Widget _line(BuildContext ctx, String name, String sign, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(sign, style: TextStyle(fontSize: 14, color: color)),
          const SizedBox(width: 6),
          FlagCell(name, width: 22, height: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(FlagUtil.strip(name),
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                textDirection: TextDirection.ltr,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
}


/// Строка срока действия. Цветом выделяется ТОЛЬКО значение «действует до»
/// (не весь блок и не просто текст — плашкой): жёлтым, если истекает в течение
/// суток, красным — если уже истекла. Пока времени много — без выделения.
class _ExpiryLine extends StatelessWidget {
  final SubscriptionInfo info;
  const _ExpiryLine({required this.info});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final DateTime? exp = info.expiresAt;
    final int? auto = info.updateIntervalHours;
    final autoText = auto != null ? l.subBarAutoUpdate(auto) : '';

    if (exp == null) {
      return Text(l.subBarValidPerpetual(autoText), style: small);
    }
    final now = DateTime.now();
    final expired = !exp.isAfter(now);
    final soon = !expired && exp.difference(now) < const Duration(days: 1);
    final scheme = Theme.of(context).colorScheme;

    Color? bg, fg;
    if (expired) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else if (soon) {
      bg = const Color(0xFFFFC107).withValues(alpha: 0.28);
      fg = const Color(0xFF8A6D00);
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(expired ? l.subBarExpired : l.subBarValidUntil, style: small),
        // Выделяем ТОЛЬКО дату — отдельной плашкой.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: bg == null
              ? null
              : BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Text(
            SubscriptionBar._date(exp),
            style: small?.copyWith(
              color: fg,
              fontWeight: (expired || soon) ? FontWeight.w700 : null,
            ),
          ),
        ),
        if (autoText.isNotEmpty) Text(autoText, style: small),
      ],
    );
  }
}

/// Переключатель активной подписки (появляется, когда их больше одной). Оформлен
/// заметной «плашкой» с иконкой и счётчиком — раньше был просто текст со стрелкой.
class _SubscriptionSwitcher extends StatelessWidget {
  final String title;
  const _SubscriptionSwitcher({required this.title});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final box = context.findRenderObject() as RenderBox?;
        final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        final picked = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(pos.dx, pos.dy + 40, pos.dx, pos.dy),
          items: [
            for (final p in state.subscriptions)
              PopupMenuItem(
                value: p.id,
                child: Row(children: [
                  // Аватарка подписки — своя у каждой (логотип из кэша либо
                  // цветной кружок с буквой названия).
                  SubscriptionAvatar(
                      path: p.logoPath, label: p.title, size: 24),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('${p.title}  ·  ${p.serverLinks.length}',
                        // Доминирует название подписки — направление по нему.
                        textDirection: autoTextDirection(p.title),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    p.id == state.activeSubscriptionId
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 16,
                    color: p.id == state.activeSubscriptionId
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ]),
              ),
          ],
        );
        if (picked != null) await state.switchSubscription(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_horiz, size: 16, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(title,
                // Название подписки — направление по содержимому.
                textDirection: autoTextDirection(title),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${state.subscriptions.length}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer)),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: scheme.onPrimaryContainer),
        ]),
      ),
    );
  }
}
