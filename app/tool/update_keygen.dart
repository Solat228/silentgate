// Генератор ключа подписи манифестов обновлений (Ed25519, RFC 8032).
//
// Запуск: `dart run tool/update_keygen.dart [--force]` из `app/`.
//
// Пишет:
//  * `../signing/update_ed25519.key` — 32-байтный seed в base64, ПРИВАТНЫЙ,
//    каталог `signing/` в .gitignore рядом с keystore Android;
//  * `lib/core/update/update_pubkey.dart` — публичный ключ, зашитый в приложение.
//
// ⚠️ Существующий приватный ключ без `--force` НЕ перезаписывается: потеря
// или смена ключа означает, что ни одна выпущенная сборка больше не примет ни
// одного обновления — как и с keystore Android, обратной дороги нет.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

const keyPath = '../signing/update_ed25519.key';
const pubkeyDartPath = 'lib/core/update/update_pubkey.dart';

void main(List<String> args) {
  final force = args.contains('--force');
  final keyFile = File(keyPath);
  if (keyFile.existsSync() && !force) {
    stderr.writeln('Ключ уже есть: $keyPath. Чтобы заменить — --force '
        '(все выпущенные сборки перестанут принимать обновления).');
    exit(2);
  }
  final rnd = Random.secure();
  final seed = List<int>.generate(32, (_) => rnd.nextInt(256));
  final priv = ed.newKeyFromSeed(Uint8List.fromList(seed));
  final pub = ed.public(priv);

  keyFile.parent.createSync(recursive: true);
  keyFile.writeAsStringSync('${base64.encode(seed)}\n');
  File(pubkeyDartPath).writeAsStringSync(renderPubkeyDart(base64.encode(pub.bytes)));
  stdout.writeln('Приватный ключ: $keyPath (НЕ коммитить)');
  stdout.writeln('Публичный ключ: ${base64.encode(pub.bytes)} → $pubkeyDartPath');
}

/// Текст модуля с публичным ключом. Вынесен, чтобы тест мог сверить формат.
String renderPubkeyDart(String pubBase64) => '''
// Сгенерировано tool/update_keygen.dart — НЕ ПРАВИТЬ РУКАМИ.
//
// Публичный ключ Ed25519, которым приложение проверяет подпись манифеста
// обновлений (см. core/update/update_signature.dart). Пара к нему лежит в
// `signing/update_ed25519.key` у владельца и в репозиторий не попадает.
//
// ⚠️ Ключ НЕ переопределяется ни переменной окружения, ни настройками, ни
// тестовым override адреса обновлений: подменить источник для стенда можно,
// подменить доверие — нет.
const kUpdatePublicKeyBase64 = '$pubBase64';
''';
