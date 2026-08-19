import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/platform/app_paths.dart';
import '../kill_switch_wfp.dart';
import 'app_alive_mutex.dart';
import 'tun_luid.dart';
import 'kill_switch_plan_file.dart';
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

  /// Имя мьютекса «интерфейс жив» для этой сессии.
  ///
  /// ⚠️ ОТДЕЛЬНЫМ ФАЙЛОМ, А НЕ ПОЛЕМ В КОНФИГЕ. sing-box отвергает конфиг
  /// ЦЕЛИКОМ из-за одного незнакомого поля — положив имя туда, мы уронили бы
  /// туннель. И не аргументом задачи Планировщика: она запекает строку запуска
  /// один раз, а имя рождается на каждую сессию.
  static String aliveFilePathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}tun_alive';

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

    // ⚠️ НАБЛЮДЕНИЕ ЗА ЖИЗНЬЮ ИНТЕРФЕЙСА. Без него помощник переживает
    // приложение: закройте окно — и он останется работать, а вместе с ним
    // останется стоять блокировка, снять которую будет некому.
    //
    // Имя мьютекса кладёт рядом сам интерфейс перед запуском. Нет файла или
    // мьютекс не открылся — значит приложения нет (или запустили помощник
    // руками): работаем как раньше, но говорим об этом вслух. ⚠️ Когда сюда
    // придут фильтры WFP, эта ветка обязана стать отказом: поднимать
    // блокировку, которую некому снять, нельзя.
    final aliveName = _readAliveName(configPath);
    final alive = AppAliveMutex.watch(aliveName);
    await log.write(alive != null
        ? '--- слежу за интерфейсом: $aliveName'
        : '--- имени интерфейса нет — работаю без слежения '
            '(kill switch в этом режиме поднимать нельзя)');

    // ⚠️ БАЗОВЫЙ НАБОР ПОДНИМАЕТСЯ ДО ЗАПУСКА ЯДРА.
    //
    // Иначе окно «ядро уже работает, адаптер ещё не появился» остаётся дырой:
    // трафик в эти секунды идёт мимо VPN под настоящим адресом. Правило
    // «пропускать туннель» в базовый набор не входит — LUID взяться неоткуда,
    // адаптера ещё нет; оно дописывается в цикле, когда адаптер появится.
    //
    // На это время машина закрыта, и это не побочный ущерб, а поведение kill
    // switch на подключении (школа Mullvad): свои бинари, адреса серверов,
    // loopback и DHCP разрешены, остальное — нет.
    final hold = _engageBase(log, alive, configPath);
    if (hold == null && _wantsKillSwitch(configPath)) {
      // ⚠️ KILL SWITCH ПРОСИЛИ, А ПОДНЯТЬ НЕ ВЫШЛО — ТУННЕЛЯ НЕ БУДЕТ.
      // Поднять туннель, который может течь, при интерфейсе, обещающем защиту,
      // — это ровно та жалоба, из-за которой всё затевалось, воспроизведённая
      // своими руками.
      await log.write('НЕ ЗАПУСКАЮ ЯДРО: kill switch включён, но блокировка не '
          'поднялась. Туннель без неё обещал бы защиту, которой нет.');
      alive?.dispose();
      await log.close();
      return;
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

    // ⚠️ ОДИН ЦИКЛ И ОДИН ВЫХОД. Ожиданий ВНЕ цикла быть не должно: пока
    // помощник ждёт что-то отдельно, он не смотрит ни stop-файл, ни признак
    // жизни интерфейса — а команда «отключить» приходит именно туда. Первая
    // редакция ждала LUID отдельным циклом до 15 с и этим заново открывала
    // гонку stop-файла, которую закрывал предыдущий коммит.
    var luidApplied = hold == null;
    var coreDeathLogged = false;

    while (true) {
      if (stopFile.existsSync()) {
        await log.write('--- получен stop-файл, останавливаю sing-box');
        proc.kill();
        break;
      }
      // Интерфейс умер — уходим следом. Смерть приложения ничем не отличается
      // от команды «стоп»: отдельная ветка означала бы второй путь выхода.
      if (alive != null && !alive.appAlive) {
        await log.write('--- интерфейс завершился, останавливаю sing-box');
        proc.kill();
        break;
      }

      // Адаптер появился — дописываем правило «пропускать туннель». До этого
      // момента стоит БАЗОВЫЙ набор: он закрывает всё, кроме своих бинарей,
      // серверов, loopback и DHCP. Так и задумано — на подключении машина
      // закрыта, иначе окно «ядро уже работает, адаптера ещё нет» остаётся
      // дырой.
      if (!luidApplied) {
        final luid = TunLuid.forAlias();
        if (luid != null) {
          final plan = _planFor(configPath, luid);
          final ok = plan != null && hold!.reengage(plan,
              log: (m) => unawaited(log.write('--- $m')));
          if (ok) {
            luidApplied = true;
          } else {
            // ⚠️ ОТКАЗ, А НЕ «ОСТАВИМ БАЗОВЫЙ». Базовый набор без правила
            // туннеля душит ровно тот трафик, ради которого VPN и включали:
            // человек увидит «Подключено» и мёртвый интернет.
            await log.write('--- kill switch: не удалось разрешить туннель — '
                'останавливаю, чтобы не оставить «подключено» без связи');
            proc.kill();
            break;
          }
        }
      }

      // ⚠️ СМЕРТЬ ЯДРА НЕ СНИМАЕТ БЛОКИРОВКУ. Здесь стоял `break`, и это была
      // главная ошибка первой редакции: адаптер исчезает вместе с ядром,
      // маршрут по умолчанию возвращается на физическую сеть — то есть защита
      // пропадала ровно в тот момент, ради которого её и ставили. Дословно та
      // жалоба владельца, из-за которой всё затевалось.
      //
      // Держать блокировку без туннеля безопасно: `teardownCore(keepCapture:
      // true)` намеренно не трогает TUN между попытками восстановления, то
      // есть живой помощник — штатный участник переподключения, а не сирота.
      // Ядро не перезапускаем: восстановление — дело движка.
      if (procExited) {
        if (hold == null) break;
        if (!coreDeathLogged) {
          coreDeathLogged = true;
          await log.write('--- ядро умерло, блокировка ДЕРЖИТСЯ: жду команду '
              'или смерть интерфейса');
        }
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    // ⚠️ СНИМАЕМ ЯВНО, хотя динамическая сессия снялась бы и сама при выходе.
    // Явное снятие — не подстраховка, а разница в СРОКЕ: между `proc.kill()` и
    // концом процесса помощник живёт секунды, и всё это время блокировка
    // стояла бы уже без туннеля. Для человека это «интернет не вернулся сразу
    // после Отключить».
    if (hold != null) {
      hold.release();
      await log.write('--- блокировка снята');
    }
    alive?.dispose();

    try {
      proc.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _delete(stopFile);
    await log.close();
  }

  /// Просили ли блокировку вообще (файл плана с `enabled: true`).
  static bool _wantsKillSwitch(String configPath) =>
      KillSwitchPlanFile.read(_dataDir(configPath),
          expectToken: _readAliveName(configPath)) !=
      null;

  /// План с подставленным LUID; `null` — плана нет или он не наш.
  static KillSwitchPlan? _planFor(String configPath, int? luid) {
    final plan = KillSwitchPlanFile.read(_dataDir(configPath),
        tunnelLuid: luid, expectToken: _readAliveName(configPath));
    return plan?.withOwnBinaries(_ownBinaries());
  }

  /// Поднять БАЗОВЫЙ набор — без правила туннеля, до старта ядра.
  ///
  /// `null` — не подняли. Причина всегда названа в журнале: молчаливое
  /// отсутствие защиты хуже её отсутствия, потому что человек считает себя
  /// защищённым.
  static KillSwitchHold? _engageBase(
      RotatingLog log, AppAliveWatch? alive, String configPath) {
    try {
      final plan = _planFor(configPath, null);
      // Блокировать не просили — штатный молчаливый выход.
      if (plan == null) return null;

      // ⚠️ БЕЗ СВЯЗИ С ИНТЕРФЕЙСОМ БЛОКИРОВКУ ПОДНИМАТЬ НЕЛЬЗЯ. Помощник, не
      // знающий, жив ли интерфейс, переживёт его падение — и снять блокировку
      // будет некому. Машина без сети до перезагрузки.
      if (alive == null) {
        unawaited(log.write('--- kill switch НЕ поднят: нет связи с '
            'интерфейсом. Блокировка, которую некому снять, опаснее её '
            'отсутствия'));
        return null;
      }
      return KillSwitchWfp.engage(plan,
          log: (m) => unawaited(log.write('--- $m')));
    } catch (e) {
      unawaited(log.write('--- kill switch не поднялся: $e'));
      return null;
    }
  }

  /// Свои бинари — те, что обязаны ходить в сеть при поднятой блокировке.
  ///
  /// ⚠️ СПРАШИВАЕМ У СЕБЯ, А НЕ У ИНТЕРФЕЙСА. Помощник и есть `silentgate.exe`,
  /// а ядра лежат рядом с ним; передавать это файлом значило бы завести второй
  /// источник правды о том, что помощник знает точнее всех.
  static List<String> _ownBinaries() {
    final out = <String>[Platform.resolvedExecutable];
    final loc = XrayPaths.locate();
    if (loc != null) {
      for (final n in const ['sing-box.exe', 'xray.exe']) {
        final f = File('${loc.assetDir}${Platform.pathSeparator}$n');
        if (f.existsSync()) out.add(f.path);
      }
    }
    return out;
  }

  /// ⚠️ КАТАЛОГ ДАННЫХ — РЯДОМ С КОНФИГОМ, А НЕ ИЗ `AppPaths.supportDir()`.
  ///
  /// Явные пути заведены ровно потому, что на учётке с ОТДЕЛЬНЫМ админом
  /// `%APPDATA%` помощника — чужой (правка #7). Спросив свой каталог, он не
  /// нашёл бы ни признака жизни, ни плана блокировки — и оба отказа прошли бы
  /// молча.
  static Directory _dataDir(String configPath) =>
      File(configPath).parent;

  /// Имя мьютекса, положенное интерфейсом. Пусто — файла нет.
  static String _readAliveName(String configPath) {
    try {
      final f = File(aliveFilePathFor(_dataDir(configPath)));
      if (!f.existsSync()) return '';
      return f.readAsStringSync().trim();
    } catch (_) {
      return '';
    }
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

  /// ДОЖДАТЬСЯ, ПОКА ПРОШЛЫЙ ХЕЛПЕР ЗАБЕРЁТ stop-ФАЙЛ.
  ///
  /// ⚠️ РАДИ ЧЕГО ЭТО ЕСТЬ — ГОНКА, КОТОРАЯ ПЛОДИТ ОСИРОТЕВШИХ ХЕЛПЕРОВ.
  /// Неудачная попытка автоподбора ставит stop-файл (`_waitUp`), а следующая
  /// попытка первым делом его СТИРАЛА — и сигнал пропадал раньше, чем хелпер
  /// успевал его прочитать: он опрашивает файл раз в 400 мс, а окно между
  /// постановкой и стиранием замерено в 393–515 мс. Промах означает живого
  /// хелпера с работающим ядром, которого никто больше не остановит.
  ///
  /// Сегодня такого сироту убирает единственная случайность: вместе с ним
  /// умирает sing-box, и хелпер выходит по `procExited`. Настоящий kill switch
  /// эту дверь закрывает (он обязан пережить смерть ядра), поэтому гонку надо
  /// закрыть ДО его включения — иначе каждая неудачная комбинация оставит
  /// процесс с полной блокировкой WFP, то есть машину без сети.
  ///
  /// Ждём исчезновения файла: хелпер удаляет его и на старте, и на выходе, —
  /// то есть пропажа и есть подтверждение, что сигнал принят. Отдельного
  /// протокола заводить не пришлось.
  ///
  /// `false` — не дождались (хелпера, возможно, и не было: права не дали,
  /// задача не запустилась). Вызывающий обязан решить сам; молча продолжать
  /// нельзя — оставленный файл убьёт СЛЕДУЮЩИЙ хелпер сразу после старта.
  static Future<bool> waitStopConsumed(String stopPath,
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (stopPath.isEmpty) return true;
    final f = File(stopPath);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (!f.existsSync()) return true;
      } catch (_) {
        return true; // прочитать не смогли — считать «висит» тем более нельзя
      }
      // Опрос чаще, чем у хелпера (400 мс): ждём ЕГО реакцию, а не свою.
      await Future.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  /// Удалить stop-файл перед новым запуском (оба расположения).
  ///
  /// ⚠️ ЗВАТЬ ТОЛЬКО ПОСЛЕ [waitStopConsumed], вернувшего `false`. Это
  /// последнее средство: файл стирается вслепую, и если прошлый хелпер ещё жив,
  /// он останется жить дальше. До 20.08.2026 этот вызов стоял первой строкой
  /// каждой попытки подъёма — и был не последним средством, а обычным путём.
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
