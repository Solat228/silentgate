import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/platform/platform_services.dart';

/// Иконка приложения по ключу правила (#1): на Windows это путь к exe и иконка
/// берётся из его ресурсов, на Android — `packageName` и `PackageManager`.
/// Заглушка Icons.apps — пока грузится или если извлечь не удалось.
/// Загрузка платформенная и фоновая (не блокирует UI даже на недоступных путях).
class AppIcon extends StatefulWidget {
  /// Ключ приложения: путь к exe (Windows) либо packageName (Android).
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
    if (!hasPlatformServices) return;
    final icons = platform.appIcons;
    if (icons.isCached(widget.path)) {
      _png = icons.cached(widget.path);
      return;
    }
    final requested = widget.path;
    icons.load(requested).then((png) {
      // Гвард: при быстрой смене ключа не подставляем чужую иконку.
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
