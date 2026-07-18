import 'dart:ffi';
import 'dart:io' show zlib;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Извлечение иконки exe (#1, split-tunnel): SHGetFileInfo → HICON → 32bpp DIB → PNG.
/// PNG кодируется вручную (zlib из dart:io + CRC32) — без внешних зависимостей.
/// Результат кэшируется по пути; неудача → null (UI покажет заглушку).
///
/// ВАЖНО: извлечение выполняется в фоновом isolate ([load]) — SHGetFileInfo может
/// блокироваться на недоступных путях (отключённый сетевой диск, вынутая флешка),
/// и синхронный вызов в build() замораживал бы весь интерфейс.
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
  static Future<Uint8List?> load(String exePath) {
    final key = exePath.toLowerCase();
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _pending.putIfAbsent(key, () async {
      Uint8List? png;
      try {
        png = await Isolate.run(() => _extract(exePath));
      } catch (_) {
        png = null;
      }
      _cache[key] = png;
      _pending.remove(key);
      return png;
    });
  }

  /// Синхронное извлечение (для тестов и предзагрузки вне UI-потока).
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
