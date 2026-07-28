import 'package:flutter/material.dart';

/// Текст, который можно выделить и скопировать.
///
/// ⚠️ НЕ применять внутри кликабельных строк (`ListTile` с `onTap`,
/// `SwitchListTile`, `RadioListTile`): распознаватель жестов выделения
/// выигрывает арену у `InkWell`, и строка перестаёт нажиматься. Там текст
/// оставляем обычным, а копирование даём отдельным действием в контекстном
/// меню строки.
///
/// ⚠️ Оборачивать всё приложение в `SelectionArea` тоже нельзя: она
/// перехватывает правый клик (а на нём держатся контекстные меню серверов и
/// подписки) и долгое нажатие, которое на Android означает то же меню; плюс
/// протяжка пальцем по списку начинала бы выделять текст вместо прокрутки.
///
/// Стиль контекстного меню — тот же, что у [InfoTooltip]: системный тулбар
/// с «Копировать»/«Выделить всё».
class SelText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  /// Направление текста. Для технических строк (адреса, пути, URL) ставим
  /// [TextDirection.ltr]: в ar/fa они иначе зеркалятся и читаются неверно.
  final TextDirection? textDirection;

  const SelText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.textDirection,
  });

  /// Технический текст (адрес/путь/URL/IP): всегда слева направо.
  const SelText.technical(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  }) : textDirection = TextDirection.ltr;

  @override
  Widget build(BuildContext context) => SelectableText(
        data,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        textDirection: textDirection,
        contextMenuBuilder: (ctx, state) =>
            AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
      );
}
