import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Известные папки Windows (`SHGetKnownFolderPath`).
///
/// «Документы» берутся у системы, а не склейкой `%USERPROFILE%\Documents`:
/// папку переносят на другой диск и в OneDrive, и склейка указала бы мимо.
abstract final class KnownFolders {
  /// Папка «Документы» текущего пользователя; `null` — не удалось узнать.
  static Directory? documents() {
    if (!Platform.isWindows) return null;
    final id = GUIDFromString(FOLDERID_Documents);
    final out = calloc<Pointer<Utf16>>();
    try {
      final hr = SHGetKnownFolderPath(id, 0, NULL, out);
      if (FAILED(hr)) return null;
      final path = out.value.toDartString();
      return path.isEmpty ? null : Directory(path);
    } catch (_) {
      return null;
    } finally {
      if (out.value != nullptr) CoTaskMemFree(out.value);
      calloc.free(out);
      calloc.free(id);
    }
  }
}
