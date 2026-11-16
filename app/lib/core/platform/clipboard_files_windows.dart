import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

typedef _IsClipboardFormatAvailableNative = Int32 Function(Uint32 format);
typedef _IsClipboardFormatAvailableDart = int Function(int format);

typedef _OpenClipboardNative = Int32 Function(IntPtr hWndNewOwner);
typedef _OpenClipboardDart = int Function(int hWndNewOwner);

typedef _CloseClipboardNative = Int32 Function();
typedef _CloseClipboardDart = int Function();

typedef _GetClipboardDataNative = IntPtr Function(Uint32 uFormat);
typedef _GetClipboardDataDart = int Function(int uFormat);

typedef _DragQueryFileWNative = Uint32 Function(
    IntPtr hDrop, Uint32 iFile, Pointer<Utf16> lpszFile, Uint32 cch);
typedef _DragQueryFileWDart = int Function(
    int hDrop, int iFile, Pointer<Utf16> lpszFile, int cch);

/// Чтение скопированных в Проводнике файлов (`CF_HDROP`, формат `15`) на Windows.
///
/// Когда человек выделяет файл вроде `Silentgate.txt` на рабочем столе и жмёт
/// `Ctrl+C`, в буфере обмена лежит список путей `CF_HDROP`, а текстовый формат
/// `CF_UNICODETEXT` пуст — поэтому штатный `Clipboard.getData(kTextPlain)`
/// возвращает `null`, и `Ctrl+V` ничего не вставляет.
abstract final class ClipboardFilesWindows {
  static const int _cfHdrop = 15;

  /// Переопределение для юнит- и виджет-тестов без прикосновения к системному буферу.
  @visibleForTesting
  static List<String> Function()? debugReadFiles;

  static DynamicLibrary? _user32;
  static DynamicLibrary? _shell32;
  static _IsClipboardFormatAvailableDart? _isFormatAvailable;
  static _OpenClipboardDart? _openClipboard;
  static _CloseClipboardDart? _closeClipboard;
  static _GetClipboardDataDart? _getClipboardData;
  static _DragQueryFileWDart? _dragQueryFileW;

  static void _ensureLoaded() {
    if (_user32 != null && _shell32 != null) return;
    final u32 = DynamicLibrary.open('user32.dll');
    final sh32 = DynamicLibrary.open('shell32.dll');
    _user32 = u32;
    _shell32 = sh32;
    _isFormatAvailable = u32.lookupFunction<_IsClipboardFormatAvailableNative,
        _IsClipboardFormatAvailableDart>('IsClipboardFormatAvailable');
    _openClipboard =
        u32.lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
            'OpenClipboard');
    _closeClipboard =
        u32.lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
            'CloseClipboard');
    _getClipboardData =
        u32.lookupFunction<_GetClipboardDataNative, _GetClipboardDataDart>(
            'GetClipboardData');
    _dragQueryFileW =
        sh32.lookupFunction<_DragQueryFileWNative, _DragQueryFileWDart>(
            'DragQueryFileW');
  }

  /// Список файлов из системного буфера обмена (`CF_HDROP`), либо пустой список.
  static List<String> readFiles() {
    final override = debugReadFiles;
    if (override != null) return override();
    if (!Platform.isWindows) return const [];
    try {
      _ensureLoaded();
      if (_isFormatAvailable!(_cfHdrop) == 0) return const [];
      var opened = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_openClipboard!(0) != 0) {
          opened = true;
          break;
        }
      }
      if (!opened) return const [];
      try {
        final hDrop = _getClipboardData!(_cfHdrop);
        if (hDrop == 0) return const [];
        final count = _dragQueryFileW!(hDrop, 0xFFFFFFFF, nullptr, 0);
        if (count <= 0 || count > 256) return const [];
        final out = <String>[];
        for (var i = 0; i < count; i++) {
          final len = _dragQueryFileW!(hDrop, i, nullptr, 0);
          if (len <= 0 || len > 32768) continue;
          final buf = calloc<Uint16>(len + 1);
          try {
            final copied =
                _dragQueryFileW!(hDrop, i, buf.cast<Utf16>(), len + 1);
            if (copied > 0) {
              final path = buf.cast<Utf16>().toDartString(length: copied).trim();
              if (path.isNotEmpty && File(path).existsSync()) {
                out.add(path);
              }
            }
          } finally {
            calloc.free(buf);
          }
        }
        return out;
      } finally {
        _closeClipboard!();
      }
    } catch (_) {
      return const [];
    }
  }

  /// Прочитать буфер обмена для импорта: сначала файлы (`CF_HDROP`), иначе текст.
  static Future<({List<String> files, String? text})> readPayload() async {
    final files = readFiles();
    if (files.isNotEmpty) return (files: files, text: null);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return (files: const <String>[], text: data?.text);
  }
}
