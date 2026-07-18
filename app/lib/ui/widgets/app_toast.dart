import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Всплывающее сообщение ПОВЕРХ интерфейса.
///
/// Раньше уведомления жили в потоке компоновки: появление сводки об обновлении
/// подписки или ошибки сдвигало большую кнопку Connect и «ломало» экран. Оверлей
/// ничего не двигает, ширина — по содержимому (не на всю ширину окна), и он сам
/// гаснет по таймеру: под текстом идёт убывающая полоска, показывающая, сколько
/// уведомление ещё провисит. По клику раскрываются подробности (если они есть),
/// и тогда таймер останавливается — читать никто не мешает.
enum ToastKind { info, success, warning, error }

class AppToast {
  static int _seq = 0;

  /// Показать уведомление. Уведомления **не перекрывают** друг друга, а копятся
  /// стопкой снизу вверх: первое — у самого низа, каждое следующее над ним.
  /// Гаснут по таймеру, уезжая вниз; остальные при этом сдвигаются на их место.
  static void show(
    BuildContext context,
    String message, {
    ToastKind kind = ToastKind.info,
    Duration duration = const Duration(seconds: 6),
    String? actionLabel,
    VoidCallback? onAction,

    /// Подробности, раскрывающиеся по клику (например, что добавилось/удалилось).
    List<ToastDetail> details = const [],
  }) {
    _MessageToasts.add(
      context,
      _MsgData(
        id: ++_seq,
        message: message,
        kind: kind,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        details: details,
      ),
    );
  }

  /// Снять все сообщения-уведомления немедленно.
  static void dismiss() => _MessageToasts.clear();

  /// Подтверждение копирования — 5 секунд (как просил пользователь). Единая точка,
  /// чтобы уведомление было одинаковым у ВСЕХ кнопок «копировать».
  static void copied(BuildContext context, {String? message}) =>
      show(context, message ?? AppLocalizations.of(context).toastCopied,
          kind: ToastKind.success, duration: const Duration(seconds: 5));

  /// Ход длинной операции (пинг серверов, автонастройка) — карточкой **слева
  /// снизу**, чтобы не перекрывать кнопку Connect и сводки по центру.
  ///
  /// Пока `finished == false`, карточка висит и не гаснет сама: полоска показывает
  /// прогресс (`value` 0..1) или бежит бесконечно, если общее число неизвестно.
  /// После `finished: true` текст меняется на итог, а полоска превращается в
  /// обратный отсчёт на [holdAfterFinish] — по нулю карточка уезжает вниз.
  ///
  /// [id] — ключ операции («ping», «autoconfig»): повторный вызов с тем же id
  /// обновляет ту же карточку, а не плодит новые.
  static void progress(
    BuildContext context, {
    required String id,
    required String message,
    double? value,
    bool finished = false,
    ToastKind kind = ToastKind.info,
    Duration holdAfterFinish = const Duration(seconds: 10),
  }) =>
      _ProgressToasts.update(
        context,
        id: id,
        message: message,
        value: value,
        finished: finished,
        kind: kind,
        hold: holdAfterFinish,
      );

  /// Снять карточку прогресса немедленно (например, операцию отменили).
  static void dismissProgress(String id) => _ProgressToasts.remove(id);
}

/// Состояние одной карточки прогресса.
class _ProgressData {
  final String id;
  String message;
  double? value;
  bool finished;
  ToastKind kind;
  Duration hold;
  _ProgressData({
    required this.id,
    required this.message,
    required this.value,
    required this.finished,
    required this.kind,
    required this.hold,
  });
}

/// Реестр карточек прогресса: один оверлей на всё окно, внутри — колонка карточек.
/// Отдельный оверлей на каждую ломал бы порядок и перекрывал соседние.
class _ProgressToasts {
  static final ValueNotifier<List<_ProgressData>> _items = ValueNotifier([]);
  static OverlayEntry? _host;

  static void update(
    BuildContext context, {
    required String id,
    required String message,
    required double? value,
    required bool finished,
    required ToastKind kind,
    required Duration hold,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    if (_host == null) {
      _host = OverlayEntry(builder: (_) => const _ProgressStack());
      overlay.insert(_host!);
    }

    final list = [..._items.value];
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      final item = list[i];
      item.message = message;
      item.value = value;
      item.finished = finished;
      item.kind = kind;
      item.hold = hold;
      list[i] = item;
    } else {
      list.add(_ProgressData(
        id: id,
        message: message,
        value: value,
        finished: finished,
        kind: kind,
        hold: hold,
      ));
    }
    _items.value = list;
  }

  static void remove(String id) {
    final list = [..._items.value]..removeWhere((e) => e.id == id);
    _items.value = list;
    if (list.isEmpty) {
      _host?.remove();
      _host = null;
    }
  }
}

class _ProgressStack extends StatelessWidget {
  const _ProgressStack();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      // Выше центрального тоста (он сидит на bottom: 24 и при длинном тексте
      // растягивается на 560 px): на минимальной ширине окна они иначе
      // перекрывались, и сводка закрывала полоску прогресса.
      bottom: 96,
      child: ValueListenableBuilder<List<_ProgressData>>(
        valueListenable: _ProgressToasts._items,
        builder: (_, items, __) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final it in items)
              // Ключ на внешнем виджете — чтобы отсчёт не сбрасывался при сдвиге.
              Padding(
                key: ValueKey(it.id),
                padding: const EdgeInsets.only(top: 8),
                child: _ProgressCard(data: it),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatefulWidget {
  final _ProgressData data;
  const _ProgressCard({required this.data});

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard>
    with TickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  /// Обратный отсчёт после завершения. Запускается один раз — повторные
  /// обновления с тем же `finished: true` его не перезапускают.
  AnimationController? _countdown;

  @override
  void initState() {
    super.initState();
    if (widget.data.finished) _startCountdown();
  }

  @override
  void didUpdateWidget(covariant _ProgressCard old) {
    super.didUpdateWidget(old);
    if (widget.data.finished && _countdown == null) _startCountdown();
    // Операция началась заново — отсчёт снимаем, карточка снова висит.
    if (!widget.data.finished && _countdown != null) {
      _countdown!.dispose();
      _countdown = null;
    }
  }

  void _startCountdown() {
    final c = AnimationController(vsync: this, duration: widget.data.hold);
    _countdown = c;
    c.addStatusListener((s) async {
      if (s != AnimationStatus.completed || !mounted) return;
      await _appear.reverse();
      _ProgressToasts.remove(widget.data.id);
    });
    c.forward();
  }

  @override
  void dispose() {
    _appear.dispose();
    _countdown?.dispose();
    super.dispose();
  }

  Color _color(ColorScheme scheme) {
    switch (widget.data.kind) {
      case ToastKind.success:
        return Colors.green;
      case ToastKind.warning:
        return Colors.orange;
      case ToastKind.error:
        return scheme.error;
      case ToastKind.info:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    final data = widget.data;
    final countdown = _countdown;

    return FadeTransition(
      opacity: _appear,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
            .animate(CurvedAnimation(parent: _appear, curve: Curves.easeOut)),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320,
            decoration: BoxDecoration(
              color: ElevationOverlay.applySurfaceTint(
                  scheme.surfaceContainerHigh, scheme.surfaceTint, 3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: data.finished
                        ? Icon(Icons.check_circle_outline, size: 16, color: color)
                        : CircularProgressIndicator(strokeWidth: 2, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(data.message,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
              // Пока идёт — прогресс операции; после завершения — сколько
              // карточка ещё провисит.
              if (countdown == null)
                LinearProgressIndicator(
                  value: data.value,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: color.withValues(alpha: 0.7),
                )
              else
                AnimatedBuilder(
                  animation: countdown,
                  builder: (_, __) => LinearProgressIndicator(
                    value: 1 - countdown.value,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Строка подробностей: значок-иконка (или флаг) + текст.
class ToastDetail {
  final String text;
  final bool added; // true — добавлено, false — удалено
  final Widget? leading;
  const ToastDetail(this.text, {required this.added, this.leading});
}

/// Данные одного сообщения-уведомления.
class _MsgData {
  final int id;
  final String message;
  final ToastKind kind;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<ToastDetail> details;
  const _MsgData({
    required this.id,
    required this.message,
    required this.kind,
    required this.duration,
    required this.details,
    this.actionLabel,
    this.onAction,
  });
}

/// Реестр сообщений-уведомлений: один оверлей на всё окно, внутри — колонка
/// карточек, привязанная к низу. Новое сообщение добавляется В НАЧАЛО списка,
/// поэтому в колонке (сверху вниз) идут: новейшее … старейшее, а у самого низа
/// оказывается первое пришедшее.
class _MessageToasts {
  static final ValueNotifier<List<_MsgData>> _items = ValueNotifier([]);
  static OverlayEntry? _host;

  static void add(BuildContext context, _MsgData d) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    if (_host == null) {
      _host = OverlayEntry(builder: (_) => const _MessageStack());
      overlay.insert(_host!);
    }
    _items.value = [d, ..._items.value];
  }

  static void remove(int id) {
    final list = [..._items.value]..removeWhere((e) => e.id == id);
    _items.value = list;
    if (list.isEmpty) {
      _host?.remove();
      _host = null;
    }
  }

  static void clear() {
    _items.value = [];
    _host?.remove();
    _host = null;
  }
}

class _MessageStack extends StatelessWidget {
  const _MessageStack();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: ValueListenableBuilder<List<_MsgData>>(
        valueListenable: _MessageToasts._items,
        builder: (_, items, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in items)
              // Ключ на ВНЕШНЕМ виджете колонки: иначе при добавлении нового
              // сообщения в начало списка Flutter пересобирал бы карточку по
              // позиции и её State (таймер) создавался бы заново — старые
              // уведомления «продлевались». С ключом на Padding состояние
              // переносится вместе с карточкой, таймеры не сбрасываются.
              Padding(
                key: ValueKey(d.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: Center(child: _ToastCard(data: d)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  final _MsgData data;
  const _ToastCard({required this.data});

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with TickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  /// Полоска обратного отсчёта: пока идёт — уведомление на экране.
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.data.duration,
  );

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // С кнопкой действия не гасим: пользователь должен успеть нажать.
    if (widget.data.actionLabel == null) {
      _life.forward();
      _life.addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) _hide();
      });
    }
  }

  Future<void> _hide() async {
    // Уезжает вниз — как и появлялось.
    await _appear.reverse();
    _MessageToasts.remove(widget.data.id);
  }

  void _act() {
    _MessageToasts.remove(widget.data.id);
    widget.data.onAction?.call();
  }

  void _toggle() {
    if (widget.data.details.isEmpty) return;
    setState(() => _expanded = !_expanded);
    // Раскрыли — останавливаем таймер, свернули — досчитываем.
    if (_expanded) {
      _life.stop();
    } else if (widget.data.actionLabel == null) {
      _life.forward();
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _life.dispose();
    super.dispose();
  }

  (IconData, Color) _style(ColorScheme scheme) {
    switch (widget.data.kind) {
      case ToastKind.success:
        return (Icons.check_circle_outline, Colors.green);
      case ToastKind.warning:
        return (Icons.warning_amber, Colors.orange);
      case ToastKind.error:
        return (Icons.error_outline, scheme.error);
      case ToastKind.info:
        return (Icons.info_outline, scheme.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = _style(scheme);
    final hasDetails = widget.data.details.isNotEmpty;

    // Позиционирует вся стопка (_MessageStack); карточка — только содержимое.
    return FadeTransition(
        opacity: _appear,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(CurvedAnimation(parent: _appear, curve: Curves.easeOut)),
          child: ConstrainedBox(
              // Ширина по содержимому с запасом, но не во весь экран.
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: ElevationOverlay.applySurfaceTint(
                        scheme.surfaceContainerHigh, scheme.surfaceTint, 3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.45)),
                    boxShadow: const [
                      BoxShadow(blurRadius: 12, color: Colors.black26),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    InkWell(
                      onTap: hasDetails ? _toggle : null,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(widget.data.message,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          if (hasDetails)
                            Icon(
                                _expanded
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                                size: 18,
                                color: color),
                          if (widget.data.actionLabel != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _act,
                              child: Text(widget.data.actionLabel!),
                            ),
                          ],
                          IconButton(
                            tooltip: l.toastHide,
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close),
                            onPressed: _hide,
                          ),
                        ]),
                      ),
                    ),
                    if (_expanded)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final d in widget.data.details)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Row(children: [
                                      if (d.leading != null) ...[
                                        d.leading!,
                                        const SizedBox(width: 6),
                                      ],
                                      Text(d.added ? '+ ' : '− ',
                                          style: TextStyle(
                                            color: d.added
                                                ? Colors.green
                                                : scheme.error,
                                            fontWeight: FontWeight.w700,
                                          )),
                                      Flexible(
                                        child: Text(d.text,
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ]),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Бегущая строка: сколько уведомление ещё провисит.
                    if (widget.data.actionLabel == null)
                      AnimatedBuilder(
                        animation: _life,
                        builder: (_, __) => LinearProgressIndicator(
                          value: 1 - _life.value,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          color: color.withValues(alpha: 0.7),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        );
  }
}
