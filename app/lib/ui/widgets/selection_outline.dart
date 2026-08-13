import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Обводка ВЫБРАННОГО блока: линия чертится двумя концами из левого верхнего
/// угла и встречается в правом нижнем.
///
/// ⚠️ ПОЧЕМУ ОТДЕЛЬНЫЙ ВИДЖЕТ, А НЕ КОД ВНУТРИ ЭКРАНА. Росчерк родился в
/// боковом меню настроек (`SettingsRailTile`), а владелец попросил тот же приём
/// для списка серверов: «сделай такую же обводку для выбранного сервера». Две
/// копии анимации разошлись бы на первой же правке цвета или скорости, поэтому
/// рисование живёт здесь, а экраны только оборачивают свой блок.
///
/// ⚠️ ОБВОДИТСЯ ВЕСЬ БЛОК, А НЕ ПОЛОСА СЛЕВА. Уточнение владельца дословно:
/// «под обводкой я имел в виду, чтобы обводился ЭТОТ БЛОК, а не слева, но
/// оставь его» — то есть линия обязана пройти по ВСЕМУ периметру. Это
/// проверяется тестом (`outlineSegments` при полном прогрессе накрывает все
/// четыре грани), потому что глазами разница между «рамка» и «толстая линия
/// слева» на скриншоте не всегда заметна.
///
/// Исходная просьба про сам росчерк: «цветная линия, которая меняет цвет, из
/// левого верхнего угла нужного меню, которая расходится в обе стороны в правый
/// нижний угол». Отсюда два конца по половине периметра каждый, а цвет меняется
/// ВДОЛЬ линии (градиент по диагонали), а не мигает во времени: мигание
/// отвлекает, а плавный переход по длине как раз и читается как «линия меняет
/// цвет».
class SelectionOutline extends StatefulWidget {
  const SelectionOutline({
    super.key,
    required this.selected,
    required this.child,
    this.radius = 10,
    this.strokeWidth = 2,
    this.inset = 0,
  });

  final bool selected;
  final Widget child;

  /// Скругление углов рамки.
  final double radius;
  final double strokeWidth;

  /// Насколько увести линию ВНУТРЬ границ блока.
  ///
  /// Нужно там, где строки идут вплотную друг к другу (список серверов с
  /// разделителем в 1 px): без отступа рамка сливалась бы с разделителем
  /// соседней строки. Отступ рисованный, а не layout-овый — высота строки от
  /// него не меняется, иначе выбранный сервер стал бы выше остальных и поехала
  /// бы оценка прокрутки по индексу.
  final double inset;

  @override
  State<SelectionOutline> createState() => _SelectionOutlineState();
}

class _SelectionOutlineState extends State<SelectionOutline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    // Уже выбранный блок (например, после перестроения при поиске или при
    // возврате строки в ленивый список) не должен перечерчиваться заново —
    // иначе список «моргает» на каждый ввод буквы и на каждой прокрутке.
    if (widget.selected) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant SelectionOutline old) {
    super.didUpdateWidget(old);
    if (widget.selected == old.selected) return;
    widget.selected ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    // ⚠️ Без этого тикер остаётся живым после снятия виджета: во Flutter это не
    // «просто утечка», а падение — SingleTickerProviderStateMixin роняет
    // «disposed with an active Ticker». Стережёт тест.
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => CustomPaint(
        painter: SelectionOutlinePainter(
          progress: Curves.easeOutCubic.transform(_c.value),
          from: scheme.primary,
          to: scheme.tertiary,
          radius: widget.radius,
          strokeWidth: widget.strokeWidth,
          inset: widget.inset,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Рамка, растущая двумя концами из левого верхнего угла в правый нижний.
class SelectionOutlinePainter extends CustomPainter {
  SelectionOutlinePainter({
    required this.progress,
    required this.from,
    required this.to,
    this.radius = 10,
    this.strokeWidth = 2,
    this.inset = 0,
  });

  /// 0 — не нарисовано ничего, 1 — замкнутая рамка.
  final double progress;
  final Color from;
  final Color to;
  final double radius;
  final double strokeWidth;
  final double inset;

  /// Куски линии, видимые при текущем [progress].
  ///
  /// Отдельный метод, а не внутренность [paint], ровно ради теста: холст
  /// проверить нечем, а так видно и что рамка идёт по всему периметру, и что
  /// оба конца стартуют из левого верхнего угла.
  List<Path> outlineSegments(Size size) {
    if (progress <= 0) return const [];
    final rect = (Offset.zero & size).deflate(inset);
    if (rect.width <= 0 || rect.height <= 0) return const [];

    // ⚠️ Путь строим РУКАМИ, а не через `addRRect`: у готового прямоугольника
    // начало обхода не гарантировано, а нам нужен ровно левый верхний угол —
    // именно из него линия должна расходиться.
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    final Path path;
    if (r < 0.01) {
      // Вырожденный случай (совсем узкий блок): дуги нулевого радиуса рисуют
      // мусор, поэтому обычный прямоугольник — его обход тоже начинается с
      // левого верхнего угла.
      path = Path()..addRect(rect);
    } else {
      path = Path()
        ..moveTo(rect.left + r, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..arcToPoint(Offset(rect.right, rect.top + r),
            radius: Radius.circular(r))
        ..lineTo(rect.right, rect.bottom - r)
        ..arcToPoint(Offset(rect.right - r, rect.bottom),
            radius: Radius.circular(r))
        ..lineTo(rect.left + r, rect.bottom)
        ..arcToPoint(Offset(rect.left, rect.bottom - r),
            radius: Radius.circular(r))
        ..lineTo(rect.left, rect.top + r)
        ..arcToPoint(Offset(rect.left + r, rect.top),
            radius: Radius.circular(r));
    }

    final metric = path.computeMetrics().first;
    final half = metric.length / 2;
    return [
      // Конец «по часовой»: верхняя грань → правая.
      metric.extractPath(0, half * progress),
      // Конец «против часовой»: левая грань → нижняя. Берём хвост пути, потому
      // что путь заканчивается там же, где начался, — в левом верхнем углу.
      metric.extractPath(metric.length - half * progress, metric.length),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final segments = outlineSegments(size);
    if (segments.isEmpty) return;
    final rect = (Offset.zero & size).deflate(inset);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      // Цвет меняется по диагонали — «из левого верхнего в правый нижний».
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [from, to],
      ).createShader(rect);

    for (final s in segments) {
      canvas.drawPath(s, paint);
    }
  }

  @override
  bool shouldRepaint(SelectionOutlinePainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.to != to ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.inset != inset;
}
