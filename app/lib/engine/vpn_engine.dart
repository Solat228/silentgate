import '../core/models/traffic_stats.dart';
import '../core/models/vpn_status.dart';
import '../core/models/vpn_server.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/xray/outbound_variant.dart';

/// Опции подключения: вариация обхода (fragment/fingerprint) + полные настройки
/// приложения. Настройки передаются целиком, чтобы новые параметры TUN/DNS доходили
/// до движка автоматически, без правки цепочки вызовов.
class ConnectionOptions {
  final OutboundVariant variant;
  final AppSettings settings;

  const ConnectionOptions({
    this.variant = OutboundVariant.none,
    this.settings = AppSettings.defaults,
  });

  CaptureMode get captureMode => settings.captureMode;
  SplitTunnelConfig get split => settings.splitTunnel;
}

/// Абстракция движка VPN. UI работает только с этим интерфейсом,
/// а конкретная реализация подставляется по платформе (см. engine_factory.dart).
abstract class VpnEngine {
  /// Поток изменений статуса подключения.
  Stream<VpnStatus> get statusStream;

  /// Поток статистики трафика (обновляется во время подключения).
  Stream<TrafficStats> get statsStream;

  /// Текущий статус (синхронно).
  VpnStatus get status;

  /// Локальный HTTP-прокси порт активного ядра — для живой проверки сервисов
  /// через уже поднятое соединение (без отдельного ядра/системного прокси).
  /// Осмыслен только при [status] == connected.
  int get httpProxyPort => 10809;

  /// Подключиться к выбранному серверу с опциями (вариация обхода, режим захвата, split).
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()});

  /// Подключиться в режиме автовыбора: balancer + burstObservatory по всем серверам,
  /// ядро само переключается на самый быстрый.
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()});

  /// Отключиться и вернуть систему в исходное состояние.
  Future<void> disconnect();

  /// Сигнал о смене сетевого окружения (Wi-Fi ↔ кабель, выход из сна, новый IP).
  /// Туннель поверх старого адаптера мёртв, даже если процессы живы, — движок
  /// сам решает, восстанавливать ли соединение (настройка «автопереподключение»).
  Future<void> onNetworkChanged() async {}

  /// Подхватить туннель, поднятый ПРОШЛЫМ запуском интерфейса.
  ///
  /// Зовётся один раз при старте. Умолчание — ничего не делать: на Windows
  /// туннель и интерфейс живут в одном процессе, и подхватывать нечего.
  ///
  /// На Android иначе: `VpnService` переживает смерть Activity, а состояние
  /// движка — нет. Без подхвата приложение показывало «Отключено» при
  /// РАБОТАЮЩЕМ VPN, а Connect поднимал второй сеанс поверх живого.
  Future<void> adoptRunningTunnel() async {}

  /// Запасные серверы для режима «Авто (лучший сервер)»: если текущий не поднялся
  /// после всех попыток, движок берёт следующий отсюда. В ручном режиме — пусто:
  /// выбор пользователя не подменяем.
  set fallbackServers(List<VpnServer> servers) {}

  /// Освободить ресурсы.
  Future<void> dispose();
}
