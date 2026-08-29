import 'package:flutter/material.dart';

import '../core/platform/log_line.dart';
import '../core/platform/log_work_counters.dart';

/// Единственное место, где разбор строки журнала встречается с темой.
///
/// ⚠️ ОТДЕЛЬНЫЙ ФАЙЛ, А НЕ МЕТОД ЭКРАНА. Разбор ([parseLogLine]) не должен
/// знать про Flutter, а раскраска — про ввод-вывод. Смешав их с экраном, оба
/// стали бы непроверяемыми без виджет-теста, а проверять надо как раз дёшево и
/// построчно.
///
/// ⚠️ КРАСИМ ПРИ ПОКАЗЕ, В ФАЙЛ НЕ ПИШЕМ НИ СИМВОЛА. Единственные операции над
/// текстом — удаление (ANSI-последовательности, «+0700» своей же зоны), замена
/// (разделители даты, скобки вокруг уровня ядра) и цвет. Отступов у строк
/// продолжения нет НАРОЧНО: отступ — это добавленные пробелы, и они уехали бы
/// в буфер обмена вместе с выделением.

/// ⚠️ ЖЁЛТЫЙ ЗАДАЁТСЯ РУКАМИ, А НЕ БЕРЁТСЯ ИЗ `ColorScheme`. Роли
/// «предупреждение» в схеме Material нет вовсе, а один и тот же жёлтый на
/// светлой теме нечитаем: на белом фоне он пропадает. Поэтому пара — тёмная
/// охра для светлой темы и светлый янтарь для тёмной; контраст к фону обеих
/// проверяется тестом `log_line_style_test.dart`.
const Color _warnOnLight = Color(0xFF8A5000);
const Color _warnOnDark = Color(0xFFFFB74D);

/// ⚠️ ЦВЕТ — НИКОГДА НЕ ЕДИНСТВЕННЫЙ ПРИЗНАК УРОВНЯ.
///
/// Дальтоник и чёрно-белый скриншот обязаны различать строки. Признаков два, и
/// оба бесплатны: (1) СЛОВО уровня остаётся в самой строке — «[ERROR]»
/// читается и без цвета; (2) насыщенность у четырёх уровней разная и
/// возрастает от `debug` к `error`.
///
/// ⚠️ Глифов («✖», «▲») здесь нет и не должно быть: это добавленные в поток
/// текста символы, и они уехали бы в выделение мышью — то есть прямо в то, что
/// владелец отправляет поддержке.
FontWeight logLevelWeight(LogSeverity s) {
  switch (s) {
    case LogSeverity.debug:
      return FontWeight.w400;
    case LogSeverity.info:
      return FontWeight.w500;
    case LogSeverity.warn:
      return FontWeight.w600;
    case LogSeverity.error:
      return FontWeight.w700;
    case LogSeverity.service:
      return FontWeight.w500;
    case LogSeverity.none:
      return FontWeight.w400;
  }
}

/// Цвет строки по уровню.
///
/// Берётся из `ColorScheme` (обе темы живые, `app.dart:81-83`), а не
/// константами: тема тёмная и светлая должны читаться обе, а хардкод цвета
/// работает ровно в одной из них.
Color logSeverityColor(LogSeverity s, ThemeData theme) {
  final cs = theme.colorScheme;
  switch (s) {
    case LogSeverity.debug:
      return cs.onSurfaceVariant;
    case LogSeverity.info:
      return cs.onSurface;
    case LogSeverity.warn:
      return theme.brightness == Brightness.dark ? _warnOnDark : _warnOnLight;
    case LogSeverity.error:
      // Владелец: «ошибки красным» — и уровень, и сам текст ошибки.
      return cs.error;
    case LogSeverity.service:
      // Границы сессий и сообщения kill switch: не ошибка, но и не рядовая
      // строка — по ним ищут, где началась сессия.
      return cs.primary;
    case LogSeverity.none:
      return cs.onSurface;
  }
}

/// Готовые объекты стиля НА ОДНУ ТЕМУ: 1 (время) + 6 (уровень) + 6
/// (сообщение) = 13 штук на всю тему.
///
/// ⚠️ ЭТО НЕ МИКРООПТИМИЗАЦИЯ, А ЛЕЧЕНИЕ РАСКЛАДКИ. Прежние `logLevelStyle` и
/// `logMessageStyle` создавали НОВЫЙ `TextStyle` на КАЖДУЮ строку, и соседние
/// спаны переставали быть одностилевыми. Замер на одном и том же тексте в
/// 1 МиБ: один общий объект стиля — 801-835 мс раскладки, свой объект на
/// строку — 1961-2005 мс. То есть свежий стиль на строку сам по себе стоит
/// ×2.4 сверх всего остального.
class _LogStyles {
  _LogStyles(this.theme)
      : time = TextStyle(color: theme.colorScheme.onSurfaceVariant),
        level = [
          for (final s in LogSeverity.values)
            TextStyle(
              color: logSeverityColor(s, theme),
              fontWeight: logLevelWeight(s),
            ),
        ],
        message = [
          for (final s in LogSeverity.values)
            TextStyle(color: logSeverityColor(s, theme)),
        ];

  final ThemeData theme;
  final TextStyle time;
  final List<TextStyle> level;
  final List<TextStyle> message;
}

_LogStyles? _cachedStyles;

/// ⚠️ КЛЮЧ КЭША — `identical(theme)`, А НЕ `brightness`. Смена seed-цвета темы
/// яркость НЕ меняет, и по яркости мы отдали бы цвета от прошлой темы —
/// устаревший цвет молча и навсегда. `ThemeData` пересоздаётся при любой смене
/// темы, так что промах по идентичности стоит одной лишней пересборки таблицы
/// (13 объектов), а не ошибки.
_LogStyles _stylesFor(ThemeData theme) {
  final cached = _cachedStyles;
  if (cached != null && identical(cached.theme, theme)) return cached;
  return _cachedStyles = _LogStyles(theme);
}

/// Метка времени — приглушённая. «Отдельная колонка времени» достигается
/// цветом и моноширинным шрифтом (метка всегда ровно 19 знаков), а НЕ
/// разметкой: колонки из пробелов уехали бы в буфер обмена.
TextStyle logTimeStyle(ThemeData theme) => _stylesFor(theme).time;

TextStyle logLevelStyle(LogSeverity s, ThemeData theme) =>
    _stylesFor(theme).level[s.index];

TextStyle logMessageStyle(LogSeverity s, ThemeData theme) =>
    _stylesFor(theme).message[s.index];

/// Плашка «Загрузка…»/«Логи пусты» — тем же спаном, чтобы у области лога был
/// ровно один вид виджета и один способ измерить её высоту.
TextSpan logPlaceholderSpan(String text, ThemeData theme) =>
    TextSpan(text: text, style: logTimeStyle(theme));

/// Собрать раскрашенный текст журнала из сплошного текста.
///
/// ⚠️ ПЛОСКИЙ ТЕКСТ СОБРАННОГО СПАНА РАВЕН ВХОДУ ПОСЛЕ СНЯТИЯ ANSI — знак в
/// знак. Для вкладки «Приложение» это значит «показано ровно то, что в
/// файле»; для вкладки «TUN» — нет, и это названо прямо: там дата
/// переставляется, а вокруг уровня синтезируются скобки ради единого вида двух
/// журналов (см. [LogLineKind]).
TextSpan buildLogSpan(String text, ThemeData theme,
        {Duration? localZoneOffset, bool coreFormat = true}) =>
    buildLogSpanForLines(text.split('\n'), theme,
        localZoneOffset: localZoneOffset, coreFormat: coreFormat);

/// То же самое, но по УЖЕ РАЗБИТЫМ строкам — так экран и хранит показанное.
///
/// ⚠️ СТОИМОСТЬ ЭТОГО ПРОХОДА ЗАДАЁТ ЗВОНЯЩИЙ, А НЕ РАЗМЕР ФАЙЛА. Экран
/// передаёт сюда ОКНО (хвост в `_windowLines` строк, `logs_screen.dart`), и в
/// этом всё лечение: кэш собранных спанов раскладку НЕ лечит — текст живого
/// лога меняется каждый тик, и `RenderParagraph` раскладывает абзац заново
/// независимо от любого кэша. Уберёте окно, посчитав разбор достаточно
/// дешёвым, — вернёте зависание на секунды (замер: 4 МиБ = 43-67 СЕКУНД на
/// раскладку одного абзаца).
///
/// Состояния между кадрами не держим НАРОЧНО — ни разобранных строк, ни
/// собранных спанов: под окном полный переразбор окна стоит единицы
/// миллисекунд, а кэш стоил бы двух самых вероятных регрессий (застывший
/// неверный разбор и разъезд кэша с текстом). Единственное, что переживает
/// вызов, — таблица стилей [_stylesFor], и она зависит только от темы.
///
/// ⚠️ ПОБОЧНЫЙ ЭФФЕКТ ОКНА, НАЗЫВАЕМ ЧЕСТНО: при срезе головы строка ошибки
/// может уехать, а её кадры стека — остаться. Верхние несколько строк окна
/// тогда серые вместо красных. Косметика, самоисправляется прокруткой данных.
TextSpan buildLogSpanForLines(List<String> lines, ThemeData theme,
    {Duration? localZoneOffset, bool coreFormat = true}) {
  final st = _stylesFor(theme);
  // ⚠️ ЗОНА — ОДИН РАЗ НА ПРОХОД. `DateTime.now().timeZoneOffset` — системный
  // вызов Windows (~3.7 мкс); на каждой строке он стоил 224-230 мс из 447 мс
  // всей стадии build на восьмимегабайтном логе, БОЛЬШЕ ПОЛОВИНЫ.
  final zone = localZoneOffset ?? currentZoneOffset();
  final spans = <InlineSpan>[];

  // ⚠️ НАСЛЕДОВАНИЕ ЦВЕТА ЖИВЁТ ЛОКАЛЬНОЙ ПЕРЕМЕННОЙ ЦИКЛА, а не полем и не
  // внутри [parseLogLine]: сама функция на одной строке в изоляции обязана
  // честно отвечать «не разобрал».
  var inherited = LogSeverity.none;
  var inheritLeft = 0;

  for (var i = 0; i < lines.length; i++) {
    final v =
        parseLogLine(lines[i], localZoneOffset: zone, coreFormat: coreFormat);
    var severity = v.severity;

    if (v.parsed) {
      inherited = severity;
      inheritLeft = maxContinuationLines;
    } else if (severity == LogSeverity.none) {
      // Продолжение записи (кадр стека) наследует цвет — но не бесконечно и
      // не от чего попало: см. [looksLikeContinuation].
      if (inheritLeft > 0 && looksLikeContinuation(v.message)) {
        severity = inherited;
        inheritLeft--;
      } else {
        inheritLeft = 0;
      }
    } else {
      // Служебная строка или наш отказ запустить ядро — своя, наследование
      // на ней обрывается.
      inheritLeft = 0;
    }

    // ⚠️ ВРЕМЯ И ЗОНА — ОДИН СПАН, А НЕ ДВА: стиль у них один и тот же, и
    // второй спан с тем же стилем — это лишний узел в раскладке абзаца
    // задаром (2.45 спана на строку вместо 2.2).
    final head = '${v.timePart}${v.zonePart}';
    if (head.isNotEmpty) {
      spans.add(TextSpan(text: head, style: st.time));
    }
    if (v.levelPart.isNotEmpty) {
      spans.add(TextSpan(text: v.levelPart, style: st.level[severity.index]));
    }
    // Перевод строки приклеивается к сообщению — лишний спан на каждую строку
    // стоил бы дороже, чем экономит.
    final tail = i == lines.length - 1 ? '' : '\n';
    final body = '${v.message}$tail';
    if (body.isNotEmpty) {
      spans.add(TextSpan(text: body, style: st.message[severity.index]));
    }
  }

  LogWorkCounters.countSpans(spans.length);
  return TextSpan(children: spans);
}
