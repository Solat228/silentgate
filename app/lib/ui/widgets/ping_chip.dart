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

  /// Высота плашки — ОДНА на пинг и скорость.
  ///
  /// ⚠️ Число не косметическое, оно вытекает из вёрстки строки сервера.
  /// `ListTile` (dense + `VisualDensity(vertical: -2)`) зажимает `trailing` в
  /// **40 dp** и молча его НЕ растягивает: прежние плашки в 25 dp давали столбик
  /// в 52 dp, тот вылезал за пределы строки на 11 px и рисовался поверх
  /// соседних — это и есть «из-за скорости всё поплыло». Столбик обязан влезать
  /// в 40 dp целиком: 2 × [chipHeight] + [chipGap] = [columnHeight] = 38.
  static const double chipHeight = 16;

  /// Просвет между пингом и скоростью: пинг прижат к верху, скорость к низу,
  /// между ними пусто (просьба владельца).
  static const double chipGap = 6;

  /// Высота столбика «пинг + скорость». Фиксированная — иначе строка «дышит»,
  /// когда замер скорости появляется или пропадает.
  static const double columnHeight = chipHeight * 2 + chipGap;


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
        //
        // Высота — ровно [chipHeight]: кружок стоит на месте будущей плашки, и
        // когда результат появится, столбик не дёрнется.
        return Tooltip(
          message: l.pingUntestedHint,
          child: SizedBox(
            width: 22,
            height: chipHeight,
            child: Center(
              child: Container(
                width: 9,
                height: 9,
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
          width: chipHeight,
          height: chipHeight,
          child: Center(
            child: SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
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
    return '$base\n${l.pingMeasuredAt(formatMoment(context, at.toLocal()))}';
  }

  /// Время замера в формате локали. Дата дописывается, только если замер не
  /// сегодняшний, — «14:05» без даты читается как «только что», а это как раз
  /// та ошибка, ради которой строку и добавляли.
  ///
  /// Публичный: тем же форматом подписывается замер скорости ([SpeedChip]) —
  /// две разные записи одного и того же времени в соседних подсказках выглядят
  /// как разные величины.
  static String formatMoment(BuildContext context, DateTime t) {
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

  Widget _pill(String text, Color color, {String? tooltip}) =>
      _chipPill(text, color, tooltip: tooltip);
}

/// Плашка одного значения — общая для пинга и скорости, чтобы столбик из двух
/// не разъезжался по высоте и радиусам.
///
/// Компактная по просьбе владельца («обводку пинга поменьше, как и скорости»):
/// высота задана числом ([PingChip.chipHeight]), отступы и радиус вдвое меньше
/// прежних, шрифт на пункт мельче. Высота именно ЖЁСТКАЯ, а не «сколько
/// получится»: столбик из двух плашек обязан влезать в 40 dp, которые
/// `ListTile` отводит на `trailing`.
///
/// ⚠️ [FittedBox] здесь не украшение: при крупном системном шрифте (Android,
/// «Размер шрифта: максимальный») текст в 11 pt перерастает 16 dp, и вместо
/// плашки была бы жёлто-чёрная полоса переполнения. Уменьшенный текст читается,
/// сломанная строка — нет.
Widget _chipPill(String text, Color color,
    {String? tooltip, double fontSize = 11}) {
  final pill = Container(
    height: PingChip.chipHeight,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(6),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: fontSize)),
    ),
  );
  return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
}

/// Скорость скачивания через сервер — вторым этажом под плашкой пинга.
///
/// Три состояния, и они РАЗНЫЕ:
///   • замер есть — цифра в Мбит/с;
///   • замера нет, но сервер не прошёл проверку канала (или мёртв) — ПРОЧЕРК с
///     пояснением. Решение владельца дословно: «у таких серверов вместо
///     значений скорости показывай минусы или крестики с пояснением при
///     наведении». Пустое место здесь читается как «сейчас досчитается», и
///     человек ждёт того, чего не будет;
///   • замера нет и мерить можно — виджет НЕ занимает места вовсе, чтобы
///     плашка пинга встала по центру строки (тоже решение владельца).
class SpeedChip extends StatelessWidget {
  final ServerSpeed? speed;
  final PingResult ping;
  const SpeedChip({super.key, required this.speed, required this.ping});

  /// Показывает ли виджет хоть что-то. Нужен строке сервера: она решает,
  /// строить столбик или оставить пинг по центру, и решать это должен тот же
  /// код, что рисует, — иначе появится «столбик» из одного пинга и пустоты.
  static bool visible({ServerSpeed? speed, required PingResult ping}) =>
      speed != null || ping.speedBlocked;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = speed;
    if (s == null) {
      if (!ping.speedBlocked) return const SizedBox.shrink();
      return _chipPill('—', Theme.of(context).disabledColor,
          tooltip: l.speedBlockedTooltip);
    }
    // Пороги те же по смыслу, что у пинга: зелёный — комфортно смотреть видео,
    // жёлтый — терпимо, оранжевый — узко. Цифра всё равно видна, цвет лишь
    // помогает глазу пробежать список.
    final color = s.mbps >= 30
        ? Colors.green
        : s.mbps >= 10
            ? Colors.amber
            : Colors.orange;
    final value = s.mbps >= 100 ? s.mbps.toStringAsFixed(0) : s.mbps.toStringAsFixed(1);
    final at = s.measuredAt;
    final tip = [
      s.fromAutoConfig ? l.speedFromAutoConfig : l.speedTooltip,
      if (at != null) l.pingMeasuredAt(PingChip.formatMoment(context, at.toLocal())),
    ].join('\n');
    // Размер шрифта НЕ задаём: у пинга и скорости он общий (умолчание
    // `_chipPill`) — плашки читаются как пара, а не как главная и приписка.
    return _chipPill(l.autoSpeedValue(value), color, tooltip: tip);
  }
}
