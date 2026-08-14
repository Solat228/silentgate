import 'dart:convert';
import 'dart:io';

import '../app_info.dart';
import '../platform/app_log.dart';
import 'app_update_defaults.dart';

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

  const AppRelease({
    required this.version,
    this.downloadUrl,
    this.notes,
    this.pageUrl,
  });

  /// Новее ли [version] текущей сборки.
  bool get isNewer => AppUpdate.isNewer(version, AppInfo.version);
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
/// Приложение НИЧЕГО не скачивает и не запускает само: без подписи кода
/// самозапуск установщика упрётся в SmartScreen и выглядит как поведение
/// зловреда. Мы лишь сообщаем о новой версии и открываем страницу по кнопке.
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

  static Future<UpdateCheckResult> check({
    Duration timeout = const Duration(seconds: 10),
    UpdateFetcher? fetcher,
    String? assetHint,
  }) async {
    final hint = assetHint ?? kPlatformAssetHint;
    try {
      final resp = await (fetcher ?? _fetch)(Uri.parse(endpoint));
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

    // ⚠️ Тег обычно с приставкой `v` (`v1.4.3`), а сравниваем мы числа.
    // `_parts` её и так отбрасывает, но чистим и здесь: версия попадает в текст
    // для пользователя, и «доступна v1.4.4» рядом с «у вас 1.4.3» читается как
    // разные системы нумерации.
    final tag = '${j['tag_name'] ?? j['name'] ?? ''}'.trim();
    final version = tag.replaceFirst(RegExp('^[vV]'), '').trim();
    if (version.isEmpty) return null;

    String? asset;
    final assets = j['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = '${a['name'] ?? ''}';
        if (!name.toLowerCase().contains(assetHint.toLowerCase())) continue;
        final url = '${a['browser_download_url'] ?? ''}'.trim();
        if (url.isNotEmpty) {
          asset = url;
          break;
        }
      }
    }

    final page = '${j['html_url'] ?? ''}'.trim();
    final notes = '${j['body'] ?? ''}'.trim();
    return AppRelease(
      version: version,
      downloadUrl: asset,
      notes: notes.isEmpty ? null : notes,
      pageUrl: page.isEmpty ? kGithubReleasesPage : page,
    );
  }

  static Future<UpdateHttpResponse> _fetch(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
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

  /// Сравнение версий вида `1.2.3` (лишние части и суффиксы игнорируются).
  static bool isNewer(String candidate, String current) {
    final a = _parts(candidate);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) => v
      .split(RegExp(r'[^0-9]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
}
