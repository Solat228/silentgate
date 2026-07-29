import 'dart:convert';
import 'dart:io';

/// Кто мы для внешнего мира: адрес, страна, город, провайдер.
class IpInfo {
  final String ip;
  final String? country;
  final String? countryCode;
  final String? city;
  final String? region;
  final String? isp;

  const IpInfo({
    required this.ip,
    this.country,
    this.countryCode,
    this.city,
    this.region,
    this.isp,
  });

  /// «Кемерово, Россия» либо что есть.
  String get location {
    final parts = [city, region, country].where((p) => (p ?? '').isNotEmpty);
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'country': country,
        'countryCode': countryCode,
        'city': city,
        'region': region,
        'isp': isp,
      };

  factory IpInfo.fromJson(Map<String, dynamic> j) => IpInfo(
        ip: '${j['ip'] ?? ''}',
        country: j['country'] as String?,
        countryCode: j['countryCode'] as String?,
        city: j['city'] as String?,
        region: j['region'] as String?,
        isp: j['isp'] as String?,
      );
}

/// Определение внешнего IP и геолокации — напрямую или через локальный прокси
/// (харнесс сервера), чтобы показать, каким адресом вы выходите в сеть.
class IpInfoService {
  /// HTTPS и без ключа. Второй — запасной, если первый недоступен.
  /// Те же адреса, но для ЧЕЛОВЕКА: пользователь должен иметь возможность
  /// открыть их в браузере и перепроверить наш результат руками. Без этого
  /// приходится верить приложению на слово — а именно доверие к цифрам «мой
  /// IP и страна» и есть смысл всей проверки.
  static const checkPageUrl = 'https://ipwho.is/';
  static const checkPageFallbackUrl = 'https://ipinfo.io/json';

  static const _primary = 'https://ipwho.is/';
  static const _fallback = 'https://ipinfo.io/json';

  /// [proxyPort] — локальный http-прокси; null = смотрим свой обычный выход.
  static Future<IpInfo?> lookup({
    int? proxyPort,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    for (final url in const [_primary, _fallback]) {
      final info = await _try(url, proxyPort, timeout);
      if (info != null) return info;
    }
    return null;
  }

  /// Геоданные КОНКРЕТНОГО адреса — узнаём страну сервера, не выходя через него
  /// и не раскрывая свой реальный адрес лишним прямым запросом.
  ///
  /// [host] может быть доменом: он резолвится обычным DNS, дальше запрашивается
  /// уже IP. Именно так заполняется «куда вы выходите» на экране сервера.
  static Future<IpInfo?> lookupHost(
    String host, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final ip = await _resolve(host, timeout);
    if (ip == null) return null;
    for (final base in const [_primary, _fallback]) {
      // ipwho.is/<ip> и ipinfo.io/<ip>/json — оба принимают адрес в пути.
      final url = base == _primary
          ? 'https://ipwho.is/$ip'
          : 'https://ipinfo.io/$ip/json';
      final info = await _try(url, null, timeout);
      if (info != null) return info;
    }
    return IpInfo(ip: ip); // адрес знаем, гео недоступно
  }

  static Future<String?> _resolve(String host, Duration timeout) async {
    final h = host.trim();
    if (h.isEmpty) return null;
    final direct = InternetAddress.tryParse(h);
    if (direct != null) return direct.address;
    try {
      final found = await InternetAddress.lookup(h).timeout(timeout);
      return found.isEmpty ? null : found.first.address;
    } catch (_) {
      return null;
    }
  }

  static Future<IpInfo?> _try(String url, int? proxyPort, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (proxyPort != null) {
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    }
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      final j = jsonDecode(body);
      if (j is! Map) return null;

      // ipwho.is отдаёт провайдера вложенно, ipinfo.io — строкой «AS… Название».
      final conn = j['connection'];
      final isp = conn is Map
          ? '${conn['isp'] ?? conn['org'] ?? ''}'
          : '${j['org'] ?? j['isp'] ?? ''}';

      final ip = '${j['ip'] ?? ''}';
      if (ip.isEmpty) return null;
      return IpInfo(
        ip: ip,
        country: _str(j['country']),
        countryCode: _str(j['country_code'] ?? j['country']),
        city: _str(j['city']),
        region: _str(j['region']),
        isp: isp.isEmpty ? null : isp,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String? _str(Object? v) {
    final s = '${v ?? ''}';
    return s.isEmpty ? null : s;
  }
}
