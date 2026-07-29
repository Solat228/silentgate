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

  const AppRelease({required this.version, this.downloadUrl, this.notes});

  /// Новее ли [version] текущей сборки.
  bool get isNewer => AppUpdate.isNewer(version, AppInfo.version);
}

/// Проверка обновлений самого приложения.
///
/// Приложение НИЧЕГО не скачивает и не запускает само: без подписи кода
/// самозапуск установщика упрётся в SmartScreen и выглядит как поведение зловреда.
/// Мы лишь сообщаем о новой версии и открываем страницу загрузки по кнопке.
class AppUpdate {
  /// Формат ответа — см. `docs/APP_UPDATE.md`:
  /// `{"version":"0.9.0","url":"https://…/SilentGateSetup.exe","notes":"…"}`
  /// Значение живёт в `app_update_defaults.dart` (файл без импортов): оттуда
  /// его берёт `AppSettings`, не притаскивая в консольные тулы `package:flutter`.
  static String get defaultEndpoint => kDefaultAppUpdateEndpoint;

  static Future<AppRelease?> check({
    String? endpoint,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Пусто → платформенный адрес по умолчанию (Android и Windows разные:
    // общий эндпоинт отдавал ссылку на .exe, который на телефон не поставить).
    final url = (endpoint ?? '').trim().isEmpty
        ? kDefaultAppUpdateEndpoint
        : endpoint!.trim();
    if (url.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader, AppInfo.userAgent);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) {
        AppLog.i('Проверка обновлений: сервер ответил ${resp.statusCode}');
        return null;
      }
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final version = '${j['version'] ?? ''}'.trim();
      if (version.isEmpty) return null;
      return AppRelease(
        version: version,
        downloadUrl: (j['url'] as String?)?.trim(),
        notes: (j['notes'] as String?)?.trim(),
      );
    } catch (e) {
      // Эндпоинта может не быть вовсе — это не ошибка приложения, шумим только в лог.
      AppLog.i('Проверка обновлений недоступна: $e');
      return null;
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
