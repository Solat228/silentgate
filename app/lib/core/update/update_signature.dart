import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

import 'update_pubkey.dart';

/// Подпись манифеста обновлений: Ed25519 (RFC 8032), ключ зашит в приложение.
///
/// ⚠️ ЧИСТЫЙ DART, БЕЗ FLUTTER. Этим же кодом подписывает `tool/sign_release.dart`
/// из `dart run` — импорт `package:flutter` сделал бы инструмент незапускаемым
/// («dart:ui is not available», см. историю `emit_*.dart`).
///
/// ⚠️ ПОЧЕМУ ПОДПИСЬ, А НЕ ТОЛЬКО SHA-256. Хэш защищает от обрыва закачки, а
/// не от подмены: кто подменил файл, тот подменил и хэш рядом. Подпись
/// проверяется ключом, которого на сервере нет, — подменить можно источник,
/// доверие подменить нельзя (`update_pubkey.dart`).
abstract final class UpdateSignature {
  /// Верна ли [sigBase64] для [bytes] под ключом [publicKeyBase64].
  ///
  /// ⚠️ НИКОГДА НЕ БРОСАЕТ. Сюда приходит то, что отдал сервер: битый base64,
  /// пустая строка, подпись не той длины. Исключение здесь — либо падение
  /// проверки обновлений, либо соблазн обернуть вызов в `catch`, который
  /// однажды кто-то напишет как «считаем, что верна». Единственный ответ на
  /// любой мусор — `false`.
  static bool verify(
    List<int> bytes,
    String sigBase64, {
    String publicKeyBase64 = kUpdatePublicKeyBase64,
  }) {
    final sig = _decodeBase64(sigBase64);
    if (sig == null || sig.length != ed.SignatureSize) return false;
    final pub = _decodeBase64(publicKeyBase64);
    // Пакет БРОСАЕТ ArgumentError на ключе не в 32 байта — отсекаем сами.
    if (pub == null || pub.length != ed.PublicKeySize) return false;
    try {
      return ed.verify(ed.PublicKey(pub), Uint8List.fromList(bytes), sig);
    } catch (_) {
      // Единственный документированный выброс уже отсечён выше; остальное —
      // защита от будущих версий пакета, а не от известного случая.
      return false;
    }
  }

  /// Подпись [bytes] приватным ключом из 32-байтного [seed32], base64.
  ///
  /// Seed не той длины — [ArgumentError]: это ошибка вызывающего (инструмента
  /// выпуска), а не данных извне, и молчать о ней нельзя.
  static String sign(List<int> bytes, List<int> seed32) {
    if (seed32.length != ed.SeedSize) {
      throw ArgumentError.value(
          seed32.length, 'seed32', 'seed Ed25519 — ровно ${ed.SeedSize} байта');
    }
    final priv = ed.newKeyFromSeed(Uint8List.fromList(seed32));
    return base64.encode(ed.sign(priv, Uint8List.fromList(bytes)));
  }

  static Uint8List? _decodeBase64(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      return base64.decode(t);
    } on FormatException {
      return null;
    }
  }
}
