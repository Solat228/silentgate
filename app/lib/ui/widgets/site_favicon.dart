import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/net/site_favicon.dart';

/// Иконка сайта: favicon из кэша/сети, иначе — глобус. Аналог иконок приложений
/// в списке раздельного туннелирования, но для доменов.
class SiteFavicon extends StatefulWidget {
  final String domain;
  final double size;
  const SiteFavicon({super.key, required this.domain, this.size = 24});

  @override
  State<SiteFavicon> createState() => _SiteFaviconState();
}

class _SiteFaviconState extends State<SiteFavicon> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SiteFavicon old) {
    super.didUpdateWidget(old);
    if (old.domain != widget.domain) {
      _path = null;
      _load();
    }
  }

  Future<void> _load() async {
    final p = await SiteFaviconService.iconFor(widget.domain);
    if (mounted && p != null) setState(() => _path = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _path;
    if (p == null || !File(p).existsSync()) {
      return Icon(Icons.language, size: widget.size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size / 5),
      child: Image.file(
        File(p),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.language, size: widget.size),
      ),
    );
  }
}
