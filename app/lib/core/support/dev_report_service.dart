import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../app_info.dart';
import '../app_store.dart';
import '../geo/sha256.dart';
import '../platform/app_log.dart';
import '../../state/support_chat_controller.dart' show SupportEndpointTarget;

/// Быстрые теги категорий проблем для отправки отчёта в 1 клик без набора текста.
enum QuickReportTag {
  cantConnect('cant_connect'),
  siteOrYoutube('site_or_youtube'),
  slowSpeed('slow_speed'),
  connectionDrops('connection_drops');

  final String wireKey;
  const QuickReportTag(this.wireKey);
}

/// Результат отправки обезличенной копии отчёта на сервер разработчика.
class DevReportUploadResult {
  final bool ok;
  final String reportCode;
  final bool linkedToSupport;
  final String? error;

  const DevReportUploadResult({
    required this.ok,
    required this.reportCode,
    this.linkedToSupport = false,
    this.error,
  });
}

typedef DevReportHttpSender = Future<(int statusCode, String body)> Function(
  Uri url,
  Map<String, String> headers,
  String jsonBody,
);

/// Обезличивание технического отчёта и отправка копии разработчику на сервер
/// `https://silentgate.lol/api/dev-report` с криптографической связкой
/// (`sub_hash` / `hwid_hash`) для пользователей экосистемы SilentGate.
abstract final class DevReportService {
  static const String defaultEndpoint = 'https://silentgate.lol/api/dev-report';

  static const String _codeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// Включена ли галочка отправки обезличенной копии по умолчанию:
  /// `true` в сборках сайта/GitHub/Stealth, `false` в сборках Google Play и MS Store.
  static bool get defaultSendCopyEnabled =>
      !AppStoreInfo.asksDataConsent(AppStoreInfo.current);

  /// Сгенерировать короткий читаемый код отчёта вида `SG-8F3A2C`.
  static String generateReportCode([Random? rng]) {
    final r = rng ?? Random.secure();
    final buf = StringBuffer('SG-');
    for (var i = 0; i < 6; i++) {
      buf.write(_codeAlphabet[r.nextInt(_codeAlphabet.length)]);
    }
    return buf.toString();
  }

  /// Односторонний хэш подписки `sha256("sub:" + shortUuid)` — побайтово
  /// совпадает с `Site/app.py:_support_sub_hash(sub)` в пульте поддержки `desk`.
  ///
  /// Для сторонних подписок хэш не сопоставим ни с одной записью на сервере и
  /// необратим, а для пользователей `silentgate.lol` позволяет мгновенно
  /// показать отчёт внутри тикета в панели поддержки без передачи токена.
  static String? computeSubHash(String? rawSubscriptionUrl) {
    final target = SupportEndpointTarget.parse(rawSubscriptionUrl);
    if (target == null || target.shortUuid.isEmpty) return null;
    return Sha256.ofBytes(utf8.encode('sub:${target.shortUuid}'));
  }

  /// Односторонний хэш устройства `sha256("hwid:" + lower(hwid))` для связки
  /// отчёта с карточкой пользователя в панели поддержки без раскрытия сырого HWID.
  static String? computeHwidHash(String? rawHwid) {
    final clean = _cleanHwid(rawHwid);
    if (clean == null) return null;
    return Sha256.ofBytes(utf8.encode('hwid:$clean'));
  }

  /// Короткий псевдоним устройства (`16` hex) внутри текста обезличенного отчёта:
  /// позволяет видеть повторные отчёты с одного устройства без деанонимизации.
  static String computeAnonDeviceId(String? rawHwid) {
    final clean = _cleanHwid(rawHwid) ?? 'unknown';
    return Sha256.ofBytes(utf8.encode('sg-anon-dev-v1:$clean'))
        .substring(0, 16);
  }

  static String? _cleanHwid(String? rawHwid) {
    final v = (rawHwid ?? '').trim().toLowerCase();
    if (v.isEmpty || v == '…' || v.startsWith('н/д') || v == 'unknown') {
      return null;
    }
    return v;
  }

  static bool _isSilentGateHost(String host) {
    final h = host.toLowerCase();
    return h == 'silentgate.lol' || h.endsWith('.silentgate.lol');
  }

  static final RegExp _winUserPathRe = RegExp(
    r'([A-Za-z]:\\Users\\)([^\\/\r\n"]+)(\\)',
    caseSensitive: false,
  );
  static final RegExp _unixUserPathRe = RegExp(
    r'(/(?:Users|home)/)([^/\r\n"]+)(/)',
  );
  static final RegExp _androidAppDirRe = RegExp(
    r'/data/app/~~[^/\s]+/[^/\s]+/',
  );
  static final RegExp _hwidLineRe = RegExp(
    r'^HWID:\s*.*$',
    multiLine: true,
  );

  // Строгий матч IPv4 (4 октета, не часть версии вида 1.18.8 и не дата 16.11.2026).
  static final RegExp _ipv4Re = RegExp(
    r'(?<![0-9A-Za-z.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![0-9.])',
  );

  // Матч IPv6-литералов и префиксов (включая `2a00:1fa2:c628:1aa6::/64` и `fe80::1`).
  static final RegExp _ipv6Re = RegExp(
    r'(?<![0-9A-Za-z:])[0-9A-Fa-f:]{2,39}(?:/\d{1,3})?(?![0-9A-Za-z:])',
  );

  static const Set<String> _keepPublicIpv4 = <String>{
    '1.1.1.1',
    '1.0.0.1',
    '8.8.8.8',
    '8.8.4.4',
    '9.9.9.9',
    '149.112.112.112',
    '77.88.8.8',
    '77.88.8.1',
    '208.67.222.222',
    '208.67.220.220',
  };

  /// Подготовить обезличенную копию отчёта для разработчика.
  ///
  /// Сохраняет все диагностические сигналы (версии, модель/ОС, настройки,
  /// выбранный профиль без боевых IP, тайминги, переходы между типами сетей и
  /// ошибки ядер), скрывая личные идентификаторы, пути пользователя, сторонние
  /// домены подписки и клиентские/целевые IP.
  static String anonymizeReportText(
    String rawReport, {
    String? rawHwid,
    String? rawSubscriptionUrl,
    String? reportCode,
  }) {
    var out = SensitiveAddresses.mask(rawReport);
    final anonId = computeAnonDeviceId(rawHwid);

    // 1. Заменяем строку HWID и любые прямые вхождения сырого HWID в тексте.
    out = out.replaceAll(_hwidLineRe, 'HWID: anon:$anonId');
    final cleanHwid = (rawHwid ?? '').trim();
    if (cleanHwid.length >= 6 &&
        !cleanHwid.startsWith('н/д') &&
        cleanHwid != 'unknown') {
      out = out.replaceAll(
        RegExp(RegExp.escape(cleanHwid), caseSensitive: false),
        'anon:$anonId',
      );
    }

    // 2. Скрываем домен сторонней подписки (оставляя факт silentgate.lol vs сторонний).
    final subTrimmed = (rawSubscriptionUrl ?? '').trim();
    if (subTrimmed.isNotEmpty) {
      final uri = Uri.tryParse(subTrimmed);
      final host = uri?.host ?? '';
      if (host.isNotEmpty && !_isSilentGateHost(host)) {
        out = out.replaceAll(
          RegExp(RegExp.escape(host), caseSensitive: false),
          '<сторонний-провайдер>',
        );
      }
    }

    // 3. Очищаем имя учётной записи ОС в путях и хэш-каталог установки Android.
    out = out.replaceAllMapped(
      _winUserPathRe,
      (m) => '${m[1]}<user>${m[3]}',
    );
    out = out.replaceAllMapped(
      _unixUserPathRe,
      (m) => '${m[1]}<user>${m[3]}',
    );
    out = out.replaceAll(_androidAppDirRe, '/data/app/<pkg>/');

    // 4. Обезличиваем IPv6-адреса и префиксы провайдера с сохранением связности.
    final v6Map = <String, String>{};
    out = out.replaceAllMapped(_ipv6Re, (m) {
      final full = m[0]!;
      if (!full.contains(':')) return full;
      final slashIdx = full.indexOf('/');
      final addrPart =
          (slashIdx >= 0 ? full.substring(0, slashIdx) : full).toLowerCase();
      final prefixSuffix = slashIdx >= 0 ? full.substring(slashIdx) : '';
      if (':'.allMatches(addrPart).length < 2) return full;

      if (addrPart == '::' ||
          addrPart == '::1' ||
          addrPart.startsWith('fdfe:dcba:9876:')) {
        return full;
      }
      // Отсекаем случайные совпадения вида `18:25:51` (время HH:MM:SS).
      if (RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(addrPart)) {
        return full;
      }
      if (InternetAddress.tryParse(addrPart) == null) {
        return full;
      }
      if (addrPart.startsWith('fe80:')) {
        return '<link-v6>$prefixSuffix';
      }
      if (addrPart.startsWith('fc') || addrPart.startsWith('fd')) {
        final tag = v6Map.putIfAbsent(addrPart, () => '<ula-v6-#${v6Map.length + 1}>');
        return '$tag$prefixSuffix';
      }
      final tag =
          v6Map.putIfAbsent(addrPart, () => '<isp-v6-#${v6Map.length + 1}>');
      return '$tag$prefixSuffix';
    });

    // 5. Обезличиваем IPv4-адреса (LAN, CGNAT и внешние личные цели) с сохранением типа сети.
    final lanMap = <String, String>{};
    final cgnatMap = <String, String>{};
    final extMap = <String, String>{};

    out = out.replaceAllMapped(_ipv4Re, (m) {
      final a = int.tryParse(m[1]!);
      final b = int.tryParse(m[2]!);
      final c = int.tryParse(m[3]!);
      final d = int.tryParse(m[4]!);
      if (a == null || b == null || c == null || d == null) return m[0]!;
      if (a > 255 || b > 255 || c > 255 || d > 255) return m[0]!;

      final ip = '$a.$b.$c.$d';
      // Служебные и диагностические адреса оставляем как есть.
      if (a == 127 ||
          ip == '0.0.0.0' ||
          ip == '255.255.255.255' ||
          (a == 169 && b == 254) ||
          (a == 172 && b == 19 && c == 0) ||
          (a == 198 && (b == 18 || b == 19)) ||
          _keepPublicIpv4.contains(ip)) {
        return ip;
      }
      // RFC1918 (домашний роутер / Wi-Fi / локальная сеть).
      if (a == 10 ||
          (a == 192 && b == 168) ||
          (a == 172 && b >= 16 && b <= 31)) {
        return lanMap.putIfAbsent(ip, () => '<lan-v4-#${lanMap.length + 1}>');
      }
      // Carrier-Grade NAT мобильного оператора (100.64.0.0/10).
      if (a == 100 && b >= 64 && b <= 127) {
        return cgnatMap.putIfAbsent(
          ip,
          () => '<cgnat-v4-#${cgnatMap.length + 1}>',
        );
      }
      // Прочие публичные адреса (личные SSH/веб-цели пользователя в логах ядра).
      return extMap.putIfAbsent(ip, () => '<ext-v4-#${extMap.length + 1}>');
    });

    if (reportCode != null &&
        reportCode.isNotEmpty &&
        !out.contains('Код отчёта: $reportCode')) {
      out = 'Код отчёта: $reportCode (обезличенная копия разработчику)\n$out';
    }
    return out;
  }

  /// Отправить обезличенный отчёт на сервер разработчика.
  ///
  /// Если [proxyPort] задан и > 0, пробует отправку через локальный прокси
  /// активного VPN и автоматически откатывается на прямое HTTPS-соединение
  /// (или наоборот), чтобы отчёт доходил и при блокировке домена провайдером,
  /// и при неработающем VPN-туннеле.
  static Future<DevReportUploadResult> upload({
    required String anonymizedReport,
    required String reportCode,
    String? rawHwid,
    String? rawSubscriptionUrl,
    List<QuickReportTag> tags = const <QuickReportTag>[],
    bool hasUserDescription = false,
    String activeServer = '',
    String activeCore = '',
    String osVersion = '',
    String deviceModel = '',
    int? proxyPort,
    String proxyUser = '',
    String proxyPassword = '',
    String endpoint = defaultEndpoint,
    DevReportHttpSender? httpSender,
  }) async {
    final subHash = computeSubHash(rawSubscriptionUrl);
    final hwidHash = computeHwidHash(rawHwid);
    final anonId = computeAnonDeviceId(rawHwid);

    final payload = <String, dynamic>{
      'report_code': reportCode,
      'client_app': AppInfo.name,
      'client_version': AppInfo.displayVersion,
      'client_os': Platform.operatingSystem,
      'os_version': osVersion,
      'device_model': deviceModel,
      'flavor': AppStoreInfo.isStealth
          ? 'stealth'
          : (AppStoreInfo.flavor.isEmpty ? 'github' : AppStoreInfo.flavor),
      'anon_device_id': anonId,
      if (subHash != null) 'sub_hash': subHash,
      if (hwidHash != null) 'hwid_hash': hwidHash,
      'tags': tags.map((t) => t.wireKey).toList(),
      'has_description': hasUserDescription,
      'active_server': SensitiveAddresses.mask(activeServer),
      'active_core': activeCore,
      'report_text': anonymizedReport,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    };

    final bodyJson = jsonEncode(payload);
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      HttpHeaders.userAgentHeader: AppInfo.userAgent,
      'X-SilentGate-App': AppInfo.fullVersion,
      'X-SilentGate-OS': Platform.operatingSystem,
      'X-SilentGate-Report-Code': reportCode,
      if (subHash != null) 'X-SilentGate-Sub-Hash': subHash,
      if (hwidHash != null) 'X-SilentGate-Hwid-Hash': hwidHash,
    };

    final uri = Uri.parse(endpoint);

    try {
      (int, String) resp;
      if (httpSender != null) {
        resp = await httpSender(uri, headers, bodyJson);
      } else {
        resp = await _postWithFallback(
          uri,
          headers,
          bodyJson,
          proxyPort: proxyPort,
          proxyUser: proxyUser,
          proxyPassword: proxyPassword,
        );
      }

      final (status, respBody) = resp;
      if (status >= 200 && status < 300) {
        var linked = false;
        var serverCode = reportCode;
        try {
          final parsed = jsonDecode(respBody);
          if (parsed is Map) {
            linked = parsed['linked'] == true;
            final rc = '${parsed['report_code'] ?? ''}'.trim();
            if (rc.isNotEmpty) serverCode = rc;
          }
        } catch (_) {}
        AppLog.i('Отчёт разработчику отправлен ($serverCode)');
        return DevReportUploadResult(
          ok: true,
          reportCode: serverCode,
          linkedToSupport: linked,
        );
      }
      AppLog.w('Отправка отчёта разработчику: сервер ответил $status');
      return DevReportUploadResult(
        ok: false,
        reportCode: reportCode,
        error: 'HTTP $status',
      );
    } catch (e) {
      AppLog.w('Не удалось отправить копию отчёта разработчику: $e');
      return DevReportUploadResult(
        ok: false,
        reportCode: reportCode,
        error: '$e',
      );
    }
  }

  static Future<(int, String)> _postWithFallback(
    Uri uri,
    Map<String, String> headers,
    String bodyJson, {
    int? proxyPort,
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    final hasProxy = proxyPort != null && proxyPort > 0;
    if (hasProxy) {
      try {
        return await _postOnce(
          uri,
          headers,
          bodyJson,
          proxyPort: proxyPort,
          proxyUser: proxyUser,
          proxyPassword: proxyPassword,
          timeout: const Duration(seconds: 7),
        );
      } catch (_) {
        // Если активный туннель сломан — пробуем напрямую мимо VPN.
      }
    }
    return _postOnce(
      uri,
      headers,
      bodyJson,
      timeout: const Duration(seconds: 8),
    );
  }

  static Future<(int, String)> _postOnce(
    Uri uri,
    Map<String, String> headers,
    String bodyJson, {
    int? proxyPort,
    String proxyUser = '',
    String proxyPassword = '',
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      if (proxyPort != null && proxyPort > 0) {
        client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
        if (proxyUser.isNotEmpty) {
          client.addProxyCredentials(
            '127.0.0.1',
            proxyPort,
            '',
            HttpClientBasicCredentials(proxyUser, proxyPassword),
          );
        }
      } else {
        client.findProxy = (_) => 'DIRECT';
      }
      final req = await client.postUrl(uri).timeout(timeout);
      headers.forEach(req.headers.set);
      final encoded = utf8.encode(bodyJson);
      req.contentLength = encoded.length;
      req.add(encoded);
      final resp = await req.close().timeout(timeout);
      final text = await resp.transform(utf8.decoder).join().timeout(timeout);
      return (resp.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }
}
