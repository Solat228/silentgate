import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/util/country_flag.dart';

/// Аватарка подписки: скачанный логотип из кэша, а если его нет (панель не отдаёт
/// картинку) — кружок с первой буквой названия. Раньше на месте отсутствующего
/// логотипа была безликая иконка-заглушка.
class SubscriptionAvatar extends StatelessWidget {
  final String? path;

  /// Название подписки — из него берётся буква для запасной аватарки.
  final String? label;
  final double size;
  const SubscriptionAvatar(
      {super.key, required this.path, this.label, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p != null && File(p).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.file(
          File(p),
          width: size,
          height: size,
          fit: BoxFit.contain,
          // Битый/недокачанный файл не должен ронять карточку — падаем на букву.
          errorBuilder: (_, __, ___) => _letter(context),
        ),
      );
    }
    return _letter(context);
  }

  Widget _letter(BuildContext context) {
    final ch = _initial(label);
    final colors = gradientFor(label);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Градиент по названию: у разных подписок разный цвет, чтобы буквы не
        // сливались в один серый ряд. У одной подписки цвет стабилен.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: ch == null
          ? Icon(Icons.workspace_premium, size: size * 0.6, color: Colors.white)
          : Text(
              ch,
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );
  }

  /// Первая буква названия без ведущих эмодзи-флагов («🇳🇱 NL» → «N»).
  static String? _initial(String? label) {
    final s = FlagUtil.strip(label ?? '').trim();
    if (s.isEmpty) return null;
    return s.characters.first.toUpperCase();
  }

  /// Детерминированная пара цветов для градиента по названию подписки.
  /// Одинаковый вход → одинаковый цвет (не «прыгает» между запусками),
  /// разные названия → заметно разные оттенки.
  static List<Color> gradientFor(String? label) {
    final s = FlagUtil.strip(label ?? '').trim();
    if (s.isEmpty) {
      return const [Color(0xFF5B6470), Color(0xFF39404A)];
    }
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    // Второй оттенок чуть смещён и темнее — получается «объёмный» градиент.
    final c1 = HSLColor.fromAHSL(1, hue, 0.55, 0.50).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 28) % 360, 0.60, 0.38).toColor();
    return [c1, c2];
  }
}
