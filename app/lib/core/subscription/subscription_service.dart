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

  /// Адрес, по которому подписка РЕАЛЬНО отдалась, если панель увела редиректом.
  ///
  /// ⚠️ Стандарт подписок XTLS требует запоминать постоянный редирект: владелец
  /// панели переезжает на новый домен, старый однажды выключают — и все
  /// пользователи молча остаются без обновлений. `package:http` следует за
  /// редиректом сам, поэтому конечный адрес виден только здесь.
  /// null — редиректа не было.
  final String? movedTo;

  const SubscriptionResult(this.servers, this.info, {this.movedTo});
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
      // ⚠️ ЛИМИТ УСТРОЙСТВ ВЫГЛЯДИТ КАК ПОЛОМКА, ЕСЛИ ЕГО НЕ НАЗВАТЬ.
      //
      // Remnawave при исчерпанном лимите HWID отдаёт 404 и говорит причину
      // ОТДЕЛЬНЫМИ заголовками. Без их чтения человек видел «Сервер вернул код
      // 404» и шёл жаловаться на сломанную подписку, хотя чинится это удалением
      // лишнего устройства в личном кабинете.
      final hw = resp.headers;
      if (hw['x-hwid-max-devices-reached']?.toLowerCase() == 'true') {
        final limit = hw['x-hwid-limit'];
        throw SubscriptionException(limit != null && limit.isNotEmpty
            ? 'Достигнут лимит устройств ($limit). Отключите лишнее устройство '
                'в личном кабинете и повторите.'
            : 'Достигнут лимит устройств. Отключите лишнее устройство в личном '
                'кабинете и повторите.');
      }
      if (hw['x-hwid-not-supported']?.toLowerCase() == 'true') {
        throw SubscriptionException(
            'Панель требует идентификатор устройства, а приложение его не '
            'прислало. Обновите приложение.');
      }
      throw SubscriptionException(
        'Сервер вернул код ${resp.statusCode}',
      );
    }

    // Формат XRAY_JSON (панель отдаёт его известным клиентам) — предпочтителен:
    // в нём приходят готовые outbound'ы, а не пересобранные из ссылок.
    final body = resp.body;
    // ⚠️ ФОРМАТ — ПО `content-type`, А НЕ ПО СОДЕРЖИМОМУ.
    //
    // Так требует стандарт подписок XTLS: клиент обязан отдавать приоритет
    // заголовку. Угадывание по телу работает, пока панель отдаёт ровно то, что
    // мы ждём, — а она умеет отдавать base64-фолбэк неизвестным клиентам и
    // менять правила ответа на лету. Заголовок снимает эту зависимость.
    final declaredJson =
        (resp.headers['content-type'] ?? '').toLowerCase().contains('json');
    var servers = (declaredJson || XrayJsonSubscription.looksLikeJson(body))
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
    // Куда нас в итоге привели. Сравниваем без учёта регистра схемы и хоста.
    final finalUrl = resp.request?.url.toString();
    final moved = (finalUrl != null && finalUrl != url) ? finalUrl : null;
    if (moved != null) {
      AppLog.w('Подписка переехала: $url → $moved (адрес обновлён)');
    }
    return SubscriptionResult(servers, info, movedTo: moved);
  }

  void close() => _client.close();
}

class SubscriptionException implements Exception {
  final String message;
  SubscriptionException(this.message);
  @override
  String toString() => message;
}
