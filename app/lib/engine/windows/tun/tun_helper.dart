import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/platform/app_paths.dart';
import '../kill_switch_wfp.dart';
import '../../../core/platform/rotating_log.dart';
import '../xray_paths.dart';

/// Элевейтнутый TUN-хелпер: запускает sing-box как дочерний процесс и следит за
/// stop-файлом. Когда GUI (без прав) создаёт stop-файл — хелпер убивает sing-box и выходит.
/// Так решается остановка привилегированного процесса из непривилегированного GUI.
///
/// Два режима запуска:
///  * `--tun-task` — из задачи Планировщика (без UAC). Пути фиксированы в `%APPDATA%`.
///  * `--tun <config> [stop]` — прямой запуск через UAC (fallback, если задачи нет).
///
/// Весь вывод sing-box пишется в `singbox.log`: без него сбой ядра был невидим —
/// приложение показывало «Подключено» при отсутствующем туннеле.
class TunHelper {
  /// Потолок ОДНОЙ части лога. Общий с прокси-ядром — обоснование числа и
  /// расхода на диске живёт в одном месте ([RotatingLog.coreLogMaxBytes]).
  static const _maxLogBytes = RotatingLog.coreLogMaxBytes;

  static File _defaultStopFile() =>
      File('${Directory.systemTemp.path}${Platform.pathSeparator}silentgate_tun_stop');

  /// Путь stop-файла в папке данных пользователя.
  static String stopFilePathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}tun_stop';

  /// Путь конфига sing-box в папке данных пользователя.
  static String configPathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}singbox_config.json';

  /// Лог sing-box (читается приложением при сбое и по кнопке «Показать лог»).
  static String logPathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}singbox.log';

  /// Хвост лога sing-box — для показа реальной причины сбоя.
  /// Хвост лога sing-box.
  ///
  /// ⚠️ Файл читается С КОНЦА, а не целиком: при уровне лога `debug` он растёт
  /// на сотни мегабайт за сессию (наблюдалось 758 МБ), и `readAsString()`
  /// затягивал всё это в память — нажатие «Написать в поддержку» подвешивало
  /// приложение или роняло его по нехватке памяти.
  static const _tailBytes = 512 * 1024;

  /// Чтение делегировано [RotatingLog.tailAcrossRotation] — тот же алгоритм
  /// нужен и прокси-ядру (`singbox_proxy.log`), а две копии этой логики
  /// неминуемо разъехались бы.
  ///
  /// ⚠️ ИМЕННО `tailAcrossRotation`, А НЕ `tail`. Лог ротируется как раз тогда,
  /// когда ядро разговорилось, — то есть в аварии; после ротации в
  /// `singbox.log` лежит начало новой части, а строки обрыва — в
  /// `singbox.prev.log`. Читатель, знающий только про первый файл, показал бы
  /// пустой хвост ровно в том случае, ради которого лог и заведён.
  static Future<String> tailLog({int lines = 40}) async =>
      RotatingLog.tailAcrossRotation(
        logPathFor(await AppPaths.supportDir()),
        lines: lines,
        tailBytes: _tailBytes,
      );

  /// Режим задачи Планировщика. Пути к конфигу/stop берём из ЯВНЫХ аргументов,
  /// если задача их передала (см. TunScheduledTask.install), иначе — из `%APPDATA%`.
  /// Явные пути важны на учётке с ОТДЕЛЬНЫМ админом: там задача бежит от админа, и
  /// его `%APPDATA%` — ЧУЖОЙ (иначе туннель поднимался бы по пустому конфигу, #7).
  static Future<void> runFromTask({String? configPath, String? stopPath}) async {
    final dir = await AppPaths.supportDir();
    await run(
      (configPath != null && configPath.isNotEmpty)
          ? configPath
          : configPathFor(dir),
      stopPath: (stopPath != null && stopPath.isNotEmpty)
          ? stopPath
          : stopFilePathFor(dir),
    );
  }

  /// Открыть лог НОВОЙ СЕССИИ ЯДРА и отметить её началом строку [header].
  ///
  /// ⚠️ ВЫНЕСЕНО ОТДЕЛЬНО РАДИ ТЕСТА, и это не украшательство. Проверить
  /// [run] целиком нельзя — он запускает элевейтнутый процесс sing-box;
  /// значит, дефект «каждая сессия стирает журнал предыдущей» жил бы в коде,
  /// который не проверяет ничто. Тест зовёт ИМЕННО ЭТУ функцию дважды подряд
  /// (две сессии ядра) и требует, чтобы строки первой уцелели.
  ///
  /// `keepPrevious` здесь обязателен: без него ротация по порогу стирает
  /// историю в ноль, и накопление сессий не даёт ничего — потолок всё равно
  /// достигается за минуты на уровне `debug`.
  @visibleForTesting
  static Future<RotatingLog> openSessionLog(String path, String header) async {
    final log =
        RotatingLog(path, maxBytes: _maxLogBytes, keepPrevious: true);
    await log.open();
    await log.write(header);
    return log;
  }

  /// Вызывается из main при `--tun`. Блокируется до остановки.
  static Future<void> run(String configPath, {String stopPath = ''}) async {
    final stopFile = stopPath.isNotEmpty ? File(stopPath) : _defaultStopFile();
    final loc = XrayPaths.locate();
    final singbox = loc != null
        ? '${loc.assetDir}${Platform.pathSeparator}sing-box.exe'
        : 'sing-box.exe';

    final log = await openSessionLog(
      logPathFor(await AppPaths.supportDir()),
      '--- запуск sing-box ${DateTime.now().toIso8601String()}: '
          '$singbox run -c $configPath',
    );
    // ⚠️ ЛОГ ЗДЕСЬ БОЛЬШЕ НЕ ОБРЕЗАЕТСЯ — ЭТО И БЫЛ ДЕФЕКТ, а не аккуратность.
    //
    // Раньше стояло `log.truncate(header: …)`: каждая сессия ядра начинала файл
    // с нуля. А новая сессия — это и есть восстановление после обрыва, то есть
    // журнал аварии уничтожался тем самым перезапуском, который аварией вызван.
    // Замерено на машине владельца 19.08.2026: в отчёте поддержки два обрыва
    // (01:29 и 02:20), отчёт собран в 02:21:56, а в `singbox.log` лежали 55
    // секунд с 02:44:42 — окна ни одной из аварий не осталось, и утечку по
    // логам не удалось ни доказать, ни опровергнуть.
    //
    // Теперь сессии НАКАПЛИВАЮТСЯ, а место стережёт ротация ([RotatingLog] с
    // `keepPrevious`): при достижении порога прежняя часть уезжает в
    // `singbox.prev.log`, а не пропадает.
    //
    // ⚠️ Обрезка (когда она нужна — по кнопке «Очистить логи») и поток обязаны
    // жить в одном месте. Раньше файл обрезал роутер (`_truncateLog`, другой
    // процесс и другой файл кода), пока хелпер держал его открытым на
    // дозапись; `IOSink` помнит смещение с момента открытия — после чужой
    // обрезки он писал по старому адресу, и Windows заливала пропуск нулями:
    // у владельца 98 % `singbox.log` (1 048 209 байт из 1 476 КБ) оказались
    // нулями при 3571 реальной строке.
    //
    // Отметка времени в заголовке обязательна: по накопленному логу сессии
    // теперь надо УМЕТЬ РАЗЛИЧАТЬ, а собственной метки у нашей строки не было —
    // время печатает только само ядро, и то в своём формате.

    // ⚠️ РАЗВЕДКА KILL SWITCH — ТОЛЬКО ОТЧЁТ, НИЧЕГО НЕ БЛОКИРУЕТ.
    //
    // Настоящий kill switch (фильтры WFP) требует прав администратора, и
    // владельцем фильтров задуман ИМЕННО ЭТОТ процесс: он элевейтнут задачей
    // Планировщика и живёт ровно столько, сколько туннель. Значит его смерть —
    // штатный сигнал снять блокировку, и Windows делает это сама, потому что
    // сессия динамическая.
    //
    // Но прежде чем что-то блокировать, надо узнать факт: хватает ли прав
    // здесь и правильно ли связаны структуры. Разведка открывает сессию,
    // пробует добавить объект и ОТКАТЫВАЕТ транзакцию — система остаётся
    // нетронутой, а в журнале появляется ответ. Порядок обратный обычному
    // нарочно: цена ошибки тут не красный тест, а машина без интернета.
    try {
      final probe = KillSwitchWfp.probe();
      await log.write('--- разведка kill switch: $probe');
    } catch (e) {
      await log.write('--- разведка kill switch не выполнилась: $e');
    }

    _delete(stopFile);
    Process proc;
    try {
      proc = await Process.start(
        singbox,
        ['run', '-c', configPath],
        workingDirectory: loc?.assetDir,
      );
    } catch (e) {
      await log.write('НЕ УДАЛОСЬ ЗАПУСТИТЬ sing-box: $e');
      await log.close();
      return;
    }

    // Вывод ядра — в лог (иначе диагностировать сбой невозможно). Режем на
    // СТРОКИ, а не пишем чанками: по строкам считается порог усечения, и на
    // чанках он занижался ровно настолько, насколько ядро болтливо.
    void pipe(Stream<List<int>> s) => s
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => unawaited(log.write(line)), onError: (_) {});
    pipe(proc.stdout);
    pipe(proc.stderr);

    var procExited = false;
    unawaited(proc.exitCode.then((code) {
      procExited = true;
      unawaited(log.write('--- sing-box завершился, код $code'));
    }));

    while (true) {
      if (procExited) break;
      if (stopFile.existsSync()) {
        await log.write('--- получен stop-файл, останавливаю sing-box');
        proc.kill();
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    try {
      proc.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _delete(stopFile);
    await log.close();
  }

  /// GUI: запросить остановку TUN — создать stop-файл по явному пути.
  static void requestStopAt(String stopPath) {
    try {
      File(stopPath).createSync(recursive: true);
    } catch (_) {}
    // Легаси-путь на случай, если работает хелпер старой версии.
    try {
      _defaultStopFile().createSync();
    } catch (_) {}
  }

  /// Удалить stop-файл перед новым запуском (оба расположения).
  static void clearStopAt(String stopPath) {
    try {
      final f = File(stopPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _delete(_defaultStopFile());
  }

  // ⚠️ Своей ротации здесь БОЛЬШЕ НЕТ, и возвращать её нельзя.
  //
  // Было: `_openLog()` открывал поток, а `_rotateLog()` обрезал файл мимо него
  // — то есть ровно тот разрыв «открытие в одном месте, обрезка в другом»,
  // который и заполнял лог нулями. Всё это умеет [RotatingLog]: он усекает файл
  // и ПЕРЕСОЗДАЁТ поток, а не пишет дальше по старому смещению. Ротация на лету
  // при этом сохранилась — она нужна: сессия TUN живёт часами, а на уровне
  // `debug` sing-box пишет каждое соединение и каждый DNS-запрос (файл
  // наблюдался размером 758 МБ, и отчёт поддержки, читавший его целиком,
  // подвешивал приложение).

  static void _delete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
