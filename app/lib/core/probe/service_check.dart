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
  static Future<ServiceCheckOutcome> check(int httpPort, ProbeService s) async {
    final ep = AutoConfigCatalog.endpointFor(s);
    if (ep == null) return const ServiceCheckOutcome(ServiceCheckState.fail);

    final r = await ProxyProbe.check(
      httpPort,
      ep.url,
      head: ep.head,
      validator: ep.validator,
      timeout: const Duration(seconds: 8),
    );
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
