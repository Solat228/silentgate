import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/text_direction.dart';
import '../../core/models/subscription_profile.dart';
import '../../core/models/vpn_server.dart';
import '../../core/probe/ping_result.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/probe_controller.dart';
import '../../state/settings_controller.dart';
import 'subscription_avatar.dart';

/// Счётчик подписки в меню: «всего · рабочих».
///
/// ⚠️ ЧТО ЗДЕСЬ СЧИТАЕТСЯ РАБОЧИМ. Только [PingVerification.passed] — сервер,
/// через который РЕАЛЬНО прошёл запрос. Достижимость по TCP ([PingOutcome.ok])
/// рабочим не делает: именно из-за подмены одного другим владелец видел
/// зелёные плашки на серверах, через которые не работало ничего (см. историю
/// `PingVerification`).
///
/// [working] равен null, пока проверки канала не было НИ У ОДНОГО сервера
/// подписки, — тогда показываем только общее число. Ноль здесь означал бы
/// «проверили и ни один не работает», а это разные вещи: до пинга мы просто
/// ничего не знаем.
class SubscriptionPingCount {
  final int total;
  final int? working;
  const SubscriptionPingCount(this.total, this.working);

  static SubscriptionPingCount of(
      List<VpnServer> servers, PingResult Function(VpnServer) resultFor) {
    var working = 0;
    var checked = false;
    for (final s in servers) {
      switch (resultFor(s).verification) {
        case PingVerification.passed:
          working++;
          checked = true;
        case PingVerification.failed:
          // Проверка была и провалилась — число рабочих уже осмысленно.
          checked = true;
        case PingVerification.pending:
        case PingVerification.notRun:
          break;
      }
    }
    return SubscriptionPingCount(servers.length, checked ? working : null);
  }
}

/// Переключатель подписок в карточке сверху: плашка с названием активной и
/// выпадающий список остальных.
///
/// ## Почему это не обычное меню на `PopupMenuItem`
///
/// В списке живут три разные вещи, и каждая требует своего:
///   • сами подписки — их можно ПЕРЕТАСКИВАТЬ, и меню при этом закрываться не
///     должно (иначе порядок пришлось бы менять по одному шагу за открытие);
///   • «Обновить подписку» и «Пинг серверов» — обычные действия, они меню
///     закрывают;
///   • выбор подписки — тоже закрывает.
///
/// Поэтому всё содержимое лежит в ОДНОМ пункте с `enabled: false` (он не
/// перехватывает нажатия и не закрывает меню сам), а закрытие делается руками
/// там, где оно нужно.
class SubscriptionSwitcher extends StatelessWidget {
  final String title;
  const SubscriptionSwitcher({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(context),
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

  Future<void> _open(BuildContext context) async {
    // Объекты состояния берём ДО открытия меню: внутри пункта контекст уже
    // принадлежит маршруту меню, и после его закрытия обращаться к нему нельзя.
    final state = context.read<AppState>();
    final probe = context.read<ProbeController>();
    final settings = context.read<SettingsController>();
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy + 40, pos.dx, pos.dy),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _SwitcherBody(
              state: state, probe: probe, settings: settings),
        ),
      ],
    );
  }
}

/// Содержимое выпадающего списка.
class _SwitcherBody extends StatefulWidget {
  final AppState state;
  final ProbeController probe;
  final SettingsController settings;
  const _SwitcherBody(
      {required this.state, required this.probe, required this.settings});

  @override
  State<_SwitcherBody> createState() => _SwitcherBodyState();
}

class _SwitcherBodyState extends State<_SwitcherBody> {
  /// Восстановленные серверы подписок, по id профиля.
  ///
  /// ⚠️ КЭШ ЗДЕСЬ ОБЯЗАТЕЛЕН. Серверы неактивных подписок существуют только как
  /// ссылки, и `serversOfSubscription` разбирает их заново на каждый вызов. А
  /// это меню перестраивается на КАЖДОЕ уведомление `ProbeController` — во
  /// время прогона их сотни, и без кэша мы бы разбирали 124 ссылки сотни раз
  /// подряд ради двух цифр. Кэш живёт ровно столько, сколько открыто меню;
  /// число рабочих при этом обновляется каждый раз — оно считается по свежим
  /// результатам пинга, а не берётся из кэша.
  final Map<String, List<VpnServer>> _serversByProfile = {};

  List<VpnServer> _serversOf(SubscriptionProfile p) => _serversByProfile
      .putIfAbsent(p.id, () => widget.state.serversOfSubscription(p.id));

  @override
  void initState() {
    super.initState();
    // Меню живёт в своём маршруте и на notifyListeners не перестраивается —
    // подписываемся сами, иначе после перетаскивания список остался бы старым.
    widget.state.addListener(_onChanged);
    widget.probe.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChanged);
    widget.probe.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = widget.state.subscriptions;
    final activeId = widget.state.activeSubscriptionId;
    // Есть ли вообще что пинговать. Считаем по тому же кэшу, что и счётчики:
    // спрашивать `allSubscriptionServers()` на каждый build значило бы
    // разбирать все ссылки заново ради одного «пусто/не пусто».
    final anyServers = widget.state.servers.isNotEmpty ||
        items.any((p) => _serversOf(p).isNotEmpty);

    return SizedBox(
      // ⚠️ ТОЧНАЯ ШИРИНА, А НЕ `ConstrainedBox(minWidth/maxWidth)`.
      //
      // `showMenu` оборачивает содержимое в `IntrinsicWidth`, а тот спрашивает
      // у потомков внутренние размеры. `ReorderableListView` внутри —
      // прокручиваемая область, и на такой вопрос она БРОСАЕТ
      // («RenderShrinkWrappingViewport does not support returning intrinsic
      // dimensions»). Диапазонные ограничения не спасают: короткое замыкание в
      // `RenderConstrainedBox` срабатывает только на ТУГОЙ ширине. Итог —
      // 31 исключение и красный экран при каждом открытии меню в debug; в
      // release-сборке проверки вырезаны, поэтому на APK и exe этого не видно
      // вовсе, и дефект дожил бы до чужого запуска `flutter run`.
      //
      // 280 — штатный потолок ширины меню (`_kMenuMaxWidth`), просить больше
      // всё равно бессмысленно.
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⚠️ Высота ОГРАНИЧЕНА и список прокручивается: подписок может быть
          // сколько угодно, а меню не должно уезжать за край экрана.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              onReorder: widget.state.reorderSubscriptions,
              itemBuilder: (context, i) {
                final p = items[i];
                final active = p.id == activeId;
                return InkWell(
                  // Ключ обязателен и обязан быть привязан к САМОЙ подписке:
                  // по ключу по позиции перетаскивание меняло бы содержимое
                  // строк, а не их порядок.
                  key: ValueKey(p.id),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (!active) widget.state.switchSubscription(p.id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(children: [
                      // Аватарка подписки — своя у каждой (логотип из кэша либо
                      // цветной кружок с буквой названия).
                      SubscriptionAvatar(
                          path: p.logoPath, label: p.title, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(p.title,
                            // Доминирует название подписки — направление по нему.
                            textDirection: autoTextDirection(p.title),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      // ⚠️ Считаем ВОССТАНОВЛЕННЫЕ серверы, а не длину
                      // `p.serverLinks` (так было раньше). Ссылка, которую
                      // парсер не понимает, в список не попадает и
                      // пропингована не будет — общее число обязано совпадать
                      // с тем, что реально уйдёт на прогон.
                      _CountBadge(
                        key: ValueKey('subCount_${p.id}'),
                        count: SubscriptionPingCount.of(
                            _serversOf(p), widget.probe.resultFor),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        active ? Icons.check_circle : Icons.circle_outlined,
                        size: 16,
                        color: active ? scheme.primary : scheme.outlineVariant,
                      ),
                      // Ручка перетаскивания. Явная, а не «тащи за строку»:
                      // строка уже занята выбором подписки, и без ручки одно
                      // действие мешало бы другому.
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.drag_handle,
                              size: 18, color: scheme.outline),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // ── Действия ──────────────────────────────────────────────────
          // Обновление — над АКТИВНОЙ подпиской (её и показывает карточка),
          // пинг — над ВСЕМИ сразу. Разные области действия у соседних строк:
          // подписи обязаны это называть, иначе человек прочтёт обе как
          // «то же самое, но другой кнопкой».
          _ActionRow(
            icon: Icons.refresh,
            label: widget.state.refreshing
                ? l.subBarRefreshing
                : l.subBarRefreshSubscription,
            busy: widget.state.refreshing,
            onTap: widget.state.subscriptionUrl == null || widget.state.refreshing
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.state.refreshSubscription();
                  },
          ),
          _ActionRow(
            icon: Icons.network_check,
            label: l.subSwitcherPingAll,
            busy: widget.probe.running,
            // ⚠️ ЗДЕСЬ ПИНГУЮТСЯ ВСЕ ПОДПИСКИ, А НЕ ТЕКУЩАЯ — решение владельца
            // (13.08.2026): «пункт меню — все подписки». Раньше пункт гонял
            // `state.servers`, то есть ровно то же, что кнопка на главном
            // экране; отличить их было нельзя, и второй пункт не имел смысла.
            // Кнопка на главном осталась прежней — тоже по решению владельца.
            //
            // Список собирает `AppState`: серверы неактивных подписок лежат
            // ссылками, и восстановить их умеет только он.
            onTap: widget.probe.running || !anyServers
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.probe.pingAll(widget.state.allSubscriptionServers(),
                        widget.settings.settings);
                  },
          ),
        ],
      ),
    );
  }
}

/// Цифры у подписки: «всего · рабочих» с пояснением по наведению.
///
/// Пояснение — прямая просьба владельца: «сделай возможность навести на цифру
/// и увидеть пояснение». Без него две цифры подряд читаются как что угодно —
/// от «из скольких выбрано» до номера подписки.
class _CountBadge extends StatelessWidget {
  final SubscriptionPingCount count;
  const _CountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final working = count.working;
    return Tooltip(
      message: working == null
          ? l.subSwitcherCountTotal(count.total)
          : l.subSwitcherCountWorking(count.total, working),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${count.total}',
            // Цифры — всегда слева направо, даже в арабской локали: это
            // технические числа, а не текст (та же политика, что у адресов).
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 12, color: scheme.outline)),
        if (working != null) ...[
          Text('  ·  ',
              style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
          Text('$working',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  // Рабочие выделены цветом состояния, а не просто жирным:
                  // в строке шириной 280 px две серые цифры сливаются в одну.
                  color: working > 0 ? Colors.green : scheme.error)),
        ],
      ]),
    );
  }
}

/// Строка-действие внизу списка: значок (или кружок ожидания) и подпись.
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionRow(
      {required this.icon,
      required this.label,
      required this.busy,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? Theme.of(context).disabledColor
        : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: color))),
        ]),
      ),
    );
  }
}
