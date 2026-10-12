/// Импорт правил раздельного туннелирования из текста.
///
/// ⚠️ ЗАЧЕМ ЭТО ВЫГЛЯДИТ ИМЕННО ТАК. Главный сценарий — человек взял чужой
/// список доменов (одна строка — один домен) и хочет ДОБАВИТЬ его к своему.
/// Поэтому в диалоге большое поле, куда список вставляется целиком, а не
/// вопрос «заменить всё?» на весь импорт: замена — редкий случай и стоит
/// отдельной кнопкой.
///
/// ⚠️ РАЗБОР ИДЁТ ПРЯМО ПО ХОДУ НАБОРА. До нажатия кнопки человек видит, что
/// именно получится: сколько новых, сколько уже есть, сколько строк спорят с
/// текущими правилами и сколько не разобрано вовсе. Молчаливый импорт, который
/// «что-то сделал», здесь и был исходной жалобой.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings/split_tunnel_text.dart';
import '../../l10n/gen/app_localizations.dart';
import 'sel_text.dart';

/// Что выбрал человек. `rules` — уже готовый список, который можно класть в
/// настройки: диалог сам решил, сливать или заменять.
typedef RuleImportResult<T> = ({
  List<T> rules,
  int added,
  int overwritten,
  bool replaced,
});

class RuleImportDialog<T> extends StatefulWidget {
  final String title;

  /// Разбор текста. Ошибки разбора приходят списком строк, а не исключением:
  /// одна кривая строка не должна отменять весь список.
  final RuleTextParse<T> Function(String text) parse;

  /// Сверка разобранного с тем, что уже есть.
  final RuleMergePlan<T> Function(List<T> incoming) plan;

  /// Применение плана к текущему списку.
  final List<T> Function(RuleMergePlan<T> plan, {required bool overwrite})
      apply;

  /// Подпись правила в списке споров (домен или имя программы).
  final String Function(T rule) label;

  /// Короткое описание того, что правило делает («Туннель», «Блок»).
  final String Function(T rule) describe;

  const RuleImportDialog({
    super.key,
    required this.title,
    required this.parse,
    required this.plan,
    required this.apply,
    required this.label,
    required this.describe,
  });

  @override
  State<RuleImportDialog<T>> createState() => _RuleImportDialogState<T>();
}

class _RuleImportDialogState<T> extends State<RuleImportDialog<T>> {
  final _text = TextEditingController();
  bool _overwrite = true;

  RuleTextParse<T>? _parsed;
  RuleMergePlan<T>? _plan;

  @override
  void initState() {
    super.initState();
    _text.addListener(_reparse);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reparse() {
    final raw = _text.text;
    if (raw.trim().isEmpty) {
      setState(() {
        _parsed = null;
        _plan = null;
      });
      return;
    }
    final parsed = widget.parse(raw);
    setState(() {
      _parsed = parsed;
      _plan = widget.plan(parsed.rules);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty || !mounted) return;
    // Дописываем, а не затираем: человек мог собирать список из нескольких
    // кусков, и потерять набранное из-за второй вставки — обидно.
    final cur = _text.text;
    _text.text = cur.isEmpty ? text : '${cur.trimRight()}\n$text';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  void _add() {
    final plan = _plan;
    if (plan == null) return;
    Navigator.of(context).pop((
      rules: widget.apply(plan, overwrite: _overwrite),
      added: plan.added.length,
      overwritten: _overwrite ? plan.conflicts.length : 0,
      replaced: false,
    ));
  }

  void _replace() {
    final parsed = _parsed;
    if (parsed == null) return;
    Navigator.of(context).pop((
      rules: parsed.rules,
      added: parsed.rules.length,
      overwritten: 0,
      replaced: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parsed = _parsed;
    final plan = _plan;
    final hasText = parsed != null;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelText(l.splitImportFormatNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 8),
            // ⚠️ Поле с ограниченной высотой, а не растущее: список на тысячу
            // строк иначе выдавил бы кнопки за край экрана, и импорт стало бы
            // нечем подтвердить.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: TextField(
                controller: _text,
                autofocus: true,
                maxLines: null,
                expands: false,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: l.splitImportFieldHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.content_paste),
                label: Text(l.splitImportPasteClipboard),
                onPressed: _paste,
              ),
            ),
            if (parsed != null && plan != null) ...[
              const Divider(),
              _stats(l, theme, parsed, plan),
              if (plan.conflicts.isNotEmpty) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _overwrite,
                  onChanged: (v) => setState(() => _overwrite = v),
                  title: Text(l.splitImportOverwrite),
                  subtitle: SelText(l.splitImportOverwriteSub,
                      style: theme.textTheme.bodySmall),
                ),
                _conflictList(l, theme, plan),
              ],
              if (parsed.badLines.isNotEmpty) _badList(l, theme, parsed),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.commonCancel)),
        TextButton(
          // Замена доступна, как только есть хоть одно разобранное правило:
          // пустым текстом стереть список нельзя — это выглядело бы как
          // «импорт удалил мои правила».
          onPressed: hasText && parsed.rules.isNotEmpty ? _replace : null,
          child: Text(l.splitImportReplaceAll),
        ),
        FilledButton(
          onPressed:
              plan != null && plan.changes(overwriteConflicts: _overwrite)
                  ? _add
                  : null,
          child: Text(l.splitImportAdd),
        ),
      ],
    );
  }

  Widget _stats(AppLocalizations l, ThemeData theme, RuleTextParse<T> parsed,
      RuleMergePlan<T> plan) {
    final parts = <String>[
      l.splitImportStatNew(plan.added.length),
      if (plan.unchanged.isNotEmpty) l.splitImportStatSame(plan.unchanged.length),
      if (plan.conflicts.isNotEmpty)
        l.splitImportStatConflict(plan.conflicts.length),
      if (parsed.badLines.isNotEmpty)
        l.splitImportStatBad(parsed.badLines.length),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SelText(parts.join(' · '),
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _conflictList(
      AppLocalizations l, ThemeData theme, RuleMergePlan<T> plan) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 140),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final c in plan.conflicts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelText(
                '${widget.label(c.incoming)} — '
                '${l.splitImportConflictLine(widget.describe(c.current), widget.describe(c.incoming))}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _badList(
      AppLocalizations l, ThemeData theme, RuleTextParse<T> parsed) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelText(l.splitImportBadLinesTitle,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.error)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 90),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final line in parsed.badLines)
                  SelText(line,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
