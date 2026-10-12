import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'flag_text.dart';

/// Иконка «!» с всплывающим пояснением (по клику — диалог, по наведению — tooltip).
/// [title] — необязательный заголовок диалога; по умолчанию локализованный «Пояснение».
///
/// [icon]/[color] переопределяют внешний вид — нужны значкам, которые обязаны
/// НЕ выглядеть как обычное «!» (иначе их не отличить от соседних: карточка
/// уже использует это «!» и для сводки панельной маршрутизации, и для причины
/// непригодности сервера, — см. `ServerTile`).
///
/// [compact] — тугая коробка [compactSize] px без внутренних отступов: для
/// мест, где кнопка стоит В ЧУЖОЙ строке и не имеет права её растить. Такое
/// место одно — полоса плашки активного сервера на главном, куда «i» переехала
/// вместе с подменю проверок (легенду убрали решением владельца, а её строка
/// стоила 42 px — ровно те, из-за которых низ экрана обрезался на минимальном
/// окне). Обычная кнопка занимает 40 px по высоте (минимум области нажатия
/// Material) и подняла бы полосу на 12 px, съев треть выигрыша.
class InfoTooltip extends StatelessWidget {
  final String message;
  final String? title;
  final IconData icon;
  final Color? color;
  final bool compact;
  const InfoTooltip(this.message,
      {super.key,
      this.title,
      this.icon = Icons.info_outline,
      this.color,
      this.compact = false});

  /// Сторона тугой коробки в [compact]. Совпадает с кнопкой подменю проверок
  /// (`ServiceChecksMenuButton`) — они стоят рядом в одной полосе, и разная
  /// высота двух соседних кнопок читалась бы как ошибка вёрстки.
  static const double compactSize = 28;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final button = IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: compact ? 16 : 18,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints.tightFor(
              width: compactSize, height: compactSize)
          : null,
      icon: Icon(icon,
          color: color ??
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)),
      tooltip: null,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          // Заголовок/текст могут прийти с именем сервера («!» непригодности
          // держит его в title) — флаги в нём рисуем картинкой, не буквами.
          title: FlagText(title ?? l.infoDialogTitle),
          // #9 — весь текст пояснения ВЫДЕЛЯЕМЫЙ (Ctrl+C / ПКМ→копировать),
          // отдельная кнопка «копировать» не нужна.
          content: SingleChildScrollView(
            child: SelectableText.rich(
                TextSpan(children: buildFlagSpans(message)),
                contextMenuBuilder: (ctx, s) =>
                    AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: s)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: Text(l.commonGotIt),
            ),
          ],
        ),
      ),
    );
    return Tooltip(
      richMessage: flagTextSpan(message),
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 300),
      // ⚠️ `SizedBox` снаружи обязателен: `constraints` у `IconButton` задают
      // минимум/максимум самой кнопке, но область нажатия Material
      // (`tapTargetSize: padded`) всё равно растягивает её до 40 px по
      // высоте, если родитель не зажал. Тугая коробка зажимает.
      child: compact
          ? SizedBox(width: compactSize, height: compactSize, child: button)
          : button,
    );
  }
}
