import 'package:flutter/material.dart';

/// Векторный значок Telegram (оригинальный бумажный самолётик Telegram).
class TelegramIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const TelegramIcon({
    super.key,
    this.size = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TelegramLogoPainter(effectiveColor),
      ),
    );
  }
}

class _TelegramLogoPainter extends CustomPainter {
  final Color color;

  const _TelegramLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scaleX = w / 24.0;
    final scaleY = h / 24.0;

    final path = Path()
      ..moveTo(21.92 * scaleX, 3.64 * scaleY)
      ..cubicTo(
        21.62 * scaleX,
        3.40 * scaleY,
        21.14 * scaleX,
        3.36 * scaleY,
        20.56 * scaleX,
        3.58 * scaleY,
      )
      ..lineTo(2.68 * scaleX, 10.48 * scaleY)
      ..cubicTo(
        2.02 * scaleX,
        10.74 * scaleY,
        1.98 * scaleX,
        11.24 * scaleY,
        2.54 * scaleX,
        11.44 * scaleY,
      )
      ..lineTo(7.12 * scaleX, 12.88 * scaleY)
      ..lineTo(17.72 * scaleX, 6.20 * scaleY)
      ..cubicTo(
        18.22 * scaleX,
        5.90 * scaleY,
        18.68 * scaleX,
        6.06 * scaleY,
        18.30 * scaleX,
        6.40 * scaleY,
      )
      ..lineTo(9.72 * scaleX, 14.16 * scaleY)
      ..lineTo(9.40 * scaleX, 18.88 * scaleY)
      ..cubicTo(
        9.86 * scaleX,
        18.88 * scaleY,
        10.06 * scaleX,
        18.67 * scaleY,
        10.32 * scaleX,
        18.42 * scaleY,
      )
      ..lineTo(12.54 * scaleX, 16.26 * scaleY)
      ..lineTo(17.14 * scaleX, 19.66 * scaleY)
      ..cubicTo(
        17.98 * scaleX,
        20.13 * scaleY,
        18.59 * scaleX,
        19.89 * scaleY,
        18.80 * scaleX,
        18.90 * scaleY,
      )
      ..lineTo(21.82 * scaleX, 4.70 * scaleY)
      ..cubicTo(
        22.02 * scaleX,
        3.96 * scaleY,
        21.98 * scaleX,
        3.69 * scaleY,
        21.92 * scaleX,
        3.64 * scaleY,
      )
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TelegramLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
