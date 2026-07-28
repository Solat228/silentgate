import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Файловый лог с усечением: пишет строки и не даёт файлу расти без предела.
///
/// Вынесено из `TunHelper`, где эта логика уже выстрадана: у пользователя
/// `singbox.log` дорос до **758 МБ**, потому что усечение проверялось только при
/// открытии, а внутри сессии ядро писало без ограничений. Второй урок оттуда же:
/// хвост нужно читать **с конца файла**, иначе кнопка «Написать в поддержку»
/// затягивает сотни мегабайт в память и подвешивает приложение.
///
/// ⚠️ Класс намеренно **инстансный**, а не статический: в одном процессе живут
/// два разных лога (TUN-ядро и прокси-ядро), и общий счётчик размера у них
/// разъезжался бы с реальностью.
class RotatingLog {
  RotatingLog(this.path, {this.maxBytes = 512 * 1024});

  final String path;

  /// Порог усечения. При достижении файл начинается заново — так дешевле и
  /// надёжнее, чем перекладывать хвост: лог нужен для диагностики «прямо
  /// сейчас», а не как архив.
  final int maxBytes;

  IOSink? _sink;
  int _written = 0;

  /// Закрыт окончательно. Ставится ДО первого await в [close], иначе идущая
  /// ротация переоткрывала файл уже после закрытия и дескриптор жил до конца
  /// процесса.
  bool _closed = false;

  /// Хвост очереди записи.
  ///
  /// ⚠️ Записи ОБЯЗАНЫ идти строго по одной. `onLine` вызывается для каждой
  /// строки чанка синхронно подряд (`LineSplitter` отдаёт их пачкой), а
  /// [write] после `await _restart()` отпускает цикл событий. Без очереди
  /// каждая строка пачки запускала СВОЮ ротацию: файл усекался повторно,
  /// стирая только что записанное, порядок строк переворачивался, а прежние
  /// `IOSink` терялись не закрытыми. На практике это значило, что FATAL-строка,
  /// ради которой лог и заводили, пропадала именно в момент аварии.
  Future<void> _queue = Future<void>.value();

  bool get isOpen => _sink != null && !_closed;

  /// Открывает файл на дозапись. Существующий лог, уже переросший порог,
  /// усекается сразу — иначе первая же сессия начиналась бы с мусора прошлой.
  Future<void> open() async {
    if (_sink != null) return;
    try {
      final f = File(path);
      var size = 0;
      if (await f.exists()) {
        size = await f.length();
        if (size > maxBytes) {
          await f.writeAsString('');
          size = 0;
        }
      } else {
        await f.parent.create(recursive: true);
      }
      _written = size;
      _sink = f.openWrite(mode: FileMode.append);
    } catch (_) {
      // Лог не имеет права уронить подъём туннеля: не смогли — работаем без него.
      _sink = null;
    }
  }

  /// Пишет строку (перевод строки добавляется сам). Когда файл перерастает
  /// порог — начинается заново прямо на лету, без перезапуска приложения.
  Future<void> write(String line) {
    if (_closed) return Future<void>.value();
    // Ставим в очередь, а не пишем сразу: см. комментарий к [_queue].
    _queue = _queue.then((_) => _writeOne(line)).catchError((_) {});
    return _queue;
  }

  Future<void> _writeOne(String line) async {
    if (_closed || _sink == null) return;
    try {
      if (_written >= maxBytes) await _restart();
      final sink = _sink;
      if (sink == null) return;
      sink.writeln(line);
      // Считаем БАЙТЫ, а не символы: поле называется maxBytes и сравнивается с
      // размером файла. На кириллице (а наши собственные строки русские) счёт
      // по символам занижал объём вдвое, по эмодзи — вчетверо.
      _written += utf8.encode(line).length + 1;
    } catch (_) {}
  }

  Future<void> _restart() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    if (_closed) return;
    try {
      final f = File(path);
      await f.writeAsString('');
      _written = 0;
      _sink = f.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
    }
  }

  Future<void> close() async {
    // Флаг ДО await: иначе запись, уже стоящая в очереди, переоткроет файл.
    _closed = true;
    try {
      await _queue;
    } catch (_) {}
    final sink = _sink;
    _sink = null;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
  }

  /// Последние [lines] строк файла [path].
  ///
  /// Читает не более [tailBytes] с КОНЦА: файл может быть на сотни мегабайт.
  /// Первая (заведомо оборванная) строка отбрасывается, битые UTF-8-границы
  /// не бросают исключение.
  static Future<String> tail(String path,
      {int lines = 40, int tailBytes = 512 * 1024}) async {
    RandomAccessFile? raf;
    try {
      final f = File(path);
      if (!await f.exists()) return '';
      final size = await f.length();
      raf = await f.open();
      final from = size > tailBytes ? size - tailBytes : 0;
      await raf.setPosition(from);
      final bytes = await raf.read(size - from);
      var text = utf8.decode(bytes, allowMalformed: true);
      if (from > 0) {
        final nl = text.indexOf('\n');
        if (nl >= 0) text = text.substring(nl + 1);
      }
      final all = const LineSplitter().convert(text);
      return all.length <= lines
          ? all.join('\n')
          : all.sublist(all.length - lines).join('\n');
    } catch (_) {
      return '';
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }
}
