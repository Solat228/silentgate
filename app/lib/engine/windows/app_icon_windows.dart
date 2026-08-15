import 'dart:ffi';
import 'dart:io' show Directory, FileSystemEntity, FileSystemEntityType, zlib;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'process_list_windows.dart';

/// Извлечение иконки exe (#1, split-tunnel): SHGetFileInfo → HICON → 32bpp DIB → PNG.
/// PNG кодируется вручную (zlib из dart:io + CRC32) — без внешних зависимостей.
/// Результат кэшируется по пути; неудача → null (UI покажет заглушку).
///
/// ВАЖНО: извлечение выполняется в фоновом isolate ([load]) — SHGetFileInfo может
/// блокироваться на недоступных путях (отключённый сетевой диск, вынутая флешка),
/// и синхронный вызов в build() замораживал бы весь интерфейс.
///
/// ⚠️ ПУТЬ ИЗ ПРАВИЛА — НЕ ГАРАНТИЯ ЖИВОГО ФАЙЛА. `AppRule.path` замораживается в
/// момент добавления и после обновления программы указывает в никуда: у владельца
/// правило `claude.exe` хранит
/// `…\anthropic.claude-code-2.1.228-win32-x64\…\claude.exe`, а на диске лежат уже
/// `2.1.232` и `2.1.233` — иконка пропадала именно поэтому, а не «иногда».
/// Подменять сам путь НЕЛЬЗЯ (он уходит в `process_name` конфига ядра), поэтому
/// живой файл ищется отдельно и только ради картинки — см. [locateExeForIcon].
class AppIconWindows {
  static final Map<String, Uint8List?> _cache = {};
  static final Map<String, Future<Uint8List?>> _pending = {};

  static const _shgfiIcon = 0x000000100; // SHGFI_ICON
  static const _shgfiLargeIcon = 0x000000000; // SHGFI_LARGEICON (32×32)

  /// Иконка из кэша (null и если ещё не грузили, и если извлечь не удалось).
  static Uint8List? cached(String exePath) => _cache[exePath.toLowerCase()];

  /// Есть ли запись в кэше (отличает «не грузили» от «не удалось»).
  static bool isCached(String exePath) =>
      _cache.containsKey(exePath.toLowerCase());

  /// Асинхронная загрузка иконки в фоновом isolate, с кэшем и дедупликацией
  /// одновременных запросов на один и тот же путь.
  ///
  /// ⚠️ ДВА ЗАХОДА, И ВТОРОЙ ПЛАТНЫЙ. Сначала пробуем ровно тот путь, что в
  /// правиле, — это обычный случай и он стоит столько же, сколько раньше.
  /// Только если иконки нет, ищем живой файл ([locateExeForIcon]) и пробуем
  /// его. Порядок именно такой, чтобы перечисление процессов не запускалось на
  /// каждом старте экрана: у большинства правил путь жив, и второй заход не
  /// нужен вовсе.
  ///
  /// Результат (в том числе НЕудача) кладётся в кэш по ИСХОДНОМУ ключу, поэтому
  /// поиск идёт максимум один раз на правило за сеанс, а не на перерисовку.
  static Future<Uint8List?> load(String exePath) {
    final key = exePath.toLowerCase();
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _pending.putIfAbsent(key, () async {
      Uint8List? png;
      try {
        png = await Isolate.run(() => _extract(exePath));
        png ??= await _extractRelocated(exePath);
      } catch (_) {
        png = null;
      }
      _cache[key] = png;
      _pending.remove(key);
      return png;
    });
  }

  /// Второй заход: иконка живого файла той же программы.
  ///
  /// Возвращает `null`, когда искать нечего или найден тот же самый путь, —
  /// повторно дёргать ядро тем же аргументом бессмысленно.
  static Future<Uint8List?> _extractRelocated(String stored) async {
    final running = await _runningIndex();
    return Isolate.run(() {
      final found = locateExeForIcon(stored, WindowsExeSources(running));
      if (found == null || found.toLowerCase() == stored.toLowerCase()) {
        return null;
      }
      return _extract(found);
    });
  }

  /// Имя exe (в нижнем регистре) → путь запущенного процесса.
  ///
  /// Считается ОДИН раз за сеанс и в фоновом isolate: перечисление открывает
  /// дескриптор к каждому процессу машины, и на UI-потоке это заметно.
  /// ⚠️ Снимок намеренно не обновляется: результат каждой иконки всё равно
  /// закэширован, и пересчёт ничего бы не изменил без сброса кэша картинок.
  static Future<Map<String, String>>? _runningIndexFuture;

  /// ⚠️ Отказ перечисления НЕ отравляет память: снимок запоминается навсегда, и
  /// сохранённая ошибка означала бы, что этот источник мёртв до перезапуска.
  /// Пустой снимок читается как «процесса с таким именем нет» — поиск спокойно
  /// идёт к следующему источнику.
  static Future<Map<String, String>> _runningIndex() =>
      _runningIndexFuture ??= Isolate.run(_enumerateRunning)
          .catchError((Object _) => <String, String>{});

  static Map<String, String> _enumerateRunning() {
    final out = <String, String>{};
    for (final p in ProcessListWindows.enumerate()) {
      // Первый победил: тёзки бывают (несколько окон одной программы), и путь
      // у них один и тот же.
      out.putIfAbsent(p.name.toLowerCase(), () => p.path);
    }
    return out;
  }

  /// Синхронное извлечение РОВНО ПО ЭТОМУ ПУТИ (для тестов и предзагрузки вне
  /// UI-потока). Живой файл не ищет — это делает только [load].
  static Uint8List? iconPng(String exePath) =>
      _cache.putIfAbsent(exePath.toLowerCase(), () => _extract(exePath));

  static Uint8List? _extract(String exePath) {
    // 1) ExtractIconEx — берёт иконку ПРЯМО из ресурсов самого exe (индекс 0).
    //    Надёжнее SHGetFileInfo, который отдаёт иконку по ассоциации оболочки и
    //    иногда путал/менял местами значки (Chrome ↔ Telegram). Если у файла нет
    //    встроенной иконки — падаем на SHGetFileInfo (2).
    final byResource = _extractByResource(exePath);
    if (byResource != null) return byResource;
    return _extractByShell(exePath);
  }

  /// ExtractIconExW из shell32 (в пакете win32 его нет — биндим вручную).
  static final _ExtractIconEx _extractIconEx = DynamicLibrary.open('shell32.dll')
      .lookupFunction<_ExtractIconExNative, _ExtractIconEx>('ExtractIconExW');

  static Uint8List? _extractByResource(String exePath) {
    final pathPtr = exePath.toNativeUtf16();
    final large = calloc<IntPtr>();
    final small = calloc<IntPtr>();
    try {
      // Запрашиваем 1 большую иконку из ресурса с индексом 0.
      final count = _extractIconEx(pathPtr, 0, large, small, 1);
      final hIcon = large.value != 0 ? large.value : small.value;
      if (count <= 0 || hIcon == 0) return null;
      try {
        return _iconToPng(hIcon);
      } finally {
        if (large.value != 0) DestroyIcon(large.value);
        if (small.value != 0 && small.value != large.value) {
          DestroyIcon(small.value);
        }
      }
    } catch (_) {
      return null;
    } finally {
      free(pathPtr);
      free(large);
      free(small);
    }
  }

  static Uint8List? _extractByShell(String exePath) {
    final pathPtr = exePath.toNativeUtf16();
    final shfi = calloc<SHFILEINFO>();
    try {
      final r = SHGetFileInfo(
          pathPtr, 0, shfi, sizeOf<SHFILEINFO>(), _shgfiIcon | _shgfiLargeIcon);
      if (r == 0 || shfi.ref.hIcon == 0) return null;
      final hIcon = shfi.ref.hIcon;
      try {
        return _iconToPng(hIcon);
      } finally {
        DestroyIcon(hIcon);
      }
    } catch (_) {
      return null;
    } finally {
      free(pathPtr);
      free(shfi);
    }
  }

  static Uint8List? _iconToPng(int hIcon) {
    final info = calloc<ICONINFO>();
    if (GetIconInfo(hIcon, info) == 0) {
      free(info);
      return null;
    }
    final hbmColor = info.ref.hbmColor;
    final hbmMask = info.ref.hbmMask;
    free(info);
    try {
      if (hbmColor == 0) return null; // монохромные не поддерживаем

      final bmp = calloc<BITMAP>();
      try {
        if (GetObject(hbmColor, sizeOf<BITMAP>(), bmp) == 0) return null;
        final w = bmp.ref.bmWidth, h = bmp.ref.bmHeight;
        if (w <= 0 || h <= 0 || w > 256 || h > 256) return null;

        final bgra = _dibits(hbmColor, w, h);
        if (bgra == null) return null;

        // Legacy-иконки без альфа-канала: берём прозрачность из битовой маски.
        var hasAlpha = false;
        for (var i = 3; i < bgra.length; i += 4) {
          if (bgra[i] != 0) {
            hasAlpha = true;
            break;
          }
        }
        if (!hasAlpha) {
          final mask = hbmMask != 0 ? _dibits(hbmMask, w, h) : null;
          for (var i = 0; i < w * h; i++) {
            // В маске белый = прозрачный, чёрный = непрозрачный.
            final opaque = mask == null || mask[i * 4] < 128;
            bgra[i * 4 + 3] = opaque ? 255 : 0;
          }
        }

        // BGRA → RGBA.
        final rgba = Uint8List(w * h * 4);
        for (var i = 0; i < w * h; i++) {
          rgba[i * 4] = bgra[i * 4 + 2];
          rgba[i * 4 + 1] = bgra[i * 4 + 1];
          rgba[i * 4 + 2] = bgra[i * 4];
          rgba[i * 4 + 3] = bgra[i * 4 + 3];
        }
        return encodePng(w, h, rgba);
      } finally {
        free(bmp);
      }
    } finally {
      if (hbmColor != 0) DeleteObject(hbmColor);
      if (hbmMask != 0) DeleteObject(hbmMask);
    }
  }

  /// Пиксели битмапа как 32bpp top-down BGRA (GetDIBits конвертирует сам).
  static Uint8List? _dibits(int hbm, int w, int h) {
    final hdc = CreateCompatibleDC(0);
    final bmi = calloc<BITMAPINFO>();
    final bits = calloc<Uint8>(w * h * 4);
    try {
      bmi.ref.bmiHeader
        ..biSize = sizeOf<BITMAPINFOHEADER>()
        ..biWidth = w
        ..biHeight = -h // top-down
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = BI_RGB;
      final got = GetDIBits(hdc, hbm, 0, h, bits.cast(), bmi, DIB_RGB_COLORS);
      if (got == 0) return null;
      return Uint8List.fromList(bits.asTypedList(w * h * 4));
    } finally {
      free(bits);
      free(bmi);
      DeleteDC(hdc);
    }
  }

  // ── Минимальный PNG-энкодер (RGBA8, без фильтров) ───────────────────────────
  static Uint8List encodePng(int w, int h, Uint8List rgba) {
    // Скан-линии: байт фильтра 0 + пиксели.
    final stride = w * 4;
    final raw = Uint8List(h * (1 + stride));
    for (var y = 0; y < h; y++) {
      final o = y * (1 + stride);
      raw[o] = 0;
      raw.setRange(o + 1, o + 1 + stride, rgba, y * stride);
    }
    final idat = zlib.encode(raw);

    final ihdr = BytesBuilder()
      ..add(_u32(w))
      ..add(_u32(h))
      ..add(const [8, 6, 0, 0, 0]); // 8 бит, RGBA, стандартные методы

    final out = BytesBuilder()
      ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      ..add(_chunk('IHDR', ihdr.toBytes()))
      ..add(_chunk('IDAT', idat))
      ..add(_chunk('IEND', const []));
    return out.toBytes();
  }

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static List<int> _chunk(String type, List<int> data) {
    final t = type.codeUnits;
    final crc = _crc32([...t, ...data]);
    return [..._u32(data.length), ...t, ...data, ..._u32(crc)];
  }

  static final Uint32List _crcTable = _buildCrcTable();
  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  static int _crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

// UINT ExtractIconExW(LPCWSTR, int nIconIndex, HICON* large, HICON* small, UINT n)
typedef _ExtractIconExNative = Uint32 Function(
    Pointer<Utf16>, Int32, Pointer<IntPtr>, Pointer<IntPtr>, Uint32);
typedef _ExtractIconEx = int Function(
    Pointer<Utf16>, int, Pointer<IntPtr>, Pointer<IntPtr>, int);

/// Откуда узнаём про диск и запущенные программы.
///
/// Вынесено интерфейсом ровно ради теста: сам поиск — чистая работа со строками
/// и парой вопросов к системе, и проверять его, подкладывая настоящие файлы и
/// процессы, значило бы проверять Windows вместо своего кода.
abstract interface class ExeSources {
  /// Есть ли на диске такой файл ИЛИ каталог.
  bool exists(String path);

  /// Имена элементов каталога (и папок, и файлов), без пути.
  List<String> entriesOf(String dir);

  /// Путь запущенного процесса с таким именем файла; `null` — не запущен.
  String? runningPathFor(String exeName);
}

/// Настоящие источники: файловая система + заранее снятый список процессов.
class WindowsExeSources implements ExeSources {
  /// Имя exe в нижнем регистре → путь. Снимок передаётся снаружи, потому что
  /// перечисление процессов делается один раз, а источников — по одному на
  /// каждый поиск.
  final Map<String, String> running;

  const WindowsExeSources(this.running);

  @override
  bool exists(String path) {
    try {
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  @override
  List<String> entriesOf(String dir) {
    try {
      return Directory(dir)
          .listSync(followLinks: false)
          .map((e) => _baseName(e.path))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  String? runningPathFor(String exeName) => running[exeName.toLowerCase()];
}

/// Живой exe той же программы — ТОЛЬКО ДЛЯ ПОКАЗА ИКОНКИ.
///
/// ⚠️ РЕЗУЛЬТАТ НЕЛЬЗЯ ЗАПИСЫВАТЬ В `AppRule.path`. Путь правила — это вход
/// конфига ядра (`process_name` и `process_path`), и подмена найденным путём
/// изменила бы то, с чем ядро сравнивает процессы: правило «по пути» начало бы
/// совпадать с другим файлом, а «по имени» — потеряло бы смысл записи, которую
/// пользователь заводил. Иконка — отдельная сущность, и живёт она в кэше
/// картинок, а не в настройках.
///
/// Порядок источников — от дешёвого к дорогому:
///  1. сам путь, если файл на месте (обычный случай, стоит один вопрос к ФС);
///  2. ЗАПУЩЕННЫЙ процесс с тем же именем файла — самый точный ответ: это
///     буквально та программа, которую правило «по имени» и ловит. Заодно
///     закрывает случай, когда в правиле лежит голое имя без каталога;
///  3. соседний каталог/файл, отличающийся ТОЛЬКО цифрами. Обновляемые
///     программы ставятся в каталог с версией в имени (`…claude-code-2.1.228…`,
///     `Discord\app-1.0.9046`), и именно у них путь умирает при каждом
///     обновлении — а программа при этом может быть не запущена.
///
/// Реестр `App Paths` намеренно НЕ спрашиваем: там регистрируются программы с
/// постоянным путём установки, то есть ровно те, у которых путь и не ломается.
String? locateExeForIcon(String stored, ExeSources src) {
  final path = stored.trim();
  if (path.isEmpty) return null;
  if (src.exists(path)) return path;

  final name = _baseName(path);
  if (name.isEmpty) return null;
  final running = src.runningPathFor(name);
  if (running != null && running.trim().isNotEmpty) return running.trim();

  return _versionSibling(path, src);
}

final RegExp _sepRe = RegExp(r'[\\/]');

String _baseName(String p) {
  final i = p.lastIndexOf(_sepRe);
  return i < 0 ? p : p.substring(i + 1);
}

/// Тот же путь, но через соседнюю версию каталога (или файла).
///
/// Ищем ПЕРВЫЙ сегмент пути, которого нет на диске: выше него всё цело, и
/// именно он «уехал» при обновлении. Среди соседей берём те, что отличаются от
/// него только цифрами, и пробуем от самой новой версии к старой — иконка
/// должна быть от того, чем человек пользуется сейчас.
String? _versionSibling(String path, ExeSources src) {
  final parts = path.split(_sepRe);
  if (parts.length < 2) return null;

  var prefix = parts.first;
  if (prefix.isEmpty) return null; // UNC (`\\server\share`) — не наш случай
  var broken = -1;
  for (var i = 1; i < parts.length; i++) {
    final next = '$prefix\\${parts[i]}';
    if (!src.exists(next)) {
      broken = i;
      break;
    }
    prefix = next;
  }
  if (broken < 0) return null;

  final missing = parts[broken];
  // ⚠️ Без цифр в имени сравнивать нечего — и каталог мы тогда НЕ читаем вовсе.
  // Иначе каждая иконка с мёртвым путём (например, удалённая программа) гоняла
  // бы перечисление каталога впустую.
  if (!RegExp(r'\d').hasMatch(missing)) return null;

  final pattern = _digitsMasked(missing);
  final tail = parts.sublist(broken + 1);
  final candidates = <String>[];
  for (final e in src.entriesOf(prefix)) {
    if (e.toLowerCase() == missing.toLowerCase()) continue;
    if (_digitsMasked(e) == pattern) candidates.add(e);
  }
  candidates.sort((a, b) => _compareVersions(b, a)); // новые впереди

  for (final c in candidates) {
    final candidate = [prefix, c, ...tail].join('\\');
    if (src.exists(candidate)) return candidate;
  }
  return null;
}

/// `claude-code-2.1.228-win32-x64` → `claude-code-#.#.#-win#-x#`.
/// Регистр гасим здесь же: на Windows он в путях не значим.
String _digitsMasked(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\d+'), '#');

/// Сравнение по числам в имени: `2.1.9` < `2.1.10` (не строкой — строкой «10»
/// меньше «9», и свежая версия оказалась бы старшей).
int _compareVersions(String a, String b) {
  final na = _numbers(a), nb = _numbers(b);
  for (var i = 0; i < na.length && i < nb.length; i++) {
    final c = na[i].compareTo(nb[i]);
    if (c != 0) return c;
  }
  if (na.length != nb.length) return na.length.compareTo(nb.length);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

List<int> _numbers(String s) => RegExp(r'\d+')
    .allMatches(s)
    .map((m) => int.tryParse(m.group(0)!) ?? 0)
    .toList();
