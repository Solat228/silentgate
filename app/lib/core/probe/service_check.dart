import '../settings/app_settings.dart';
import 'auto_config_engine.dart';
import 'proxy_probe.dart';

/// Итог живой проверки сервиса ЧЕРЕЗ уже поднятый VPN (у кнопки Connect).
enum ServiceCheckState {
  /// Ещё не проверяли.
  idle,

  /// Проверка идёт.
  checking,

  /// Открывается и (для ИИ) доступен в стране выхода.
  ok,

  /// Открывается, но заблокирован в стране выхода VPN (ИИ: «недоступно в регионе»).
  geoBlocked,

  /// Не открывается (недоступен/таймаут).
  fail,
}

class ServiceCheckOutcome {
  final ServiceCheckState state;

  /// Задержка ответа (RTT) через активный туннель, мс.
  final int? latencyMs;

  const ServiceCheckOutcome(this.state, {this.latencyMs});

  static const idle = ServiceCheckOutcome(ServiceCheckState.idle);
  static const checking = ServiceCheckOutcome(ServiceCheckState.checking);

  bool get isTerminal =>
      state == ServiceCheckState.ok ||
      state == ServiceCheckState.geoBlocked ||
      state == ServiceCheckState.fail;
}

/// Проверяет сервис ЧЕРЕЗ активный локальный http-прокси уже поднятого VPN —
/// не включает системный прокси и не поднимает отдельное ядро. Сначала
/// доступность (открывается ли), затем — для ИИ — гео-ограничение по стране
/// выхода. Гео-проба неинформативна ⇒ считаем доступным (безопасный дефолт).
class ServiceChecker {
  /// Проверить ОДНУ мишень через прокси-порт, выбрав способ по адресу.
  ///
  /// ⚠️ ЕДИНАЯ ТОЧКА ДЛЯ ВСЕХ, КТО ПРОВЕРЯЕТ СЕРВИСЫ, И ЭТО НЕ ВКУСОВЩИНА.
  /// Мишень Telegram задана как `tcp://149.154.167.51:443`: его дата-центры
  /// говорят по MTProto, и обычный HTTP-запрос провалился бы на сертификате
  /// при полностью живом канале. Сервис-чипы это учитывали, а автонастройка —
  /// НЕТ: она гнала тот же адрес в `HttpClient`, где `tcp://` не схема вовсе.
  /// Telegram у неё падал ВСЕГДА, при любом сервере, а он входит в набор по
  /// умолчанию — то есть «найдено 0» получалось на исправной подписке.
  ///
  /// Два разных разбора одного адреса — это всегда расхождение; тот же урок
  /// уже записан про разрешение и исполнение url-схем. Теперь способ выбирает
  /// один код, и оба потребителя спрашивают его.
  static Future<ProbeOutcome> probeEndpoint(
    int proxyPort,
    ProbeEndpoint ep, {
    Duration timeout = const Duration(seconds: 8),
    String? proxyUser,
    String? proxyPassword,
  }) {
    if (ep.url.startsWith('tcp://')) {
      return _tcpProbe(proxyPort, ep.url);
    }
    return ProxyProbe.check(
      proxyPort,
      ep.url,
      head: ep.head,
      validator: ep.validator,
      timeout: timeout,
      proxyUser: proxyUser,
      proxyPassword: proxyPassword,
    );
  }

  /// Разобрать `tcp://host:port` и дозвониться туда через прокси.
  static Future<ProbeOutcome> _tcpProbe(int httpPort, String url) async {
    final rest = url.substring('tcp://'.length);
    final i = rest.lastIndexOf(':');
    if (i <= 0) return const ProbeOutcome(ok: false);
    final host = rest.substring(0, i);
    final port = int.tryParse(rest.substring(i + 1)) ?? 0;
    if (port <= 0) return const ProbeOutcome(ok: false);
    return ProxyProbe.tcpConnect(httpPort, host, port);
  }

  static Future<ServiceCheckOutcome> check(int httpPort, ProbeService s) async {
    final ep = AutoConfigCatalog.endpointFor(s);
    if (ep == null) return const ServiceCheckOutcome(ServiceCheckState.fail);

    final r = await probeEndpoint(httpPort, ep);
    if (!r.ok) {
      return ServiceCheckOutcome(ServiceCheckState.fail, latencyMs: r.rttMs);
    }

    final geo = AutoConfigCatalog.geoEndpointFor(s);
    if (geo != null) {
      // validator == geo.blocked: ok==true ⇒ сервис заблокирован в регионе.
      final g = await ProxyProbe.check(
        httpPort,
        geo.url,
        validator: geo.blocked,
        timeout: const Duration(seconds: 8),
      );
      if (g.ok) {
        return ServiceCheckOutcome(ServiceCheckState.geoBlocked, latencyMs: r.rttMs);
      }
    }
    return ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: r.rttMs);
  }
}
