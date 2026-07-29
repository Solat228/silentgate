import '../../../core/settings/split_tunnel.dart';
import '../../../core/singbox/singbox_config_builder.dart';

/// Абстракция TUN-роутера (поднимает TUN и маршрутизацию поверх локального прокси Xray).
abstract class TunRouter {
  /// Запустить (элевейтнуто). [xraySocksPort] — локальный SOCKS Xray, куда уходит
  /// прокси-трафик; [options] — параметры туннеля (стек, DNS, IPv6, IP серверов…).
  /// Бросает [TunStartException] с текстом из лога sing-box, если туннель не поднялся.
  /// [onProgress] — сообщения о ходе автоподбора параметров (стек/MTU) для статуса.
  /// [abort] — вернёт true, если пользователь отключился: автоподбор (до 2 мин)
  /// обязан свериться и прекратить перебор, иначе туннель поднимется уже ПОСЛЕ
  /// «Отключить» и продолжит переэлевировать комбинации.
  Future<void> start(SplitTunnelConfig split,
      {required int xraySocksPort,
      required TunOptions options,
      void Function(String message)? onProgress,
      bool Function()? abort});

  /// Остановить и снять TUN.
  Future<void> stop();
}

/// TUN не поднялся. [details] — хвост лога sing-box (для показа пользователю).
class TunStartException implements Exception {
  final String message;
  final String details;
  TunStartException(this.message, {this.details = ''});
  @override
  String toString() => details.isEmpty ? message : '$message\n\n$details';
}

/// Прав администратора получить не удалось.
///
/// Отдельный тип, а не просто текст в [TunStartException]: автоподбор стека и
/// MTU обязан на нём ОСТАНОВИТЬСЯ. Без прав не поднимется ни одна комбинация, а
/// продолжение перебора означает новый запрос прав на каждой — девять окон UAC
/// подряд у пользователя (а при зависшем запросе — минуты немого «Подключение…»).
class TunElevationDenied extends TunStartException {
  TunElevationDenied(super.message, {super.details});
}
