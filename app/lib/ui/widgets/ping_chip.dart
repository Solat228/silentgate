import 'package:flutter/material.dart';

import '../../core/probe/ping_result.dart';
import '../../l10n/gen/app_localizations.dart';
import 'measured_at.dart';

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

  /// Крупный вид — тот, что был ДО появления замера скорости: плашка читается
  /// с расстояния и стоит по центру строки.
  ///
  /// ⚠️ Это не украшение, а требование владельца (18.08.2026): «если серверы
  /// только пинговали — пинг большими буквами посередине». Мелкой плашка обязана
  /// быть ТОЛЬКО тогда, когда под ней стоит вторая, со скоростью: две плашки
  /// вместе обязаны влезть в 40 dp, которые `ListTile` отводит `trailing`
  /// (см. [columnHeight]). Раз второй плашки нет — экономить высоту не на чем.
  ///
  /// Умолчание — компактный вид: остальные экраны (главный, автонастройка,
  /// информация о сервере) держат пинг в одну строку с текстом, и там крупная
  /// плашка распирала бы строку. Крупный вид просит тот, кому он нужен.
  final bool large;

  const PingChip({super.key, required this.result, this.large = false});

  /// Неяркий красный для «мёртвых» серверов (n/a): не сливается с фоном, но не
  /// такой резкий, как чистый Colors.red.
  static const _dimRed = Color(0xFFCC7777);

  /// Высота КОМПАКТНОЙ плашки — той, что стоит в столбике вместе со скоростью.
  ///
  /// ⚠️ Число не косметическое, оно вытекает из вёрстки строки сервера.
  /// `ListTile` (dense + `VisualDensity(vertical: -2)`) зажимает `trailing` в
  /// **40 dp** и молча его НЕ растягивает: прежние плашки в 25 dp давали столбик
  /// в 52 dp, тот вылезал за пределы строки на 11 px и рисовался поверх
  /// соседних — это и есть «из-за скорости всё поплыло». Столбик обязан влезать
  /// в 40 dp целиком: 2 × [chipHeight] + [chipGap] = [columnHeight] = 38.
  static const double chipHeight = 16;

  /// Высота КРУПНОЙ плашки ([large]) — ровно та, что была до появления замера
  /// скорости. Влезает в [columnHeight] с запасом, поэтому строка не «дышит»,
  /// когда плашка меняет вид.
  static const double largeChipHeight = 25;

  /// Просвет между пингом и скоростью: пинг прижат к верху, скорость к низу,
  /// между ними пусто (просьба владельца).
  static const double chipGap = 6;

  /// Высота столбика «пинг + скорость». Фиксированная — иначе строка «дышит»,
  /// когда замер скорости появляется или пропадает.
  static const double columnHeight = chipHeight * 2 + chipGap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = large ? _ChipMetrics.large : _ChipMetrics.compact;
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
        // Высота — ровно высота плашки того же вида: кружок стоит на месте
        // будущей плашки, и когда результат появится, столбик не дёрнется.
        return Tooltip(
          message: l.pingUntestedHint,
          child: SizedBox(
            width: m.slotWidth,
            height: m.height,
            child: Center(
              child: Container(
                width: m.dot,
                height: m.dot,
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
        return SizedBox(
          width: m.height,
          height: m.height,
          child: Center(
            child: SizedBox(
              width: m.progress,
              height: m.progress,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case PingOutcome.failed:
        // #12 — мёртв (не ответил по TCP): НЕЯРКИЙ красный (виден на тёмном фоне,
        // но не кричит как чистый красный).
        return _pill(l.pingNa, _dimRed, m,
            tooltip: _tip(context, l.pingNaTooltip));
      case PingOutcome.timeout:
        return _pill(l.pingTimeout, _dimRed, m,
            tooltip: _tip(context, l.pingTimeoutTooltip));
      case PingOutcome.ok:
        final ms = result.latencyMs;
        switch (result.verification) {
          case PingVerification.pending:
            // Проверка ещё идёт: число уже есть (это TCP), вердикта — нет.
            // Цвет нейтральный, иначе плашка обещала бы рабочий сервер авансом.
            return _pill(
                ms != null ? l.pingMs(ms) : l.pingChecking, Colors.grey, m,
                tooltip: _tip(context, l.pingPendingTooltip));
          case PingVerification.notRun:
            // Проверки не было вовсе (двухфазность выключена, платформа не
            // умеет, прогон отменён). Известна ТОЛЬКО достижимость — красить в
            // зелёный нельзя, но и в красный тоже: сервер ни в чём не виноват.
            return _pill(ms != null ? l.pingMs(ms) : l.pingOk, Colors.grey, m,
                tooltip: _tip(context, l.pingUnverifiedTooltip));
          case PingVerification.failed:
            // Отвечает, но не проксирует — цифру показываем, но приглушённо.
            return _pill(
                ms != null ? l.pingMs(ms) : l.pingNoProxy, Colors.blueGrey, m,
                tooltip: _tip(context, l.pingNoProxyTooltip));
          case PingVerification.passed:
            final color = ms == null
                ? Colors.grey
                : ms < 150
                    ? Colors.green
                    : ms < 300
                        ? Colors.amber
                        : Colors.orange;
            return _pill(ms != null ? l.pingMs(ms) : l.pingOk, color, m,
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
  ///
  /// ⚠️ Формат — ТОЛЬКО через [measuredAtLine] (`measured_at.dart`), тот же
  /// вызов у [SpeedChip]. Пока свой формат был здесь, подсказка пинга
  /// отвечала «во сколько», а подсказка скорости — «когда»; владелец увидел
  /// это как две разные величины в соседних плашках.
  String _tip(BuildContext context, String base) {
    final at = result.measuredAt;
    if (at == null) return base;
    return '$base\n${measuredAtLine(context, at)}';
  }

  Widget _pill(String text, Color color, _ChipMetrics m, {String? tooltip}) =>
      _chipPill(text, color, tooltip: tooltip, metrics: m);
}

/// Размеры плашки. Два набора — крупный и компактный, — потому что вид плашки
/// зависит от соседа: одна плашка в строке может позволить себе прежний размер,
/// две обязаны уместиться в 40 dp вдвоём.
class _ChipMetrics {
  final double height;
  final double hPadding;
  final double radius;
  final double fontSize;

  /// Размер кружка-заглушки «ещё не проверяли» и ширина места под неё.
  final double dot;
  final double slotWidth;

  /// Размер кружка прогресса «проверяю прямо сейчас».
  final double progress;

  const _ChipMetrics({
    required this.height,
    required this.hPadding,
    required this.radius,
    required this.fontSize,
    required this.dot,
    required this.slotWidth,
    required this.progress,
  });

  /// Вид «пинг и скорость столбиком»: всё вдвое мельче прежнего, чтобы две
  /// плашки и просвет между ними влезли в отведённые `trailing` 40 dp.
  static const compact = _ChipMetrics(
    height: PingChip.chipHeight,
    hPadding: 6,
    radius: 6,
    fontSize: 11,
    dot: 9,
    slotWidth: 22,
    progress: 13,
  );

  /// Вид «пинг один» — ровно тот, что был до появления замера скорости
  /// (отступы 10/4, радиус 12, шрифт 12). Владелец просил вернуть именно его.
  static const large = _ChipMetrics(
    height: PingChip.largeChipHeight,
    hPadding: 10,
    radius: 12,
    fontSize: 12,
    dot: 10,
    slotWidth: 26,
    progress: 16,
  );
}

/// Плашка одного значения — общая для пинга и скорости, чтобы столбик из двух
/// не разъезжался по высоте и радиусам.
///
/// Высота задана ЖЁСТКО, а не «сколько получится»: столбик из двух плашек
/// обязан влезать в 40 dp, которые `ListTile` отводит на `trailing`.
///
/// ⚠️ [FittedBox] здесь не украшение: при крупном системном шрифте (Android,
/// «Размер шрифта: максимальный») текст перерастает высоту плашки, и вместо неё
/// была бы жёлто-чёрная полоса переполнения. Уменьшенный текст читается,
/// сломанная строка — нет.
Widget _chipPill(String text, Color color,
    {String? tooltip, _ChipMetrics metrics = _ChipMetrics.compact}) {
  final pill = Container(
    height: metrics.height,
    padding: EdgeInsets.symmetric(horizontal: metrics.hPadding),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(metrics.radius),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: metrics.fontSize)),
    ),
  );
  return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
}

/// Скорость скачивания через сервер — вторым этажом под плашкой пинга.
///
/// ⚠️ ПЛАШКА СУЩЕСТВУЕТ ТОЛЬКО ТАМ, ГДЕ ЗАМЕР РЕАЛЬНО БЫЛ. Поэтому [speed]
/// здесь НЕ nullable: «показать заранее» нечем, и компилятор не даст построить
/// плашку про несуществующий замер.
///
/// ⚠️ ПРОЧЕРКА «—» ЗДЕСЬ БОЛЬШЕ НЕТ, И ВОЗВРАЩАТЬ ЕГО НЕ НАДО. Раньше у
/// сервера, который не прошёл проверку канала (или мёртв), на месте скорости
/// стоял прочерк с пояснением — это было прежнее решение владельца («вместо
/// значений скорости показывай минусы с пояснением»). **18.08.2026 он его
/// ОТМЕНИЛ:** прочерков в списке оказалось большинство, они занимали место и
/// заставляли плашку пинга ужиматься в столбик у ВСЕХ строк, хотя скорость не
/// мерили ни у одной. Дословно: «убери значок проверки скорости, если он не
/// проводился».
class SpeedChip extends StatelessWidget {
  final ServerSpeed speed;
  const SpeedChip({super.key, required this.speed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = speed;
    // Пороги те же по смыслу, что у пинга: зелёный — комфортно смотреть видео,
    // жёлтый — терпимо, оранжевый — узко. Цифра всё равно видна, цвет лишь
    // помогает глазу пробежать список.
    final color = s.mbps >= 30
        ? Colors.green
        : s.mbps >= 10
            ? Colors.amber
            : Colors.orange;
    final value =
        s.mbps >= 100 ? s.mbps.toStringAsFixed(0) : s.mbps.toStringAsFixed(1);
    final at = s.measuredAt;
    // Строка «когда мерили» — тот же вызов, что у пинга: см. `measured_at.dart`.
    final tip = [
      s.fromAutoConfig ? l.speedFromAutoConfig : l.speedTooltip,
      if (at != null) measuredAtLine(context, at),
    ].join('\n');
    // Размер шрифта НЕ задаём: у пинга и скорости он общий (умолчание
    // `_chipPill`) — плашки читаются как пара, а не как главная и приписка.
    return _chipPill(l.autoSpeedValue(value), color, tooltip: tip);
  }
}
