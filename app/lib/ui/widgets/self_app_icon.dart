import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Иконка САМОГО приложения, взятая в рантайме.
///
/// ⚠️ Намеренно не константа и не файл в assets. Владелец предупредил, что имя
/// и иконка ещё могут смениться, и зашивать их в код нельзя: иначе при
/// ребрендинге где-то останется старая картинка, и заметит это пользователь, а
/// не тест. Здесь картинка берётся у платформы — что установлено, то и
/// показывается.
///
/// Android: `PackageManager.getApplicationIcon` через канал.
/// Windows: иконка из ресурса собственного exe (механизм уже есть в
/// `engine/windows/app_icon_windows.dart`).
/// Не получилось — рисуем ничего: пустое место лучше чужого логотипа.
class SelfAppIcon extends StatefulWidget {
  const SelfAppIcon({super.key, this.size = 20});

  final double size;

  @override
  State<SelfAppIcon> createState() => _SelfAppIconState();
}

class _SelfAppIconState extends State<SelfAppIcon> {
  static const _channel = MethodChannel('lol.silentgate/device');

  /// Кэш на процесс: иконка не меняется в течение сессии, а плашка
  /// перестраивается часто (раз в секунду от счётчика трафика).
  static Uint8List? _cached;
  static bool _tried = false;

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_tried) {
      if (mounted) setState(() => _bytes = _cached);
      return;
    }
    _tried = true;
    try {
      if (Platform.isAndroid) {
        _cached = await _channel.invokeMethod<Uint8List>('appIcon');
      }
    } catch (_) {
      // Канала нет (старая сборка) или платформа не умеет — не повод падать.
    }
    if (mounted) setState(() => _bytes = _cached);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null || b.isEmpty) return SizedBox(width: widget.size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.22),
      child: Image.memory(b,
          width: widget.size, height: widget.size, filterQuality: FilterQuality.medium),
    );
  }
}
