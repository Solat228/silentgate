// Инструмент выпуска: манифест релиза + подпись Ed25519.
//
// Запуск из `app/`, после сборки exe/apk:
//   dart run tool/sign_release.dart <версия> <stable|beta> <файл> [<файл>…]
//
// Читает `../signing/update_ed25519.key` (приватный seed, НЕ в git), считает
// размер и SHA-256 каждого файла и кладёт РЯДОМ С ПЕРВЫМ файлом:
//   SilentGate-<версия>.manifest.json   — что качать, размеры, хэши;
//   SilentGate-<версия>.manifest.sig    — base64-подпись над байтами .json.
// Оба файла идут в релиз вместе с активами. Версия — тег без `v`, для беты
// полный (`1.14.1-beta.1`).
//
// ⚠️ Манифест обязан перечислять ВСЁ, что приложение может скачать, включая
// TEST-ONLY apk для эмулятора: актива нет в манифесте — приложение его не
// поставит (это защита, а не недосмотр).
//
// Логика — в `lib/core/update/release_signing.dart`, здесь только разбор
// аргументов: тест гоняет то же самое без процесса.
import 'dart:io';

import 'package:silentgate/core/update/release_signing.dart';

const keyPath = '../signing/update_ed25519.key';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
        'Использование: dart run tool/sign_release.dart <версия> <stable|beta> <файл>…');
    exit(2);
  }
  final version = args[0];
  final channel = args[1];
  final files = [for (final p in args.sublist(2)) File(p)];

  for (final f in files) {
    if (!f.existsSync()) {
      stderr.writeln('Файла нет: ${f.path}');
      exit(1);
    }
  }
  final keyFile = File(keyPath);
  if (!keyFile.existsSync()) {
    stderr.writeln('Нет приватного ключа $keyPath — '
        'сгенерировать: dart run tool/update_keygen.dart');
    exit(1);
  }

  final List<int> seed;
  try {
    seed = parseSeed(keyFile.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('Ключ $keyPath не по форме: ${e.message}');
    exit(1);
  }

  final UpdateManifestResult result;
  try {
    final manifest = await buildManifest(version, channel, files);
    result = UpdateManifestResult(
      manifest.assets.length,
      writeSignedManifest(manifest, seed, besides: files.first),
    );
  } on ArgumentError catch (e) {
    stderr.writeln('Ошибка: ${e.message}');
    exit(1);
  }

  if (!signedManifestVerifies(result.files)) {
    for (final f in [result.files.manifest, result.files.signature]) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    stderr.writeln('Подпись НЕ сходится с ключом, вшитым в приложение '
        '(update_pubkey.dart). Ключ $keyPath не тот — манифест удалён.');
    exit(1);
  }

  stdout.writeln('Активов: ${result.count}');
  stdout.writeln('Манифест: ${result.files.manifest.path}');
  stdout.writeln('Подпись:  ${result.files.signature.path}');
}

class UpdateManifestResult {
  final int count;
  final SignedManifestFiles files;
  const UpdateManifestResult(this.count, this.files);
}
