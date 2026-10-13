import 'dart:convert';
import 'dart:io';

import '../geo/sha256.dart';
import 'update_manifest.dart';
import 'update_pubkey.dart';
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
///
/// ⚠️ ПРИСТАВКА `update-` НУЖНА РАДИ СТРАНИЦЫ РЕЛИЗА (владелец, 13.10.2026).
/// GitHub показывает активы по алфавиту, и `SilentGate-<версия>.manifest.json`
/// стоял среди установщиков, сбивая человека, который пришёл за программой.
/// Строчная `u` идёт после всех `SilentGate-…` и `TEST-ONLY-…`, поэтому
/// служебные файлы оказываются в самом конце списка.
String manifestFileName(String version) =>
    'update-SilentGate-${normalizeVersion(version)}.manifest.json';

/// Имя файла подписи для версии.
String signatureFileName(String version) =>
    'update-SilentGate-${normalizeVersion(version)}.manifest.sig';

/// Прежнее имя манифеста (1.14.0–1.15.1).
///
/// Эти версии ищут манифест ТОЛЬКО под ним, поэтому переходный выпуск
/// кладёт копию и под старым именем (`sign_release.dart --legacy-names`),
/// иначе они не обновятся сами, а дадут лишь ссылку. Новые версии понимают
/// оба имени и предпочитают новое.
String legacyManifestFileName(String version) =>
    'SilentGate-${normalizeVersion(version)}.manifest.json';

/// Прежнее имя подписи (1.14.0–1.15.1), см. [legacyManifestFileName].
String legacySignatureFileName(String version) =>
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

  /// Копии под прежними именами, если их просили; иначе пусто.
  final List<File> legacy;
  const SignedManifestFiles(this.manifest, this.signature,
      {this.legacy = const []});
}

/// Пишет `.manifest.json` и `.manifest.sig` в каталог файла [besides].
///
/// ⚠️ Подпись — над БАЙТАМИ, записанными в `.json`, а не над объектом: файл
/// потом отдаётся сервером как есть, и проверять приложение будет ровно то,
/// что скачало.
///
/// [legacyNames] — ещё и копии под прежними именами для 1.14.0–1.15.1 (см.
/// [legacyManifestFileName]). Байты те же, подпись та же.
SignedManifestFiles writeSignedManifest(
  UpdateManifest m,
  List<int> seed, {
  required File besides,
  bool legacyNames = false,
}) {
  final dir = besides.parent.path;
  final sep = Platform.pathSeparator;
  final jsonBytes = utf8.encode(m.toJson());
  final sigText = '${signManifestBytes(jsonBytes, seed)}\n';
  final manifestFile = File('$dir$sep${manifestFileName(m.version)}')
    ..writeAsBytesSync(jsonBytes);
  final sigFile = File('$dir$sep${signatureFileName(m.version)}')
    ..writeAsStringSync(sigText);
  final legacy = <File>[
    if (legacyNames) ...[
      File('$dir$sep${legacyManifestFileName(m.version)}')
        ..writeAsBytesSync(jsonBytes),
      File('$dir$sep${legacySignatureFileName(m.version)}')
        ..writeAsStringSync(sigText),
    ],
  ];
  return SignedManifestFiles(manifestFile, sigFile, legacy: legacy);
}

/// Принимает ли подпись, ЗАПИСАННУЮ на диск, ключ, вшитый в приложение.
///
/// ⚠️ Сверка с вшитым ключом, а не с парой только что использованного seed:
/// ровно так проверит приложение. Ключ в `signing/` подменили или перепутали —
/// релиз подписан, но ни одна копия его не примет, и узнать об этом надо до
/// публикации, а не от людей, у которых обновление молча не ставится.
bool signedManifestVerifies(SignedManifestFiles f,
        {String publicKeyBase64 = kUpdatePublicKeyBase64}) =>
    UpdateSignature.verify(
      f.manifest.readAsBytesSync(),
      f.signature.readAsStringSync().trim(),
      publicKeyBase64: publicKeyBase64,
    );

String _baseName(File f) {
  final p = f.path;
  final cut = p.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? p : p.substring(cut + 1);
}
