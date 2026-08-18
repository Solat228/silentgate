import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/net/site_favicon.dart';

/// Как виджет достаёт путь к иконке. Подменяется ТОЛЬКО в тестах: иначе
/// проверить, что вшитый сервис не ходит в сеть, можно было бы лишь наблюдением
/// за настоящими сокетами.
typedef SiteIconResolver = Future<String?> Function(String domain,
    {required bool builtIn});

/// Иконка сайта: бренд-иконка из поставки, иначе favicon из кэша/сети, иначе —
/// глобус. Аналог иконок приложений в списке раздельного туннелирования, но для
/// доменов.
class SiteFavicon extends StatefulWidget {
  final String domain;
  final double size;

  /// Домен ВШИТ В ПРИЛОЖЕНИЕ (сервис-чипы, автонастройка), а не внесён
  /// пользователем в правила. Умолчание — `false`, то есть строгий режим:
  /// новый вызов без явного разрешения приватность не ослабит. Почему для
  /// вшитых можно иначе — в `SiteFaviconService.iconFor`.
  final bool builtIn;

  /// Только для тестов (см. [SiteIconResolver]); в приложении — null.
  final SiteIconResolver? resolver;

  const SiteFavicon({
    super.key,
    required this.domain,
    this.size = 24,
    this.builtIn = false,
    this.resolver,
  });

  @override
  State<SiteFavicon> createState() => _SiteFaviconState();
}

class _SiteFaviconState extends State<SiteFavicon> {
  /// Файл в кэше (`%APPDATA%\…\site_icons`), если иконку пришлось искать.
  String? _path;

  /// Иконка из поставки — сеть и диск не нужны вовсе.
  String? _asset;

  /// Ассет не отрисовался (не попал в сборку) — второй раз не пробуем, уходим
  /// прежним путём.
  bool _assetFailed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(SiteFavicon old) {
    super.didUpdateWidget(old);
    if (old.domain != widget.domain || old.builtIn != widget.builtIn) {
      // ⚠️ ЭТА ВЕТКА — ТА САМАЯ, ГДЕ РОЖДАЛИСЬ «ТРИ WHATSAPP ПОДРЯД».
      // Элемент списка Flutter переиспользует под другой сервис, поэтому один
      // и тот же State успевает поработать на несколько доменов подряд.
      _path = null;
      _asset = null;
      _assetFailed = false;
      _start();
    }
  }

  /// Вшитый сервис рисуется из поставки и НИКУДА не идёт; всем остальным —
  /// прежний путь через кэш и сеть.
  void _start() {
    final asset = widget.builtIn && !_assetFailed
        ? SiteFaviconService.bundledAsset(widget.domain)
        : null;
    if (asset != null) {
      _asset = asset;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    // ⚠️ СТОРОЖ АКТУАЛЬНОСТИ. Запоминаем, ЧЕЙ это запрос, до единственного
    // await: пока ответ идёт (а он идёт из сети — секунды), тот же State уже
    // может рисовать другой сервис. Прежний код проверял только `mounted` — и
    // медленный ответ соседа затирал уже нарисованную иконку. Владелец видел
    // это как «три сервиса подряд с иконкой WhatsApp».
    final domain = widget.domain;
    final builtIn = widget.builtIn;
    final resolve = widget.resolver ?? SiteFaviconService.iconFor;
    final p = await resolve(domain, builtIn: builtIn);
    if (!mounted) return;
    if (domain != widget.domain || builtIn != widget.builtIn) return;
    if (p == null) return;
    setState(() => _path = p);
  }

  /// Ассета нет в сборке (недокрученный `pubspec.yaml`) — не оставляем
  /// пользователя с глобусом, а доигрываем прежним путём.
  void _onAssetFailed() {
    if (_assetFailed) return;
    _assetFailed = true;
    // Не из build: setState во время построения кадра запрещён.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _asset = null);
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    if (asset != null) {
      return _rounded(Image.asset(
        asset,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) {
          _onAssetFailed();
          return Icon(Icons.language, size: widget.size);
        },
      ));
    }
    final p = _path;
    if (p == null || !File(p).existsSync()) {
      return Icon(Icons.language, size: widget.size);
    }
    return _rounded(Image.file(
      File(p),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.language, size: widget.size),
    ));
  }

  Widget _rounded(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.size / 5),
        child: child,
      );
}
