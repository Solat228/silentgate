import 'dart:io';
import 'package:http/io_client.dart';
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

  /// Новый ПОСТОЯННЫЙ адрес подписки, если панель увела редиректом 301/308.
  ///
  /// ⚠️ Стандарт подписок XTLS требует запоминать ТОЛЬКО постоянный редирект:
  /// владелец панели переезжает на новый домен, старый однажды выключают — и все
  /// пользователи молча остаются без обновлений.
  ///
  /// ⚠️ ВРЕМЕННЫЙ редирект (302/303/307) запоминать НЕЛЬЗЯ. Наша инфраструктура
  /// отдаёт `302` как совместимость: короткая ссылка `s.silentgate.lol/<id>`
  /// (новый канон) при попадании на мейн уводит на легаси `sub.silentgate.lol/
  /// sub/<id>`. Если запомнить конечный адрес, пользователя молча переносит с
  /// нового домена на старый — а смена URL ещё и меняет id профиля, из-за чего
  /// цикл автообновления теряет подписку. Поэтому за 302 мы следуем ради ЭТОГО
  /// запроса, но сохранённый адрес не трогаем.
  ///
  /// Следуем редиректам вручную (`followRedirects = false`), потому что
  /// `package:http` при авто-следовании прячет коды статуса — а без них 301 и
  /// 302 неразличимы. `null` — постоянного переезда не было.
  final String? movedTo;

  const SubscriptionResult(this.servers, this.info, {this.movedTo});
}

/// Загружает и разбирает подписку по URL.
///
/// Отправляет заголовки идентификации устройства (совместимо с device-limit Remnawave)
/// и разбирает как тело (base64-список share-ссылок), так и мета-заголовки ответа.
class SubscriptionService {
  final http.Client _client;

  /// Транспортный UA — ВТОРАЯ линия защиты формата ответа.
  ///
  /// Панель Remnawave выбирает ФОРМАТ ответа по User-Agent: своим клиентам она
  /// отдаёт XRAY_JSON, остальным — base64-ссылки. Раньше `package:http` при
  /// АВТО-следовании за редиректом выполнял повторный запрос без заголовков
  /// запроса — панель видела `Dart/3.12 (dart:io)` и присылала не тот формат
  /// (на этом горели и мы, и FlClash v0.8.79 «Fix get profile redirect client
  /// ua issues»). Теперь [fetch] следует за редиректами САМ и ставит UA на
  /// КАЖДЫЙ хоп, поэтому потерять его негде; транспортный UA оставлен как
  /// подстраховка на случай запросов мимо этого пути.
  static http.Client _defaultClient() {
    final io = HttpClient()..userAgent = AppInfo.userAgent;
    return IOClient(io);
  }

  SubscriptionService({http.Client? client})
      : _client = client ?? _defaultClient();

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
    // Следуем редиректам САМИ, чтобы видеть коды статуса: постоянный переезд
    // (301/308) запоминаем, временный (302/303/307) — нет. См. [movedTo].
    final (resp, permanentMove) =
        await _fetchFollowing(Uri.parse(url), ua, deviceHeaders);

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
    // Постоянный переезд (301/308) — новый адрес; временный (302/307) сюда не
    // попадает (см. [_fetchFollowing] и [movedTo]).
    final moved = (permanentMove != null && permanentMove != url) ? permanentMove : null;
    if (moved != null) {
      AppLog.w('Подписка переехала (постоянно, 301/308): $url → $moved (адрес обновлён)');
    }
    return SubscriptionResult(servers, info, movedTo: moved);
  }

  /// Выполняет GET, следуя редиректам ВРУЧНУЮ (до пяти хопов), и возвращает
  /// конечный ответ вместе с новым ПОСТОЯННЫМ адресом (или `null`).
  ///
  /// Ручное следование нужно ради двух вещей сразу:
  ///  * видеть код каждого редиректа — 301/308 (постоянный) закрепляем адресом,
  ///    302/303/307 (временный) только проходим;
  ///  * ставить наш User-Agent на КАЖДЫЙ хоп. Панель выбирает формат ответа по
  ///    UA, а `package:http` при АВТО-следовании выполняет повторный запрос без
  ///    заголовков запроса — панель видела `Dart/3.x` и присылала base64 вместо
  ///    XRAY_JSON. На этом горели и мы, и FlClash (v0.8.79). Теперь UA явный на
  ///    каждом запросе, потерять его негде.
  ///
  /// `movedTo` = адрес, достигнутый НЕПРЕРЫВНОЙ цепочкой постоянных редиректов от
  /// начала: первый же временный редирект обрывает её, и дальше адрес не растёт
  /// (конечный адрес за 302 нестабилен — запоминать нечего).
  Future<(http.Response, String?)> _fetchFollowing(
    Uri start,
    String ua,
    Map<String, String> deviceHeaders,
  ) async {
    var current = start;
    String? permanentMove;
    var chainStillPermanent = true;
    for (var hop = 0;; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false;
      request.headers['User-Agent'] = ua;
      request.headers['Accept'] = '*/*';
      request.headers.addAll(deviceHeaders);
      final resp = await http.Response.fromStream(await _client.send(request));
      final code = resp.statusCode;
      final isRedirect =
          code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
      final location = resp.headers['location'];
      if (!isRedirect || location == null || location.isEmpty) {
        return (resp, permanentMove);
      }
      if (hop >= 5) {
        throw SubscriptionException('Слишком много редиректов подписки');
      }
      final next = current.resolve(location);
      // Постоянный редирект в непрерывной цепочке двигает запоминаемый адрес;
      // временный — обрывает цепочку, дальше адрес не запоминаем.
      if ((code == 301 || code == 308) && chainStillPermanent) {
        permanentMove = next.toString();
      } else {
        chainStillPermanent = false;
      }
      current = next;
    }
  }

  void close() => _client.close();
}

class SubscriptionException implements Exception {
  final String message;
  SubscriptionException(this.message);
  @override
  String toString() => message;
}
