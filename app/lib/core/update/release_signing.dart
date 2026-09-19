import 'dart:convert';
import 'dart:io';

import '../geo/sha256.dart';
import 'update_manifest.dart';
import 'update_signature.dart';

/// Сторона ВЫПУСКА: сборка и подпись манифеста релиза.
///
/// Это логика `tool/sign_release.dart`, вынесенная из него целиком, чтобы
/// тест прогонял её без процесса — инструмент и проверка в приложении никогда
/// не компилируются вместе, и расхождение между ними всплыло бы только у
/// пользователей («обновление не ставится» на каждом релизе).
///
/// Чистый Dart, без Flutter: запускается из `dart run`.

/// Имя файла манифеста для версии (ведущий `v` снимается).
String manifestFileName(String version) =>
    'SilentGate-${normalizeVersion(version)}.manifest.json';

/// Имя файла подписи для версии.
String signatureFileName(String version) =>
    'SilentGate-${normalizeVersion(version)}.manifest.sig';

/// Манифест по файлам: имя = базовое имя файла, размер и SHA-256 — с диска.
///
/// [ArgumentError] на пустой версии, неизвестном канале, пустом списке и
/// двух файлах с одним именем: приложение ищет актив по имени, и два
/// одинаковых имени с разными хэшами — манифест без однозначного ответа.
Future<UpdateManifest> buildManifest(
  String version,
  String channel,
  List<File> files,
) async {
  final v = normalizeVersion(version);
  if (v.isEmpty) throw ArgumentError.value(version, 'version', 'пустая версия');
  if (channel != UpdateManifest.channelStable &&
      channel != UpdateManifest.channelBeta) {
    throw ArgumentError.value(channel, 'channel', 'ожидается stable|beta');
  }
  if (files.isEmpty) throw ArgumentError('нет файлов для манифеста');

  final seen = <String>{};
  for (final f in files) {
    final name = _baseName(f);
    if (!seen.add(name)) {
      throw ArgumentError('два файла с именем «$name» — актив неоднозначен');
    }
  }

  final assets = <UpdateAsset>[];
  for (final f in files) {
    assets.add(UpdateAsset(
      name: _baseName(f),
      size: await f.length(),
      sha256: await Sha256.ofFile(f),
    ));
  }
  return UpdateManifest(version: v, channel: channel, assets: assets);
}

/// Подпись над байтами файла манифеста — теми же, что уйдут в `.json`.
String signManifestBytes(List<int> bytes, List<int> seed) =>
    UpdateSignature.sign(bytes, seed);

/// Разбор `signing/update_ed25519.key`: одна строка base64, 32 байта seed.
/// Не по форме — [FormatException], а не тихая подпись мусорным ключом.
List<int> parseSeed(String content) {
  final t = content.trim();
  if (t.isEmpty) throw const FormatException('файл ключа пуст');
  final bytes = base64.decode(t);
  if (bytes.length != 32) {
    throw FormatException('seed должен быть 32 байта, а не ${bytes.length}');
  }
  return bytes;
}

/// Что записал [writeSignedManifest].
class SignedManifestFiles {
  final File manifest;
  final File signature;
  const SignedManifestFiles(this.manifest, this.signature);
}

/// Пишет `.manifest.json` и `.manifest.sig` в каталог файла [besides].
///
/// ⚠️ Подпись — над БАЙТАМИ, записанными в `.json`, а не над объектом: файл
/// потом отдаётся сервером как есть, и проверять приложение будет ровно то,
/// что скачало.
SignedManifestFiles writeSignedManifest(
  UpdateManifest m,
  List<int> seed, {
  required File besides,
}) {
  final dir = besides.parent.path;
  final jsonBytes = utf8.encode(m.toJson());
  final manifestFile = File('$dir${Platform.pathSeparator}${manifestFileName(m.version)}')
    ..writeAsBytesSync(jsonBytes);
  final sigFile = File('$dir${Platform.pathSeparator}${signatureFileName(m.version)}')
    ..writeAsStringSync('${signManifestBytes(jsonBytes, seed)}\n');
  return SignedManifestFiles(manifestFile, sigFile);
}

String _baseName(File f) {
  final p = f.path;
  final cut = p.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? p : p.substring(cut + 1);
}
