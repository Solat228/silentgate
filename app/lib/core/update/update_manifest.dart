import 'dart:convert';

/// Манифест релиза: что качать, какого размера и с каким хэшем.
///
/// Файл `SilentGate-<версия>.manifest.json` лежит в активах релиза рядом с
/// `…manifest.sig` — подписью Ed25519 над его БАЙТАМИ (`update_signature.dart`).
/// Одна подпись на релиз, хэши на все активы: приложение качает манифест,
/// проверяет подпись, и только потом по манифесту — сам установщик.
///
/// ⚠️ ПОДПИСЬ ДОКАЗЫВАЕТ АВТОРА, НЕ РЕЛИЗ. Честно подписанный манифест 1.14.0,
/// подсунутый вместо 1.14.1, — откат с валидной подписью. Поэтому после подписи
/// [validateManifest] сверяет версию, канал и ТОЧНОЕ имя актива, и каждому
/// отказу даёт имя ([ManifestRejection]): «не обновилось» без причины — то,
/// от чего этот файл и защищает.
///
/// Чистый Dart: тем же кодом манифест собирает `tool/sign_release.dart`.
class UpdateAsset {
  /// Имя файла в релизе, как есть (`SilentGateSetup-1.14.1.exe`).
  final String name;

  /// Размер в байтах; сверяется с `Content-Length` и с принятым объёмом.
  final int size;

  /// SHA-256 содержимого, шестнадцатеричная строка в НИЖНЕМ регистре — как
  /// отдаёт `Sha256.ofFile`, чтобы сравнивать без приведения.
  final String sha256;

  const UpdateAsset({
    required this.name,
    required this.size,
    required this.sha256,
  });

  Map<String, Object> toJson() => {
        'name': name,
        'size': size,
        'sha256': sha256,
      };
}

class UpdateManifest {
  static const channelStable = 'stable';
  static const channelBeta = 'beta';
  static const _channels = {channelStable, channelBeta};

  /// Версия без ведущего `v`; для беты — полный тег (`1.14.1-beta.1`).
  final String version;

  /// `stable` | `beta`. Третьего не бывает — [parse] такое не принимает.
  final String channel;

  final List<UpdateAsset> assets;

  const UpdateManifest({
    required this.version,
    required this.channel,
    required this.assets,
  });

  /// Разбор текста манифеста. `null` на ЛЮБОМ мусоре — не JSON, не объект,
  /// нет поля, поле не того типа, неизвестный канал, пустое имя актива.
  ///
  /// Проверяется только ФОРМА (типы и наличие); значения (размер > 0,
  /// 64 hex у хэша) — дело [validateManifest], чтобы отказ был назван.
  static UpdateManifest? parse(String json) {
    Object? raw;
    try {
      raw = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (raw is! Map) return null;
    final version = raw['version'];
    final channel = raw['channel'];
    final assets = raw['assets'];
    if (version is! String || version.trim().isEmpty) return null;
    if (channel is! String || !_channels.contains(channel)) return null;
    if (assets is! List) return null;

    final parsed = <UpdateAsset>[];
    for (final item in assets) {
      if (item is! Map) return null;
      final name = item['name'];
      final size = item['size'];
      final sha256 = item['sha256'];
      if (name is! String || name.isEmpty) return null;
      if (size is! int) return null;
      if (sha256 is! String) return null;
      parsed.add(UpdateAsset(
        name: name,
        size: size,
        // К нижнему регистру: сравнивать будем с `Sha256.ofFile`, а
        // инструмент, писавший манифест руками, мог дать и верхний.
        sha256: sha256.toLowerCase(),
      ));
    }
    return UpdateManifest(
      version: normalizeVersion(version),
      channel: channel,
      assets: List.unmodifiable(parsed),
    );
  }

  /// Актив по ТОЧНОМУ имени. Не `contains`, не без учёта регистра:
  /// `SilentGateSetup-1.14.1.exe` и `SilentGateSetup-1.14.1.exe.bak` — разные
  /// файлы, и подставить второй вместо первого — ровно то, что здесь ловится.
  UpdateAsset? assetNamed(String name) {
    for (final a in assets) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// Каноничная сериализация: фиксированный порядок ключей, активы в порядке
  /// списка, без пробелов. Подпись ставится над байтами именно этого текста,
  /// поэтому два запуска инструмента на одних файлах дают один и тот же файл.
  String toJson() => jsonEncode({
        'version': version,
        'channel': channel,
        'assets': [for (final a in assets) a.toJson()],
      });
}

/// Почему манифест отвергнут. [badSignature] сюда не ставит [validateManifest]
/// — подпись проверяется раньше и отдельно; значение есть, чтобы у вызывающего
/// была ОДНА шкала причин для журнала и интерфейса.
enum ManifestRejection {
  badSignature,
  versionMismatch,
  channelMismatch,
  assetMissing,
  malformed,
}

/// Ведущий `v`/`V` снимается, края обрезаются; остальное — как есть.
/// Теги GitHub — `v1.14.1`, версия приложения — `1.14.1`; сравнивать надо
/// одно с другим.
String normalizeVersion(String v) {
  final t = v.trim();
  if (t.startsWith('v') || t.startsWith('V')) return t.substring(1);
  return t;
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Подходит ли [m] для установки [assetName] версии [expectedVersion].
///
/// Порядок фиксирован — версия → канал → актив → форма актива — и первый
/// отказ называется. `null` = всё сходится.
///
/// ⚠️ [expectedVersion] — версия РЕЛИЗА, с которого пришёл манифест, а не
/// версия приложения: манифест доказывает «этот файл принадлежит этому
/// релизу», а «релиз новее нас» решается до закачки, отдельно.
ManifestRejection? validateManifest(
  UpdateManifest m, {
  required String expectedVersion,
  required String assetName,
  required bool betaAllowed,
}) {
  if (normalizeVersion(m.version) != normalizeVersion(expectedVersion)) {
    return ManifestRejection.versionMismatch;
  }
  if (m.channel == UpdateManifest.channelBeta && !betaAllowed) {
    return ManifestRejection.channelMismatch;
  }
  final asset = m.assetNamed(assetName);
  if (asset == null) return ManifestRejection.assetMissing;
  if (asset.size <= 0 || !_hex64.hasMatch(asset.sha256)) {
    return ManifestRejection.malformed;
  }
  return null;
}
