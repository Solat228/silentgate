import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/platform/app_log.dart';
import '../../../core/platform/app_paths.dart';
import '../../../core/platform/platform_services.dart';
import '../elevation.dart';
import 'tun_helper.dart';

/// Запуск TUN без UAC при каждом подключении.
///
/// Идея: один раз (с одним UAC) создаём задачу Планировщика с «Высшими правами».
/// Дальше `schtasks /Run` стартует её **без UAC**. Задача запускает
/// `silentgate.exe --tun-task "<config>" "<stop>"` с ЯВНЫМИ путями (per-user appdata
/// GUI): так туннель читает правильный конфиг, даже если задача выполняется от
/// ОТДЕЛЬНОГО админа (у него другой `%APPDATA%`, #7).
class TunScheduledTask {
  static const taskName = 'SilentGateTun';

  /// Задача зарегистрирована в Планировщике?
  static Future<bool> exists() async {
    try {
      final r = await Process.run('schtasks', ['/Query', '/TN', taskName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Путь к exe и аргументы, которые задача ДОЛЖНА запускать сейчас.
  ///
  /// ⚠️ ВЫНЕСЕНО ОТДЕЛЬНО, ЧТОБЫ БЫЛО С ЧЕМ СРАВНИВАТЬ. Раньше строка запуска
  /// существовала только внутри [install] — то есть проверить, ту ли программу
  /// запускает уже созданная задача, было нечем.
  static Future<({String exe, String args})> expected() async {
    final dir = await AppPaths.supportDir();
    return (
      exe: Platform.resolvedExecutable,
      args: '--tun-task "${TunHelper.configPathFor(dir)}" '
          '"${TunHelper.stopFilePathFor(dir)}"',
    );
  }

  /// Запускает ли СУЩЕСТВУЮЩАЯ задача именно то, что нужно сейчас.
  ///
  /// ⚠️ РАДИ ЧЕГО ЭТО ЕСТЬ. Задача создаётся один раз и не пересматривается
  /// никогда: путь настройки первой строкой делает `if (isConfigured()) return`.
  /// На машине владельца это дало задачу от 20.07.2026, которая до сих пор
  /// запускает **exe из папки сборки** (`appuild\…\Release`) и с голым
  /// `--tun-task` без путей конфига и stop-файла. Следствия тихие и разные:
  /// после обновления интерфейс новый, а туннельное ядро старое; правка с
  /// явными путями (#7) не применилась вовсе; удалите папку сборки — и TUN
  /// перестанет подниматься, а выглядеть это будет как «не работает VPN».
  ///
  /// Возвращает `false` и когда задачи нет, и когда прочитать её не удалось:
  /// «не знаю» здесь обязано вести себя как «не подходит», иначе мы снова
  /// запустим чужой бинарь.
  static Future<bool> isCurrent() async {
    try {
      final r = await Process.run(
          'schtasks', ['/Query', '/TN', taskName, '/XML'],
          stdoutEncoding: null);
      if (r.exitCode != 0) return false;
      final want = await expected();
      return matches(
          decodeQueryOutput(r.stdout as List<int>), want.exe, want.args);
    } catch (_) {
      return false;
    }
  }

  /// Совпадает ли XML задачи с ожидаемой командой.
  ///
  /// ⚠️ ЧИСТАЯ ФУНКЦИЯ НАМЕРЕННО. Сам [isCurrent] запускает `schtasks` и в
  /// тестах недоступен, а ошибка сравнения здесь тихая и дорогая: «совпало» на
  /// самом деле означает «запускаем чужой бинарь под правами администратора».
  @visibleForTesting
  static bool matches(String xml, String exe, String args) {
    // Пути сравниваем без учёта регистра: Windows его не различает, а
    // Планировщик возвращает то, что записали.
    return _unquote(tag(xml, 'Command')).toLowerCase() == exe.toLowerCase() &&
        tag(xml, 'Arguments').toLowerCase() == args.toLowerCase();
  }

  /// ⚠️ ПЛАНИРОВЩИК ХРАНИТ ПРОГРАММУ В КАВЫЧКАХ: `/TR "\"<exe>\" …"` ложится
  /// в `<Command>` как `"C:\…\silentgate.exe"`. Проверено живьём в VM
  /// 08.10.2026. Прежняя сверка сравнивала это с путём без кавычек, и верно
  /// созданная задача объявлялась чужой — тесты писались по догадке о
  /// формате, а не по настоящему выводу.
  static String _unquote(String v) =>
      v.length >= 2 && v.startsWith('"') && v.endsWith('"')
          ? v.substring(1, v.length - 1)
          : v;

  /// Содержимое одного тега XML. Полноценный разбор здесь не нужен: оба поля
  /// плоские и без вложенности.
  ///
  /// ⚠️ `&quot;` разворачивается обратно в кавычку: пути с пробелами Планировщик
  /// хранит экранированными, и без этого сравнение не совпадало бы НИКОГДА —
  /// то есть задача всегда считалась бы устаревшей, а запуск без UAC пропал бы
  /// у всех.
  @visibleForTesting
  static String tag(String xml, String name) {
    final m = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
    return (m?.group(1) ?? '').trim().replaceAll('&quot;', '"');
  }

  /// Вывод `schtasks /Query … /XML`, прочитанный через пайп, — в строку.
  ///
  /// ⚠️ ШАПКА XML ВРЁТ. Она пишет `encoding="UTF-16"`, а в пайп `schtasks`
  /// отдаёт ОДНОБАЙТНЫЙ текст в OEM-кодировке консоли (cp866 на русской
  /// Windows) и без метки порядка байт. Проверено 08.10.2026 и на хосте
  /// (26100), и в VM (23H2): первые байты `3C 3F 78 6D 6C`, «Иван» —
  /// `88 A2 A0 AD`. Прежний код читал вывод как UTF-16 ВСЕГДА, получал мусор,
  /// и [isCurrent] не совпадал НИКОГДА и ни у кого: заметка «задача устарела»
  /// приходила в каждой сессии, а «Исправить» через 10 с сдавалось.
  ///
  /// UTF-16 оставлен на случай, если на какой-то сборке Windows он всё-таки
  /// придёт: с меткой или по нулевым старшим байтам ASCII.
  @visibleForTesting
  static String decodeQueryOutput(List<int> bytes,
      {String Function(List<int>)? oem}) {
    final utf16 = bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) || bytes[1] == 0);
    if (utf16) return decodeUtf16(bytes);
    return (oem ?? _decodeOem)(bytes);
  }

  /// OEM-кодировка консоли → строка, средствами самой Windows.
  ///
  /// Своя таблица cp866 была бы верна только на русской системе; Windows знает
  /// OEM-страницу любой локали.
  static String _decodeOem(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final src = calloc<Uint8>(bytes.length);
    try {
      src.asTypedList(bytes.length).setAll(0, bytes);
      // CP_OEMCP = 1.
      final n = _multiByteToWideChar(1, 0, src, bytes.length, nullptr, 0);
      if (n <= 0) return String.fromCharCodes(bytes);
      final dst = calloc<Uint16>(n);
      try {
        _multiByteToWideChar(1, 0, src, bytes.length, dst, n);
        return String.fromCharCodes(dst.asTypedList(n));
      } finally {
        calloc.free(dst);
      }
    } finally {
      calloc.free(src);
    }
  }

  // В пакете win32 5.15 этой функции нет — привязка вручную.
  static final _multiByteToWideChar = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
          Int32 Function(Uint32, Uint32, Pointer<Uint8>, Int32, Pointer<Uint16>,
              Int32),
          int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>,
              int)>('MultiByteToWideChar');

  /// UTF-16LE (с меткой порядка байт или без) → строка.
  @visibleForTesting
  static String decodeUtf16(List<int> bytes) {
    var b = bytes;
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) b = b.sublist(2);
    final units = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      units.add(b[i] | (b[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  /// Строка параметров `schtasks /Create` — одна на все пути элевации.
  ///
  /// ⚠️ ВЛОЖЕННЫЕ КАВЫЧКИ ЭКРАНИРОВАНЫ ПО ПРАВИЛАМ КОМАНДНОЙ СТРОКИ WINDOWS
  /// (`\"`). Значение `/TR` после разбора обязано быть ровно
  /// `"<exe>" --tun-task "<cfg>" "<stop>"` — то, с чем потом сверяет
  /// [isCurrent]. Тест сверяет именно разобранное, а не саму строку.
  @visibleForTesting
  static String createArgs(String exe, String cfg, String stop) =>
      '/Create /TN $taskName /TR "\\"$exe\\" --tun-task \\"$cfg\\" \\"$stop\\"" '
      '/SC ONCE /ST 00:00 /RL HIGHEST /F';

  /// Создать/пересоздать задачу. Показывает UAC ОДИН раз.
  ///
  /// Ждём появления задачи: `ShellExecuteEx` возвращает управление сразу, а schtasks
  /// отрабатывает уже в элевейтнутом процессе.
  static Future<PrivilegeSetupResult> install() async {
    final exe = Platform.resolvedExecutable;
    // Пути к конфигу/stop берём из per-user appdata GUI и ЗАПЕКАЕМ в команду
    // задачи — иначе задача, выполняясь от отдельного админа, читала бы чужой
    // %APPDATA% и поднимала туннель по пустому конфигу (#7).
    final dir = await AppPaths.supportDir();
    final cfg = TunHelper.configPathFor(dir);
    final stop = TunHelper.stopFilePathFor(dir);
    final args = createArgs(exe, cfg, stop);
    // ⚠️ Только асинхронно. Эту задачу заводят из настройки «запуск без UAC»,
    // то есть ровно тогда, когда пользователь уже устал от зависаний, — и
    // замерзший здесь интерфейс убил бы сам обходной путь.
    // ⚠️ ЖДЁМ РЕЗУЛЬТАТ. Смысл вызова здесь — создана ли задача, а не
    // «запустился ли schtasks». Без ожидания мы возвращали успех, даже
    // когда команда падала, и человек видел «UAC отклонён» там, где UAC
    // вообще не участвовал (жалоба владельца 07.09.2026).
    final outcome = await Elevation.runElevatedDetailed('schtasks.exe', args,
        waitForExit: true);
    switch (outcome) {
      case ElevationOutcome.ok:
        break;
      case ElevationOutcome.denied:
        return PrivilegeSetupResult.denied;
      case ElevationOutcome.commandFailed:
        return PrivilegeSetupResult.failed;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      // ⚠️ СВЕРЯЕМ isCurrent, А НЕ exists — ЗДЕСЬ И БЫЛ ДЕФЕКТ.
      //
      // Кнопку «Исправить» жмут ровно тогда, когда задача УЖЕ ЕСТЬ, но ведёт
      // на другой exe или другие пути. exists() в этом случае истинно с
      // первой же итерации: метод возвращал успех, даже если schtasks не
      // отработал, интерфейс писал «задача пересоздана», а при следующем
      // подключении заметка приходила снова. Жалоба владельца 03.09.2026:
      // «кнопка Исправить НЕ РАБОТАЕТ» — она отчитывалась об успехе,
      // которого не случилось.
      if (await isCurrent()) {
        AppLog.i('Задача Планировщика создана и запускает то, что нужно');
        return PrivilegeSetupResult.done;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    // Права были, команда отработала — а задача не та. Это не отказ в
    // правах, и называть его так нельзя: в журнал — что именно записалось.
    AppLog.e('Задача Планировщика после создания не совпала с ожидаемой. '
        'Записано: ${await _describe()}');
    return PrivilegeSetupResult.failed;
  }

  /// Команда и аргументы задачи как они лежат в Планировщике — для журнала.
  static Future<String> _describe() async {
    try {
      final r = await Process.run(
          'schtasks', ['/Query', '/TN', taskName, '/XML'],
          stdoutEncoding: null);
      if (r.exitCode != 0) return 'задачи нет';
      final xml = decodeQueryOutput(r.stdout as List<int>);
      return '«${tag(xml, 'Command')}» «${tag(xml, 'Arguments')}»';
    } catch (e) {
      return 'не прочитать: $e';
    }
  }

  /// Запустить TUN через задачу — без UAC. false, если задачи нет или запуск не удался.
  static Future<bool> run() async {
    try {
      // #8 — `schtasks /Run` МОЛЧА игнорирует запуск, пока задача в состоянии
      // Running: при частом переподключении новый старт терялся, пока прошлый
      // инстанс доигрывал. Ждём, пока прошлый завершится (до 5 с), потом стартуем.
      await _waitNotRunning();
      final r = await Process.run('schtasks', ['/Run', '/TN', taskName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Ждать, пока задача НЕ в состоянии Running (или истечёт таймаут).
  static Future<void> _waitNotRunning() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isRunning()) return;
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  static Future<bool> _isRunning() async {
    try {
      // Вывод — в OEM-кодировке, см. [decodeQueryOutput]: прочитанный
      // системной, русский статус «Выполняется» не узнавался бы никогда.
      final r = await Process.run(
          'schtasks', ['/Query', '/TN', taskName, '/FO', 'LIST', '/V'],
          stdoutEncoding: null);
      final out = decodeQueryOutput(r.stdout as List<int>);
      // Статус локализован: en «Running», ru «Выполняется».
      return out.contains('Running') || out.contains('Выполняется');
    } catch (_) {
      return false;
    }
  }

  /// Удалить задачу (кнопка в настройках и деинсталлятор).
  static Future<bool> uninstall() async {
    try {
      final r = await Process.run('schtasks', ['/Delete', '/TN', taskName, '/F']);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    // Своя задача обычно удаляется и без прав; если нет — просим их.
    return Elevation.runElevatedAsync('schtasks.exe', '/Delete /TN $taskName /F');
  }
}
