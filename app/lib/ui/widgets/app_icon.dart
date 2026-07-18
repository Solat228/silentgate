import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../engine/windows/app_icon_windows.dart';

/// Иконка приложения по пути к exe (#1): реальная из ресурсов файла,
/// заглушка Icons.apps — пока грузится или если извлечь не удалось.
/// Загрузка — в фоновом isolate (не блокирует UI даже на недоступных путях).
class AppIcon extends StatefulWidget {
  final String path;
  final double size;
  const AppIcon({super.key, required this.path, this.size = 28});

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppIcon old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _png = null;
      _load();
    }
  }

  void _load() {
    if (AppIconWindows.isCached(widget.path)) {
      _png = AppIconWindows.cached(widget.path);
      return;
    }
    final requested = widget.path;
    AppIconWindows.load(requested).then((png) {
      if (mounted && widget.path == requested && png != null) {
        setState(() => _png = png);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final png = _png;
    if (png == null) return Icon(Icons.apps, size: widget.size);
    return Image.memory(
      png,
      width: widget.size,
      height: widget.size,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Icon(Icons.apps, size: widget.size),
    );
  }
}
