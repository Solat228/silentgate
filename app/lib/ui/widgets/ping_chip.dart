import 'package:flutter/material.dart';

import '../../core/probe/ping_result.dart';
import '../../l10n/gen/app_localizations.dart';

/// Чип с результатом пинга.
///
/// Показываем **только задержку TCP** — как и просили, никакой второй цифры
/// «через прокси». Цвет несёт итог проверки канала ([PingResult.verification]):
///   • зелёный/жёлтый/оранжевый + мс — проверка ПРОШЛА (`passed`): сервер
///     ответил по TCP и запрос через него дошёл;
///   • нейтральный серый + мс — проверка идёт (`pending`) либо её не делали
///     (`notRun`): известна только достижимость;
///   • приглушённый сине-серый — проверка НЕ прошла (`failed`): порт отвечает,
///     трафик не идёт (типичный Reality-порт);
///   • «n/a» — не ответил по TCP, из проверки исключён.
///
/// ⚠️ Зелёный ставится ТОЛЬКО по факту пройденной пробы. Раньше он загорался
/// сразу после TCP — на сервере, через который не работало ничего, плашка была
/// зелёной всё время проверки. Не возвращать «оптимистичный» цвет.
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
        // ⚠️ Пустоты здесь быть не должно: пользователь не отличит «ещё не
        // проверяли» от «проверили и всё плохо». Особенно больно на Android,
        // где hysteria2 не измеряется до подключения — сервер выглядел так же,
        // как непроверенный, и казался сломанным.
        //
        // Но и длинного тире быть не должно тоже: в ряду цифр оно читается как
        // значение («прочерк» = плохо), хотя означает «данных нет». Пустой
        // кружок ровно того же размера, что и плашка с числом, не притворяется
        // результатом и не двигает вёрстку, когда результат появится.
        return Tooltip(
          message: l.pingUntestedHint,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).disabledColor, width: 1.5),
                ),
              ),
            ),
          ),
        );
      case PingOutcome.testing:
        return const SizedBox(
            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
      case PingOutcome.failed:
        // #12 — мёртв (не ответил по TCP): НЕЯРКИЙ красный (виден на тёмном фоне,
        // но не кричит как чистый красный).
        return _pill(l.pingNa, _dimRed, tooltip: _tip(context, l.pingNaTooltip));
      case PingOutcome.timeout:
        return _pill(l.pingTimeout, _dimRed,
            tooltip: _tip(context, l.pingTimeoutTooltip));
      case PingOutcome.ok:
        final ms = result.latencyMs;
        switch (result.verification) {
          case PingVerification.pending:
            // Проверка ещё идёт: число уже есть (это TCP), вердикта — нет.
            // Цвет нейтральный, иначе плашка обещала бы рабочий сервер авансом.
            return _pill(ms != null ? l.pingMs(ms) : l.pingChecking, Colors.grey,
                tooltip: _tip(context, l.pingPendingTooltip));
          case PingVerification.notRun:
            // Проверки не было вовсе (двухфазность выключена, платформа не
            // умеет, прогон отменён). Известна ТОЛЬКО достижимость — красить в
            // зелёный нельзя, но и в красный тоже: сервер ни в чём не виноват.
            return _pill(ms != null ? l.pingMs(ms) : l.pingOk, Colors.grey,
                tooltip: _tip(context, l.pingUnverifiedTooltip));
          case PingVerification.failed:
            // Отвечает, но не проксирует — цифру показываем, но приглушённо.
            return _pill(ms != null ? l.pingMs(ms) : l.pingNoProxy,
                Colors.blueGrey,
                tooltip: _tip(context, l.pingNoProxyTooltip));
          case PingVerification.passed:
            final color = ms == null
                ? Colors.grey
                : ms < 150
                    ? Colors.green
                    : ms < 300
                        ? Colors.amber
                        : Colors.orange;
            return _pill(ms != null ? l.pingMs(ms) : l.pingOk, color,
                tooltip: _tip(context, l.pingOkTooltip));
        }
    }
  }

  /// Подсказка + строка «когда мерили».
  ///
  /// ⚠️ Результат пинга переживает перезапуск приложения и внешне ничем не
  /// отличается от свежего: зелёная плашка недельной давности выглядит как
  /// проверка, сделанную минуту назад. Гасить старые результаты владелец
  /// запретил (решение по плану 1.4.1) — поэтому просто показываем время
  /// замера, чтобы человек сам понимал, насколько цифре верить.
  String _tip(BuildContext context, String base) {
    final at = result.measuredAt;
    if (at == null) return base;
    final l = AppLocalizations.of(context);
    return '$base\n${l.pingMeasuredAt(_formatMoment(context, at.toLocal()))}';
  }

  /// Время замера в формате локали. Дата дописывается, только если замер не
  /// сегодняшний, — «14:05» без даты читается как «только что», а это как раз
  /// та ошибка, ради которой строку и добавляли.
  static String _formatMoment(BuildContext context, DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    // MaterialLocalizations может не быть (виджет вне MaterialApp) — тогда
    // ручной ISO-подобный формат вместо исключения.
    final ml = Localizations.of<MaterialLocalizations>(
        context, MaterialLocalizations);
    String two(int v) => v.toString().padLeft(2, '0');
    if (ml == null) {
      final hm = '${two(t.hour)}:${two(t.minute)}';
      return sameDay ? hm : '${two(t.day)}.${two(t.month)} $hm';
    }
    final use24 = MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? true;
    final time = ml.formatTimeOfDay(TimeOfDay.fromDateTime(t),
        alwaysUse24HourFormat: use24);
    return sameDay ? time : '${ml.formatShortDate(t)} $time';
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
