import 'dart:io';

import 'app_paths.dart';

/// Сколько файлов и байт унесла уборка.
class LogPruneResult {
  const LogPruneResult(this.files, this.bytes);
  static const empty = LogPruneResult(0, 0);
  final int files;
  final int bytes;
}

/// ИСТОРИЯ ЖУРНАЛОВ ПО СУТКАМ — то, чего настройка «срок хранения» обещала, а
/// код не делал.
///
/// ⚠️ ЧТО БЫЛО НЕ ТАК. `LogRetention` и `LogMaintenance` в проекте есть давно,
/// но занимались они другим: `clean()` удаляет файлы, которым давно не писали,
/// а `RotatingLog` при переполнении сдвигает текущий в единственный
/// `.prev.log`. Активный файл при этом НИКОГДА не стареет — в него пишут
/// постоянно, — значит удалять нечего, архивов не образуется, и «хранить
/// месяц» на деле означает «хранить последние восемь мегабайт». У `singbox.log`
/// на уровне `debug` это сорок минут.
///
/// Владелец 07.09.2026 спросил прямо: «разве не для этого мы делали ротацию с
/// отсрочками в день, неделю, месяц и навсегда? хочешь сказать, там всё
/// затёрлось?» — затёрлось. У него на Wi-Fi отваливалась половина сайтов, он
/// перезагрузился, и разбирать стало нечего.
///
/// ⚠️ ПОЧЕМУ ПО СУТКАМ, А НЕ ПО РАЗМЕРУ. Размер уже есть и решает свою задачу —
/// не дать одному файлу съесть диск. Но человек помнит беду не в мегабайтах, а
/// в днях: «вчера вечером не открывались сайты». Архив по дате отвечает ровно
/// на такой вопрос, а порог размера на него не отвечает никогда.
class LogArchive {
  /// Папка с историей внутри каталога данных.
  static const dirName = 'archive';

  /// Сдвинуть в архив логи, которым последний раз писали НЕ СЕГОДНЯ.
  ///
  /// Возвращает имена уехавших файлов. Вызывается на старте приложения: это
  /// единственный момент, когда файлы гарантированно никем не заняты — ядра
  /// ещё не запущены, а свой лог мы открываем позже.
  ///
  /// ⚠️ ПРИЗНАК — ДАТА ПОСЛЕДНЕЙ ЗАПИСИ, А НЕ ФАКТ ЗАПУСКА. Приложение могут
  /// открывать по десять раз в день; двигая файл на каждом старте, мы получили
  /// бы не историю, а горсть огрызков по паре килобайт.
  static Future<List<String>> rollDaily({Directory? dir, DateTime? now}) async {
    final root = dir ?? await AppPaths.supportDir();
    final today = _dayOf(now ?? DateTime.now());
    final moved = <String>[];
    List<File> files;
    try {
      files = root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.log'))
          .toList();
    } catch (_) {
      return moved;
    }

    for (final f in files) {
      try {
        // Пустой файл — не история, а лишняя строка в списке.
        if (await f.length() == 0) continue;
        final day = _dayOf(await f.lastModified());
        if (day == today) continue;

        final archive = Directory('${root.path}${Platform.pathSeparator}$dirName');
        if (!archive.existsSync()) archive.createSync(recursive: true);

        final base = f.uri.pathSegments.last.replaceAll(RegExp(r'\.log$'), '');
        final target = _freeName(archive, base, day);
        await f.rename(target.path);
        moved.add(target.uri.pathSegments.last);
      } catch (_) {
        // Занятый или недоступный файл пропускаем молча: журнал не имеет права
        // мешать запуску приложения.
      }
    }
    return moved;
  }

  /// Удалить архивы старше [maxAge]. `null` — «навсегда», не трогаем ничего.
  static Future<LogPruneResult> prune(
      {Directory? dir, required Duration? maxAge, DateTime? now}) async {
    if (maxAge == null) return LogPruneResult.empty;
    final root = dir ?? await AppPaths.supportDir();
    final archive = Directory('${root.path}${Platform.pathSeparator}$dirName');
    if (!archive.existsSync()) return LogPruneResult.empty;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    var files = 0;
    var bytes = 0;
    try {
      for (final f in archive.listSync().whereType<File>()) {
        try {
          if (!(await f.lastModified()).isBefore(cutoff)) continue;
          final size = await f.length();
          await f.delete();
          files++;
          bytes += size;
        } catch (_) {}
      }
    } catch (_) {}
    return LogPruneResult(files, bytes);
  }

  /// Свободное имя `<база>-ГГГГ-ММ-ДД[-N].log`.
  ///
  /// ⚠️ СУФФИКС ОБЯЗАТЕЛЕН. За сутки лог ядра переполняется не раз (порог
  /// 8 МиБ), и совпадение имён уничтожило бы ровно то, ради чего архив и
  /// заводится.
  static File _freeName(Directory archive, String base, String day) {
    final sep = Platform.pathSeparator;
    var f = File('${archive.path}$sep$base-$day.log');
    var n = 2;
    while (f.existsSync()) {
      f = File('${archive.path}$sep$base-$day-$n.log');
      n++;
    }
    return f;
  }

  static String _dayOf(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
