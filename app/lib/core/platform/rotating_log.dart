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
///
/// ⚠️ ЗДЕСЬ ЖЕ ЖИВЁТ ОБРЕЗКА — И ЭТО ГЛАВНОЕ ПРАВИЛО ФАЙЛА. Обрезать лог
/// откуда-то ещё (`File.writeAsString('')` мимо этого класса) НЕЛЬЗЯ. Причина
/// измерена на живых файлах владельца 12.08.2026: в `app.log` 93 % содержимого
/// оказались НУЛЕВЫМИ БАЙТАМИ (434 847 подряд), в `singbox.log` — 98 %.
/// `openWrite(FileMode.append)` в Dart запоминает смещение ОДИН раз, в момент
/// открытия, и дальше пишет по нему; после чужой обрезки поток продолжает
/// писать по старому адресу, а Windows добивает пропуск нулями. Отсюда же
/// [truncate]: обрезка обязана идти через тот же объект, чтобы поток был
/// ПЕРЕСОЗДАН, а не продолжил писать в пустоту.
class RotatingLog {
  RotatingLog(this.path, {this.maxBytes = 512 * 1024});

  final String path;

  /// Порог усечения. При достижении файл начинается заново — так дешевле и
  /// надёжнее, чем перекладывать хвост: лог нужен для диагностики «прямо
  /// сейчас», а не как архив.
  final int maxBytes;

  IOSink? _sink;
  int _written = 0;

  /// [open] уже отработал (успешно или нет). Отделено от `_sink != null`:
  /// гость (см. [isOwner]) пишет без своего потока, но писать ему можно.
  bool _opened = false;

  /// Мы — владелец файла, то есть только нам можно его ОБРЕЗАТЬ.
  ///
  /// ⚠️ У владельца запущены ДВЕ копии приложения, и обе пишут в один файл.
  /// Обрезка из второй копии портит лог первой гарантированно: её поток
  /// продолжит писать по своему старому смещению (см. шапку класса).
  bool _owner = false;

  /// Захваченная блокировка диапазона ЗА пределами файла (см. [_claimOwnership]).
  RandomAccessFile? _ownerLock;

  /// Смещение блокировки — заведомо дальше любого реального размера лога,
  /// чтобы блокировка не мешала собственным записям (Windows-блокировки
  /// обязательные: диапазон, запертый одним дескриптором, недоступен другому
  /// даже внутри того же процесса).
  static const _lockOffset = 1 << 40;

  /// Открытие мемоизировано: [open] зовут и явно, и (для гостя) косвенно, а
  /// повторный захват блокировки означал бы потерю владения на ровном месте.
  Future<void>? _opening;

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

  /// Владеем ли мы файлом. Гость (вторая копия приложения, второй экземпляр
  /// хелпера) писать может, а обрезать — нет.
  bool get isOwner => _owner;

  /// Открывает файл на дозапись. Существующий лог, уже переросший порог,
  /// усекается сразу — иначе первая же сессия начиналась бы с мусора прошлой.
  ///
  /// Идемпотентна: повторный вызов возвращает тот же Future.
  Future<void> open() => _opening ??= _open();

  Future<void> _open() async {
    if (_sink != null) return;
    try {
      await File(path).parent.create(recursive: true);
    } catch (_) {}
    await _claimOwnership();
    try {
      final f = File(path);
      var size = 0;
      if (await f.exists()) {
        size = await f.length();
        // ⚠️ Усечение — только владельцу. Гость, обрезавший файл при открытии,
        // разом обнулил бы смещение живого потока первой копии, и весь пропуск
        // Windows залила бы нулями.
        if (size > maxBytes && _owner) {
          await f.writeAsString('');
          size = 0;
        }
      }
      _written = size;
      // Гость своего потока НЕ держит: он дописывает каждую строку отдельным
      // открытием файла (см. [_appendAsGuest]) — так его смещение всегда
      // равно реальному концу файла, что бы ни делала первая копия.
      if (_owner) _sink = f.openWrite(mode: FileMode.append);
    } catch (_) {
      // Лог не имеет права уронить подъём туннеля: не смогли — работаем без него.
      _sink = null;
    }
    _opened = true;
  }

  /// Пробуем стать владельцем: запираем однобайтовый диапазон далеко за концом
  /// файла. Блокировка снимается операционной системой сама, если процесс умер,
  /// — поэтому она переживает аварийное завершение, в отличие от файла-метки.
  ///
  /// Не смогли даже открыть файл — считаем себя владельцем: иначе единственная
  /// копия приложения из-за случайной ошибки навсегда осталась бы без ротации,
  /// и лог рос бы без предела (ровно та беда, ради которой класс и написан).
  Future<void> _claimOwnership() async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open(mode: FileMode.append);
    } catch (_) {
      _owner = true;
      return;
    }
    try {
      await raf.lock(FileLock.exclusive, _lockOffset, _lockOffset + 1);
      _ownerLock = raf;
      _owner = true;
    } catch (_) {
      // Диапазон занят — файл уже ведёт другой экземпляр.
      _owner = false;
      try {
        await raf.close();
      } catch (_) {}
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
    // Без open() запись игнорируется: лог не имеет права создавать файлы сам по
    // себе — иначе он появлялся бы у тех, кто ядро ни разу не запускал.
    if (_closed || !_opened) return;
    try {
      if (!_owner) {
        await _appendAsGuest(line);
        return;
      }
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

  /// Запись гостя: КАЖДАЯ строка — отдельным открытием файла.
  ///
  /// Дороже потока, но единственно верно для второй копии приложения: смещение
  /// у `FileMode.append` фиксируется при открытии, поэтому долгоживущий поток
  /// гостя затирал бы написанное владельцем, а после обрезки владельцем — ещё
  /// и заливал бы разрыв нулями. Гость к тому же не держит дескриптор, и его
  /// лог можно удалить чисткой по сроку хранения.
  Future<void> _appendAsGuest(String line) async {
    try {
      await File(path).writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Обрезать файл, не ломая запись: поток ПЕРЕСОЗДАЁТСЯ.
  ///
  /// ⚠️ Единственный разрешённый способ очистить лог. Прямой
  /// `File.writeAsString('')` мимо этого метода оставляет живой поток с
  /// прежним смещением — и файл заполняется нулями до этого смещения (см.
  /// шапку класса). [header] — строка, с которой начинается новый файл.
  ///
  /// Гость (вторая копия) чужой лог не обрезает вовсе: молча ничего не делает.
  Future<void> truncate({String header = ''}) {
    _queue = _queue.then((_) => _truncateOne(header)).catchError((_) {});
    return _queue;
  }

  Future<void> _truncateOne(String header) async {
    if (_closed) return;
    await open();
    if (!_owner) return;
    await _restart(header: header);
  }

  /// Дописать всё, что осело в буфере потока, на диск.
  ///
  /// Нужно перед чтением файла (экран логов, отчёт поддержки): `writeln`
  /// буферизуется, и без сброса последние — самые важные — строки в файле ещё
  /// не лежат.
  Future<void> flush() {
    _queue = _queue.then((_) async {
      try {
        await _sink?.flush();
      } catch (_) {}
    }).catchError((_) {});
    return _queue;
  }

  Future<void> _restart({String header = ''}) async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    if (_closed) return;
    try {
      final f = File(path);
      await f.writeAsString(header);
      _written = utf8.encode(header).length;
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
    // Блокировку владения отпускаем ЯВНО: иначе следующий экземпляр в этом же
    // процессе (тесты, перезапуск ядра) считал бы себя гостем и перестал бы
    // ротировать файл.
    final lock = _ownerLock;
    _ownerLock = null;
    _owner = false;
    try {
      await lock?.unlock(_lockOffset, _lockOffset + 1);
      await lock?.close();
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
