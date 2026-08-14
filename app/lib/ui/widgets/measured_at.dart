/// «Когда это измерили» — ОДИН способ на всё приложение.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Жалоба владельца дословно: «у скорости в подсказке
/// видно, КОГДА была проверка, а у пинга — только время суток». Оба места жили
/// в `ping_chip.dart` и звали общий метод, но сам метод давал для сегодняшнего
/// замера ГОЛОЕ время («14:05»), а для вчерашнего — дату со временем. Значит
/// одна и та же подсказка отвечала то на вопрос «когда», то на вопрос «во
/// сколько» — в зависимости от того, когда мерили. Разошлись не два места, а
/// два ответа одной функции.
///
/// Поэтому здесь лежит и решение «что показать» ([momentAge]), и его
/// оформление ([measuredAtLine]). Третье место (например, экран информации о
/// сервере) обязано звать отсюда, а не форматировать своё: любая своя копия
/// снова разойдётся на первой же правке порога.
///
/// ⚠️ И `toLocal()` ТОЖЕ ЗДЕСЬ. На диске моменты лежат в UTC; забытый перевод в
/// местное время сдвигает подсказку на часовой пояс, и заметить это на своей
/// машине почти невозможно — у половины разработчиков смещение нулевое.
library;

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Что именно показать про момент.
enum MomentKind {
  /// Меньше минуты назад.
  justNow,

  /// Минуты назад — [MomentAge.value] штук.
  minutesAgo,

  /// Часы назад — [MomentAge.value] штук.
  hoursAgo,

  /// Давно: показываем ДАТУ и время, а не «во сколько».
  absolute,
}

/// Возраст момента: что показывать и с каким числом.
class MomentAge {
  final MomentKind kind;

  /// Минуты или часы — по [kind]. Для [MomentKind.justNow] и
  /// [MomentKind.absolute] всегда 0.
  final int value;
  const MomentAge(this.kind, [this.value = 0]);

  @override
  bool operator ==(Object other) =>
      other is MomentAge && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'MomentAge($kind, $value)';
}

/// Докуда считаем «недавно» и показываем относительное время.
///
/// ⚠️ ПОЧЕМУ 12 ЧАСОВ, А НЕ «СЕГОДНЯ». Замер в 23:50 в 00:10 перестал бы быть
/// «сегодняшним» и показался бы датой, хотя ему двадцать минут; а замер в 00:05
/// в 23:00 того же дня остался бы «сегодняшним» и показал бы голое время — то
/// есть ровно та ошибка, из-за которой жалоба и появилась. Половина суток —
/// граница, за которой «5 часов назад» уже не помогает («это утром или вчера
/// вечером?»), а дата помогает.
const Duration kMomentRelativeLimit = Duration(hours: 12);

/// Насколько давно был момент [t] относительно [now].
///
/// Чистая функция — её и проверяет тест: у виджета спросить «что он решил»
/// нечем, а границы порогов ошибиться проще всего.
///
/// ⚠️ Момент В БУДУЩЕМ считается свежим. Так бывает и без ошибок в коде:
/// переведённые часы, поправка времени по сети, замер, сделанный за долю
/// секунды до сравнения. «−3 минуты назад» выглядит как поломка приложения,
/// «только что» — как правда с точностью до минуты.
MomentAge momentAge(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.isNegative || d.inMinutes < 1) return const MomentAge(MomentKind.justNow);
  if (d.inMinutes < 60) return MomentAge(MomentKind.minutesAgo, d.inMinutes);
  if (d < kMomentRelativeLimit) return MomentAge(MomentKind.hoursAgo, d.inHours);
  return const MomentAge(MomentKind.absolute);
}

/// Момент [t] словами: «только что» / «5 минут назад» / «14 авг. 2026 г. 14:05».
///
/// [now] задаётся только тестом; в приложении берётся текущее время.
String formatMeasuredAt(BuildContext context, DateTime t, {DateTime? now}) {
  final local = t.toLocal();
  final l = AppLocalizations.of(context);
  final age = momentAge(local, now?.toLocal() ?? DateTime.now());
  switch (age.kind) {
    case MomentKind.justNow:
      return l.momentJustNow;
    case MomentKind.minutesAgo:
      return l.momentMinutesAgo(age.value);
    case MomentKind.hoursAgo:
      return l.momentHoursAgo(age.value);
    case MomentKind.absolute:
      return _absolute(context, local);
  }
}

/// Готовая строка подсказки: «Замер: 5 минут назад».
///
/// Именно ЕЁ зовут и пинг, и скорость — общий не только формат времени, но и
/// подпись перед ним: разойдись подписи, две соседние плашки снова читались бы
/// как разные величины.
String measuredAtLine(BuildContext context, DateTime t, {DateTime? now}) =>
    AppLocalizations.of(context)
        .pingMeasuredAt(formatMeasuredAt(context, t, now: now));

/// Дата И время. Дата обязательна: голое «14:05» и есть та самая подсказка,
/// которая отвечает «во сколько» вместо «когда».
String _absolute(BuildContext context, DateTime t) {
  // MaterialLocalizations может не быть (виджет вне MaterialApp) — тогда
  // ручной формат вместо исключения.
  final ml =
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  String two(int v) => v.toString().padLeft(2, '0');
  final manual = '${two(t.day)}.${two(t.month)}.${t.year} '
      '${two(t.hour)}:${two(t.minute)}';
  if (ml == null) return manual;
  final use24 = MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? true;
  final time = ml.formatTimeOfDay(TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: use24);
  return '${ml.formatShortDate(t)} $time';
}
