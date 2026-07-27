import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../platform/app_log.dart';
import '../models/subscription_info.dart';
import '../models/vpn_server.dart';
import '../parser/share_link_parser.dart';
import 'xray_json_subscription.dart';

class SubscriptionResult {
  final List<VpnServer> servers;
  final SubscriptionInfo info;
  const SubscriptionResult(this.servers, this.info);
}

/// Загружает и разбирает подписку по URL.
///
/// Отправляет заголовки идентификации устройства (совместимо с device-limit Remnawave)
/// и разбирает как тело (base64-список share-ссылок), так и мета-заголовки ответа.
class SubscriptionService {
  final http.Client _client;
  SubscriptionService({http.Client? client}) : _client = client ?? http.Client();

  /// Всегда представляемся своим именем и версией — «SilentGate/x.y.z (платформа)».
  /// Панель по этому имени выбирает формат ответа (правило Response Rules → XRAY_JSON).
  /// Не `const`: суффикс платформы вычисляется в рантайме (`AppInfo.platformTag`).
  static String get defaultUserAgent => AppInfo.userAgent;

  Future<SubscriptionResult> fetch(
    String url, {
    Map<String, String> deviceHeaders = const {},
  }) async {
    // Всегда своё имя и версия: панель по нему выбирает формат (XRAY_JSON).
    final ua = defaultUserAgent;
    final resp = await _client.get(
      Uri.parse(url),
      headers: {
        'User-Agent': ua,
        'Accept': '*/*',
        ...deviceHeaders,
      },
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw SubscriptionException(
        'Сервер вернул код ${resp.statusCode}',
      );
    }

    // Формат XRAY_JSON (панель отдаёт его известным клиентам) — предпочтителен:
    // в нём приходят готовые outbound'ы, а не пересобранные из ссылок.
    final body = resp.body;
    var servers = XrayJsonSubscription.looksLikeJson(body)
        ? XrayJsonSubscription.parse(body)
        : const <VpnServer>[];
    if (servers.isEmpty) {
      servers = ShareLinkParser.parseSubscriptionBody(body);
    }
    if (servers.isEmpty) {
      throw SubscriptionException('В подписке не найдено ни одного сервера');
    }
    final info = SubscriptionInfo.fromHeaders(resp.headers);
    final ct = resp.headers['content-type'] ?? '?';
    final panel = servers.where((s) => (s.rawOutboundJson ?? '').isNotEmpty).length;
    final profiles = servers.where((s) => s.isPanelProfile).length;
    AppLog.i('Подписка: UA=$ua, Content-Type=$ct, ${resp.bodyBytes.length} Б, '
        'серверов=${servers.length}, с конфигом панели=$panel, профилей «Авто»=$profiles');
    if (panel == 0) {
      AppLog.w('Панель прислала НЕ XRAY_JSON — конфиги пересобираются из ссылок. '
          'Проверьте правило Response Rules (user-agent CONTAINS SilentGate → XRAY_JSON).');
    }
    return SubscriptionResult(servers, info);
  }

  void close() => _client.close();
}

class SubscriptionException implements Exception {
  final String message;
  SubscriptionException(this.message);
  @override
  String toString() => message;
}
