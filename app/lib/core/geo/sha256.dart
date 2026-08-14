import 'dart:io';
import 'dart:typed_data';

/// SHA-256 своими руками — без пакета `crypto`.
///
/// ⚠️ ПОЧЕМУ НЕ `package:crypto`. В `pubspec.yaml` его нет: он приезжает
/// ТРАНЗИТИВНО (через Flutter), а зависеть от транзитивного пакета — значит
/// сломаться в тот день, когда посредник его уронит. Прямой зависимостью
/// добавлять нельзя: `pubspec.yaml` в этом заходе правят другие руки, и
/// конфликт в общем файле дороже восьмидесяти строк арифметики.
///
/// ⚠️ ЗАЧЕМ ХЭШ ВООБЩЕ НУЖЕН. По нему отвечаем на два вопроса, на которые
/// иначе честного ответа нет:
///   1. «есть ли что обновлять» — сравниваем свой файл с `*.sha256sum`
///      релиза (74 байта вместо 25 МБ);
///   2. «не оборвалась ли закачка» — свежескачанный файл проверяется ДО того,
///      как встанет на место рабочего.
///
/// Реализация — прямо по FIPS 180-4, без оптимизаций: 25 МБ считаются меньше
/// секунды, а читаемость тут важнее.
class Sha256 {
  Sha256._();

  /// Хэш байтов, шестнадцатеричной строкой в нижнем регистре.
  static String ofBytes(List<int> data) {
    final s = Sha256Sink();
    s.add(data);
    return s.close();
  }

  /// Хэш файла потоком.
  ///
  /// ⚠️ ИМЕННО ПОТОКОМ. `readAsBytes` на `geoip.dat` — это 25 МБ в куче разом,
  /// на телефоне с 2 ГБ памяти такое кончается убийством процесса системой.
  /// Между кусками управление возвращается циклу событий (`await` на чтении),
  /// поэтому интерфейс не замирает.
  static Future<String> ofFile(File file) async {
    final sink = Sha256Sink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    return sink.close();
  }
}

/// Накопитель: скармливай куски, в конце позови [close].
class Sha256Sink {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint32List _h = Uint32List.fromList(const [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);
  final Uint8List _block = Uint8List(64);
  final Uint32List _w = Uint32List(64);
  int _filled = 0;
  int _totalBytes = 0;
  bool _closed = false;

  void add(List<int> data) {
    if (_closed) {
      throw StateError('Sha256Sink.add после close(): накопитель одноразовый');
    }
    _totalBytes += data.length;
    var i = 0;
    while (i < data.length) {
      final take = data.length - i < 64 - _filled ? data.length - i : 64 - _filled;
      for (var j = 0; j < take; j++) {
        _block[_filled + j] = data[i + j];
      }
      _filled += take;
      i += take;
      if (_filled == 64) {
        _compress();
        _filled = 0;
      }
    }
  }

  /// Шестнадцатеричный хэш; после вызова накопитель использовать нельзя.
  String close() {
    if (_closed) {
      throw StateError('Sha256Sink.close дважды: результат уже забран');
    }
    _closed = true;
    final bitLen = _totalBytes * 8;

    // Дополнение: байт 0x80, нули, и 64-битная длина в БИТАХ big-endian.
    _block[_filled++] = 0x80;
    if (_filled > 56) {
      while (_filled < 64) {
        _block[_filled++] = 0;
      }
      _compress();
      _filled = 0;
    }
    while (_filled < 56) {
      _block[_filled++] = 0;
    }
    // ⚠️ Длина пишется сдвигами, а не через ByteData.setUint64: на вебе 64-бит
    // целых нет. Проект пока не веб, но ломать это по неосторожности незачем.
    for (var i = 0; i < 8; i++) {
      _block[56 + i] = (bitLen >> (56 - 8 * i)) & 0xff;
    }
    _compress();

    final sb = StringBuffer();
    for (final word in _h) {
      sb.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return sb.toString();
  }

  static int _rotr(int x, int n) =>
      ((x >> n) | (x << (32 - n))) & 0xffffffff;

  void _compress() {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final o = i * 4;
      w[i] = (_block[o] << 24) |
          (_block[o + 1] << 16) |
          (_block[o + 2] << 8) |
          _block[o + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], hh = _h[7];

    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;

      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }

    _h[0] = (_h[0] + a) & 0xffffffff;
    _h[1] = (_h[1] + b) & 0xffffffff;
    _h[2] = (_h[2] + c) & 0xffffffff;
    _h[3] = (_h[3] + d) & 0xffffffff;
    _h[4] = (_h[4] + e) & 0xffffffff;
    _h[5] = (_h[5] + f) & 0xffffffff;
    _h[6] = (_h[6] + g) & 0xffffffff;
    _h[7] = (_h[7] + hh) & 0xffffffff;
  }
}
