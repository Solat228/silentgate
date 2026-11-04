import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Контроллер быстрого выделения зажатой левой кнопкой мыши (как в Telegram Desktop).
///
/// Поддерживает:
/// * автоматический вход в режим выбора, как только зажатый курсор пересёк 2-ю строку;
/// * докрашивание / снятие галочек протяжкой (`paint-select` / `paint-deselect`),
///   когда режим выбора уже включён;
/// * автопрокрутку списка у верхнего и нижнего края области;
/// * нулевое вмешательство в тач-прокрутку на телефонах (`PointerDeviceKind.touch`
///   игнорируется, оставляя нативный скролл и `onLongPress`).
class DragSelectController<T> {
  final Map<T, BuildContext> _mountedContexts = <T, BuildContext>{};

  /// Визуальный порядок всех элементов списка сверху вниз.
  List<T> orderedIds = const [];

  int? _activePointer;
  T? _anchorId;
  int _anchorIndex = -1;
  Offset? _downGlobalPos;
  Offset? _lastGlobalPos;
  bool _dragCommitted = false;
  bool _paintSelect = true;
  Set<T> _baseSelection = <T>{};
  bool _suppressNextTap = false;
  Timer? _autoScrollTimer;
  Timer? _clearSuppressTimer;

  /// Активна ли прямо сейчас протяжка мышью.
  bool get isDragging => _dragCommitted && _activePointer != null;

  void _registerItem(T id, BuildContext context) {
    _mountedContexts[id] = context;
  }

  void _unregisterItem(T id, BuildContext context) {
    if (_mountedContexts[id] == context) {
      _mountedContexts.remove(id);
    }
  }

  /// Поглощает одиночный `onTap`, который Flutter генерирует при отпускании ЛКМ
  /// после завершённой протяжки по нескольким строкам.
  bool consumeTapSuppression() {
    if (!_suppressNextTap) return false;
    _suppressNextTap = false;
    _clearSuppressTimer?.cancel();
    _clearSuppressTimer = null;
    return true;
  }

  void dispose() {
    _stopAutoScroll();
    _clearSuppressTimer?.cancel();
    _mountedContexts.clear();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  T? _hitTestExact(Offset globalPos) {
    for (final entry in _mountedContexts.entries) {
      final ctx = entry.value;
      if (!ctx.mounted) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      final rect = ro.localToGlobal(Offset.zero) & ro.size;
      if (rect.contains(globalPos)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Находит строку под курсором при протяжке, учитывая заголовки секций и разделители
  /// между строками, чтобы выделение шло непрерывно через секции.
  T? _hitTestDrag(Offset globalPos, Offset anchorGlobalPos) {
    // 1. Прямое попадание по вертикали (с небольшим горизонтальным допуском).
    for (final entry in _mountedContexts.entries) {
      final ctx = entry.value;
      if (!ctx.mounted) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      final rect = ro.localToGlobal(Offset.zero) & ro.size;
      if (globalPos.dy >= rect.top &&
          globalPos.dy <= rect.bottom &&
          globalPos.dx >= rect.left - 48 &&
          globalPos.dx <= rect.right + 48) {
        return entry.key;
      }
    }

    // 2. Курсор оказался над заголовком секции или разделителем: берём последнюю
    // пересечённую по направлению движения смонтированную строку.
    final indexMap = <T, int>{
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };

    final movingDown = globalPos.dy >= anchorGlobalPos.dy;
    T? bestId;
    var bestIdx = movingDown ? -1 : orderedIds.length + 1;

    for (final entry in _mountedContexts.entries) {
      final idx = indexMap[entry.key];
      if (idx == null) continue;
      final ctx = entry.value;
      if (!ctx.mounted) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      final rect = ro.localToGlobal(Offset.zero) & ro.size;

      if (movingDown) {
        if (rect.center.dy <= globalPos.dy && idx > bestIdx) {
          bestIdx = idx;
          bestId = entry.key;
        }
      } else {
        if (rect.center.dy >= globalPos.dy && idx < bestIdx) {
          bestIdx = idx;
          bestId = entry.key;
        }
      }
    }
    return bestId;
  }
}

/// Обёртка вокруг прокручиваемого списка, отслеживающая протяжку зажатой ЛКМ.
class DragSelectRegion<T> extends StatefulWidget {
  const DragSelectRegion({
    super.key,
    required this.controller,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.child,
    this.scrollController,
    this.enabled = true,
  });

  final DragSelectController<T> controller;
  final bool isSelectionMode;
  final Set<T> selectedIds;

  /// Вызывается при изменении набора выделенных элементов во время протяжки.
  final void Function(Set<T> nextSelected, {required bool enteredSelectionMode})
      onSelectionChanged;

  final ScrollController? scrollController;
  final bool enabled;
  final Widget child;

  @override
  State<DragSelectRegion<T>> createState() => _DragSelectRegionState<T>();
}

class _DragSelectRegionState<T> extends State<DragSelectRegion<T>> {
  DragSelectController<T> get _ctrl => widget.controller;

  bool _isMouseLike(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || !_isMouseLike(event.kind)) return;
    if ((event.buttons & kPrimaryMouseButton) == 0) return;

    final hit = _ctrl._hitTestExact(event.position);
    if (hit == null) return;
    final idx = _ctrl.orderedIds.indexOf(hit);
    if (idx < 0) return;

    _ctrl._activePointer = event.pointer;
    _ctrl._anchorId = hit;
    _ctrl._anchorIndex = idx;
    _ctrl._downGlobalPos = event.position;
    _ctrl._lastGlobalPos = event.position;
    _ctrl._dragCommitted = false;
    _ctrl._baseSelection = Set<T>.of(widget.selectedIds);
    _ctrl._paintSelect =
        widget.isSelectionMode ? !_ctrl._baseSelection.contains(hit) : true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_ctrl._activePointer != event.pointer) return;
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      _finishPointer();
      return;
    }
    _ctrl._lastGlobalPos = event.position;
    _evaluateDrag(event.position);
    _updateAutoScroll(event.position);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_ctrl._activePointer != event.pointer) return;
    _finishPointer();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_ctrl._activePointer != event.pointer) return;
    _finishPointer();
  }

  void _finishPointer() {
    final wasCommitted = _ctrl._dragCommitted;
    _ctrl._stopAutoScroll();
    _ctrl._activePointer = null;
    _ctrl._anchorId = null;
    _ctrl._anchorIndex = -1;
    _ctrl._downGlobalPos = null;
    _ctrl._lastGlobalPos = null;
    _ctrl._dragCommitted = false;

    if (wasCommitted) {
      _ctrl._suppressNextTap = true;
      _ctrl._clearSuppressTimer?.cancel();
      _ctrl._clearSuppressTimer = Timer(
        const Duration(milliseconds: 120),
        () => _ctrl._suppressNextTap = false,
      );
    }
  }

  void _evaluateDrag(Offset globalPos) {
    final anchorId = _ctrl._anchorId;
    final downPos = _ctrl._downGlobalPos;
    if (anchorId == null || downPos == null) return;

    // Обновляем индекс якоря на случай, если список успел отфильтроваться.
    final liveAnchorIdx = _ctrl.orderedIds.indexOf(anchorId);
    final anchorIdx = liveAnchorIdx >= 0 ? liveAnchorIdx : _ctrl._anchorIndex;
    if (anchorIdx < 0 || anchorIdx >= _ctrl.orderedIds.length) return;

    final hovered = _ctrl._hitTestDrag(globalPos, downPos);
    if (hovered == null) return;
    final hoveredIdx = _ctrl.orderedIds.indexOf(hovered);
    if (hoveredIdx < 0) return;

    var enteredNow = false;
    if (!_ctrl._dragCommitted) {
      // Главный порог из требования: пока не коснулись 2-й строки — режим выбора
      // протяжкой НЕ включаем (одиночный клик остаётся обычным кликом).
      if (hovered == anchorId) return;
      _ctrl._dragCommitted = true;
      if (!widget.isSelectionMode) {
        enteredNow = true;
      }
    }

    final start = math.min(anchorIdx, hoveredIdx);
    final end = math.max(anchorIdx, hoveredIdx);
    final rangeSlice = _ctrl.orderedIds.sublist(start, end + 1);

    final next = Set<T>.of(_ctrl._baseSelection);
    if (_ctrl._paintSelect) {
      next.addAll(rangeSlice);
    } else {
      next.removeAll(rangeSlice);
    }

    if (!_sameSet(next, widget.selectedIds) || enteredNow) {
      widget.onSelectionChanged(next, enteredSelectionMode: enteredNow);
    }
  }

  void _updateAutoScroll(Offset globalPos) {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) {
      _ctrl._stopAutoScroll();
      return;
    }
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) {
      _ctrl._stopAutoScroll();
      return;
    }
    final local = ro.globalToLocal(globalPos);
    const edgeZone = 42.0;
    double step = 0;
    if (local.dy < edgeZone) {
      final ratio = ((edgeZone - local.dy) / edgeZone).clamp(0.15, 1.0);
      step = -14.0 * ratio;
    } else if (local.dy > ro.size.height - edgeZone) {
      final ratio =
          ((local.dy - (ro.size.height - edgeZone)) / edgeZone).clamp(0.15, 1.0);
      step = 14.0 * ratio;
    }

    if (step == 0) {
      _ctrl._stopAutoScroll();
      return;
    }

    _ctrl._autoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (!mounted ||
            _ctrl._activePointer == null ||
            _ctrl._lastGlobalPos == null ||
            !sc.hasClients) {
          _ctrl._stopAutoScroll();
          return;
        }
        final curBox = context.findRenderObject();
        if (curBox is! RenderBox || !curBox.hasSize) return;
        final curLocal = curBox.globalToLocal(_ctrl._lastGlobalPos!);
        double delta = 0;
        if (curLocal.dy < edgeZone) {
          final r = ((edgeZone - curLocal.dy) / edgeZone).clamp(0.15, 1.0);
          delta = -14.0 * r;
        } else if (curLocal.dy > curBox.size.height - edgeZone) {
          final r = ((curLocal.dy - (curBox.size.height - edgeZone)) / edgeZone)
              .clamp(0.15, 1.0);
          delta = 14.0 * r;
        }
        if (delta == 0) {
          _ctrl._stopAutoScroll();
          return;
        }
        final pos = sc.position;
        final target =
            (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((target - pos.pixels).abs() < 0.5) return;
        sc.jumpTo(target);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ctrl._lastGlobalPos != null) {
            _evaluateDrag(_ctrl._lastGlobalPos!);
          }
        });
      },
    );
  }

  static bool _sameSet<E>(Set<E> a, Set<E> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}

/// Маркер отдельной выбираемой строки внутри [DragSelectRegion].
class DragSelectItem<T> extends StatefulWidget {
  const DragSelectItem({
    super.key,
    required this.id,
    required this.controller,
    required this.child,
  });

  final T id;
  final DragSelectController<T> controller;
  final Widget child;

  @override
  State<DragSelectItem<T>> createState() => _DragSelectItemState<T>();
}

class _DragSelectItemState<T> extends State<DragSelectItem<T>> {
  @override
  void initState() {
    super.initState();
    widget.controller._registerItem(widget.id, context);
  }

  @override
  void didUpdateWidget(covariant DragSelectItem<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.id != widget.id) {
      oldWidget.controller._unregisterItem(oldWidget.id, context);
    }
    widget.controller._registerItem(widget.id, context);
  }

  @override
  void deactivate() {
    widget.controller._unregisterItem(widget.id, context);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    // При перестройке элемента обновляем ссылку на контекст.
    widget.controller._registerItem(widget.id, context);
    return widget.child;
  }
}
