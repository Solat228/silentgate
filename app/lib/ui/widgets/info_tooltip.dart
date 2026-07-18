import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Иконка «!» с всплывающим пояснением (по клику — диалог, по наведению — tooltip).
/// [title] — необязательный заголовок диалога; по умолчанию локализованный «Пояснение».
class InfoTooltip extends StatelessWidget {
  final String message;
  final String? title;
  const InfoTooltip(this.message, {super.key, this.title});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: message,
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 300),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: Icon(Icons.info_outline,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)),
        tooltip: null,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(title ?? l.infoDialogTitle),
            // #9 — весь текст пояснения ВЫДЕЛЯЕМЫЙ (Ctrl+C / ПКМ→копировать),
            // отдельная кнопка «копировать» не нужна.
            content: SingleChildScrollView(
              child: SelectableText(message,
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
      ),
    );
  }
}
