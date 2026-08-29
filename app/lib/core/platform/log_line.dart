/// Разбор ОДНОЙ строки журнала — нашего (`app.log`) или ядра (`singbox.log`) —
/// ради КРАСИВОГО ПОКАЗА на экране логов.
///
/// ⚠️ ГЛАВНОЕ ПРАВИЛО, РАДИ КОТОРОГО ЭТОТ ФАЙЛ ОТДЕЛЬНЫЙ: РАЗБОР ТОЛЬКО ЧИТАЕТ.
/// Владелец сформулировал требование прямо: «преобразование в красивые логи
/// должно происходить не добавлением в логи пометок в текст». Поэтому здесь
/// нет и не должно появиться ни `dart:io`, ни `File`, ни записи куда бы то ни
/// было: файл, который уедет в поддержку, обязан остаться ровно таким, каким
/// его написали. Стережёт это `test/log_parser_no_io_test.dart` — он читает
/// ИСХОДНИК и падает на самом появлении такого кода, а не на его срабатывании.
///
/// ⚠️ И БЕЗ FLUTTER. Разбор не должен знать про виджеты и темы (раскраска
/// живёт в `ui/log_line_style.dart`): смешав их, оба стали бы непроверяемыми
/// без виджет-теста, а тут проверять надо как раз построчно и дёшево.
///
/// ⚠️ ОДНА ФУНКЦИЯ НА ОБА ЖУРНАЛА, а не «свой разбор на вкладку». На Android
/// во вкладку «TUN» при пустом `singbox.log` подставляется `app.log`
/// (`platform_services_android.dart:183-189`) — разбор «по вкладке» там соврал
/// бы в первый же раз.
library;

import 'log_work_counters.dart';

/// Символ ESC (0x1B) — начало любой управляющей последовательности терминала.
///
/// ⚠️ ЗАДАЁТСЯ КОДОМ, А НЕ САМИМ БАЙТОМ. Невидимый управляющий символ в
/// исходнике нельзя ни увидеть, ни сверить глазами, и он уже терялся при
/// правке (см. тот же комментарий в `singbox_log_format.dart`): цвет снимался
/// наполовину, и вместо уровня в логе был мусор.
final String _esc = String.fromCharCode(0x1b);

/// Ровно тот же шаблон, что у [tidySingboxLog] в `singbox_log_format.dart`:
/// только SGR-последовательности (те, что кончаются на «m»). Расширять его
/// здесь в одиночку нельзя — иначе два чистильщика одного формата разъедутся,
/// а согласованность их сегодня держит `log_line_parse_test.dart`.
final RegExp _ansi = RegExp('$_esc\\[[0-9;]*m');

/// Снять управляющие последовательности цвета.
///
/// Это УДАЛЕНИЕ, а не добавление: ни одного своего символа в текст не попадает.
/// Пустая работа, если ESC в строке нет, — и это частый случай.
String stripAnsiSequences(String s) =>
    s.contains(_esc) ? s.replaceAll(_ansi, '') : s;

/// Насколько строка «громкая» — по этому раскрашивается показ.
///
/// `service` — наши служебные строки в логе ядра («--- запуск …»), `none` —
/// строка, которую разобрать не удалось: цвет обычный, текст дословный.
enum LogSeverity { debug, info, warn, error, service, none }

/// Какого формата оказалась строка.
///
/// ⚠️ [LogLineKind.app] — единственный вид, у которого показ ПОБАЙТНО совпадает
/// с файлом (см. [LogLineView.text]). У [LogLineKind.core] дата переставляется
/// и вокруг уровня синтезируются скобки — там такой гарантии нет и быть не
/// может, и это надо говорить вслух, а не подразумевать.
enum LogLineKind { app, core, unparsed }

/// Разобранная строка журнала, готовая к показу.
///
/// ⚠️ ПОЛЯ ХРАНЯТ РАЗДЕЛИТЕЛИ. `timePart` — это «04.08.2026 01:23:33 » ВМЕСТЕ
/// с пробелом после, `levelPart` — «[INFO] » вместе с пробелом. Сделано ради
/// одного: [text] складывается конкатенацией без единого добавленного символа,
/// поэтому «показали ровно то, что в файле» — свойство конструкции, а не
/// обещание в комментарии.
class LogLineView {
  /// Метка времени с хвостовым разделителем, либо пусто.
  final String timePart;

  /// Смещение часового пояса с хвостовым разделителем — ТОЛЬКО если оно
  /// расходится с местным (см. [parseLogLine]), иначе пусто.
  final String zonePart;

  /// «[ERROR] » — с квадратными скобками и хвостовым разделителем, либо пусто.
  final String levelPart;

  /// Всё остальное — ДОСЛОВНО, включая пробелы и «№» из маски адресов
  /// («адрес №3:443»). Никогда не режется и не сокращается.
  final String message;

  final LogLineKind kind;
  final LogSeverity severity;

  const LogLineView({
    required this.timePart,
    required this.zonePart,
    required this.levelPart,
    required this.message,
    required this.kind,
    required this.severity,
  });

  /// Строка целиком в том виде, в каком она будет показана.
  ///
  /// Для [LogLineKind.app] и [LogLineKind.unparsed] это ровно
  /// `stripAnsiSequences(исходная строка)` — знак в знак.
  String get text => '$timePart$zonePart$levelPart$message';

  bool get parsed => kind != LogLineKind.unparsed;
}

/// Местное смещение часового пояса — ⚠️ ЕДИНСТВЕННОЕ МЕСТО, ГДЕ ПОКАЗ
/// СПРАШИВАЕТ СИСТЕМУ, и спрашивать её на каждой строке нельзя.
///
/// `DateTime.now().timeZoneOffset` — системный вызов Windows ценой ~3.7 мкс.
/// На восьмимегабайтном логе ядра это ~54 500 вызовов и 224-230 мс из 447 мс
/// всей стадии `build()` — БОЛЬШЕ ПОЛОВИНЫ. Поэтому проход разбора считает
/// смещение ОДИН раз и передаёт его в [parseLogLine] параметром
/// `localZoneOffset` (см. `buildLogSpanForLines`), а сама функция остаётся
/// честной и на одиночном вызове.
Duration currentZoneOffset() {
  LogWorkCounters.countZoneLookup();
  return DateTime.now().timeZoneOffset;
}

/// Формат нашего журнала: `04.08.2026 01:23:33 [INFO] сообщение`.
///
/// ⚠️ УРОВЕНЬ — ЗАКРЫТЫМ СПИСКОМ ИЗ ЧЕТЫРЁХ ЗНАЧЕНИЙ (`enum LogLevel`,
/// `app_log.dart:13`), а не `\w+`: иначе чужая строка вида `… [OK] …`
/// притворилась бы нашей записью.
///
/// Сообщение забирается ОДНИМ куском до конца строки и больше ничем не
/// режется: в нём штатно живут пробелы и не-ASCII — маска адресов подставляет
/// «адрес №3:443» (`app_log.dart:791`), и разбор «по пробелам» ломался бы
/// именно на самых частых строках отчёта.
final RegExp _appRe = RegExp(
    r'^(\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}) '
    r'(\[(?:DEBUG|INFO|WARN|ERROR)\])(.*)$');

/// Формат ядра sing-box.
///
/// ⚠️ СМЕЩЕНИЕ ЗОНЫ ЛОВИМ И ДО МЕТКИ, И ПОСЛЕ. Само ядро печатает его ПЕРЕД
/// датой («+0700 2026-08-11 02:09:08 INFO …»), а уже причёсанный
/// [tidySingboxLog] текст несёт его ПОСЛЕ. Функция обязана работать на обоих:
/// экран читает сырой файл, а отчёт поддержки — причёсанный.
///
/// Уровней у ядра больше четырёх; сводим их к нашим (см. `_coreSeverity`).
final RegExp _coreRe = RegExp(r'^(?:([+-]\d{4})\s+)?'
    r'(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2}:\d{2})'
    r'(?:\s+([+-]\d{4}))?'
    r'\s+(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|PANIC)(?: (.*))?$');

/// Наши служебные строки в логе ядра — границы сессий, сообщения kill switch.
const String _servicePrefix = '--- ';

/// ⚠️ ДВЕ ВАЖНЕЙШИЕ СТРОКИ ЛОГА ЯДРА ПРЕФИКСА «--- » НЕ ИМЕЮТ.
///
/// Это ровно те строки, которые объясняют, почему ядро не поднялось, — они
/// обязаны краснеть, а не теряться среди обычных. Литералы здесь ТОЧНЫЕ и
/// продублированы намеренно: писатель (`tun_helper.dart:224-225` и `:240`)
/// не должен зависеть от разборщика — иначе получилось бы, что запись лога
/// знает про его показ, а это ровно то, чего задача запрещает.
///
/// ⚠️ ПЕРЕИМЕНУЮТ ИХ ТАМ — ЗДЕСЬ ОНИ МОЛЧА ПЕРЕСТАНУТ КРАСНЕТЬ. Поэтому
/// совпадение стережёт `test/log_parser_no_io_test.dart`: он читает исходник
/// `tun_helper.dart` и падает, если этих подстрок в нём больше нет.
const List<String> tunHelperFailurePrefixes = [
  'НЕ ЗАПУСКАЮ ЯДРО',
  'НЕ УДАЛОСЬ ЗАПУСТИТЬ',
];

/// Разобрать строку журнала.
///
/// Ответ всегда один из двух: «разобрал» (время, уровень и сообщение дословно)
/// либо «не разобрал» ([LogLineView.parsed] `== false`) — и тогда сообщение
/// равно ВСЕЙ строке, дословно, без обрезки. Неразобранная строка никогда не
/// прячется: так выглядят кадры стека `shortStack`, наши строки в третьем
/// формате времени («--- запуск прокси-ядра 2026-08-11T02:09:10.184221»),
/// строки прошлых версий и второй копии приложения, вывод харнесса вообще без
/// метки времени и обрывок, оставшийся от чтения по байтам.
///
/// [localZoneOffset] — местное смещение, с которым сверяется смещение из
/// строки ядра; по умолчанию берётся у системы. ⚠️ Параметр существует не
/// только ради ТЕСТОВ (без него проверка «+0700 не показывается» проходила бы
/// только на машине, которая сама живёт в +0700), но и ради ЦЕНЫ: проход по
/// логу обязан спросить систему один раз, а не на каждой строке (см.
/// [currentZoneOffset]).
///
/// [coreFormat] — разбирать ли формат sing-box. ⚠️ ДЛЯ ВКЛАДКИ «ПРИЛОЖЕНИЕ»
/// ЕГО ВЫКЛЮЧАЮТ, и вот почему. Строки формата ядра попадают в `app.log`
/// ТЕЛОМ НАШЕЙ ЗАПИСИ: `engine_base.dart:1698` пишет
/// `AppLog.e('Последние строки вывода <ядро>:' + перевод строки + хвост)` —
/// и весь хвост вывода ядра ложится в журнал телом одной нашей записи. Разобрав его как
/// «строку ядра», показ переставлял бы в НЕЙ дату и синтезировал скобки —
/// то есть переписывал бы тело чужой записи. На вкладке «TUN» флаг остаётся
/// включённым: там строки ядра — самостоятельные записи (и на Android туда же
/// подставляется `app.log`, поэтому наш формат разбирается всегда).
///
/// ⚠️ ЧЕГО ЭТА ФУНКЦИЯ НЕ ДЕЛАЕТ: не сортирует, не дедуплицирует и не
/// группирует по времени. Метка локальная, без миллисекунд, `fatalSync` пишет
/// мимо очереди (`app_log.dart:94-104`), два события в одну секунду — обычное
/// дело; любая логика «по возрастанию времени» врала бы.
LogLineView parseLogLine(String raw,
    {Duration? localZoneOffset, bool coreFormat = true}) {
  LogWorkCounters.countParsedLine(raw.length);
  final s = stripAnsiSequences(raw);

  // Наши служебные строки — до всяких регулярок: их формат не похож ни на
  // один из двух, а покрасить их надо.
  if (s.startsWith(_servicePrefix)) return _plain(s, LogSeverity.service);
  for (final p in tunHelperFailurePrefixes) {
    if (s.startsWith(p)) return _plain(s, LogSeverity.error);
  }

  // ⚠️ ДЕШЁВАЯ ОТБРАКОВКА ДО РЕГУЛЯРОК. Кадры стека («#3 main …»), хвост
  // «  … ещё 4 строк» и просто мусор не должны платить за две якорные
  // регулярки: их в живом логе больше, чем разбираемых строк.
  //
  // ⚠️ УСЛОВИЕ — ПО ПЕРВОМУ СИМВОЛУ, А НЕ ПО ИНДЕКСАМ 2 И 4. Сырая строка
  // ядра начинается со смещения зоны («+0700 2026-08-11 …»), и проверка вида
  // «на позиции 2 точка, на позиции 4 дефис» отбраковала бы САМУЮ ЧАСТУЮ
  // строку вкладки «TUN» — весь разбор формата ядра стал бы мёртвым кодом,
  // причём молча.
  if (s.length < 20) return _plain(s, LogSeverity.none);
  final c = s.codeUnitAt(0);
  final startsRight =
      (c >= 0x30 && c <= 0x39) || c == 0x2B /* + */ || c == 0x2D /* - */;
  if (!startsRight) return _plain(s, LogSeverity.none);

  final app = _appRe.firstMatch(s);
  if (app != null) return _fromApp(s, app);

  if (coreFormat) {
    final core = _coreRe.firstMatch(s);
    if (core != null) return _fromCore(s, core, localZoneOffset);
  }

  return _plain(s, LogSeverity.none);
}

LogLineView _plain(String s, LogSeverity severity) => LogLineView(
      timePart: '',
      zonePart: '',
      levelPart: '',
      message: s,
      kind: LogLineKind.unparsed,
      severity: severity,
    );

/// ⚠️ РЕЖЕМ ИСХОДНУЮ СТРОКУ ПО ИНДЕКСАМ, А НЕ СКЛЕИВАЕМ ИЗ ГРУПП. Куски
/// показанной строки тогда физически ЯВЛЯЮТСЯ кусками файла, и вставить в
/// показ лишний пробел или скобку становится нельзя даже по невнимательности.
LogLineView _fromApp(String s, RegExpMatch m) {
  // Шаблон привязан к началу строки якорем `^`, между группами стоит РОВНО
  // один литеральный пробел — поэтому смещения кусков считаются по длинам
  // групп, и складывать их обратно не приходится.
  final levelStart = m[1]!.length + 1;
  final levelEnd = levelStart + m[2]!.length;
  final rest = m[3]!;
  // Пробел после «]» отдаём уровню — тогда сумма кусков равна строке.
  final levelLen = (levelEnd - levelStart) + (rest.startsWith(' ') ? 1 : 0);
  final word = s.substring(levelStart + 1, levelEnd - 1);
  return LogLineView(
    timePart: s.substring(0, levelStart),
    zonePart: '',
    levelPart: s.substring(levelStart, levelStart + levelLen),
    message: s.substring(levelStart + levelLen),
    kind: LogLineKind.app,
    severity: _appSeverity(word),
  );
}

LogLineView _fromCore(String s, RegExpMatch m, Duration? localZoneOffset) {
  final zone = m[1] ?? m[6];
  final year = m[2]!;
  final month = m[3]!;
  final day = m[4]!;
  final time = m[5]!;
  final word = m[7]!;
  final message = m[8] ?? '';

  // ⚠️ ПЕРЕСТАНОВКА ЦИФРОВЫХ ПОДСТРОК, А НЕ `DateTime.parse`. Разбор в
  // `DateTime` с последующим форматированием сдвинул бы время ядра
  // относительно нашего на величину смещения — и два соседних журнала
  // разъехались бы по-настоящему, а не только на вид.
  final stamp = '$day.$month.$year $time';

  // ⚠️ «+0700» ПО УМОЛЧАНИЮ НЕ ПОКАЗЫВАЕМ: это и есть то самое «чё за +700»,
  // о которое споткнулся владелец, и оно всегда равно зоне его же машины.
  // Но молча выбрасывать РАСХОДЯЩЕЕСЯ смещение нельзя (лог остался от сессии
  // до перевода часов) — тогда время в строке врало бы на часы.
  var zonePart = '';
  if (zone != null &&
      zone != formatZoneOffset(localZoneOffset ?? currentZoneOffset())) {
    zonePart = '$zone ';
  }

  return LogLineView(
    timePart: '$stamp ',
    zonePart: zonePart,
    // ⚠️ СКОБКИ СИНТЕЗИРУЮТСЯ — именно здесь показ ядра перестаёт совпадать с
    // файлом побайтно, и это осознанная цена единого вида двух вкладок.
    levelPart: '[${_coreCanonicalWord(word)}] ',
    message: message,
    kind: LogLineKind.core,
    severity: _coreSeverity(word),
  );
}

LogSeverity _appSeverity(String word) {
  switch (word) {
    case 'DEBUG':
      return LogSeverity.debug;
    case 'WARN':
      return LogSeverity.warn;
    case 'ERROR':
      return LogSeverity.error;
    default:
      return LogSeverity.info;
  }
}

/// Уровни ядра сводятся к нашей четвёрке: у нас их ровно столько, и вкладки
/// должны читаться как один источник.
LogSeverity _coreSeverity(String word) {
  switch (word) {
    case 'TRACE':
    case 'DEBUG':
      return LogSeverity.debug;
    case 'WARN':
    case 'WARNING':
      return LogSeverity.warn;
    case 'ERROR':
    case 'FATAL':
    case 'PANIC':
      return LogSeverity.error;
    default:
      return LogSeverity.info;
  }
}

String _coreCanonicalWord(String word) {
  switch (_coreSeverity(word)) {
    case LogSeverity.debug:
      return 'DEBUG';
    case LogSeverity.warn:
      return 'WARN';
    case LogSeverity.error:
      return 'ERROR';
    default:
      return 'INFO';
  }
}

String _two(int v) => v < 10 ? '0$v' : '$v';

/// Смещение зоны в том виде, в каком его печатает sing-box: «+0700», «-0500».
///
/// Открыто наружу ради тестов: фикстуру лога ядра надо собирать с МЕСТНЫМ
/// смещением машины, иначе тест «зона не показывается» зелен только в одном
/// часовом поясе.
String formatZoneOffset(Duration offset) {
  final total = offset.inMinutes;
  final sign = total < 0 ? '-' : '+';
  final abs = total.abs();
  return '$sign${_two(abs ~/ 60)}${_two(abs % 60)}';
}

/// Похожа ли неразобранная строка на ПРОДОЛЖЕНИЕ предыдущей записи.
///
/// Кадры стека (`#3 main …`) и хвост `  … ещё 4 строк` — части одной записи
/// `AppLog.shortStack`, и читаться они должны как одна запись, а не как
/// двенадцать сирот.
///
/// ⚠️ ПРОВЕРКА ОБЯЗАТЕЛЬНА, А НЕ «наследуем всё подряд». В `app.log` пишет и
/// ВТОРАЯ копия приложения (`support_report.dart:107-110`), в `singbox.log` на
/// Android — два независимых писателя. Чужая строка, легшая сразу за нашей
/// ошибкой, покрасилась бы красной и прочиталась как кадр её стека: мусор не
/// потерян, но приписан чужому событию — а это хуже, чем серый цвет.
bool looksLikeContinuation(String line) {
  if (line.isEmpty) return false;
  final c = line.codeUnitAt(0);
  if (c == 0x23 /* # */ || c == 0x20 /* пробел */ || c == 0x09 /* таб */) {
    return true;
  }
  return line.startsWith('at ');
}

/// Предел наследования цвета — 12 кадров `shortStack` плюс строка «… ещё N».
const int maxContinuationLines = 16;
