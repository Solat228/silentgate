import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/traffic_stats.dart';
import '../core/platform/app_log.dart';
import '../core/platform/log_line.dart';
import '../core/platform/platform_services.dart';
import '../core/platform/rotating_log.dart';
// ⚠️ Импорт остаётся РАДИ КОПИРОВАНИЯ, а не ради показа: в кадре
// `tidySingboxLog` больше не участвует (см. [_spanFor]), а на кнопке
// «Копировать» он повторяет порядок действий отчёта поддержки —
// `SensitiveAddresses.mask(tidySingboxLog(raw))`, ровно как
// `support_report.dart:266-267`. Прежняя редакция этого комментария обещала
// «ровно тот текст, что в отчёте» ещё тогда, когда маски здесь не было вовсе.
import '../core/platform/singbox_log_format.dart';
import '../core/settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/settings_controller.dart';
import 'log_line_style.dart';

/// Логи приложения и ядра — чтобы диагностировать без запуска из консоли.
///
/// «Приложение» — `%APPDATA%\SilentGate\app.log` (импорт подписки и её формат,
/// пинг, автонастройка, подключения). «TUN (sing-box)» — `singbox.log`.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  /// Хук для тестов: даёт дёрнуть ровно один цикл опроса прироста без
  /// ожидания настоящего таймера (`Timer.periodic`, созданный под
  /// `flutter_test`, живёт в поддельном времени, а опрос читает файлы по
  /// РЕАЛЬНОМУ вводу-выводу — эти два мира без явного хука не совмещаются).
  ///
  /// Настоящий экран сам ставит себя сюда в `initState` и снимает в
  /// `dispose`; звать хук можно только между этими моментами.
  @visibleForTesting
  static Future<void> Function()? debugPollOnce;

  /// Тестам: не звать `_load()` из `initState`.
  ///
  /// ⚠️ БЕЗ ЭТОГО ФЛАГА ТЕСТЫ ПАДАЛИ НЕВОСПРОИЗВОДИМО. `initState` вызывает
  /// `_load()` СРАЗУ по `pumpWidget`, то есть ДО того, как тест успевает
  /// обернуть что-либо в `runAsync`, — её чтение файлов уходит в поддельное
  /// время и НИКОГДА не завершается. Зависший `File.readAsBytes()` при этом
  /// не «ничего не делает»: он держит файл открытым на уровне ОС, и
  /// следующая же попытка теста удалить этот файл падает с «файл занят
  /// другим процессом». Тесты сами наполняют экран через [debugPollOnce].
  @visibleForTesting
  static bool debugSkipInitialLoad = false;

  /// Хук для тестов: дёрнуть ровно одну ПЕРВУЮ загрузку.
  ///
  /// ⚠️ БЕЗ НЕГО ШОВ «первый показ → первый прирост» НЕ ПРОВЕРИТЬ НИЧЕМ.
  /// `_load()` из `initState` уходит в поддельное время теста и не
  /// завершается (см. [debugSkipInitialLoad]), а именно она задаёт стартовое
  /// смещение — то самое, на котором первая новая строка когда-то
  /// приклеивалась к последней старой. Тест обязан позвать её сам, внутри
  /// `runAsync`.
  @visibleForTesting
  static Future<void> Function()? debugLoadOnce;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// ПОКАЗЫВАЕМОЕ ОКНО: хвост журнала строками, а не весь накопленный буфер.
  /// `null` — ещё не загружено (показываем «Загрузка…»).
  ///
  /// ⚠️ ЗАЧЕМ ОКНО И ПОЧЕМУ ИМЕННО ОНО ЛЕЧИТ ЭКРАН. Раньше здесь лежал один
  /// растущий `String` со ВСЕМ, что накопилось за сессию, и кадр разбирал его
  /// целиком: на восьмимегабайтном логе ядра 449-478 мс одной только стадии
  /// `build()` и 209 971 спан в ОДНОМ абзаце `SelectableText.rich`. Раскладку
  /// такого абзаца не мерил никто: 1 МиБ = 1951-2151 мс, 4 МиБ = 43-67 СЕКУНД
  /// на кадр. При опросе раз в 500 мс это зависание, а не замедление, и росло
  /// оно с каждой минутой сессии.
  ///
  /// ⚠️ РАСКЛАДКУ ЛЕЧИТ ОКНО, А НЕ ДЕШЁВЫЙ РАЗБОР. Текст живого лога меняется
  /// КАЖДЫЙ тик, и `RenderParagraph` раскладывает абзац заново независимо от
  /// любого кэша разобранных строк или собранных спанов. Уберёте окно,
  /// посчитав разбор достаточно дешёвым, — вернёте зависание.
  ///
  /// ⚠️ СТРОКАМИ, А НЕ ОДНОЙ СТРОКОЙ. Срез окна обязан быть `removeRange`, а
  /// не поиском N-го перевода строки с конца по мегабайтному буферу; заодно
  /// исчезает склейка на стыке кусков — новые строки ДОБАВЛЯЮТСЯ списком, а не
  /// приклеиваются к последней показанной.
  List<String>? _appLines;
  List<String>? _tunLines;

  /// Длина окна в символах — ведётся по длинам строк, чтобы предел по объёму
  /// не требовал прохода по всему буферу.
  int _appChars = 0;
  int _tunChars = 0;

  /// ⚠️ ЧИСЛА ОКНА НАЗВАНЫ ВЛАДЕЛЬЦЕМ 02.09.2026: **3000 строк / 384 КиБ**
  /// (выбор из трёх замеренных вариантов; было 1500 / 192 КиБ).
  ///
  /// Колено раскладки намерено: при 6 583 спанах новый и прежний путь
  /// раскладываются неотличимо (61-64 против 68-71 мс), ВЫШЕ — расходятся в
  /// десятки раз. Поэтому окно обязано оставаться под ним, и это стережёт
  /// `log_window_perf_test.dart` («спанов в абзаце — константа окна»,
  /// `lessThan(6000)`). На 3000 строках страж зелёный.
  ///
  /// ⚠️ ЗАПАС ДО КОЛЕНА ЗАМЕРЕН НА КОРПУСЕ СТРАЖА, а его строки короткие
  /// (40-60 знаков) и раскрашены небогато. Настоящий журнал уровня `debug`
  /// даёт больше спанов на строку, и там запас меньше. Поднимать окно ВЫШЕ
  /// 3000 без нового замера нельзя — за коленом кадр дорожает не вдвое, а на
  /// порядок. Живой проверки в VM на уровне `debug` эта правка ещё не прошла.
  ///
  /// Для сравнения: вкладка «TUN» открывается с [_initialTunLines] = 400
  /// строк, то есть окно режет только длинную сессию, а не первый экран.
  static const _windowLines = 3000;
  static const _windowChars = 384 * 1024;

  /// Во сколько раз окну позволено перерасти, пока человек прокрутил прочь от
  /// конца (см. [_trimWindow]).
  static const _windowPausedFactor = 2;

  /// Сколько строк лога ядра показывать при открытии экрана.
  static const _initialTunLines = 400;

  /// Байтовое смещение, докуда каждый файл уже прочитан.
  int _appOffset = 0;
  int _tunOffset = 0;

  final _appScroll = ScrollController();
  final _tunScroll = ScrollController();

  /// Слежение «за концом» лога — решение владельца 29.08.2026: пока
  /// пользователь у конца списка, новые строки сами подъезжают на глаза; стоит
  /// прокрутить прочь — их подстановка перестаёт дёргать его позицию.
  bool _appFollow = true;
  bool _tunFollow = true;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _appScroll.addListener(() => _onScroll(_appScroll, (v) => _appFollow = v));
    _tunScroll.addListener(() => _onScroll(_tunScroll, (v) => _tunFollow = v));
    LogsScreen.debugPollOnce = _pollIncrement;
    LogsScreen.debugLoadOnce = _load;
    if (!LogsScreen.debugSkipInitialLoad) _load();
    _poll = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _pollIncrement());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (identical(LogsScreen.debugPollOnce, _pollIncrement)) {
      LogsScreen.debugPollOnce = null;
    }
    if (identical(LogsScreen.debugLoadOnce, _load)) {
      LogsScreen.debugLoadOnce = null;
    }
    _appScroll.dispose();
    _tunScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// «У конца» — с запасом в несколько пикселей: пиксель-в-пиксель сравнение
  /// с плавающей точкой почти никогда не совпадает точно.
  static const _endTolerance = 24.0;

  void _onScroll(ScrollController c, void Function(bool) setFollow) {
    if (!c.hasClients) return;
    setFollow(c.position.pixels >= c.position.maxScrollExtent - _endTolerance);
  }

  /// Прыгнуть в конец там, где слежение включено — ПОСЛЕ кадра: сразу после
  /// `setState` разметка ещё не знает новой высоты контента.
  void _followIfNeeded() => _followAttempt(_followRetries);

  /// Сколько кадров ждать `ScrollController`, у которого ещё нет клиента.
  ///
  /// ⚠️ ЗАЧЕМ ПОВТОР, А НЕ ОДИН ПОСТ-КАДРОВЫЙ ВЫЗОВ. Переключение вкладки
  /// анимировано (300 мс), а `TabBarView` строит страницу, на которую только
  /// что переключились, НЕ мгновенно — её `SingleChildScrollView` получает
  /// клиента через несколько кадров после начала анимации. Один точечный
  /// `addPostFrameCallback`, поставленный в момент переключения, чаще всего
  /// стреляет РАНЬШЕ этого момента и молча ничего не делает. 20 кадров с
  /// запасом перекрывают анимацию при любой частоте кадров.
  static const _followRetries = 20;

  void _followAttempt(int retriesLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var pending = false;
      if (_appFollow) {
        if (_appScroll.hasClients) {
          _appScroll.jumpTo(_appScroll.position.maxScrollExtent);
        } else {
          pending = true;
        }
      }
      if (_tunFollow) {
        if (_tunScroll.hasClients) {
          _tunScroll.jumpTo(_tunScroll.position.maxScrollExtent);
        } else {
          pending = true;
        }
      }
      if (pending && retriesLeft > 0) _followAttempt(retriesLeft - 1);
    });
  }

  Future<void> _load() async {
    final appPath = await AppLog.filePath();
    final tunPath = await platform.tunLog.filePath();
    final app = await AppLog.dump();
    // ⚠️ МАСКА ЗДЕСЬ ОБЯЗАТЕЛЬНА, И ЭТО НЕ ДУБЛИРОВАНИЕ. Прирост
    // маскируется в `_apply`, а ПЕРВЫЙ показ идёт мимо него — и именно его
    // человек видит, открыв экран. У журнала приложения защита есть внутри
    // `AppLog.dump()`, у журнала ядра нет НИ НА ОДНОЙ платформе: и
    // `TunHelper.tailLog`, и `RotatingLog.tail` отдают файл как есть.
    // Без этой строки самые частые записи ядра — `dial tcp <адрес>:443` —
    // висели на экране с настоящими адресами узлов до тех пор, пока окно не
    // срежет голову, то есть на спокойном ядре всю сессию.
    final tun = SensitiveAddresses.mask(
        await platform.tunLog.tail(lines: _initialTunLines));
    // ⚠️ СТАРТОВОЕ СМЕЩЕНИЕ — ПО ПОСЛЕДНЕМУ ПЕРЕВОДУ СТРОКИ, А НЕ ПО
    // ДЛИНЕ ФАЙЛА. Здесь был ШОВ: `tail` кончается на `join` по переводу
    // строки, то есть БЕЗ хвостового, а длина файла — это байт ПОСЛЕ него.
    // Первый же прирост приклеивался вплотную к последней показанной строке, и
    // метка времени новой записи уезжала в середину предыдущего сообщения —
    // разбор видел ОДНУ строку вместо двух. Недописанную строку не показываем
    // вовсе: она придёт целиком следующим опросом (полсекунды).
    final appEnd = await RotatingLog.completeTailOffset(appPath);
    final tunEnd = await RotatingLog.completeTailOffset(tunPath);
    var appLen = appEnd;
    var tunLen = tunEnd;
    try {
      appLen = await File(appPath).length();
    } catch (_) {}
    try {
      tunLen = await File(tunPath).length();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _replaceLines(
          app: true, lines: _linesOf(app, dropPartialTail: appEnd < appLen));
      _appOffset = appEnd;
      _replaceLines(
          app: false, lines: _linesOf(tun, dropPartialTail: tunEnd < tunLen));
      _tunOffset = tunEnd;
      _trimWindow(app: true);
      _trimWindow(app: false);
    });
    _followIfNeeded();
  }

  /// Разложить сплошной текст в строки окна.
  ///
  /// Хвостовой перевод строки даёт пустой последний элемент — это не строка, а
  /// признак конца последней. [dropPartialTail] — выбросить ещё и последнюю
  /// строку: она недописана (файл кончается не переводом строки), и показывать
  /// её нельзя, иначе прирост приклеится к ней вторым куском той же строки.
  static List<String> _linesOf(String text, {required bool dropPartialTail}) {
    final rows = text.split('\n');
    if (rows.isNotEmpty && rows.last.isEmpty) rows.removeLast();
    if (dropPartialTail && rows.isNotEmpty) rows.removeLast();
    return rows;
  }

  static int _charsOf(List<String> lines) {
    var n = 0;
    for (final l in lines) {
      n += l.length + 1; // перевод строки между строками
    }
    return n;
  }

  /// Прирост — читает ТОЛЬКО то, что дописалось с прошлого раза
  /// ([RotatingLog.readSince]), а не файл целиком. Без этого лог ядра на
  /// уровне `debug` (сотни строк в секунду) перечитывался бы полностью на
  /// каждый тик — и подвесил бы интерфейс, а не просто нагрузил его.
  Future<void> _pollIncrement() async {
    await AppLog.flushFile();
    // ⚠️ `wholeLines: true` — НЕ КОСМЕТИКА. Чтение режет файл по байтам, и
    // кусок может оборваться посреди строки: многобайтный символ (кириллица,
    // «№») разваливается в «□» необратимо, а адрес своего узла, разрезанный
    // границей куска, не попадает под маску ниже и уезжает на экран открытым
    // (маска накладывается на каждый кусок отдельно). Обоснование целиком — у
    // самого [RotatingLog.readSince].
    final appChunk = await RotatingLog.readSince(
        await AppLog.filePath(), _appOffset,
        wholeLines: true);
    final tunChunk = await RotatingLog.readSince(
        await platform.tunLog.filePath(), _tunOffset,
        wholeLines: true);
    if (!mounted) return;
    final appChanged = appChunk.offset != _appOffset || appChunk.text.isNotEmpty;
    final tunChanged = tunChunk.offset != _tunOffset || tunChunk.text.isNotEmpty;
    if (!appChanged && !tunChanged) return; // ничего нового — не дёргаем кадр
    setState(() {
      _apply(app: true, chunk: appChunk);
      _apply(app: false, chunk: tunChunk);
    });
    _followIfNeeded();
  }

  /// ⚠️ ЕДИНСТВЕННОЕ МЕСТО, ГДЕ МЕНЯЕТСЯ ПОКАЗЫВАЕМОЕ. Строки окна,
  /// его длина в символах и байтовое смещение файла двигаются здесь — и только
  /// здесь. Второго такого места не существует: разъедься они, разъехались бы
  /// молча.
  void _apply({required bool app, required LogTailChunk chunk}) {
    final offset = app ? _appOffset : _tunOffset;
    // ⚠️ МАСКА АДРЕСОВ — НА КУСОК, ДО РАЗБОРА, И НА ОБЕИХ ВКЛАДКАХ.
    // До 30.08.2026 вкладка «TUN» не маскировалась ВООБЩЕ: реестр наполняется
    // адресами ВСЕХ узлов подписки (`app_state.dart:932`), строки ядра вида
    // `dial tcp <адрес>:443` называют боевой узел в каждой второй строке — и
    // они уезжали и на экран, и в буфер обмена открытыми, тогда как отчёт
    // поддержки те же строки маскирует (`support_report.dart:266-267`).
    // Накладывать надо на кусок целиком: разбор режет строку на части, и
    // адрес, попавший на границу частей, под маску бы уже не встал.
    final text = SensitiveAddresses.mask(chunk.text);
    // Смещение НОВОГО чтения меньше прежнего — файл обрезали или он начался
    // заново (своя кнопка «Удалить этот лог», общая чистка, ротация): текст
    // ЗАМЕНЯЕТСЯ, а не дополняется, иначе на экране осталась бы призрачная
    // хвостовая часть уже стёртого файла.
    if (chunk.offset < offset) {
      _replaceLines(app: app, lines: _linesOf(text, dropPartialTail: false));
    } else if (text.isNotEmpty) {
      // ⚠️ Кусок от [RotatingLog.readSince] с `wholeLines: true`
      // ВСЕГДА кончается переводом строки — недописанного хвоста тут не бывает.
      _appendLines(app: app, lines: _linesOf(text, dropPartialTail: false));
    }
    if (app) {
      _appOffset = chunk.offset;
    } else {
      _tunOffset = chunk.offset;
    }
    _trimWindow(app: app);
  }

  void _replaceLines({required bool app, required List<String> lines}) {
    if (app) {
      _appLines = lines;
      _appChars = _charsOf(lines);
    } else {
      _tunLines = lines;
      _tunChars = _charsOf(lines);
    }
  }

  void _appendLines({required bool app, required List<String> lines}) {
    if (lines.isEmpty) return;
    final target = (app ? _appLines : _tunLines) ?? <String>[];
    target.addAll(lines);
    final grown = _charsOf(lines);
    if (app) {
      _appLines = target;
      _appChars += grown;
    } else {
      _tunLines = target;
      _tunChars += grown;
    }
  }

  /// Срезать голову окна.
  ///
  /// ⚠️ ТОЛЬКО ЗДЕСЬ, В МЕСТЕ МУТАЦИИ СОСТОЯНИЯ, И НИКОГДА В
  /// `build()`.
  ///
  /// ⚠️ ГИСТЕРЕЗИС ОБЯЗАТЕЛЕН: режем, лишь когда переросли в ПОЛТОРА
  /// раза, и сразу до одного окна. Режь мы «всё лишнее» каждый тик — срез
  /// случался бы на каждом кадре, а `maxScrollExtent` дрожал бы вместе с ним.
  ///
  /// ⚠️ ПОКА ЧЕЛОВЕК ПРОКРУТИЛ ПРОЧЬ ОТ КОНЦА, ГОЛОВУ НЕ ТРОГАЕМ:
  /// срез сдвинул бы ровно то, что он сейчас читает. Но и расти бесконечно
  /// нельзя — на уровне `debug` пауза в прокрутке вернула бы ту самую
  /// стоимость кадра, ради которой окно и заведено. Поэтому на паузе окну
  /// позволено перерасти в [_windowPausedFactor] раза, и на этом потолке мы
  /// режем даже её. Цена названа честно: один рывок прокрутки у того, кто ушёл
  /// далеко от конца и стоит там, пока ядро говорит сотнями строк в секунду.
  void _trimWindow({required bool app}) {
    final lines = app ? _appLines : _tunLines;
    if (lines == null) return;
    final following = app ? _appFollow : _tunFollow;
    final factor = following ? 1 : _windowPausedFactor;
    final maxLines = _windowLines * factor;
    final maxChars = _windowChars * factor;
    var chars = app ? _appChars : _tunChars;
    if (lines.length * 2 <= maxLines * 3 && chars * 2 <= maxChars * 3) return;
    var drop = 0;
    while (drop < lines.length &&
        (lines.length - drop > maxLines || chars > maxChars)) {
      chars -= lines[drop].length + 1;
      drop++;
    }
    if (drop == 0) return;
    lines.removeRange(0, drop);
    if (app) {
      _appChars = chars;
    } else {
      _tunChars = chars;
    }
  }

  /// Срезать хвостовые пустые строки — для текста, уходящего в буфер обмена.
  ///
  /// ⚠️ СКАНОМ С КОНЦА, А НЕ `replaceAll(RegExp(r'\n+$'))`. Прежняя
  /// версия гоняла регулярку по ВСЕМУ буферу (до 512 КБ у нашего журнала и до
  /// мегабайтов у лога ядра); здесь работа — несколько сравнений байт.
  ///
  /// ⚠️ И 0x0D ТОЖЕ, А НЕ ТОЛЬКО 0x0A. На файле с CRLF прежняя версия
  /// оставляла после среза одинокий `\r`: «пустая» вкладка считалась
  /// непустой и вместо плашки «Логи пусты» показывала невидимый мусор.
  static String _trimTrailingNewlines(String s) {
    var end = s.length;
    while (end > 0 &&
        (s.codeUnitAt(end - 1) == 0x0a || s.codeUnitAt(end - 1) == 0x0d)) {
      end--;
    }
    return end == s.length ? s : s.substring(0, end);
  }

  /// Индекс за последней ЗНАЧАЩЕЙ строкой окна.
  ///
  /// ⚠️ ПУСТАЯ СТРОКА — ЭТО И СТРОКА ИЗ ОДНОГО `\r`. Та же ловушка CRLF,
  /// что и у [_trimTrailingNewlines]: без этого вкладка, в файле которой одни
  /// переводы строк, показывала бы невидимый мусор вместо плашки.
  static int _visibleEnd(List<String> lines) {
    var end = lines.length;
    while (end > 0 && _isBlankLine(lines[end - 1])) {
      end--;
    }
    return end;
  }

  static bool _isBlankLine(String s) {
    for (var i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) != 0x0d) return false;
    }
    return true;
  }

  /// Раскрашенный текст вкладки: пока не загружено — «Загрузка…», пусто —
  /// плашка, иначе — ОКНО, разобранное построчно.
  ///
  /// ⚠️ ЧЕСТНО ПРО ЦЕНУ (прежняя редакция этого комментария утверждала ровно
  /// обратное тому, что делал код). Кэша между кадрами здесь нет: разбор идёт
  /// КАЖДЫЙ кадр. Дёшево это не потому, что мы что-то запомнили, а потому, что
  /// разбирается ОКНО — [_windowLines] строк, — а не весь накопленный буфер.
  /// Стоимость кадра перестала зависеть и от размера файла, и от длительности
  /// сессии; сторожит это `log_window_perf_test.dart`.
  ///
  /// ⚠️ `tidySingboxLog` В КАДРЕ НЕ УЧАСТВУЕТ. Раньше он вызывался в
  /// `build()` на ВЕСЬ буфер вкладки «TUN» — split + две регулярки + join по
  /// мегабайтам на каждый кадр. Его работу делает тот же разбор, что и
  /// раскраску, за один проход ([buildLogSpanForLines] → [parseLogLine]); на
  /// кнопке «Копировать» он остался и платится один раз на нажатие.
  /// ⚠️ ПЕРВЫЙ КАДР ОТКРЫТИЯ — БЕЗ РАСКРАСКИ, И ЭТО НЕ ЭКОНОМИЯ НА СПИЧКАХ.
  ///
  /// Жалоба владельца 02.09.2026: «при открытии есть микро подвисание на
  /// секунду». Замер показал точную цену: первый кадр разбирал 3000 строк и
  /// строил 5000 спанов — и платится это ровно тогда, когда человек нажал
  /// «Логи» и смотрит на экран. Самое дорогое здесь не разбор, а РАСКЛАДКА
  /// абзаца из тысяч спанов.
  ///
  /// Теперь первый кадр показывает текст ОДНИМ спаном (разбора нет вовсе), а
  /// раскраска приезжает следующим — экран к тому моменту уже открыт, и
  /// задержка попадает туда, где её не ждут.
  ///
  /// ⚠️ Флаг взводится ОДИН РАЗ на жизнь экрана, а не на каждую вкладку: иначе
  /// переключение вкладок мигало бы серым текстом. И взводится он ИЗ `build`,
  /// а не из `initState`, потому что содержимое приезжает асинхронно — на
  /// момент `initState` показывать ещё нечего, и кадр «без раскраски» был бы
  /// потрачен на заглушку «загружаю».
  bool _colorReady = false;

  TextSpan _spanFor(List<String>? lines, String loading, String empty,
      ThemeData theme,
      {required bool coreFormat}) {
    if (lines == null) return logPlaceholderSpan(loading, theme);
    final end = _visibleEnd(lines);
    if (end == 0) return logPlaceholderSpan(empty, theme);
    final window = end == lines.length ? lines : lines.sublist(0, end);
    if (!_colorReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_colorReady) setState(() => _colorReady = true);
      });
      // Один спан: ни `parseLogLine`, ни таблицы стилей, ни перестановки
      // времени у строк ядра. Всё это придёт следующим кадром.
      return TextSpan(text: window.join('\n'));
    }
    return buildLogSpanForLines(window, theme, coreFormat: coreFormat);
  }

  /// Текст вкладки «Приложение» ДЛЯ БУФЕРА ОБМЕНА.
  ///
  /// ⚠️ В БУФЕР УХОДЯТ ДАННЫЕ, А НЕ ПОКАЗ. Владелец делится с поддержкой
  /// именно этим текстом — чаще, чем целым отчётом, — и его должно быть можно
  /// сопоставить с присланным `app.log` посимвольно и найти в нём поиском.
  /// Поэтому здесь нет ни колонок из пробелов, ни переставленных дат:
  /// единственное отличие от файла — снятые управляющие последовательности
  /// цвета, то есть УДАЛЕНИЕ мусора (ESC-байты попадают в `app.log` вместе с
  /// сырым хвостом вывода ядра, `engine_base.dart:1697`), а не добавление
  /// своего. Ровно это и есть «поддержке логи уходят нормальными, без utf
  /// приколов».
  ///
  /// ⚠️ ЧИТАЕТСЯ ИЗ ФАЙЛА, А НЕ С ЭКРАНА, И ЭТО ОБЯЗАТЕЛЬНОЕ УСЛОВИЕ
  /// ОКНА. Экран держит хвост в [_windowLines] строк; возьми копия его —
  /// поддержка молча получила бы обрезок вместо журнала, а заметить это
  /// снаружи было бы нечем. `AppLog.dump()` — тот же путь, которым журнал
  /// вкладывается в отчёт поддержки, и он же накладывает маску адресов.
  Future<String> _copyTextApp(AppLocalizations l) async {
    final body = _trimTrailingNewlines(stripAnsiSequences(await AppLog.dump()));
    return body.isEmpty ? l.logsEmpty : body;
  }

  /// Текст вкладки «TUN» для буфера обмена — ровно тот, что уходит в отчёт
  /// поддержки. Показ на экране от него отличается: там дата переставлена в
  /// наш формат ради единого вида двух вкладок, а сопоставлять с файлом надо
  /// не показ, а данные.
  ///
  /// ⚠️ ПОРЯДОК ДЕЙСТВИЙ ПОБАЙТНО ТОТ ЖЕ, ЧТО У ОТЧЁТА: маска ПОВЕРХ
  /// причёсывания, `SensitiveAddresses.mask(tidySingboxLog(raw))` — как
  /// `SupportReport.maskCoreLog` (`support_report.dart:266-267`). Разойдись
  /// они порядком — присланный кусок перестал бы совпадать с присланным
  /// отчётом, и разошлись бы они молча.
  ///
  /// ⚠️ И ТОЖЕ ИЗ ФАЙЛА: см. [_copyTextApp]. Платим за это один раз на
  /// нажатие, а не на каждый кадр.
  Future<String> _copyTextTun(AppLocalizations l) async {
    final body = _trimTrailingNewlines(
        SensitiveAddresses.mask(tidySingboxLog(await _tunFileText())));
    return body.isEmpty ? l.logsTunEmpty : body;
  }

  /// Лог ядра ЦЕЛИКОМ — как он лежит на диске.
  Future<String> _tunFileText() async {
    try {
      final f = File(await platform.tunLog.filePath());
      if (await f.exists()) {
        final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
        if (text.trim().isNotEmpty) return text;
      }
    } catch (_) {}
    // ⚠️ ЗАПАСНОЙ ПУТЬ РАДИ ANDROID. Там при пустом `singbox.log` вкладка
    // «TUN» показывает `app.log` (`platform_services_android.dart:183-189`), и
    // чтение по `filePath()` отдало бы пустоту — то есть кнопка «Копировать»
    // молча копировала бы плашку вместо того, что человек видит на экране.
    try {
      return await platform.tunLog.tail(lines: _initialTunLines);
    } catch (_) {
      return '';
    }
  }

  /// Кнопка «Копировать»: текст берётся из файла, поэтому нажатие ждёт
  /// чтения — это видимая цена того, что в буфер уходит ВЕСЬ журнал, а не
  /// показанное окно.
  Future<void> _copyFrom(Future<String> Function(AppLocalizations) text) async {
    final l = AppLocalizations.of(context);
    final body = await text(l);
    if (!mounted) return;
    _copy(body);
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';
  static String _fmtDate(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.logsTitle),
        bottom: TabBar(
          controller: _tabs,
          // ⚠️ И `_followIfNeeded()` ТОЖЕ: вкладка могла накопить строки, пока
          // была скрыта, — у её `ScrollController` ещё не было клиентов, и
          // прыжок в конец из `_pollIncrement` молча пропускался. Здесь его
          // ретраи (см. [_followAttempt]) застанут страницу, когда анимация
          // переключения её действительно построит.
          onTap: (_) {
            setState(() {});
            _followIfNeeded();
          },
          tabs: [
            Tab(text: l.logsTabApp),
            Tab(text: l.logsTabTun),
          ],
        ),
        actions: [
          // Значок + слово, видимые без наведения — решение владельца
          // 29.08.2026: подсказка по наведению на сенсорном экране (и просто
          // с непривычки) никто не видит.
          TextButton.icon(
            icon: const Icon(Icons.settings),
            label: Text(l.logsSettingsLabel),
            onPressed: _openStorage,
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(l.logsClearAllLabel),
            onPressed: _openClearAllDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _view(
            // ⚠️ ФОРМАТ ЯДРА ЗДЕСЬ НЕ РАЗБИРАЕТСЯ. В `app.log` строки
            // формата sing-box попадают ТЕЛОМ НАШЕЙ записи: `engine_base`
            // пишет «Последние строки вывода <ядро>:» и следом сам хвост
            // вывода. Разбирая их как строки ядра, показ переставлял бы в них
            // дату и синтезировал скобки — то есть переписывал бы тело чужой
            // записи (см. `coreFormat` у [parseLogLine]).
            spanOf: () => _spanFor(_appLines, l.logsLoading, l.logsEmpty, theme,
                coreFormat: false),
            controller: _appScroll,
            onCopy: () => _copyFrom(_copyTextApp),
            onDeleteCurrent: () => _deleteCurrent(app: true),
          ),
          _view(
            spanOf: () => _spanFor(
                _tunLines, l.logsLoading, l.logsTunEmpty, theme,
                coreFormat: true),
            controller: _tunScroll,
            onCopy: () => _copyFrom(_copyTextTun),
            onDeleteCurrent: () => _deleteCurrent(app: false),
          ),
        ],
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.copied(context);
  }

  /// Удалить ТОЛЬКО лог текущей вкладки — решение владельца 29.08.2026:
  /// кнопка живёт рядом с копированием, над самим логом, и не требует
  /// подтверждения (в отличие от «Очистить все логи» ниже) — человек уже
  /// смотрит именно в этот лог и явно просит стереть именно его.
  Future<void> _deleteCurrent({required bool app}) async {
    final l = AppLocalizations.of(context);
    final res = await LogMaintenance.cleanSelected(app: app, tun: !app);
    if (!mounted) return;
    setState(() {
      if (app) {
        _replaceLines(app: true, lines: <String>[]);
        _appOffset = 0;
      } else {
        _replaceLines(app: false, lines: <String>[]);
        _tunOffset = 0;
      }
    });
    AppToast.show(
      context,
      res.isEmpty
          ? l.logsNothingToClean
          : l.logsCleaned(res.files, TrafficStats.formatBytes(res.bytes)),
    );
  }

  /// Окно «сколько всё это занимает и сколько хранить».
  ///
  /// Держит СВОЁ состояние переписи (`inv`) и перечитывает её после чистки:
  /// иначе кнопка «Удалить старые сейчас» отработала бы, а цифры остались
  /// прежними — и выглядело бы, что она ничего не делает.
  Future<void> _openStorage() async {
    final l = AppLocalizations.of(context);
    final settings = context.read<SettingsController>();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        // Перепись строится ОДИН раз и пересоздаётся только после чистки:
        // считать её на каждый кадр значило бы перечитывать мегабайтные файлы
        // при каждом нажатии в диалоге.
        var inventory = LogMaintenance.inventory();
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l.logsTitle),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<LogInventory>(
                        future: inventory,
                        builder: (_, snap) {
                          final data = snap.data;
                          if (data == null) return Text(l.logsLoading);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final f in data.logs)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    l.logsFileLine(f.name,
                                        TrafficStats.formatBytes(f.bytes),
                                        f.lines),
                                    textDirection: TextDirection.ltr,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(l.logsReportsLine(data.reportCount,
                                  TrafficStats.formatBytes(data.reportBytes))),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 24),
                      Consumer<SettingsController>(
                        builder: (_, c, __) =>
                            DropdownButtonFormField<LogRetention>(
                          initialValue: c.settings.logRetention,
                          decoration:
                              InputDecoration(labelText: l.logsRetentionTitle),
                          items: [
                            for (final r in LogRetention.values)
                              DropdownMenuItem(
                                  value: r, child: Text(_retentionLabel(l, r))),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            settings.update((s) => s.copyWith(logRetention: v));
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(l.logsRetentionInfo,
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final res = await LogMaintenance.clean(
                        maxAge: settings.settings.logRetention.maxAge);
                    if (!ctx.mounted) return;
                    AppToast.show(
                      ctx,
                      res.isEmpty
                          ? l.logsNothingToClean
                          : l.logsCleaned(res.files,
                              TrafficStats.formatBytes(res.bytes)),
                    );
                    setLocal(() => inventory = LogMaintenance.inventory());
                    if (mounted) await _load();
                  },
                  child: Text(l.logsCleanNow),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.commonClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Диалог «Очистить все логи» — с ВЫБОРОМ, что именно чистить (решение
  /// владельца 29.08.2026): галочка на категорию, размер рядом, и период, за
  /// который логи накопились. Удаление — только по нажатию «Очистить»,
  /// снятая галочка категорию не трогает.
  Future<void> _openClearAllDialog() async {
    final l = AppLocalizations.of(context);
    var app = true;
    var tun = true;
    var proxy = true;
    var reports = true;
    // ⚠️ ПЕРЕПИСЬ — ДО `showDialog`, А НЕ ВНУТРИ ЕГО `builder` ЧЕРЕЗ
    // `FutureBuilder`. Каталог логов маленький, чтение — доли секунды, зато
    // диалог сразу открывается с готовыми цифрами: ни лишнего кадра
    // «Загрузка…», ни рассинхрона между нажатием кнопки и результатом.
    final data = await LogMaintenance.inventory();
    if (!mounted) return;
    final days = data.periodDays;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l.logsClearAllLabel),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: app,
                        onChanged: (v) => setLocal(() => app = v ?? false),
                        title: Text(l.logsClearOptionApp(
                            TrafficStats.formatBytes(
                                data.appLog?.bytes ?? 0))),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: tun,
                        onChanged: (v) => setLocal(() => tun = v ?? false),
                        title: Text(l.logsClearOptionTun(
                            TrafficStats.formatBytes(
                                data.tunLog?.bytes ?? 0))),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: proxy,
                        onChanged: (v) => setLocal(() => proxy = v ?? false),
                        title: Text(l.logsClearOptionProxy(
                            TrafficStats.formatBytes(data.proxyBytes))),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: reports,
                        onChanged: (v) => setLocal(() => reports = v ?? false),
                        title: Text(l.logsClearOptionReports(
                            TrafficStats.formatBytes(data.reportBytes))),
                      ),
                      if (days != null) ...[
                        const Divider(height: 24),
                        Text(
                          l.logsClearPeriod(
                            _fmtDate(data.oldest!),
                            _fmtDate(data.newest!),
                            l.logsDaysCount(days),
                          ),
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.commonCancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final res = await LogMaintenance.cleanSelected(
                      app: app,
                      tun: tun,
                      proxy: proxy,
                      reports: reports,
                    );
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    if (!mounted) return;
                    AppToast.show(
                      context,
                      res.isEmpty
                          ? l.logsNothingToClean
                          : l.logsCleaned(res.files,
                              TrafficStats.formatBytes(res.bytes)),
                    );
                    setState(() {
                      if (app) {
                        _replaceLines(app: true, lines: <String>[]);
                        _appOffset = 0;
                      }
                      if (tun) {
                        _replaceLines(app: false, lines: <String>[]);
                        _tunOffset = 0;
                      }
                    });
                  },
                  child: Text(l.logsClearConfirm),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _retentionLabel(AppLocalizations l, LogRetention r) {
    switch (r) {
      case LogRetention.day:
        return l.logsRetentionDay;
      case LogRetention.twoWeeks:
        return l.logsRetentionTwoWeeks;
      case LogRetention.month:
        return l.logsRetentionMonth;
      case LogRetention.never:
        return l.logsRetentionNever;
    }
  }

  /// Область одного лога: сам текст плюс копирование/удаление в правом
  /// верхнем углу ЭТОЙ области — решение владельца 29.08.2026: кнопки
  /// относятся к конкретному открытому логу, а не к экрану в целом.
  Widget _view({
    required TextSpan Function() spanOf,
    required ScrollController controller,
    required VoidCallback onCopy,
    required VoidCallback onDeleteCurrent,
  }) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: controller,
              child: Padding(
                padding: const EdgeInsets.only(top: 48),
                // ⚠️ `SelectableText.rich`, А НЕ ЛЕНИВЫЙ СПИСОК СТРОК —
                // и запрет этот НЕ ВЕЧНЫЙ, а куплен окном. Ленивый список
                // ломает три вещи: выделение мышью через весь лог
                // (`SelectionArea` в этом проекте уже признана неприменимой,
                // `sel_text.dart:11-14`), точность `maxScrollExtent`, на
                // которой держится слежение за концом, и тест слежения в
                // `logs_screen_test.dart`. Ради стоимости кадра он больше не
                // нужен: её сделало постоянной ОКНО ([_windowLines]).
                // Возвращаться к нему стоит ровно в одном случае — если
                // владелец потребует бесконечную прокрутку ПОКАЗА, то есть
                // видеть на экране больше окна.
                //
                // ⚠️ `Builder` — НЕ УКРАШЕНИЕ. `TabBarView` строит
                // только ту страницу, которую показывает; собери мы спан в
                // `build()` экрана — платили бы за обе вкладки, а раскладывали
                // одну. Здесь спан собирается внутри страницы, то есть ровно
                // для видимой (и обеих — на те кадры, пока идёт анимация
                // переключения).
                child: Builder(
                  builder: (context) => SelectableText.rich(
                    spanOf(),
                    textDirection: TextDirection.ltr,
                    // Цвет задан явно и здесь: `SelectableText` по умолчанию
                    // берёт цвет темы, а спаны его переопределяют — без
                    // корневого значения строки без своего цвета выглядели бы
                    // иначе, чем строки с ним.
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            // ⚠️ ОБЯЗАТЕЛЬНО `Material`, А НЕ ГОЛЫЙ `Row`. Кнопки лежат ПОВЕРХ
            // прокручиваемого текста лога — без непрозрачной подложки строки
            // лога просвечивали бы сквозь них.
            child: Material(
              elevation: 2,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l.logsCopy),
                  ),
                  TextButton.icon(
                    onPressed: onDeleteCurrent,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(l.logsDeleteCurrentLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
