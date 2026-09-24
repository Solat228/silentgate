import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/text_direction.dart';
import '../../core/util/country_flag.dart';

/// Сколько символов провайдерского notice-текста показывать без разворота
/// (по просьбе владельца — иначе гигантский текст растягивает плитку сервера).
/// Считаем рунами через [FlagUtil.truncateRunes] — суррогатную пару и флаг-пару
/// он не режет.
const int kNoticeTextCap = 200;

/// [InlineSpan]-représentation [text]: флаг-пары regional-indicator (Windows
/// их не рисует — показывает две буквы) заменяются на [WidgetSpan] с
/// настоящей картинкой флага (`country_flags`, тот же пакет, что у
/// [FlagCell]/[FlagUtil]). Остальной текст, включая любые другие эмодзи,
/// идёт как обычный [TextSpan] без изменений.
///
/// Флаг размером с строку текущего стиля (~1.2 em высотой, пропорция 4:3 —
/// как в `FlagCell`), по центру строки.
List<InlineSpan> buildFlagSpans(String text, {TextStyle? style}) {
  final fontSize = style?.fontSize ?? 14.0;
  final flagHeight = fontSize * 1.2;
  final flagWidth = flagHeight * 4 / 3;
  final parts = FlagUtil.splitFlagPairs(text);
  return [
    for (final p in parts)
      if (p.flagCode != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CountryFlag.fromCountryCode(p.flagCode!,
                  height: flagHeight, width: flagWidth),
            ),
          ),
        )
      else
        TextSpan(text: p.text, style: style),
  ];
}

/// Текст notice-сервера (фейковый сервер-заглушка от истёкшей подписки):
/// флаги вместо голых эмодзи-пар + ограничение длины по [kNoticeTextCap] с
/// разворотом по тапу — панель не ограничивает длину `remark`, а плитка
/// резиновой быть не должна.
///
/// ⚠️ Кнопка «Скопировать» рядом с плиткой берёт ОРИГИНАЛЬНЫЙ текст из
/// `server.remark` — не из этого виджета: обрезка и флаги только для показа.
class NoticeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const NoticeText(this.text, {super.key, this.style});

  @override
  State<NoticeText> createState() => _NoticeTextState();
}

class _NoticeTextState extends State<NoticeText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final full = widget.text;
    final truncated = FlagUtil.truncateRunes(full, kNoticeTextCap);
    final isTruncated = truncated != full;
    final shown = (_expanded || !isTruncated) ? full : '$truncated…';
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isTruncated ? () => setState(() => _expanded = !_expanded) : null,
      child: Text.rich(
        TextSpan(children: buildFlagSpans(shown, style: style)),
        style: style,
        // Направление — по ПОЛНОМУ тексту: обрезка не должна менять его,
        // иначе строка могла бы «прыгать» при разворачивании.
        textDirection: full.trim().isEmpty ? null : autoTextDirection(full),
      ),
    );
  }
}
