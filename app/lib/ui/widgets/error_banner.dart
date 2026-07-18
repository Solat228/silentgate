import 'package:flutter/material.dart';

/// Баннер ошибки с автоскрытием: снизу — убывающая полоска-таймер; по истечении вызывается [onClose].
class ErrorBanner extends StatefulWidget {
  final String message;
  final VoidCallback onClose;
  final Duration duration;
  const ErrorBanner(
    this.message, {
    super.key,
    required this.onClose,
    this.duration = const Duration(seconds: 6),
  });

  @override
  State<ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<ErrorBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onClose();
      })
      ..forward();
  }

  @override
  void didUpdateWidget(covariant ErrorBanner old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.message,
                    style: TextStyle(color: scheme.onErrorContainer)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onClose,
              ),
            ]),
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => LinearProgressIndicator(
              value: 1 - _c.value,
              minHeight: 3,
              backgroundColor: Colors.transparent,
              color: scheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
