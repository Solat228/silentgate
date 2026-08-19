import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../layout/adaptive.dart';
import 'sel_text.dart';

/// Окно «что нового» после обновления.
///
/// ⚠️ РАДИ ЧЕГО ОНО ЗАВЕДЕНО. Раньше описание релиза целиком уходило в ТОСТ:
/// `AppToast.show(..., 'Доступна версия X — ' + notes)`. А `notes` — это тело
/// релиза с GitHub, то есть весь раздел changelog: тысячи символов сырого
/// markdown со звёздочками, дефисами и заголовками. На телефоне владельца
/// (снимок 19.08.2026) это заняло весь экран стеной нечитаемого текста, у
/// которой не было ни кнопки закрытия, ни возможности отказаться от показа.
/// Сообщение, которое нельзя ни прочитать, ни убрать, — хуже отсутствующего.
class UpdateNotesDialog extends StatelessWidget {
  const UpdateNotesDialog({
    super.key,
    required this.version,
    required this.notes,
    this.onDownload,
    this.onNeverShow,
  });

  final String version;
  final String notes;
  final VoidCallback? onDownload;

  /// «Больше не показывать». ⚠️ Гасит ОКНО, а не проверку обновлений: человек
  /// просил убрать всплывающее сообщение, а не остаться без новых версий.
  final VoidCallback? onNeverShow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = formatNotes(notes);

    return AlertDialog(
      title: Text(l.updateNotesTitle(version)),
      // ⚠️ ВЫСОТА ОГРАНИЧЕНА И СОДЕРЖИМОЕ ПРОКРУЧИВАЕТСЯ. Описание релиза
      // бывает на десятки строк, и без ограничения диалог упирался бы в края
      // экрана, унося кнопки за границу — ровно то, из-за чего окно и нельзя
      // было закрыть.
      // ⚠️ Ширину и высоту считает общий помощник: на телефоне запрошенные
      // 460×420 недостижимы в принципе, и настаивать на них — это и есть тот
      // диалог, у которого кнопки уезжают за край экрана.
      content: adaptiveDialogBody(
        context,
        width: 460,
        height: lines.isEmpty ? null : 420,
        child: lines.isEmpty
            ? Text(l.updateNotesEmpty)
            : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final line in lines)
                        Padding(
                          padding: EdgeInsets.only(
                            left: line.bullet ? 12 : 0,
                            top: line.heading ? 10 : 2,
                            bottom: 2,
                          ),
                          child: SelText(
                            line.bullet ? '•  ${line.text}' : line.text,
                            style: line.heading
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
      ),
      actions: [
        if (onNeverShow != null)
          TextButton(
            key: const Key('updateNotesNeverShow'),
            onPressed: () {
              onNeverShow!();
              Navigator.of(context).pop();
            },
            child: Text(l.updateNotesNeverShow),
          ),
        if (onDownload != null)
          TextButton(
            key: const Key('updateNotesDownload'),
            onPressed: onDownload,
            child: Text(l.homeDownload),
          ),
        // ⚠️ КНОПКА ЗАКРЫТИЯ ЕСТЬ ВСЕГДА, и она последняя (то есть ближайшая к
        // большому пальцу на телефоне). Её отсутствие и было главной жалобой.
        FilledButton(
          key: const Key('updateNotesClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonClose),
        ),
      ],
    );
  }

  /// Разобрать markdown в простые читаемые строки.
  ///
  /// ⚠️ ЭТО НАМЕРЕННО НЕ ПОЛНОЦЕННЫЙ ОТРИСОВЩИК MARKDOWN. Тянуть библиотеку
  /// ради описания релиза — лишняя зависимость и лишний вес; а показывать сырой
  /// текст, как было, нельзя. Нужен минимум: убрать разметку, которая мешает
  /// читать, и сохранить структуру — заголовки и списки.
  ///
  /// ⚠️ Чистая функция и `@visibleForTesting` не нужны: она публичная нарочно,
  /// её проверяют тестом отдельно от вёрстки.
  static List<NoteLine> formatNotes(String raw) {
    final out = <NoteLine>[];
    for (final rawLine in raw.split('\n')) {
      var t = rawLine.trim();
      if (t.isEmpty) continue;
      // Горизонтальные линейки в тексте только мешают.
      if (RegExp(r'^-{3,}$').hasMatch(t)) continue;

      final heading = t.startsWith('#');
      if (heading) t = t.replaceFirst(RegExp(r'^#+\s*'), '');

      final bullet = t.startsWith('- ') || t.startsWith('* ');
      if (bullet) t = t.substring(2);

      // Жирный, курсив, code и ссылки — снимаем разметку, оставляем текст.
      t = t
          .replaceAll(RegExp(r'\*\*'), '')
          .replaceAll(RegExp(r'`'), '')
          .replaceAllMapped(
              RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!);

      if (t.isEmpty) continue;
      out.add(NoteLine(text: t, bullet: bullet, heading: heading));
    }
    return out;
  }
}

/// Строка описания релиза после разбора разметки.
class NoteLine {
  final String text;
  final bool bullet;
  final bool heading;
  const NoteLine({
    required this.text,
    this.bullet = false,
    this.heading = false,
  });
}
