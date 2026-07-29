import 'package:flutter/material.dart';

import '../../core/probe/ping_result.dart';
import '../../l10n/gen/app_localizations.dart';

/// Чип с результатом пинга.
///
/// Показываем **только задержку TCP** — как и просили, никакой второй цифры
/// «через прокси». Цвет несёт итог проверки:
///   • зелёный/жёлтый/оранжевый + мс — сервер рабочий (TCP ответил и GET/HEAD прошёл);
///   • серый + мс — отвечает по TCP, но трафик не проксирует (типичный Reality-порт);
///   • «n/a» — не ответил по TCP, из проверки исключён.
class PingChip extends StatelessWidget {
  final PingResult result;
  const PingChip({super.key, required this.result});

  /// Неяркий красный для «мёртвых» серверов (n/a): не сливается с фоном, но не
  /// такой резкий, как чистый Colors.red.
  static const _dimRed = Color(0xFFCC7777);


  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    switch (result.outcome) {
      case PingOutcome.untested:
        // ⚠️ Раньше здесь была пустота, и пользователь не мог отличить «ещё не
        // проверяли» от «проверили и всё плохо». Особенно больно на Android,
        // где hysteria2 не измеряется до подключения: сервер выглядел так же,
        // как непроверенный, и казался сломанным.
        return _pill('—', Theme.of(context).disabledColor,
            tooltip: l.pingUntestedHint);
      case PingOutcome.testing:
        return const SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
      case PingOutcome.failed:
        // #12 — мёртв (не ответил по TCP): НЕЯРКИЙ красный (виден на тёмном фоне,
        // но не кричит как чистый красный).
        return _pill(l.pingNa, _dimRed, tooltip: l.pingNaTooltip);
      case PingOutcome.timeout:
        return _pill(l.pingTimeout, _dimRed, tooltip: l.pingTimeoutTooltip);
      case PingOutcome.ok:
        final ms = result.latencyMs;
        // Отвечает, но не проксирует — цифру показываем, но приглушённо.
        if (!result.working) {
          return _pill(ms != null ? l.pingMs(ms) : l.pingNoProxy,
              Colors.blueGrey,
              tooltip: l.pingNoProxyTooltip);
        }
        final color = ms == null
            ? Colors.grey
            : ms < 150
                ? Colors.green
                : ms < 300
                    ? Colors.amber
                    : Colors.orange;
        return _pill(ms != null ? l.pingMs(ms) : l.pingOk, color,
            tooltip: l.pingOkTooltip);
    }
  }

  Widget _pill(String text, Color color, {String? tooltip}) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          textDirection: TextDirection.ltr,
          style:
              TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}
