import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/text_direction.dart';
import '../../core/models/subscription_info.dart';
import '../../core/models/subscription_sync.dart';
import '../../core/util/country_flag.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'flag_cell.dart';
import 'flag_text.dart';
import 'subscription_avatar.dart';
import 'subscription_switcher.dart';
import '../../core/i18n/enum_labels.dart';

/// Карточка подписки сверху: название, трафик (использовано/всего), срок, поддержка.
/// Меню (кнопка ⋮ и ПКМ): обновить, копировать URL, поддержка, удалить.
///
/// ⚠️ ДВА ВИДА — ПОЛНЫЙ И КОМПАКТНЫЙ, и это не украшение. Разбор вёрстки
/// 10.09.2026: на минимальном окне 980×800 (клиент 964×761) карточка с
/// объявлением от панели съедала до 200 px, и при длинном тексте низ главного
/// экрана прятался за край. На низком окне ([isCompactFor]) остаются
/// аватарка, имя, шкала и одна строка «N ГБ из M · срок»; ссылки
/// «Поддержка / Сайт» уезжают под «⋮». Замер — `test/subscription_bar_compact_test.dart`.
///
/// ⚠️ ОБЪЯВЛЕНИЕ ОТ СЕРВИСА КОМПАКТНОСТЬ НЕ ПРЯЧЕТ. В 1.13.1 оно тоже уезжало
/// под «⋮» с меткой «непрочитанное» — и 17.09.2026 владелец открыл телефон:
/// «ты съел объявление от панели». На телефоне окно ниже порога ВСЕГДА, то
/// есть компактный вид там — не исключение, а правило, и слово панели человек
/// не видел вовсе; метка на «⋮» этого не спасала — её никто не трогает.
/// Решение владельца: объявление видно по умолчанию на любой высоте (блок
/// ограничен по высоте и крутится внутри), спрятать его можно настройкой
/// [AppSettings.hidePanelAnnounce], заголовок — «Объявления от сервиса <имя>».
class SubscriptionBar extends StatelessWidget {
  /// Принудительный вид: `true` — компактный, `false` — полный, `null` —
  /// по высоте окна ([isCompactFor]). Явное значение нужно стражам вёрстки
  /// (замер «до/после» на одном и том же окне) и тому, кто знает про место
  /// больше карточки — например панели, которая уже посчитала свою высоту.
  final bool? compact;

  const SubscriptionBar({super.key, this.compact});

  /// Ниже этой высоты окна (за вычетом клавиатуры) карточка сворачивается.
  ///
  /// ⚠️ ЧИСЛО НЕ ПРИДУМАНО. Минимальное окно Windows — 980×800, клиентская
  /// область 964×761: там низ экрана прячется, и это ОБЯЗАНО быть «низко».
  /// Компактная карточка выигрывает на этом окне ~130 px на реальном шрифте
  /// (в тесте, где шрифт Ahem шире, — 170: полная 306, компактная 136).
  /// Окну на столько же выше полная карточка мешает не больше, чем компактная
  /// минимальному: 761 + 130 ≈ 890, округлено до 900. `context.sg.isShort`
  /// (< 600) для этого не годится: он про телефон с клавиатурой, не про окно 800.
  static const double compactBelowHeight = 900;

  /// Заголовок блока объявления: «Объявления от сервиса <имя>», а без имени —
  /// просто «Объявления от сервиса». Имя — то же, что у подписи «Написать в
  /// поддержку (<имя>)» в настройках: `info.title` подписки.
  ///
  /// ⚠️ Механизма «прочитано» (набор открытых текстов + метка на «⋮») больше
  /// нет — ему нечего значить: объявление либо на виду всегда, либо спрятано
  /// настройкой навсегда, а метка «внутри непрочитанное» на кнопке, которую
  /// не нажимают, и была причиной, по которой объявление «съедалось».
  static String announceTitle(AppLocalizations l, String? serviceName) {
    final name = (serviceName ?? '').trim();
    return name.isEmpty
        ? l.subBarAnnounceFromUnnamed
        : l.subBarAnnounceFrom(name);
  }

  /// Мало ли окну по высоте для полной карточки.
  static bool isCompactFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    // Высоту считаем ЗА ВЫЧЕТОМ клавиатуры — на телефоне она забирает ~280 dp.
    return (size.height - insets.bottom) < compactBelowHeight;
  }

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
    final isCompact = compact ?? isCompactFor(context);
    // ⚠️ ГЕЙТ ОБЪЯВЛЕНИЯ — НАСТРОЙКА, А НЕ ВЫСОТА ОКНА. Контроллер спрашиваем
    // как необязательный: карточка живёт и в стражах, где его нет, — тогда
    // действует умолчание «показывать».
    final hideAnnounce =
        context.watch<SettingsController?>()?.settings.hidePanelAnnounce ??
            false;
    final announce = !hideAnnounce && (info.announce ?? '').isNotEmpty
        ? info.announce
        : null;

    final frac = info.usedFraction;
    final hasBar = info.usedBytes != null && !info.unlimitedTraffic;
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
                SubscriptionAvatar(
                    path: state.logoPath, label: info.title, size: 22),
                const SizedBox(width: 8),
                // Имя/переключатель занимает всё свободное место — длинное название
                // больше не срезается кнопкой «Обновить» и треугольником.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: state.subscriptions.length > 1
                        ? SubscriptionSwitcher(
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
              // Шкала рисуется ТОЛЬКО когда есть реальный лимит. При безлимите
              // доля неизвестна, а LinearProgressIndicator с value == null
              // крутит бесконечную полосу — она выглядит как вечно идущее
              // обновление подписки. Показываем просто израсходованное.
              if (hasBar) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: frac, minHeight: 6),
                ),
              ],
              // Компактно: «N ГБ из M · Действует до: дата» ОДНОЙ строкой —
              // вторая строка стоила бы ~20 px, ради которых всё и затевалось.
              // Полный вид: трафик своей строкой, срок — своей, отступы
              // прежние (регресс на высоком окне стережёт тест).
              if (isCompact) ...[
                const SizedBox(height: 4),
                _ExpiryLine(info: info, leading: _usageText(l, info)),
              ] else ...[
                if (_usageText(l, info) case final usage?) ...[
                  SizedBox(height: hasBar ? 4 : 8),
                  Text(usage, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 4),
                _ExpiryLine(info: info),
              ],
              // Объявление сервиса (announce) — как в Happ. Панель может
              // прислать очень длинный текст, поэтому ограничиваем высоту и даём
              // прокрутку внутри — иначе карточка растянулась бы на весь экран.
              //
              // ⚠️ НЕ ЗАВИСИТ ОТ `isCompact` — и это не забывчивость (см.
              // шапку класса): компактность на телефоне — постоянное
              // состояние, и гейт по высоте прятал бы объявление там навсегда.
              // Единственный гейт — настройка, она уже учтена в `announce`.
              if (announce != null)
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Заголовок с именем сервиса — вне прокрутки, чтобы
                        // не уезжал вместе с текстом.
                        Text(announceTitle(l, info.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        // `Flexible`, а не `Expanded`: при коротком тексте
                        // блок берёт по содержимому, при длинном — остаток
                        // до maxHeight и крутится.
                        Flexible(
                          child: SingleChildScrollView(
                            // Флаг-эмодзи от панели картинкой: Windows их
                            // не рисует, вместо 🇸🇬 выходят буквы «SG».
                            child: SelectableText.rich(
                                TextSpan(
                                    children: buildFlagSpans(announce,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)),
                                // Объявление сервиса — направление по
                                // содержимому.
                                textDirection: autoTextDirection(announce),
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Кнопки-ссылки в компактном виде — пунктами меню «⋮» (они там
              // и так есть: `SubscriptionActions.menuItems`).
              if (!isCompact)
                Align(
                  alignment: Alignment.centerLeft,
                  // ⚠️ `Wrap`, А НЕ `Row`. Кнопок стало две, а подписи у нас на
                  // десяти языках и различаются в разы по длине: в узком окне
                  // `Row` дал бы «RenderFlex overflowed» (жёлто-чёрная полоса в
                  // отладке, обрезанная подпись в релизе). `Wrap` переносит
                  // вторую кнопку на следующую строку.
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6)),
                        icon: const Icon(Icons.support_agent, size: 16),
                        label: Text(l.subBarSupport),
                        // Кнопка «Поддержка» ВЕЗДЕ ведёт в настройки → раздел
                        // поддержки, где объяснено, что будет сделано, и дана
                        // ссылка из конфига.
                        onPressed: () =>
                            SubscriptionActions.openSupport(context),
                      ),
                      // ⚠️ КНОПКИ НЕТ, ЕСЛИ НЕТ ССЫЛКИ. Сервер, добавленный
                      // руками (share-ссылка или свой JSON), подписки за собой не
                      // имеет — открывать нечего, а кнопка, ведущая в никуда,
                      // хуже отсутствующей.
                      if ((state.subscriptionUrl ?? '').isNotEmpty)
                        Tooltip(
                          // ⚠️ В ПОДСКАЗКЕ АДРЕСА НЕТ: в нём токен доступа, а
                          // карточку отправляют скриншотом в поддержку. Кнопка
                          // просто открывает ту самую страницу, по которой
                          // подписка и импортирована.
                          message: l.subBarOpenSiteHint,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6)),
                            icon: const Icon(Icons.public, size: 16),
                            label: Text(l.subBarOpenSite),
                            onPressed: () => SubscriptionActions.run(
                                context, SubscriptionActions.site),
                          ),
                        ),
                    ],
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

  /// Меню карточки (кнопка ⋮ и ПКМ по карточке) — про АКТИВНУЮ подписку.
  ///
  /// ⚠️ Пункты и их исполнение общие с ПКМ-меню строки переключателя
  /// ([SubscriptionActions]): одинаковые на вид действия обязаны и работать
  /// одинаково. `profile` здесь не передаётся — это и означает «активная».
  ///
  /// ⚠️ «Добавить подписку» ЗДЕСЬ НЕТ — убрано по просьбе владельца как лишний
  /// пункт. Добавление никуда не делось: кнопка «Импорт» стоит в шапке главного
  /// экрана (`home_screen`, `l.homeImport`) и видна всегда, а на пустом
  /// состоянии экран импорта открывается сам. Меню карточки — про ЭТУ подписку,
  /// и заведение новой в нём чужое.
  ///
  /// ⚠️ Пункта «Объявление» здесь НЕТ (был в 1.13.1 для компактного вида):
  /// объявление теперь в карточке на любой высоте, а при настройке «скрыть»
  /// его не должно быть и в меню — человек попросил не видеть.
  Future<void> _menu(BuildContext context, Offset pos) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: SubscriptionActions.menuItems(l,
          hasUrl: (state.subscriptionUrl ?? '').isNotEmpty),
    );
    if (action == null || !context.mounted) return;
    await SubscriptionActions.run(context, action);
  }

  /// Строка трафика: «N из M» при лимите, «Израсходовано N · без ограничений»
  /// при безлимите, `null` — данных о трафике нет вовсе.
  static String? _usageText(AppLocalizations l, SubscriptionInfo info) {
    if (info.usedBytes == null) return null;
    if (!info.unlimitedTraffic) {
      return l.subBarUsage(_gb(info.usedBytes, l.subBarGbUnit),
          _gb(info.totalBytes, l.subBarGbUnit));
    }
    return '${l.subBarUsedOnly(_gb(info.usedBytes, l.subBarGbUnit))}'
        ' · ${l.subBarUnlimitedTraffic}';
  }
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
          final pos =
              box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero;
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
                    _header(
                        ctx, l.subBarRemoved(r.removed.length), scheme.error),
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
  Widget _line(BuildContext ctx, String name, String sign, Color color) =>
      Padding(
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

  /// Текст ПЕРЕД сроком в той же строке (компактный вид: трафик · срок).
  /// `null` — строка начинается со срока, как в полном виде.
  final String? leading;

  const _ExpiryLine({required this.info, this.leading});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final DateTime? exp = info.expiresAt;
    final int? auto = info.updateIntervalHours;
    final autoText = auto != null ? l.subBarAutoUpdate(auto) : '';

    final lead = leading == null
        ? const <Widget>[]
        : <Widget>[Text('$leading ·', style: small)];

    if (exp == null) {
      final perpetual = Text(l.subBarValidPerpetual(autoText), style: small);
      if (lead.isEmpty) return perpetual;
      return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [...lead, perpetual]);
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
        ...lead,
        Text(expired ? l.subBarExpired : l.subBarValidUntil, style: small),
        // Выделяем ТОЛЬКО дату — отдельной плашкой.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: bg == null
              ? null
              : BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(10)),
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
