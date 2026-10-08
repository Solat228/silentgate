import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32/win32.dart';

import '../../core/platform/app_log.dart';

/// Чем кончился запуск с правами администратора.
///
/// ⚠️ РАЗЛИЧИЕ НЕ КОСМЕТИЧЕСКОЕ. Раньше всё это было одним `false`, и
/// интерфейс на любой отказ писал «UAC отклонён» — в том числе когда UAC не
/// спрашивался вовсе, а падала сама команда. Человек искал беду в правах.
enum ElevationOutcome {
  /// Запуск состоялся (а при ожидании — команда завершилась с кодом 0).
  ok,

  /// Права не получены: отказ в окне UAC, запрет политикой или таймаут.
  denied,

  /// Права были, команда запустилась и завершилась с ошибкой.
  commandFailed,
}

/// Запуск процесса с правами администратора.
///
/// `dart:io` Process.start возвышать не умеет, поэтому в общем случае идём
/// через `ShellExecuteEx("runas")` — это и есть запрос UAC.
class Elevation {
  /// Уже возвышен ли САМ процесс приложения.
  ///
  /// Проверяется один раз: в пределах жизни процесса значение не меняется.
  static bool? _elevatedCache;

  static bool get isElevated => _elevatedCache ??= _checkElevated();

  static bool _checkElevated() {
    final pToken = calloc<HANDLE>();
    final pElev = calloc<Uint32>();
    final pLen = calloc<Uint32>();
    try {
      if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, pToken) == 0) {
        return false;
      }
      try {
        // TokenElevation = 20; ненулевое значение = процесс возвышен.
        final ok = GetTokenInformation(
            pToken.value, TOKEN_INFORMATION_CLASS.TokenElevation,
            pElev.cast(), sizeOf<Uint32>(), pLen);
        return ok != 0 && pElev.value != 0;
      } finally {
        CloseHandle(pToken.value);
      }
    } catch (_) {
      return false;
    } finally {
      calloc.free(pToken);
      calloc.free(pElev);
      calloc.free(pLen);
    }
  }

  /// Запустить процесс с правами администратора, не морозя приложение.
  ///
  /// Возвращает true, если запуск состоялся.
  ///
  /// ⚠️ ДВА РАЗНЫХ ПУТИ, и это не оптимизация, а лечение живого дефекта.
  ///
  /// 1. Если приложение УЖЕ возвышено, `ShellExecuteEx` не нужен вовсе:
  ///    дочерний процесс и так унаследует права. Здесь берётся обычный
  ///    `Process.start` — без оболочки, без службы AppInfo, без брокера UAC.
  ///    Живой тест в VM (учётка администратора, приложение возвышено, запрос
  ///    согласия отключён политикой) показал ровно то, чего не должно быть:
  ///    `ShellExecuteEx` НЕ ВОЗВРАЩАЛСЯ 20 секунд и хелпер не запускался, хотя
  ///    тот же самый вызов из обычного консольного Dart-процесса отрабатывал за
  ///    29 мс и туннель поднимал. То есть дефект живёт в связке
  ///    «Flutter-процесс + брокер UAC», а не в самом FFI, и лечится он тем, что
  ///    в этом случае брокера в цепочке просто не остаётся.
  ///
  /// 2. Если приложение не возвышено, обойтись без UAC нельзя. Тогда вызов
  ///    уезжает в отдельный изолят, чтобы интерфейс жил и кнопка «Отключить»
  ///    отвечала. Зависший вызов утечёт вместе с изолятом — прервать FFI
  ///    нечем, — но приложение останется управляемым.
  static Future<bool> runElevatedAsync(
    String exePath,
    String params, {
    bool show = false,
    // Раньше было 20 с. Это меньше, чем нужно живому человеку, чтобы заметить
    // окно UAC (оно может открыться за другими окнами) и нажать «Да». Отказ по
    // такому таймауту — не отказ пользователя, а наша нетерпеливость.
    Duration timeout = const Duration(minutes: 2),
    /// Дождаться завершения и вернуть его РЕЗУЛЬТАТ, а не факт запуска.
    ///
    /// ⚠️ Для хелпера TUN — `false`: он держит туннель и обязан пережить
    /// нас. Для команд вроде `schtasks`, чей результат и есть смысл вызова,
    /// — `true`, иначе мы рапортуем об успехе, ничего о нём не зная.
    bool waitForExit = false,
  }) async =>
      await runElevatedDetailed(exePath, params,
          show: show, timeout: timeout, waitForExit: waitForExit) ==
      ElevationOutcome.ok;

  /// То же, что [runElevatedAsync], но с причиной отказа — для тех, кто
  /// показывает её человеку.
  static Future<ElevationOutcome> runElevatedDetailed(
    String exePath,
    String params, {
    bool show = false,
    Duration timeout = const Duration(minutes: 2),
    bool waitForExit = false,
  }) async {
    // Способ можно переопределить переменной окружения SILENTGATE_ELEVATION:
    //   direct    — только прямой запуск (когда права уже есть);
    //   powershell — только посредник;
    //   shellexec — только прежний путь через FFI.
    // Нужно и для проверки веток на стенде, и как обходной путь пользователю,
    // если у него один из способов заблокирован политикой.
    final mode = Platform.environment['SILENTGATE_ELEVATION'] ?? '';

    if (isElevated && mode != 'powershell' && mode != 'shellexec') {
      // Права уже есть — запрашивать нечего.
      try {
        // ⚠️ ЕСТЬ ДВА РАЗНЫХ СЛУЧАЯ, И РАНЬШЕ ОНИ БЫЛИ ОДНИМ.
        //
        // Хелпер TUN обязан ПЕРЕЖИТЬ нас: он держит туннель, и ждать его
        // завершения значило бы висеть всё подключение. А `schtasks` — команда,
        // чей РЕЗУЛЬТАТ и есть смысл вызова: не дождавшись её, мы не знаем,
        // создана задача или нет.
        //
        // ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 07.09.2026: «перестал создаваться UAC совсем,
        // приложение запущено от админа, никаких окон не было», а на экране —
        // «Не удалось создать задачу (UAC отклонён или запрещено политикой)».
        // Сообщение врало дважды: UAC здесь не запрашивается вовсе (права уже
        // есть, идём этой веткой), а настоящую причину отказа `schtasks` мы не
        // видели — процесс запускался отсоединённым, и его код возврата со
        // stderr уходили в никуда. Возвращали `true` независимо от того, что
        // там случилось.
        if (!waitForExit) {
          await Process.start(exePath, splitArgs(params),
              mode: ProcessStartMode.detached);
          AppLog.i(
              'Хелпер запущен напрямую (приложение уже с правами администратора)');
          return ElevationOutcome.ok;
        }
        final r = await Process.run(exePath, splitArgs(params),
            runInShell: false);
        if (r.exitCode == 0) {
          AppLog.i('Команда выполнена напрямую (права администратора уже есть)');
          return ElevationOutcome.ok;
        }
        // Причину печатаем ЦЕЛИКОМ: без неё «не удалось» неотличимо от
        // «отказали в правах», и человек ищет беду не там.
        final err = '${r.stderr}'.trim();
        final out = '${r.stdout}'.trim();
        AppLog.e('Команда завершилась с кодом ${r.exitCode}: '
            '${err.isNotEmpty ? err : out}');
        return ElevationOutcome.commandFailed;
      } catch (e) {
        AppLog.e('Не удалось запустить хелпер напрямую: $e');
        return ElevationOutcome.commandFailed;
      }
    }

    AppLog.i('Запрашиваю права администратора: $exePath $params');

    // Сначала — посредник вне нашего процесса. Именно внутри Flutter-процесса
    // вызов и зависает: в логе владельца после «пробую system, MTU 1500» не
    // появлялось НИ ОДНОЙ строки по 25, 96, 199 и однажды 1128 секунд, при 25
    // успешных подъёмах за ту же историю — то есть дефект плавающий, а не
    // постоянный. Тот же вызов из отдельного процесса отрабатывает за 29 мс.
    // Окно UAC пользователь видит ровно то же самое: его показывает система, а
    // не посредник.
    if (mode != 'shellexec') {
      final viaPs =
          await _viaPowerShell(exePath, params, show, timeout, waitForExit);
      if (viaPs != null) {
        AppLog.i('Права администратора: ${switch (viaPs) {
          ElevationOutcome.ok => 'получены',
          ElevationOutcome.denied => 'ОТКАЗ',
          ElevationOutcome.commandFailed =>
            'получены, но команда завершилась с ошибкой',
        }}');
        return viaPs;
      }
      // null = посредник недоступен (политика, урезанный PATH). Идём прежним
      // путём: он ненадёжен, но лучше, чем ничего.
      AppLog.w('Посредник элевации недоступен — пробую напрямую');
    }

    try {
      final ok = await Isolate.run(() => runElevated(exePath, params, show: show))
          .timeout(timeout);
      AppLog.i('Права администратора: ${ok ? "получены" : "ОТКАЗ"}');
      return ok ? ElevationOutcome.ok : ElevationOutcome.denied;
    } on TimeoutException {
      AppLog.e('Запрос прав администратора не ответил за '
          '${timeout.inSeconds} с — считаю отказом');
      return ElevationOutcome.denied;
    } catch (e) {
      AppLog.e('Запрос прав администратора сорвался: $e');
      return ElevationOutcome.denied;
    }
  }

  /// Возвышение чужими руками: `Start-Process -Verb RunAs` в отдельном процессе.
  ///
  /// Возвращает исход либо **null** — посредник недоступен, решение принимать
  /// нечем.
  ///
  /// Почему не наш процесс: см. [runElevatedAsync]. Здесь важно, что ожидание
  /// прерываемо — зависший посредник можно убить, в отличие от зависшего FFI.
  static Future<ElevationOutcome?> _viaPowerShell(String exePath,
      String params, bool show, Duration timeout, bool waitForExit) async {
    Process proc;
    try {
      // ⚠️ `-EncodedCommand`, А НЕ `-Command`. Текст команды несёт кавычки
      // (строка параметров передаётся как есть, см. [psCommand]), а
      // `-Command` прошёл бы ещё через один разбор командной строки — уже
      // самого powershell.exe — со своими правилами про `\"`. Base64 в
      // UTF-16LE экранирования не требует вовсе.
      proc = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        encodePs(psCommand(exePath, params, show: show, wait: waitForExit)),
      ]);
    } catch (e) {
      // ⚠️ ПРИЧИНУ НАЗЫВАЕМ. Вызывающий пишет обобщённое «посредник
      // недоступен», и по нему нельзя отличить вырезанный антивирусом
      // powershell.exe от урезанного PATH и от запрета политикой — а лечатся
      // эти три случая по-разному.
      AppLog.w('Посредник элевации не запустился: $e');
      return null; // powershell не запустился — это не отказ пользователя
    }
    try {
      final code = await proc.exitCode.timeout(timeout);
      return outcomeOfPsExit(code);
    } on TimeoutException {
      AppLog.e('Посредник элевации не ответил за ${timeout.inSeconds} с');
      proc.kill(ProcessSignal.sigkill);
      return ElevationOutcome.denied;
    }
  }

  /// Код возврата посредника → исход. Пары с [psCommand]: коды назначает он.
  @visibleForTesting
  static ElevationOutcome? outcomeOfPsExit(int code) => switch (code) {
        0 => ElevationOutcome.ok,
        1 => ElevationOutcome.denied,
        // 2 — сам посредник не смог даже попытаться; отказом это считать нельзя.
        2 => null,
        3 => ElevationOutcome.commandFailed,
        _ => ElevationOutcome.denied,
      };

  /// Текст для `powershell -EncodedCommand`: base64 от UTF-16LE.
  @visibleForTesting
  static String encodePs(String script) {
    final bytes = <int>[];
    for (final u in script.codeUnits) {
      bytes
        ..add(u & 0xFF)
        ..add(u >> 8);
    }
    return base64.encode(bytes);
  }

  /// Команда для посредника. Вынесена отдельно ради тестов на экранирование:
  /// в путях бывают пробелы и апострофы, а неверная кавычка молча превратится
  /// в «конфиг не найден» уже внутри хелпера.
  ///
  /// ⚠️ ПАРАМЕТРЫ ИДУТ ОДНОЙ СТРОКОЙ, КАК ЕСТЬ. `Start-Process -ArgumentList`
  /// склеивает элементы массива пробелом и НИЧЕГО НЕ ЭКРАНИРУЕТ: путь
  /// `C:\Users\Иван Петров\…`, разобранный в отдельный элемент, на той стороне
  /// снова распадался на два аргумента. Строка параметров у нас уже составлена
  /// по правилам командной строки Windows — ровно её `ShellExecuteEx` и ждёт
  /// в `lpParameters`, тем же путём, что и запасная ветка [runElevated].
  ///
  /// [wait] — дождаться команды и отличить её отказ (код 3) от отказа в правах.
  static String psCommand(String exePath, String params,
      {bool show = false, bool wait = false}) {
    final style = show ? 'Normal' : 'Hidden';
    final start = StringBuffer('Start-Process -FilePath ${_psQuote(exePath)}');
    if (params.trim().isNotEmpty) {
      start.write(' -ArgumentList ${_psQuote(params)}');
    }
    start.write(' -Verb RunAs -WindowStyle $style -ErrorAction Stop');
    if (wait) start.write(' -Wait -PassThru');
    // Отказ пользователя и невозможность запустить посредника — РАЗНЫЕ исходы:
    // первый окончателен, второй означает «попробуй иначе».
    final body = wait
        ? '\$p = $start; if (\$p.ExitCode -ne 0) { exit 3 }; exit 0'
        : '$start; exit 0';
    return 'try { $body } '
        'catch [System.ComponentModel.Win32Exception] { exit 1 } '
        'catch { exit 2 }';
  }

  /// Апостроф внутри одинарных кавычек PowerShell удваивается.
  static String _psQuote(String v) => "'${v.replaceAll("'", "''")}'";

  /// Разбор строки параметров в список аргументов — по правилам
  /// `CommandLineToArgvW`, то есть так же, как её разберёт запущенная программа.
  ///
  /// `ShellExecuteEx` принимает параметры одной строкой, `Process.start` — уже
  /// разобранным списком (и экранирует его обратно сам). Кавычки вокруг путей
  /// обязаны сниматься здесь: иначе хелпер получит имя файла ВМЕСТЕ с кавычками
  /// и не найдёт конфиг.
  ///
  /// ⚠️ ОБРАТНАЯ КОСАЯ ПЕРЕД КАВЫЧКОЙ — НЕ МЕЛОЧЬ. Прежний разбор переключался на
  /// КАЖДОЙ кавычке и про `\"` не знал ничего. А задача Планировщика заводится
  /// строкой `/TR "\"<exe>\" --tun-task \"<cfg>\" \"<stop>\""` — вложенные
  /// кавычки в ней экранированы именно так. Разбор рвал её на куски, и в
  /// задачу записывалось `\I:\…\silentgate.exe\` — команда, которую Windows
  /// запустить не может. Проверка после создания такую задачу честно не
  /// узнавала, «Исправить» через 10 с сдавалось, а интерфейс объявлял
  /// виноватым UAC. Каждое нажатие повторяло то же самое.
  @visibleForTesting
  static List<String> splitArgs(String params) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    // Аргумент начат, даже если пуст: `""` — это законный пустой аргумент.
    var started = false;
    var i = 0;
    while (i < params.length) {
      final ch = params[i];
      if (ch == r'\') {
        var n = 0;
        while (i < params.length && params[i] == r'\') {
          n++;
          i++;
        }
        started = true;
        if (i < params.length && params[i] == '"') {
          // 2n косых + кавычка → n косых и кавычка-разделитель;
          // 2n+1 косых + кавычка → n косых и буквальная кавычка.
          buf.write(r'\' * (n ~/ 2));
          if (n.isOdd) {
            buf.write('"');
          } else {
            quoted = !quoted;
          }
          i++;
        } else {
          // Косые не перед кавычкой — буквально: это обычный путь Windows.
          buf.write(r'\' * n);
        }
        continue;
      }
      if (ch == '"') {
        quoted = !quoted;
        started = true;
      } else if ((ch == ' ' || ch == '\t') && !quoted) {
        if (started) {
          out.add(buf.toString());
          buf.clear();
          started = false;
        }
      } else {
        buf.write(ch);
        started = true;
      }
      i++;
    }
    if (started) out.add(buf.toString());
    return out;
  }

  static bool runElevated(String exePath, String params, {bool show = false}) {
    final pVerb = 'runas'.toNativeUtf16();
    final pFile = exePath.toNativeUtf16();
    final pParams = params.toNativeUtf16();
    final sei = calloc<SHELLEXECUTEINFO>();
    try {
      sei.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      sei.ref.lpVerb = pVerb;
      sei.ref.lpFile = pFile;
      sei.ref.lpParameters = pParams;
      sei.ref.nShow = show ? SW_SHOWNORMAL : SW_HIDE;
      // SEE_MASK_NOASYNC: документация требует этот флаг, когда вызов делается
      // из потока, который вскоре завершится, — иначе операция может не
      // довестись до конца. У нас ровно этот случай: изолят живёт только на
      // время вызова.
      sei.ref.fMask = 0x00000100;
      final result = ShellExecuteEx(sei);
      return result != 0;
    } finally {
      free(pVerb);
      free(pFile);
      free(pParams);
      free(sei);
    }
  }
}
