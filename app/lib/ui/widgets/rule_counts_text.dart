/// Строка-сводка под заголовком списка правил.
///
/// ⚠️ ПУСТЫЕ ГРАФЫ НЕ ПИШУТСЯ. «Всего 20 · выкл 0 · блок 0» читается как
/// перечень того, чего нет, и прячет то, что есть. Остаётся только «Всего»:
/// оно отвечает на вопрос «список вообще не пуст?» даже когда всё остальное
/// по нулям.
library;

import '../../core/settings/split_tunnel_counts.dart';
import '../../l10n/gen/app_localizations.dart';

String formatRuleCounts(AppLocalizations l, RuleCounts c) {
  if (c.isEmpty) return l.splitCountEmpty;
  final parts = <String>[
    l.splitCountTotal(c.total),
    // Выключенные называем парой «вкл/выкл»: одно число без второго не даёт
    // понять, много ли выключено из общего.
    if (c.disabled > 0) ...[
      l.splitCountOn(c.enabled),
      l.splitCountOff(c.disabled),
    ],
    if (c.tunnel > 0) l.splitCountTunnel(c.tunnel),
    if (c.direct > 0) l.splitCountDirect(c.direct),
    if (c.block > 0) l.splitCountBlock(c.block),
  ];
  return parts.join(' · ');
}
