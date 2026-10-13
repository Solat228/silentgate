import 'dart:convert';
import 'dart:io';

import '../app_info.dart';
import '../platform/app_log.dart';
import '../platform/apk_installer_android.dart';
import '../platform/app_paths.dart';
import 'app_update_defaults.dart';
import 'release_signing.dart'
    show
        legacyManifestFileName,
        legacySignatureFileName,
        manifestFileName,
        signatureFileName;
import 'update_manifest.dart' show UpdateManifest, normalizeVersion;
import 'update_pubkey.dart';
import 'update_signature.dart';

/// Что сказал сервер обновлений.
class AppRelease {
  final String version;
  final String? downloadUrl;
  final String? notes;

  /// Страница релиза для человека — её открывает кнопка «Скачать».
  /// Нужна отдельно от [downloadUrl]: артефакта под текущую платформу в релизе
  /// может не оказаться (собрали только под одну), но страницу открыть всё
  /// равно есть смысл.
  final String? pageUrl;

  /// Пре-релиз (GitHub `prerelease: true`) либо ответ, явно помеченный полем
  /// `beta`/`channel` у запасного источника сайта.
  ///
  /// ⚠️ Умолчание — `false`, и это единственный безопасный выбор: обычный
  /// путь (стабильный `/releases/latest` + основной манифест сайта) никогда
  /// беты не отдаёт, но если когда-нибудь отдаст — молчаливое `true` было бы
  /// хуже, чем незамеченная бета: человек решил бы, что ставит стабильную
  /// версию, хотя это пре-релиз.
  final bool isBeta;

  /// Когда релиз опубликован — для списка «Прежние версии» (кнопка отката):
  /// без даты человек не отличит вчерашний хвост от версии годовой давности.
  final DateTime? publishedAt;

  /// ТОЧНОЕ имя актива платформы (`SilentGateSetup-1.14.0.exe`) — по нему
  /// актив ищется в подписанном манифесте. [downloadUrl] — его прямой адрес.
  final String? assetName;

  /// Размер актива в байтах, как его объявил источник. Сверяется с манифестом
  /// и ограничивает закачку.
  final int? assetSize;

  /// Адрес `SilentGate-<версия>.manifest.json`.
  final String? manifestUrl;

  /// Адрес `SilentGate-<версия>.manifest.sig` (подпись Ed25519 над байтами
  /// манифеста).
  final String? signatureUrl;

  const AppRelease({
    required this.version,
    this.downloadUrl,
    this.notes,
    this.pageUrl,
    this.isBeta = false,
    this.publishedAt,
    this.assetName,
    this.assetSize,
    this.manifestUrl,
    this.signatureUrl,
  });

  /// Новее ли [version] текущей сборки.
  bool get isNewer => AppUpdate.isNewer(version, AppUpdate.installedVersion);

  /// Хватает ли данных, чтобы скачать, проверить и поставить релиз самим.
  ///
  /// ⚠️ ВСЁ ИЛИ НИЧЕГО. Нет хоть одного из пяти (прямой адрес, имя, размер,
  /// манифест, подпись) — прежнее поведение «открыть страницу». И каждый адрес
  /// обязан пройти [isUpdateUrlAllowed]: `http://` допустим только под
  /// тестовым override, в боевом режиме — никогда.
  bool get canSelfUpdate =>
      downloadUrl != null &&
      assetName != null &&
      assetName!.isNotEmpty &&
      manifestUrl != null &&
      signatureUrl != null &&
      (assetSize ?? 0) > 0 &&
      isUpdateUrlAllowed(downloadUrl) &&
      isUpdateUrlAllowed(manifestUrl) &&
      isUpdateUrlAllowed(signatureUrl);
}

/// Чем кончилась проверка обновлений.
///
/// ⚠️ ТРИ ИСХОДА, А НЕ ДВА, И ЭТО ГЛАВНОЕ В ЭТОМ ФАЙЛЕ. Раньше [AppUpdate.check]
/// отдавала `null` И когда обновления нет, И когда проверить не удалось —
/// различить было нечем. Интерфейс из-за этого показывал «у вас последняя
/// версия» человеку, у которого просто не было сети или чей запрос упёрся в
/// лимит GitHub. Сказать «всё в порядке», не проверив, — худший вид лжи в
/// проверке обновлений: пользователь перестаёт проверять вручную.
enum UpdateCheckState {
  /// Проверили, версия новее нашей есть.
  available,

  /// Проверили, у пользователя последняя.
  upToDate,

  /// НЕ проверили: сеть, лимит, приватный репозиторий, битый ответ.
  failed,
}

class UpdateCheckResult {
  final UpdateCheckState state;
  final AppRelease? release;

  /// Человеческая причина отказа — показывается пользователю, поэтому без
  /// технических подробностей и без адресов.
  final String? failure;

  const UpdateCheckResult._(this.state, {this.release, this.failure});

  const UpdateCheckResult.available(AppRelease r)
      : this._(UpdateCheckState.available, release: r);
  const UpdateCheckResult.upToDate([AppRelease? r])
      : this._(UpdateCheckState.upToDate, release: r);
  const UpdateCheckResult.failed(String why)
      : this._(UpdateCheckState.failed, failure: why);

  bool get isAvailable => state == UpdateCheckState.available;
  bool get isFailed => state == UpdateCheckState.failed;
}

/// Ответ сети в том виде, в каком его разбирает [AppUpdate]. Отдельный тип —
/// чтобы проверку можно было гонять тестом без сети.
/// Запись ленты релизов github.com.
class GithubFeedEntry {
  /// Тег как есть (`v1.15.1`) — из него собираются адреса загрузки.
  final String tag;

  /// Тег без `v`.
  final String version;
  final String? notes;
  final DateTime? updated;

  const GithubFeedEntry({
    required this.tag,
    required this.version,
    this.notes,
    this.updated,
  });
}

class UpdateHttpResponse {
  final int statusCode;
  final String body;

  /// Заголовки в нижнем регистре: у GitHub по ним отличается «кончился лимит»
  /// от «доступ запрещён», а это разные сообщения пользователю.
  final Map<String, String> headers;

  const UpdateHttpResponse(this.statusCode, this.body,
      {this.headers = const {}});
}

typedef UpdateFetcher = Future<UpdateHttpResponse> Function(Uri url);

/// Проверка обновлений самого приложения.
///
/// Этот класс только УЗНАЁТ о новой версии и находит её файлы (актив,
/// манифест, подпись). Скачивание, проверку подписи и запуск установщика с
/// 1.14.0 ведёт `state/app_update_controller.dart` — и только для релиза с
/// подписанным манифестом ([AppRelease.canSelfUpdate]); без него остаётся
/// прежнее «открыть страницу». Почему SmartScreen здесь не мешает —
/// `docs/APP_UPDATE.md`.
///
/// ⚠️ ИСТОЧНИК ОДИН — GITHUB RELEASES (см. `app_update_defaults.dart`), адреса
/// в настройках больше нет. Поле «Эндпоинт версии» просило пользователя
/// настроить то, чего он знать не может, и молчаливо ничего не давало.
class AppUpdate {
  /// Адрес, который спрашивается на самом деле. Оставлен геттером (а не
  /// константой в месте вызова), чтобы источник правды был один.
  static String get endpoint => kGithubReleasesApi;

  /// Страница для кнопки «Скачать», когда артефакта под платформу нет.
  static String get releasesPage => kGithubReleasesPage;

  static bool _apiOverrideLoaded = false;

  /// Android: подхватить тестовый override адреса API из
  /// `<каталог данных>/update_api.txt` (см. [kUpdateApiEnvVar] в
  /// `app_update_defaults.dart`). На Windows ничего не делает — там override
  /// читается из окружения лениво. Идемпотентна; [check] и
  /// [fetchReleaseHistory] зовут её сами, но звать раньше (на старте) тоже
  /// можно — чтобы плашка «тестовый адрес» появилась до первой проверки.
  static Future<void> loadApiOverride() async {
    if (_apiOverrideLoaded || !Platform.isAndroid) return;
    try {
      final dir = await AppPaths.supportDir();
      final base = loadUpdateApiOverrideFrom(dir.path);
      _apiOverrideLoaded = true;
      if (base != null) {
        AppLog.i('Проверка обновлений: найден $kUpdateApiOverrideFileName — '
            'адрес API подменён');
      }
    } catch (e) {
      // Каталог данных не получен — override просто не включается, а проверка
      // идёт на боевой адрес. Флаг не ставим: следующая проверка попробует снова.
      AppLog.i('Override адреса обновлений не прочитан: $e');
    }
  }

  static String? _hintCache;

  /// Хвост имени актива ЭТОГО устройства. На Android — по ABI
  /// (`Build.SUPPORTED_ABIS[0]`): без неё эмулятор x86_64 получал бы
  /// телефонную arm64-сборку, которая на нём не запустится. ABI не меняется,
  /// поэтому спрашиваем канал один раз; не ответил — телефонная сборка, как
  /// было всегда, и ответ не кэшируем (спросим на следующей проверке).
  static Future<String> _platformHint() async {
    final cached = _hintCache;
    if (cached != null) return cached;
    if (!Platform.isAndroid) return _hintCache = kPlatformAssetHint;
    final abi = await ApkInstallerAndroid().deviceAbi();
    final hint = platformAssetHint(androidAbi: abi);
    if (abi != null) _hintCache = hint;
    return hint;
  }

  /// ⚠️ ДВА ИСТОЧНИКА, И ВТОРОЙ ЗАВЕДЁН НЕ ДЛЯ КРАСОТЫ.
  ///
  /// GitHub — основной: он не зависит от нашей панели и переживает её простой.
  /// Но 15.08.2026 выяснилось, что у владельца `api.github.com` **не открывается
  /// вовсе**: TLS-рукопожатие падает с `CERTIFICATE_VERIFY_FAILED: Hostname
  /// mismatch`. Воспроизведено в чистой VM, где VPN не поднимался ни разу, при
  /// живом `github.com` — то есть API перехватывают у провайдера. Для клиента,
  /// которым пользуются именно там, где интернет фильтруют, «основной источник
  /// недоступен» — это норма, а не исключение.
  ///
  /// Поэтому: спрашиваем GitHub, а при ЛЮБОМ его отказе — свой сайт. Ответ
  /// сайта проще (`{"version","url","notes"}`), формат описан в
  /// `docs/APP_UPDATE_SERVER.md`.
  ///
  /// ⚠️ ПОРЯДОК ИМЕННО ТАКОЙ. Сайт знает про подписки и может отдавать разное
  /// разным людям — а обновление приложения должно быть одинаковым для всех.
  /// GitHub первым делает подмену версии заметной: чтобы обмануть, надо
  /// подменить оба источника.
  /// [beta] — галочка «Получать бета-версии» из настроек
  /// (`AppSettings.betaChannel`). По умолчанию `false`: источники те же, что
  /// были всегда, `/releases/latest` пре-релизы не отдаёт по определению.
  ///
  /// ⚠️ ГАЛОЧКА МЕНЯЕТ ТОЛЬКО ЭТОТ ЗАПРОС, А НЕ ОСНОВНОЙ МАНИФЕСТ. Смотреть
  /// список релизов вместо `/latest` при включённой галочке — единственный
  /// способ узнать про бету, не поместив признак канала в манифест, который
  /// получают ВСЕ: тогда бета уехала бы в рассылку без разрешения (см.
  /// комментарий у [kPanelBetaUpdateEndpoint]).
  static Future<UpdateCheckResult> check({
    Duration timeout = const Duration(seconds: 10),
    UpdateFetcher? fetcher,
    String? assetHint,
    bool beta = false,
    // ТОЛЬКО для тестов: своя пара ключей. Боевой вызов не передаёт ничего,
    // и подпись проверяется вшитым ключом.
    String publicKeyBase64 = kUpdatePublicKeyBase64,
  }) async {
    await loadApiOverride();
    final hint = assetHint ?? await _platformHint();
    final fetch = fetcher ?? _fetch;
    if (kUpdateApiOverridden) {
      AppLog.i('Проверка обновлений: ТЕСТОВЫЙ адрес API (override), '
          'http:// для закачки разрешён');
    }

    final primary =
        beta ? await _tryGithubBeta(fetch, hint) : await _tryGithub(fetch, hint);
    if (primary.state != UpdateCheckState.failed) return primary;

    // API не ответил — тот же GitHub через сайт (лента + прямые загрузки).
    // Раньше запасного сайта: только здесь есть манифест и подпись, то есть
    // самообновление, а не ссылка.
    final web = await _tryGithubWeb(fetch, hint,
        beta: beta, publicKeyBase64: publicKeyBase64);
    if (web.state != UpdateCheckState.failed) {
      AppLog.i('Проверка обновлений: api.github.com недоступен, ответил '
          'github.com');
      return web;
    }

    final backup =
        beta ? await _tryPanelBeta(fetch, hint) : await _tryPanel(fetch, hint);
    if (backup.state != UpdateCheckState.failed) {
      AppLog.i('Проверка обновлений: GitHub недоступен, ответил запасной '
          'источник');
      return backup;
    }
    // Оба молчат — показываем причину ПЕРВОГО: она конкретнее («лимит»,
    // «репозиторий закрыт»), чем общее «не удалось связаться» у запасного.
    return primary;
  }

  static Future<UpdateCheckResult> _tryGithub(
      UpdateFetcher fetch, String hint) async {
    try {
      final resp = await fetch(Uri.parse(endpoint));
      final failure = _failureFor(resp);
      if (failure != null) {
        AppLog.i('Проверка обновлений не удалась: код ${resp.statusCode}');
        return UpdateCheckResult.failed(failure);
      }
      final release = parseGithubRelease(resp.body, assetHint: hint);
      if (release == null) {
        // Двухсотый ответ, который не разбирается, — это НЕ «обновлений нет».
        return const UpdateCheckResult.failed(
            'Сервер обновлений ответил непонятным образом');
      }
      return release.isNewer
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } catch (e) {
      AppLog.i('Проверка обновлений недоступна: $e');
      return const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
    }
  }

  /// Источник «сайт GitHub без API»: версия из ленты релизов, манифест,
  /// подпись и файлы — по прямым адресам `releases/download/<тег>/<имя>`.
  ///
  /// Имя и размер файла берутся из ПОДПИСАННОГО манифеста: лента их не знает.
  /// Манифест не скачался или подпись не сошлась — версию мы всё равно знаем,
  /// поэтому ответ не «не удалось проверить», а релиз без самообновления
  /// (кнопка откроет страницу).
  static Future<UpdateCheckResult> _tryGithubWeb(
      UpdateFetcher fetch, String hint,
      {required bool beta, required String publicKeyBase64}) async {
    try {
      final resp = await fetch(Uri.parse(kGithubReleasesFeed));
      if (resp.statusCode != 200) {
        AppLog.i('Лента релизов github.com: код ${resp.statusCode}');
        return UpdateCheckResult.failed(
            'Сервер обновлений ответил кодом ${resp.statusCode}');
      }
      final entry = pickFeedEntry(parseReleasesFeed(resp.body), beta: beta);
      if (entry == null) {
        return const UpdateCheckResult.failed(
            'Сервер обновлений ответил непонятным образом');
      }
      final bare = AppRelease(
        version: entry.version,
        notes: entry.notes,
        pageUrl: githubTagPage(entry.tag),
        isBeta: _pre(entry.version) != null,
        publishedAt: entry.updated,
      );
      if (!bare.isNewer) return UpdateCheckResult.upToDate(bare);
      final full =
          await _webSelfUpdate(fetch, hint, entry, bare, publicKeyBase64);
      return UpdateCheckResult.available(full ?? bare);
    } catch (e) {
      AppLog.i('Лента релизов github.com недоступна: $e');
      return const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
    }
  }

  /// Манифест релиза [entry] с github.com: новое имя, затем прежнее. Подпись
  /// проверяется уже здесь — иначе предложение «обновить само» строилось бы
  /// на файле, который потом всё равно отвергнет закачка.
  static Future<AppRelease?> _webSelfUpdate(UpdateFetcher fetch, String hint,
      GithubFeedEntry entry, AppRelease bare, String publicKeyBase64) async {
    final v = entry.version;
    final pairs = [
      (manifestFileName(v), signatureFileName(v)),
      (legacyManifestFileName(v), legacySignatureFileName(v)),
    ];
    for (final (manifestName, sigName) in pairs) {
      final manifestUrl = githubDownloadUrl(entry.tag, manifestName);
      final signatureUrl = githubDownloadUrl(entry.tag, sigName);
      final m = await fetch(Uri.parse(manifestUrl));
      if (m.statusCode != 200) continue;
      final sig = await fetch(Uri.parse(signatureUrl));
      if (sig.statusCode != 200) continue;
      if (!UpdateSignature.verify(utf8.encode(m.body), sig.body.trim(),
          publicKeyBase64: publicKeyBase64)) {
        AppLog.w('Обновление $v: подпись манифеста $manifestName не сошлась');
        continue;
      }
      final manifest = UpdateManifest.parse(m.body);
      if (manifest == null || normalizeVersion(manifest.version) != v) {
        AppLog.w('Обновление $v: манифест $manifestName не той версии');
        continue;
      }
      for (final a in manifest.assets) {
        if (!_assetMatches(a.name, hint, v)) continue;
        return AppRelease(
          version: v,
          downloadUrl: githubDownloadUrl(entry.tag, a.name),
          notes: bare.notes,
          pageUrl: bare.pageUrl,
          isBeta: bare.isBeta,
          publishedAt: bare.publishedAt,
          assetName: a.name,
          assetSize: a.size,
          manifestUrl: manifestUrl,
          signatureUrl: signatureUrl,
        );
      }
      AppLog.i('Обновление $v: в манифесте нет файла под эту платформу');
      return null;
    }
    AppLog.i('Обновление $v: подписанного манифеста на github.com нет');
    return null;
  }

  /// Записи ленты релизов github.com (`releases.atom`).
  ///
  /// Разбор регулярными выражениями, без XML-пакета: из ленты нужны три поля
  /// на запись, и формат её у GitHub не менялся годами. Запись без тега
  /// пропускается.
  static List<GithubFeedEntry> parseReleasesFeed(String xml) {
    final out = <GithubFeedEntry>[];
    final entryRe = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    final tagRe = RegExp(r'/releases/tag/([^"<>\s]+)"');
    final contentRe = RegExp(r'<content[^>]*>(.*?)</content>', dotAll: true);
    final updatedRe = RegExp(r'<updated>([^<]+)</updated>');
    for (final m in entryRe.allMatches(xml)) {
      final body = m[1]!;
      final tagRaw = tagRe.firstMatch(body)?[1];
      if (tagRaw == null) continue;
      final tag = Uri.decodeComponent(tagRaw);
      final version = tag.replaceFirst(RegExp('^[vV]'), '').trim();
      if (version.isEmpty) continue;
      // Содержимое экранировано дважды: XML поверх HTML. Сперва снимаем
      // слой XML, получаем HTML, его переводим в текст.
      final html = _unescapeXml(contentRe.firstMatch(body)?[1] ?? '');
      final notes = htmlToText(html);
      out.add(GithubFeedEntry(
        tag: tag,
        version: version,
        notes: notes.isEmpty ? null : notes,
        updated: DateTime.tryParse(updatedRe.firstMatch(body)?[1] ?? ''),
      ));
    }
    return out;
  }

  /// Новейшая запись канала.
  ///
  /// ⚠️ Стабильный канал — только версии без суффикса: лента, в отличие от
  /// `/releases/latest`, пре-релизов не прячет, а признака «prerelease» в ней
  /// нет. Бета у нас всегда с суффиксом (`1.15.0-beta.1`). Выбор по номеру
  /// версии, а не по порядку записей.
  static GithubFeedEntry? pickFeedEntry(List<GithubFeedEntry> entries,
      {required bool beta}) {
    GithubFeedEntry? best;
    for (final e in entries) {
      if (!beta && _pre(e.version) != null) continue;
      if (best == null || isNewer(e.version, best.version)) best = e;
    }
    return best;
  }

  /// HTML заметок релиза в текст для окна обновления: пункты списка — «- »,
  /// абзацы — с новой строки, остальные теги снимаются.
  static String htmlToText(String html) {
    // Переводы строк между тегами — разметка исходника, не текст: без их
    // снятия между пунктами списка появлялись пустые строки.
    var t = html
        .replaceAll(RegExp(r'>\s+<'), '><')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ')
        .replaceAll(RegExp(r'</(p|h[1-6])>', caseSensitive: false), '\n\n')
        .replaceAll(
            RegExp(r'</(li|ul|ol)>|<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    t = _unescapeXml(t);
    return t
        .split('\n')
        .map((l) => l.trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _unescapeXml(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&amp;', '&');

  static Future<UpdateCheckResult> _tryPanel(
      UpdateFetcher fetch, String hint) async {
    try {
      final resp = await fetch(Uri.parse(kPanelUpdateEndpoint));
      if (resp.statusCode != 200) {
        return UpdateCheckResult.failed(
            'Запасной сервер обновлений ответил кодом ${resp.statusCode}');
      }
      final release = parsePanelRelease(resp.body);
      if (release == null) {
        return const UpdateCheckResult.failed(
            'Запасной сервер обновлений ответил непонятным образом');
      }
      return release.isNewer
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } catch (e) {
      AppLog.i('Запасная проверка обновлений недоступна: $e');
      return const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
    }
  }

  /// Бета-путь основного источника: СПИСОК релизов вместо `/latest`.
  ///
  /// GitHub отдаёт список от новых к старым по дате публикации — первый
  /// элемент и есть «новейшее, включая пре-релизы», без отдельного сравнения
  /// версий между элементами списка.
  static Future<UpdateCheckResult> _tryGithubBeta(
      UpdateFetcher fetch, String hint) async {
    try {
      final resp = await fetch(Uri.parse(kGithubReleasesListApi));
      final failure = _failureFor(resp);
      if (failure != null) {
        AppLog.i('Проверка бета-обновлений не удалась: код ${resp.statusCode}');
        return UpdateCheckResult.failed(failure);
      }
      final list = parseGithubReleaseList(resp.body, assetHint: hint);
      if (list == null || list.isEmpty) {
        return const UpdateCheckResult.failed(
            'Сервер обновлений ответил непонятным образом');
      }
      final release = list.first;
      return release.isNewer
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } catch (e) {
      AppLog.i('Проверка бета-обновлений недоступна: $e');
      return const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
    }
  }

  /// Запасной источник бета-канала — тот же сайт, отдельный путь
  /// ([kPanelBetaUpdateEndpoint]). Формат ответа общий с обычным
  /// [_tryPanel] — тот же [parsePanelRelease] понимает необязательное поле
  /// `beta`/`channel`.
  static Future<UpdateCheckResult> _tryPanelBeta(
      UpdateFetcher fetch, String hint) async {
    try {
      final resp = await fetch(Uri.parse(kPanelBetaUpdateEndpoint));
      if (resp.statusCode != 200) {
        return UpdateCheckResult.failed(
            'Запасной сервер обновлений ответил кодом ${resp.statusCode}');
      }
      final release = parsePanelRelease(resp.body);
      if (release == null) {
        return const UpdateCheckResult.failed(
            'Запасной сервер обновлений ответил непонятным образом');
      }
      return release.isNewer
          ? UpdateCheckResult.available(release)
          : UpdateCheckResult.upToDate(release);
    } catch (e) {
      AppLog.i('Запасная проверка бета-обновлений недоступна: $e');
      return const UpdateCheckResult.failed(
          'Не удалось связаться с сервером обновлений');
    }
  }

  /// Запасной источник ФАЙЛОВ того же выпуска: GitHub ответил на проверку, а
  /// его файлы не отдаются (ТСПУ подменяет сертификат с перебоями — у владельца
  /// 3 проверки из 4 ушли на запасной источник, при этом сама проверка потом
  /// проходила). Наш сайт держит байт-в-байт копии.
  ///
  /// ⚠️ ВЕРСИЯ СВЕРЯЕТСЯ ТОЧНО: другая версия — другой выпуск, и подставлять
  /// его файлы под уже показанное человеку предложение нельзя. Целостность
  /// по-прежнему доказывает подпись манифеста, а не то, с какого хоста приехал
  /// файл, — поэтому смена источника сама по себе ничего не ослабляет.
  ///
  /// Спрашивается ТОЛЬКО сайт: GitHub свой ответ уже дал, и повторять его
  /// запрос смысла нет. Сети не бросает — не ответил никто, значит `null`.
  static Future<AppRelease?> mirrorRelease({
    required bool beta,
    required String version,
    UpdateFetcher? fetcher,
    String? assetHint,
  }) async {
    try {
      await loadApiOverride();
      final hint = assetHint ?? await _platformHint();
      final fetch = fetcher ?? _fetch;
      final result =
          beta ? await _tryPanelBeta(fetch, hint) : await _tryPanel(fetch, hint);
      final release = result.release;
      if (release == null) return null;
      if (normalizeVersion(release.version) != normalizeVersion(version)) {
        AppLog.w('Обновление: у запасного источника версия '
            '${release.version}, а нужна $version — файлы не беру');
        return null;
      }
      if (!release.canSelfUpdate) {
        AppLog.w('Обновление: запасной источник не отдаёт манифест, подпись '
            'и размер для $version — самому не поставить');
        return null;
      }
      return release;
    } catch (e) {
      AppLog.i('Запасной источник файлов обновления недоступен: $e');
      return null;
    }
  }

  /// Прежние версии для кнопки отката — из того же СПИСКА релизов, что и
  /// бета-канал, поэтому сети не требует ничего сверх того, что уже
  /// запрашивается при включённой галочке «Получать бета-версии».
  ///
  /// ⚠️ ЧЕСТНОСТЬ СПИСКА. Это ровно то, что лежит в GitHub Releases — не
  /// более. Если там нет какой-то версии (см. `docs/HANDOFF_1.11.0.md` про
  /// пустой `GITHUB_TOKEN` — релизов 1.11.x не существует), в списке её тоже
  /// не будет, и это не ошибка приложения.
  static Future<List<AppRelease>> fetchReleaseHistory({
    int limit = 15,
    UpdateFetcher? fetcher,
    String? assetHint,
  }) async {
    await loadApiOverride();
    final hint = assetHint ?? await _platformHint();
    final fetch = fetcher ?? _fetch;
    try {
      final resp = await fetch(Uri.parse(kGithubReleasesListApi));
      if (resp.statusCode != 200) return const [];
      final list = parseGithubReleaseList(resp.body, assetHint: hint);
      if (list == null) return const [];
      return list.take(limit).toList();
    } catch (e) {
      AppLog.i('Список прежних версий недоступен: $e');
      return const [];
    }
  }

  /// Разбор ответа НАШЕГО сайта. Формат намеренно плоский — его пишет не
  /// GitHub, а наш бэкенд, и чем меньше в нём мест для ошибки, тем лучше.
  ///
  /// ```json
  /// {"version":"1.5.1","url":"https://…/SilentGateSetup.exe","notes":"…"}
  /// ```
  ///
  /// ⚠️ `url` НЕ обязателен: релиз бывает собран под одну платформу. Тогда
  /// кнопка ведёт на страницу загрузок — версию мы всё равно узнали.
  /// ⚠️ И `url` обязан быть `https`: иначе кнопка «Скачать» повела бы человека
  /// за установщиком по открытому каналу, где его можно подменить. Исключение
  /// одно — тестовый override адреса API ([isUpdateUrlAllowed]).
  ///
  /// ⚠️ Необязательное поле `beta` (булево) либо `channel: "beta"` — признак
  /// канала. Умолчание `false`: старый ответ панели (ни того, ни другого
  /// поля нет) ведёт себя ровно как раньше, обратная совместимость полная.
  ///
  /// Необязательные поля САМООБНОВЛЕНИЯ: `asset` (точное имя файла), `size`
  /// (байты), `manifest` и `sig` (адреса манифеста и подписи). Нет любого —
  /// [AppRelease.canSelfUpdate] ложно, и остаётся прежняя кнопка-ссылка.
  static AppRelease? parsePanelRelease(String body) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (j is! Map) return null;
    final version =
        '${j['version'] ?? ''}'.trim().replaceFirst(RegExp('^[vV]'), '');
    if (version.isEmpty) return null;
    final url = '${j['url'] ?? ''}'.trim();
    final notes = '${j['notes'] ?? ''}'.trim();
    final page = '${j['page'] ?? ''}'.trim();
    final beta = j['beta'] == true ||
        '${j['channel'] ?? ''}'.trim().toLowerCase() == 'beta';
    final asset = '${j['asset'] ?? ''}'.trim();
    return AppRelease(
      version: version,
      downloadUrl: isUpdateUrlAllowed(url) ? url : null,
      notes: notes.isEmpty ? null : notes,
      pageUrl: page.startsWith('https://') ? page : kPanelDownloadsPage,
      isBeta: beta,
      assetName: asset.isEmpty ? null : asset,
      assetSize: _positiveInt(j['size']),
      manifestUrl: _allowedUrl(j['manifest']),
      signatureUrl: _allowedUrl(j['sig']),
    );
  }

  /// Адрес из ответа — если он проходит [isUpdateUrlAllowed], иначе `null`.
  static String? _allowedUrl(Object? raw) {
    final s = '${raw ?? ''}'.trim();
    return isUpdateUrlAllowed(s) ? s : null;
  }

  /// Положительное целое из числа или строки; иначе `null`.
  static int? _positiveInt(Object? raw) {
    final int? v;
    if (raw is int) {
      v = raw;
    } else if (raw is num && raw == raw.truncate()) {
      v = raw.toInt();
    } else if (raw is String) {
      v = int.tryParse(raw.trim());
    } else {
      v = null;
    }
    return (v != null && v > 0) ? v : null;
  }

  /// Причина отказа по коду ответа — или `null`, если ответ годный.
  ///
  /// ⚠️ У GITHUB ЧЕТЫРЕ РАЗНЫХ «НЕТ», И ПУТАТЬ ИХ НЕЛЬЗЯ:
  /// * **404** — репозиторий приватный ЛИБО релизов ещё не выпускали. Снаружи
  ///   это неразличимо (GitHub намеренно отвечает одинаково, чтобы не выдавать
  ///   существование приватных репозиториев), поэтому и текст общий.
  /// * **403 с исчерпанным лимитом** — 60 запросов в час на адрес для
  ///   неавторизованных. Реально достижимо: за одним адресом сидит вся
  ///   квартира или офис.
  /// * **403 без лимита** — доступ запрещён.
  /// * **5xx** — у GitHub сбой, наше дело подождать.
  static String? _failureFor(UpdateHttpResponse resp) {
    if (resp.statusCode == 200) return null;
    if (resp.statusCode == 404) {
      return 'Релизы недоступны: репозиторий закрыт или релизов ещё нет';
    }
    if (resp.statusCode == 403 || resp.statusCode == 429) {
      final left = resp.headers['x-ratelimit-remaining'];
      if (left == '0' || resp.statusCode == 429) {
        return 'Слишком много проверок с этого адреса — попробуйте через час';
      }
      return 'Сервер обновлений отказал в доступе';
    }
    if (resp.statusCode >= 500) {
      return 'Сервер обновлений временно недоступен';
    }
    return 'Сервер обновлений ответил кодом ${resp.statusCode}';
  }

  /// Разбор ответа GitHub Releases. Вынесен отдельно и публично: сеть в тестах
  /// не нужна, а форма ответа — единственное, что здесь можно сломать молча.
  ///
  /// [assetHint] — кусок имени файла под текущую платформу
  /// (`arm64-v8a.apk` / `Setup.exe`). Артефакта может не быть: релиз бывает
  /// собран под одну платформу, и это НЕ повод считать проверку неудачной —
  /// версию мы узнали, а вместо прямой ссылки отдадим страницу релиза.
  static AppRelease? parseGithubRelease(String body,
      {required String assetHint}) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (j is! Map) return null;
    return _releaseFromMap(j, assetHint);
  }

  /// Разбор СПИСКА релизов (`GET /releases`, без `/latest`) — для бета-канала
  /// и кнопки отката версии.
  ///
  /// ⚠️ Черновики (`draft: true`) отбрасываются: они не опубликованы, и
  /// предлагать их как доступную версию значило бы врать про статус релиза.
  /// Пре-релизы, наоборот, ОСТАЮТСЯ — ради них список и запрашивается.
  /// Порядок элементов не переставляется: GitHub уже отдаёт от новых к
  /// старым по дате публикации, а пересчитывать это сравнением версий было
  /// бы лишней операцией с тем же результатом.
  static List<AppRelease>? parseGithubReleaseList(String body,
      {required String assetHint}) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (j is! List) return null;
    final out = <AppRelease>[];
    for (final item in j) {
      if (item is! Map) continue;
      if (item['draft'] == true) continue;
      final r = _releaseFromMap(item, assetHint);
      if (r != null) out.add(r);
    }
    return out;
  }

  /// Общее тело разбора одного элемента ответа GitHub — использует и
  /// [parseGithubRelease] (объект `/releases/latest`), и
  /// [parseGithubReleaseList] (каждый элемент массива `/releases`): формат
  /// объекта релиза у GitHub один и тот же в обоих ответах.
  static AppRelease? _releaseFromMap(Map j, String assetHint) {
    // ⚠️ Тег обычно с приставкой `v` (`v1.4.3`), а сравниваем мы числа.
    // `_parts` её и так отбрасывает, но чистим и здесь: версия попадает в текст
    // для пользователя, и «доступна v1.4.4» рядом с «у вас 1.4.3» читается как
    // разные системы нумерации.
    final tag = '${j['tag_name'] ?? j['name'] ?? ''}'.trim();
    final version = tag.replaceFirst(RegExp('^[vV]'), '').trim();
    if (version.isEmpty) return null;

    String? assetUrl;
    String? assetName;
    int? assetSize;
    String? manifestUrl;
    String? signatureUrl;
    String? legacyManifestUrl;
    String? legacySignatureUrl;
    // ⚠️ Манифест и подпись — по ТОЧНОМУ имени (тег без `v`, у бет полный:
    // `update-SilentGate-1.14.1-beta.1.manifest.json`). Не `contains`:
    // соседний `….manifest.json.bak` или манифест другой версии в том же
    // релизе означали бы проверку подписи НЕ ТОГО файла. Прежнее имя без
    // `update-` — запасное: им подписаны выпуски 1.14.0–1.15.1.
    final manifestName = manifestFileName(version);
    final signatureName = signatureFileName(version);
    final legacyManifestName = legacyManifestFileName(version);
    final legacySignatureName = legacySignatureFileName(version);
    final assets = j['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = '${a['name'] ?? ''}'.trim();
        final url = '${a['browser_download_url'] ?? ''}'.trim();
        if (name.isEmpty || url.isEmpty) continue;
        if (name == manifestName) {
          manifestUrl ??= url;
        } else if (name == signatureName) {
          signatureUrl ??= url;
        } else if (name == legacyManifestName) {
          legacyManifestUrl ??= url;
        } else if (name == legacySignatureName) {
          legacySignatureUrl ??= url;
        } else if (assetUrl == null &&
            _assetMatches(name, assetHint, version)) {
          assetUrl = url;
          assetName = name;
          assetSize = _positiveInt(a['size']);
        }
      }
    }

    final page = '${j['html_url'] ?? ''}'.trim();
    final notes = '${j['body'] ?? ''}'.trim();
    final publishedRaw = '${j['published_at'] ?? j['created_at'] ?? ''}';
    final published = DateTime.tryParse(publishedRaw);
    return AppRelease(
      version: version,
      downloadUrl: assetUrl,
      notes: notes.isEmpty ? null : notes,
      pageUrl: page.isEmpty ? kGithubReleasesPage : page,
      isBeta: j['prerelease'] == true,
      publishedAt: published,
      assetName: assetName,
      assetSize: assetSize,
      // Пара берётся целиком из одного поколения имён: копии под старым
      // именем байт в байт те же, но смешивать незачем.
      manifestUrl: manifestUrl != null && signatureUrl != null
          ? manifestUrl
          : legacyManifestUrl,
      signatureUrl: manifestUrl != null && signatureUrl != null
          ? signatureUrl
          : legacySignatureUrl,
    );
  }

  /// Подходит ли актив [name] под хвост платформы [hint].
  ///
  /// ⚠️ СРАВНЕНИЕ ПО ХВОСТУ ИМЕНИ БЕЗ ВЕРСИИ, а не `contains`. Прежний
  /// `contains('Setup.exe')` НЕ находил настоящий установщик: Inno называет его
  /// `SilentGateSetup-1.13.1.exe` — версия стоит между «Setup» и «.exe», и
  /// кнопка на Windows всегда вела на страницу, а не на файл. Поэтому сперва
  /// из имени вырезается `-<версия>`, затем хвост сравнивается `endsWith`:
  /// * `SilentGateSetup-1.13.1.exe` → `SilentGateSetup.exe` ⊃ `Setup.exe`;
  /// * `SilentGate-1.13.1-arm64-v8a.apk` → `…-arm64-v8a.apk`;
  /// * `….apk.idsig`, `….zip`, x86_64 для телефона — не подходят.
  /// Регистр не важен: имена файлов на странице релиза пишут руками.
  static bool _assetMatches(String name, String hint, String version) {
    final n = name.toLowerCase();
    final h = hint.toLowerCase();
    if (h.isEmpty) return false;
    if (n.endsWith(h)) return true;
    final v = version.toLowerCase();
    if (v.isEmpty) return false;
    if (n.replaceAll('-$v', '').endsWith(h)) return true;
    // Бета: тег `1.14.1-beta.1`, а Inno называет установщик по версии exe —
    // `SilentGateSetup-1.14.1.exe`. Без второго прохода Windows-бета не
    // находила бы свой установщик и откатывалась на «открыть страницу».
    final core = _core(v);
    return core != v && n.replaceAll('-$core', '').endsWith(h);
  }

  static Future<UpdateHttpResponse> _fetch(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    // ⚠️ «Напрямую» ЗАДАЁТСЯ ЯВНО (идиома `core/probe/proxy_probe.dart`).
    // Умолчание Dart берёт прокси из окружения (`http_proxy`/`all_proxy`), и
    // проверка обновлений могла бы уйти через чужой прокси или через порт
    // нашего же туннеля — и упасть вместе с ним, когда туннель лежит.
    client.findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, AppInfo.userAgent);
      // Без этого GitHub вправе отдать другой формат: версия API закрепляется
      // заголовком, а не адресом.
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final headers = <String, String>{};
      resp.headers.forEach((k, v) {
        if (v.isNotEmpty) headers[k.toLowerCase()] = v.first;
      });
      return UpdateHttpResponse(resp.statusCode, body, headers: headers);
    } finally {
      client.close(force: true);
    }
  }

  /// Сравнение версий вида `1.2.3[-beta.N]`.
  ///
  /// Три числа решают всё. При равных числах решает суффикс, как в SemVer:
  /// стабильная `1.14.1` новее своей же беты `1.14.1-beta.2` — иначе человек,
  /// поставивший бету, так и остался бы на ней, когда вышла стабильная с тем
  /// же номером. Две беты одного номера сравниваются по номеру беты, но
  /// только когда он есть у ОБЕИХ: у установленной беты номер неизвестен
  /// (сборка знает только `AppInfo.isBeta`), и без этой оговорки та же самая
  /// бета предлагалась бы заново при каждой проверке.
  static bool isNewer(String candidate, String current) {
    final a = _parts(_core(candidate));
    final b = _parts(_core(current));
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    final candPre = _pre(candidate);
    final curPre = _pre(current);
    if (candPre == null) return curPre != null;
    if (curPre == null) return false;
    final pa = _parts(candPre);
    final pb = _parts(curPre);
    if (pa.isEmpty || pb.isEmpty) return false;
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Версия ЭТОЙ сборки для сравнения: у бета-сборки — с суффиксом, чтобы
  /// стабильная того же номера считалась новее (см. [isNewer]).
  static String get installedVersion =>
      AppInfo.isBeta ? '${AppInfo.version}-beta' : AppInfo.version;

  /// Числовая часть без `v` и без суффикса после первого `-`.
  static String _core(String v) {
    final t = v.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final dash = t.indexOf('-');
    return dash < 0 ? t : t.substring(0, dash);
  }

  /// Суффикс пре-релиза (`beta.2`) либо `null` у стабильной.
  static String? _pre(String v) {
    final t = v.trim();
    final dash = t.indexOf('-');
    if (dash < 0) return null;
    final s = t.substring(dash + 1);
    return s.isEmpty ? null : s;
  }

  static List<int> _parts(String v) => v
      .split(RegExp(r'[^0-9]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
}
