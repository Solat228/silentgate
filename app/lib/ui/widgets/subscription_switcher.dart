import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/text_direction.dart';
import '../../core/models/subscription_profile.dart';
import '../../core/models/vpn_server.dart';
import '../../core/platform/app_launcher.dart';
import '../../core/probe/ping_result.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/probe_controller.dart';
import '../../state/settings_controller.dart';
import '../settings_screen.dart';
import 'app_toast.dart';
import 'ping_gate.dart';
import 'subscription_avatar.dart';

/// Действия над ОДНОЙ подпиской: обновить, копировать ссылку, открыть её
/// страницу, поддержка, удалить.
///
/// ⚠️ ОБЩИЙ КОД ДЛЯ ДВУХ МЕНЮ, И ЭТО НЕ УКРАШЕНИЕ. Одни и те же действия
/// вызываются из карточки (кнопка ⋮ и ПКМ по карточке) и из строки
/// переключателя (ПКМ/долгое нажатие). Разойдись они — правка сервера или
/// адресность удаления чинилась бы в одном месте и оставалась сломанной в
/// другом, а внешне пункты выглядят одинаково.
///
/// ⚠️ И ЖИВЁТ ЭТО ЗДЕСЬ, А НЕ В `subscription_bar.dart`, чтобы не заводить
/// кольцевой импорт: карточка уже импортирует переключатель.
///
/// [SubscriptionProfile] `profile == null` означает «активная подписка» — так
/// зовёт карточка, которая всегда показывает именно её.
abstract final class SubscriptionActions {
  static const String refresh = 'refresh';
  static const String copy = 'copy';
  static const String site = 'site';
  static const String support = 'support';
  static const String delete = 'delete';

  /// Пункты меню. [hasUrl] — есть ли у подписки адрес: без него обновлять,
  /// копировать и открывать нечего.
  ///
  /// ⚠️ ПУНКТ, КОТОРЫЙ НИЧЕГО НЕ ДЕЛАЕТ, ХУЖЕ ОТСУТСТВУЮЩЕГО. Раньше
  /// «Обновить» и «Копировать ссылку» показывались всегда, а обработчик молча
  /// выходил при пустом адресе (сервер добавлен ссылкой или своим JSON —
  /// подписки за ним нет).
  static List<PopupMenuEntry<String>> menuItems(AppLocalizations l,
          {required bool hasUrl}) =>
      [
        if (hasUrl) item(refresh, Icons.refresh, l.subBarRefresh),
        if (hasUrl) item(copy, Icons.copy, l.subBarCopyLink),
        if (hasUrl) item(site, Icons.public, l.subBarOpenSite),
        item(support, Icons.support_agent, l.subBarSupport),
        item(delete, Icons.delete_outline, l.subBarDeleteSubscription),
      ];

  static PopupMenuItem<String> item(String v, IconData icon, String text) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          // ⚠️ ПОДПИСЬ ГИБКАЯ, А НЕ ЖЁСТКАЯ. Ширина меню упирается в потолок
          // `showMenu` (280 px), и подпись, которая в него не влезла, раньше
          // просто вылезала за край: в отладочной сборке — жёлто-чёрная полоса
          // «RenderFlex overflowed», в релизной — обрезанный текст. Языков у
          // нас десять, и длина подписи меняется в разы. `Flexible` переносит
          // строку вместо переполнения — ничего не теряется.
          Flexible(child: Text(text)),
        ]),
      );

  /// «Поддержка» ВЕЗДЕ ведёт в настройки → раздел поддержки, где объяснено,
  /// что будет сделано, и дана ссылка из конфига.
  static void openSupport(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const SettingsScreen(scrollToSupport: true)));
  }

  /// Выполнить выбранное действие над [profile] (null = активная подписка).
  static Future<void> run(BuildContext context, String action,
      {SubscriptionProfile? profile}) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final id = profile?.id;
    // ⚠️ АДРЕС СПРАШИВАЕМ У ТОЙ ПОДПИСКИ, О КОТОРОЙ ИДЁТ РЕЧЬ.
    // `state.subscriptionUrl` — адрес АКТИВНОЙ, и на чужой строке меню он
    // скопировал бы и открыл чужую страницу, ничем не выдав подмену.
    final url = id == null ? state.subscriptionUrl : state.subscriptionUrlOf(id);
    switch (action) {
      case refresh:
        if ((url ?? '').isEmpty) return;
        // Активная показывает ход в самой карточке (крутилка вместо значка);
        // соседняя на экране не двигает ничего — о ней говорим сообщениями,
        // иначе нажатие выглядит холостым.
        if (id == null || id == state.activeSubscriptionId) {
          unawaited(state.refreshSubscription());
          return;
        }
        // ⚠️ ИМЯ — `safeTitle`: запасное `title` при отсутствии названия от
        // панели вырождается в `хост/…<последний сегмент>`, а у Remnawave
        // последний сегмент и есть токен подписки.
        final title = profile!.safeTitle;
        AppToast.show(context, l.subSwitcherRefreshingOne(title));
        final ok = await state.refreshSubscription(id: id);
        if (!context.mounted) return;
        AppToast.show(
            context,
            ok
                ? l.subSwitcherRefreshedOne(title)
                : l.subSwitcherRefreshFailedOne(title),
            kind: ok ? ToastKind.success : ToastKind.error);
        return;
      case copy:
        if ((url ?? '').isEmpty) return;
        await Clipboard.setData(ClipboardData(text: url!));
        if (context.mounted) {
          AppToast.copied(context, message: l.subBarLinkCopied);
        }
        return;
      case site:
        if ((url ?? '').isEmpty) return;
        // ⚠️ ОТКРЫВАЕТ И МОЛЧИТ. В адресе подписки лежит токен доступа: ни в
        // подсказке кнопки, ни в сообщении, ни в журнале (он уезжает в отчёт
        // поддержки) его быть не должно. Ссылка открывается КАК ЕСТЬ — это
        // собственная страница подписки пользователя.
        await UrlOpener.open(url!);
        return;
      case support:
        openSupport(context);
        return;
      case delete:
        await confirmDelete(context, profile: profile);
        return;
    }
  }

  /// #5 — закреплённые серверы переживают подписку, поэтому спрашиваем про них
  /// явно: иначе после удаления список не пустеет и это выглядит как баг.
  static Future<void> confirmDelete(BuildContext context,
      {SubscriptionProfile? profile}) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final id = profile?.id;
    var alsoPinned = false;
    // ⚠️ СПРАШИВАЕМ РОВНО ПРО ТО, ЧТО РЕАЛЬНО ПРОПАДЁТ. Здесь стоял общий
    // счётчик всех закреплённых серверов — и на удалении ОДНОЙ подписки из
    // четырёх приложение предлагало убрать закрепления, принадлежащие другим
    // (жалоба владельца 18.08.2026). Само удаление адресное с той же даты,
    // а вопрос оставался прежним: человек соглашался на одно, а терял другое.
    final atRisk = state.pinnedAtRiskOf(id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setState) => AlertDialog(
          // Из меню можно удалить ЛЮБУЮ строку, в том числе не ту, что открыта,
          // — имя в заголовке единственное, что отличает их друг от друга.
          title: Text(profile == null
              ? l.subBarDeleteConfirmTitle
              : l.subBarDeleteConfirmNamed(profile.safeTitle)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.subBarDeleteConfirmBody),
              if (atRisk > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alsoPinned,
                  onChanged: (v) => setState(() => alsoPinned = v ?? false),
                  title: Text(l.subBarDeletePinned(atRisk)),
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
    if (ok != true) return;
    await state.deleteSubscription(removePinned: alsoPinned, id: id);
    if (context.mounted) {
      AppToast.show(context, l.subBarSubscriptionDeleted,
          kind: ToastKind.success);
    }
  }
}

/// Состояние счётчика подписки — то, НАСКОЛЬКО его числу можно верить.
///
/// ⚠️ ТРЁХ СОСТОЯНИЙ, А НЕ ОДНОГО ЧИСЛА. Пока состояние было одно, счётчик врал
/// дважды и оба раза убедительно: во время прогона он показывал недосчитанный
/// промежуточный итог (в первые секунды — красный ноль, который читается как
/// «подписка мертва»), а после отмены — «101 · 4» ровно так же, как после
/// законченной проверки.
enum SubscriptionCountState {
  /// Показываем то, что знаем: числу можно верить как итогу.
  ready,

  /// Прогон идёт прямо сейчас и взял НЕСКОЛЬКО серверов ЭТОЙ подписки. Число
  /// рабочих существует, но оно промежуточное — показывать его нельзя.
  running,

  /// Последний прогон оборвался (отмена или сбой) и до части серверов не
  /// дошёл: число рабочих неполное.
  partial,
}

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
/// ничего не знаем. По той же причине [working] равен null и в состоянии
/// [SubscriptionCountState.running].
class SubscriptionPingCount {
  final int total;
  final int? working;
  final SubscriptionCountState state;
  const SubscriptionPingCount(this.total, this.working,
      {this.state = SubscriptionCountState.ready});

  /// [runningKeys] — ключи серверов, которые прогон проверяет прямо сейчас
  /// (`ProbeController.runningKeys`; пусто, когда прогона нет), [unfinished] —
  /// ключи серверов, до которых прогон не дошёл (`ProbeController.unfinishedKeys`).
  ///
  /// ⚠️ ОБА ПРИЗНАКА СВЕРЯЮТСЯ С СОБСТВЕННЫМИ СЕРВЕРАМИ ПОДПИСКИ, а не берутся
  /// как есть: пинг с главного экрана гоняет ТОЛЬКО активную подписку, и
  /// пометить «идёт проверка» у всех четырёх значило бы соврать по-новому.
  ///
  /// ⚠️ И «ИДЁТ» — ЭТО ПРО ПОДПИСКУ, А НЕ ПРО ОДНУ ЕЁ СТРОКУ. Признаком служил
  /// голый флаг `ProbeController.running`, а его поднимает и перепроверка
  /// одного сервера по тапу на плашке пинга (`pingOne` идёт тем же путём): в
  /// стосерверной подписке счётчик целиком прятался за многоточие из-за одной
  /// строки. Порог — БОЛЬШЕ ОДНОГО сервера подписки в прогоне: он отделяет
  /// массовый прогон от одиночной перепроверки, и только это. Цена: пока
  /// перепроверяется одна строка, число рабочих на неё устаревает (её прежний
  /// вердикт уже стёрт). Это меньшее зло, чем спрятать весь счётчик; подписка
  /// ровно из одного сервера в этот момент числа рабочих не показывает вовсе —
  /// проверять там больше некого.
  ///
  /// ⚠️ ЧЕГО ПОРОГ НЕ ОЗНАЧАЕТ: «прогон взял подписку целиком». Прежняя
  /// редакция обещала именно это — «массовые прогоны берут либо всю активную
  /// подписку (кнопка на главном), либо все подписки (пункт меню)» — и была
  /// неправдой. Кнопка на главном пингует то, что ВИДНО: при активном поиске
  /// только найденное (`home_screen`, подпись «Пинг найденных»). Два сервера,
  /// найденных поиском из ста одного, порог проходят — и счётчик всей подписки
  /// на время их проверки прячется за многоточие. Так и задумано: два стёртых
  /// вердикта из ста одного уже делают показанное число промежуточным, а
  /// молчание честнее.
  static SubscriptionPingCount of(
      List<VpnServer> servers, PingResult Function(VpnServer) resultFor,
      {Set<String> runningKeys = const {},
      Set<String> unfinished = const {}}) {
    var working = 0;
    var checked = false;
    var inFlight = false;
    var partial = false;
    var inRun = 0;
    for (final s in servers) {
      final r = resultFor(s);
      // Замер ещё не сделан вовсе — сервер в очереди текущего прогона.
      if (r.outcome == PingOutcome.testing) inFlight = true;
      switch (r.verification) {
        case PingVerification.passed:
          working++;
          checked = true;
        case PingVerification.failed:
          // Проверка была и провалилась — число рабочих уже осмысленно.
          checked = true;
        case PingVerification.pending:
          // Замер есть, проверка канала идёт — итога у сервера ещё нет.
          inFlight = true;
        case PingVerification.notRun:
          break;
      }
      if (unfinished.contains(s.key)) partial = true;
      if (runningKeys.contains(s.key)) inRun++;
    }
    if (inRun > 1 && inFlight) {
      return SubscriptionPingCount(servers.length, null,
          state: SubscriptionCountState.running);
    }
    return SubscriptionPingCount(servers.length, checked ? working : null,
        // Помечать неполным есть смысл только там, где число ПОКАЗЫВАЕТСЯ:
        // без единого вердикта счётчик и так честно молчит о рабочих.
        state: partial && checked
            ? SubscriptionCountState.partial
            : SubscriptionCountState.ready);
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
    // ⚠️ ЧИСТКА ПОМЕТКИ «прогон сюда не дошёл» — ЗДЕСЬ, ПЕРЕД ПОКАЗОМ СЧЁТЧИКА.
    // Снимает её только прогон, взявший сервер в работу, а сервер, пропавший из
    // подписки, не возьмёт уже никто: `ping_unfinished.json` рос без предела, и
    // вернувшийся с тем же ключом узел помечал подписку неполной без причины.
    // Место выбрано за полнотой списка: `allSubscriptionServers` — это ровно
    // всё, что приложение знает (активный список плюс серверы остальных
    // подписок), и собирается он здесь по нажатию, а не в build.
    unawaited(probe.forgetUnknownServers(
        [for (final s in state.allSubscriptionServers()) s.key]));
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
            state: state,
            probe: probe,
            settings: settings,
            // ⚠️ ДЕЙСТВИЕ ВЫПОЛНЯЕТСЯ В КОНТЕКСТЕ КАРТОЧКИ, А НЕ МЕНЮ.
            // Меню к этому моменту уже закрыто, и его контекст мёртв: диалог
            // удаления и всплывающие сообщения открывать из него нельзя.
            // Контекст самого переключателя живёт в карточке и переживает
            // закрытие меню — сверяемся с `mounted` на случай, если карточка
            // ушла с экрана (импорт первой подписки, удаление последней).
            onAction: (action, profile) {
              if (!context.mounted) return;
              unawaited(SubscriptionActions.run(context, action,
                  profile: profile));
            },
          ),
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

  /// Что делать с выбранным в ПКМ-меню строки действием. Выполняет его не
  /// список, а карточка (см. `SubscriptionSwitcher._open`): к моменту вызова
  /// меню переключателя уже закрыто вместе со своим контекстом.
  final void Function(String action, SubscriptionProfile profile) onAction;
  const _SwitcherBody(
      {required this.state,
      required this.probe,
      required this.settings,
      required this.onAction});

  @override
  State<_SwitcherBody> createState() => _SwitcherBodyState();
}

class _SwitcherBodyState extends State<_SwitcherBody> {
  /// Восстановленные серверы подписок: id профиля → сам профиль и его серверы.
  ///
  /// ⚠️ КЭШ ЗДЕСЬ ОБЯЗАТЕЛЕН. Серверы неактивных подписок существуют только как
  /// ссылки, и `serversOfSubscription` разбирает их заново на каждый вызов. А
  /// это меню перестраивается на КАЖДОЕ уведомление `ProbeController` — во
  /// время прогона их сотни, и без кэша мы бы разбирали 124 ссылки сотни раз
  /// подряд ради двух цифр. Число рабочих при этом обновляется каждый раз — оно
  /// считается по свежим результатам пинга, а не берётся из кэша.
  ///
  /// ⚠️ И КЭШ ОБЯЗАН СБРАСЫВАТЬСЯ. Ключом был один `id`, а `id` подписки не
  /// меняется никогда: обновление подписки, завершившееся при ОТКРЫТОМ меню,
  /// счётчик не замечал — прежнее количество серверов висело до закрытия и
  /// повторного открытия. С обновлением при каждом запуске случай стал частым.
  /// Сверяем сам ОБЪЕКТ профиля: `AppState` при обновлении кладёт в список
  /// новый (`_upsertProfile`, `copyWith` в `_syncActiveProfileServers`), а
  /// перетаскивание переставляет те же самые объекты — его кэш переживает, как
  /// и раньше.
  final Map<String, ({SubscriptionProfile profile, List<VpnServer> servers})>
      _serversByProfile = {};

  List<VpnServer> _serversOf(SubscriptionProfile p) {
    final hit = _serversByProfile[p.id];
    if (hit != null && identical(hit.profile, p)) return hit.servers;
    final servers = widget.state.serversOfSubscription(p.id);
    _serversByProfile[p.id] = (profile: p, servers: servers);
    return servers;
  }

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

  /// Меню действий над КОНКРЕТНОЙ строкой (ПКМ / долгое нажатие).
  ///
  /// ⚠️ ЭТО МЕНЮ ВНУТРИ МЕНЮ. Переключатель сам живёт в маршруте `showMenu`;
  /// вложенный `showMenu` кладёт поверх него свой маршрут и, закрываясь,
  /// снимает только себя — родительский список остаётся на месте. Пункты здесь
  /// обычные (без прокручиваемых списков): `showMenu` оборачивает содержимое в
  /// `IntrinsicWidth`, и прокручиваемая область внутри бросила бы исключение —
  /// ровно то, из-за чего у самого переключателя ТУГАЯ ширина.
  ///
  /// Выбранное действие исполняет карточка ([_SwitcherBody.onAction]): к тому
  /// моменту переключатель уже закрыт, а вместе с ним мёртв и его контекст.
  Future<void> _rowMenu(
      BuildContext context, SubscriptionProfile p, Offset pos) async {
    final l = AppLocalizations.of(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: SubscriptionActions.menuItems(l, hasUrl: p.url.isNotEmpty),
    );
    if (action == null || !context.mounted) return;
    // Закрываем сам переключатель: дальше действие показывает свои диалоги и
    // сообщения, а список поверх них — лишний слой, из-под которого не видно
    // ни вопроса об удалении, ни ответа на него.
    Navigator.of(context).pop();
    widget.onAction(action, p);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = widget.state.subscriptions;
    final activeId = widget.state.activeSubscriptionId;
    // Один момент времени на всю отрисовку списка: иначе две подписки с одной и
    // той же датой могли бы разойтись в вердикте на границе секунды.
    final now = DateTime.now();
    // Есть ли вообще что пинговать. Считаем по тому же кэшу, что и счётчики:
    // спрашивать `allSubscriptionServers()` на каждый build значило бы
    // разбирать все ссылки заново ради одного «пусто/не пусто».
    final anyServers = widget.state.servers.isNotEmpty ||
        items.any((p) => _serversOf(p).isNotEmpty);
    // Гейт пинга — общий с экраном серверов и главным экраном: одно место
    // решает «можно ли» и оно же называет причину. Отдельный признак «идёт
    // замер скорости» больше не нужен — он одно из условий внутри гейта, а
    // держать его снаружи значило бы снова проверять часть условий вручную.
    final pingGate = PingGate.of(widget.probe, hasTargets: anyServers);

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
                // Истёкшая подписка снаружи ничем не отличается от рабочей:
                // название то же, серверы в ссылках те же, счётчик тот же —
                // владелец с четырьмя подписками не мог понять, какая из них
                // уже не работает, пока не переключится и не получит отказ.
                final expired = p.isExpiredAt(now);
                return GestureDetector(
                  // Ключ обязателен и обязан быть привязан к САМОЙ подписке:
                  // по ключу по позиции перетаскивание меняло бы содержимое
                  // строк, а не их порядок. Живёт на САМОМ ВЕРХНЕМ виджете
                  // строки — `ReorderableListView` смотрит только туда.
                  key: ValueKey(p.id),
                  // Действия над подпиской — правой кнопкой (ПК) и долгим
                  // нажатием (телефон). Обычный тап остаётся за выбором
                  // подписки: он и есть главное назначение строки.
                  onSecondaryTapDown: (d) =>
                      _rowMenu(context, p, d.globalPosition),
                  onLongPressStart: (d) =>
                      _rowMenu(context, p, d.globalPosition),
                  child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    if (!active) widget.state.switchSubscription(p.id);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(children: [
                      // Аватарка подписки — своя у каждой (логотип из кэша либо
                      // цветной кружок с буквой названия).
                      //
                      // ⚠️ Приглушаются ТОЛЬКО картинка и название. Счётчик,
                      // отметка активной и ручка перетаскивания остаются в
                      // полную силу: истёкшую подписку всё ещё можно выбрать,
                      // переставить и обновить — она не «отключённый пункт», а
                      // помеченный.
                      Opacity(
                        opacity: expired ? 0.45 : 1,
                        child: SubscriptionAvatar(
                            path: p.logoPath, label: p.title, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title,
                                // Доминирует название подписки — направление по нему.
                                textDirection: autoTextDirection(p.title),
                                overflow: TextOverflow.ellipsis,
                                style: expired
                                    ? TextStyle(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.55))
                                    : null),
                            if (expired)
                              _ExpiredMark(
                                  key: ValueKey('subExpired_${p.id}'),
                                  expiresAt: p.info.expiresAt),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // ⚠️ Считаем ВОССТАНОВЛЕННЫЕ серверы, а не длину
                      // `p.serverLinks` (так было раньше). Ссылка, которую
                      // парсер не понимает, в список не попадает и
                      // пропингована не будет.
                      //
                      // ⚠️ ЭТО ЧИСЛО ПОДПИСКИ, А НЕ ЕЁ ДОЛЯ В ПРОГОНЕ. Сумма
                      // счётчиков сходится с объёмом прогона ровно до тех пор,
                      // пока подписки не пересекаются: `allSubscriptionServers()`
                      // отсекает повторы ПО КЛЮЧУ, и сервер, лежащий в двух
                      // подписках, в каждой из них свой, а пингуется один раз —
                      // на столько сумма и больше (у владельца 101 · 40 и 4 · 2
                      // в меню против 108 в прогоне). Прежний комментарий обещал
                      // совпадение, нынешний — расхождение всегда; неверно и то,
                      // и другое. Обе половины — и совпадение на непересекающихся
                      // подписках, и расхождение на общем сервере — стережёт
                      // группа «счётчик подписки и объём прогона» в
                      // `test/subscription_counter_test.dart`.
                      _CountBadge(
                        key: ValueKey('subCount_${p.id}'),
                        count: SubscriptionPingCount.of(
                            _serversOf(p), widget.probe.resultFor,
                            runningKeys: widget.probe.runningKeys,
                            unfinished: widget.probe.unfinishedKeys),
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
            // ⚠️ ЗАМЕР СКОРОСТИ ЗАПРЕЩАЕТ ПИНГ, И ЭТО НАДО ГОВОРИТЬ ВСЛУХ.
            // Оба прогона делят один харнесс и одни локальные порты, поэтому
            // `_pingBatch` при `speedRunning` молча выходит первой же строкой.
            // Пункт при этом выглядел совершенно живым: нажатие закрывало меню
            // и не делало ничего — а замер сотни серверов идёт десятки минут,
            // и всё это время человек жал впустую.
            // ⚠️ ПРИЧИНУ СПРАШИВАЕМ У ОБЩЕГО ГЕЙТА, а не считаем свою. Здесь
            // проверялся только замер скорости, а исполнитель отказывает ещё и
            // во время автопрогона проверки сервисов — пункт в этот момент
            // выглядел живым и молча ничего не делал.
            label: pingGate.label(l, l.subSwitcherPingAll),
            busy: widget.probe.running,
            // ⚠️ ЗДЕСЬ ПИНГУЮТСЯ ВСЕ ПОДПИСКИ, А НЕ ТЕКУЩАЯ — решение владельца
            // (13.08.2026): «пункт меню — все подписки». Раньше пункт гонял
            // `state.servers`, то есть ровно то же, что кнопка на главном
            // экране; отличить их было нельзя, и второй пункт не имел смысла.
            // Кнопка на главном осталась прежней — тоже по решению владельца.
            //
            // Список собирает `AppState`: серверы неактивных подписок лежат
            // ссылками, и восстановить их умеет только он.
            onTap: !pingGate.allowed
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

/// Пометка истёкшей подписки под её названием: значок и подпись.
///
/// ⚠️ ПОЧЕМУ ЗАМЕТНО, НО НЕ КРИКЛИВО. Красная плашка во всю строку сделала бы
/// список из четырёх подписок похожим на аварию, хотя истёкшая подписка — это
/// нормальное состояние (её продлевают). Поэтому: строка приглушена, а цветом
/// выделены только значок и слово — глазом находится сразу, внимание не
/// перетягивает.
///
/// Дата уходит в подсказку по наведению, а не в строку: меню шириной 280 px, и
/// «Истекла 12.08.2026» рядом со счётчиком обрезало бы название подписки —
/// ровно то, по чему её и узнают.
class _ExpiredMark extends StatelessWidget {
  final DateTime? expiresAt;
  const _ExpiredMark({super.key, required this.expiresAt});

  /// Дата в привычном виде ДД.ММ.ГГГГ и в ЛОКАЛЬНОЙ зоне: на диске лежит UTC
  /// (см. `SubscriptionInfo.toJson`), и показать его как есть значило бы
  /// сдвинуть дату на сутки у половины часовых поясов.
  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.'
        '${l.month.toString().padLeft(2, '0')}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final exp = expiresAt;
    final mark = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.event_busy, size: 13, color: scheme.error),
      const SizedBox(width: 4),
      Text(l.subSwitcherExpired,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error)),
    ]);
    if (exp == null) return mark;
    return Tooltip(message: l.subSwitcherExpiredOn(_date(exp)), child: mark);
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
    final partial = count.state == SubscriptionCountState.partial;
    final message = switch (count.state) {
      SubscriptionCountState.running => l.subSwitcherCountChecking(count.total),
      // В этом состоянии число рабочих есть всегда (см. `SubscriptionPingCount.of`).
      SubscriptionCountState.partial =>
        l.subSwitcherCountPartial(count.total, working ?? 0),
      SubscriptionCountState.ready => working == null
          ? l.subSwitcherCountTotal(count.total)
          : l.subSwitcherCountWorking(count.total, working),
    };
    final dot = Text('  ·  ',
        style: TextStyle(fontSize: 12, color: scheme.outlineVariant));
    return Tooltip(
      message: message,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${count.total}',
            // Цифры — всегда слева направо, даже в арабской локали: это
            // технические числа, а не текст (та же политика, что у адресов).
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 12, color: scheme.outline)),
        if (count.state == SubscriptionCountState.running) ...[
          dot,
          // ⚠️ ЗНАЧОК ВМЕСТО ЦИФРЫ, А НЕ ЦИФРА ПОБЛЕДНЕЕ. Любое число во время
          // прогона — промежуточный итог, и первые секунды это НОЛЬ: красный
          // ноль рядом с сотней серверов человек читает как «подписка умерла»
          // и идёт её перевыпускать. Три точки не обещают ничего.
          //
          // И не крутилка: она анимируется бесконечно, а меню — обычный
          // маршрут поверх экрана, где такой кадр никогда не «успокаивается».
          Icon(Icons.more_horiz, size: 14, color: scheme.outline),
        ] else if (working != null) ...[
          dot,
          Text('$working',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  // Рабочие выделены цветом состояния, а не просто жирным:
                  // в строке шириной 280 px две серые цифры сливаются в одну.
                  // ⚠️ Кроме неполного итога: цвет — это вердикт, а после
                  // отмены вердикта нет. Зелёная четвёрка из ста одного
                  // сервера соврала бы не меньше красного нуля.
                  color: partial
                      ? scheme.outline
                      : (working > 0 ? Colors.green : scheme.error))),
          if (partial)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 3),
              child: Icon(Icons.error_outline, size: 13, color: scheme.outline),
            ),
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
