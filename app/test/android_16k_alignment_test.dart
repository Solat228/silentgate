import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// ⚠️ ВЫРАВНИВАНИЕ 16 КБ У НАТИВНЫХ ЯДЕР ANDROID.
///
/// На устройстве со страницей памяти 16 КБ (Android 15+) библиотека, у которой
/// сегменты `LOAD` выровнены на 4 КБ, не загружается вовсе — приложение падает
/// на первом же обращении к ядру. 10.10.2026 `libcores.so` из `cores.aar` стоял
/// ровно на 4096: NDK r27 по умолчанию даёт 4 КБ, а флага линковщика в рецепте
/// не было (`tools/build-android-cores.md`).
///
/// AAR в репозиторий не коммитится, поэтому тест читает тот, что лежит в слоте
/// Gradle, и пропускается, если его нет.
void main() {
  final aar = File('android/app/libs/cores.aar');

  test('libcores.so во всех ABI выровнен на 16 КБ', () {
    final libs = _elfEntries(aar.readAsBytesSync());
    expect(libs.keys, containsAll(['jni/arm64-v8a/libcores.so', 'jni/x86_64/libcores.so']));
    libs.forEach((name, elf) {
      final aligns = loadAlignments(elf);
      expect(aligns, isNotEmpty, reason: name);
      for (final a in aligns) {
        expect(a, greaterThanOrEqualTo(16384), reason: '$name: LOAD align $a');
      }
    });
  }, skip: aar.existsSync() ? false : 'cores.aar не положен в android/app/libs');

  test('разбор ELF: выравнивание LOAD читается из заголовков программы', () {
    expect(loadAlignments(_fakeElf64(0x1000)), [0x1000]);
    expect(loadAlignments(_fakeElf64(0x4000)), [0x4000]);
    expect(loadAlignments(Uint8List.fromList([1, 2, 3])), isEmpty);
  });
}

/// Выравнивание всех сегментов `PT_LOAD` 64-битного ELF (little-endian).
List<int> loadAlignments(Uint8List elf) {
  if (elf.length < 64 ||
      elf[0] != 0x7f ||
      elf[1] != 0x45 ||
      elf[2] != 0x4c ||
      elf[3] != 0x46 ||
      elf[4] != 2) {
    return const [];
  }
  final b = ByteData.sublistView(elf);
  final phoff = b.getUint64(0x20, Endian.little);
  final phentsize = b.getUint16(0x36, Endian.little);
  final phnum = b.getUint16(0x38, Endian.little);
  final out = <int>[];
  for (var i = 0; i < phnum; i++) {
    final o = phoff + i * phentsize;
    if (b.getUint32(o, Endian.little) != 1) continue; // PT_LOAD
    out.add(b.getUint64(o + 48, Endian.little));
  }
  return out;
}

/// `.so` внутри ZIP: имя → распакованное содержимое. Разбор центрального
/// каталога руками — пакета для ZIP в зависимостях нет, а тянуть его ради
/// одного теста незачем.
Map<String, Uint8List> _elfEntries(Uint8List zip) {
  final b = ByteData.sublistView(zip);
  var eocd = zip.length - 22;
  while (eocd >= 0 && b.getUint32(eocd, Endian.little) != 0x06054b50) {
    eocd--;
  }
  final count = b.getUint16(eocd + 10, Endian.little);
  var p = b.getUint32(eocd + 16, Endian.little);
  final out = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    final method = b.getUint16(p + 10, Endian.little);
    final csize = b.getUint32(p + 20, Endian.little);
    final nlen = b.getUint16(p + 28, Endian.little);
    final xlen = b.getUint16(p + 30, Endian.little);
    final clen = b.getUint16(p + 32, Endian.little);
    final local = b.getUint32(p + 42, Endian.little);
    final name = String.fromCharCodes(zip.sublist(p + 46, p + 46 + nlen));
    p += 46 + nlen + xlen + clen;
    if (!name.endsWith('.so')) continue;
    final lnlen = b.getUint16(local + 26, Endian.little);
    final lxlen = b.getUint16(local + 28, Endian.little);
    final start = local + 30 + lnlen + lxlen;
    final raw = zip.sublist(start, start + csize);
    out[name] = method == 0
        ? raw
        : Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
  }
  return out;
}

Uint8List _fakeElf64(int align) {
  final d = ByteData(64 + 56);
  d
    ..setUint32(0, 0x464c457f, Endian.little)
    ..setUint8(4, 2)
    ..setUint64(0x20, 64, Endian.little)
    ..setUint16(0x36, 56, Endian.little)
    ..setUint16(0x38, 1, Endian.little)
    ..setUint32(64, 1, Endian.little)
    ..setUint64(64 + 48, align, Endian.little);
  return d.buffer.asUint8List();
}
