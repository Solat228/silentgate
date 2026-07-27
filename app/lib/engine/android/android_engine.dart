import '../../core/models/vpn_status.dart';
import '../engine_base.dart';

/// Движок Android — **каркас фазы 3**, датапуть ещё не подключён.
///
/// Вся платформо-независимая половина (сессия, поколения, автовосстановление,
/// выбор конфига и ядра) уже работает: она живёт в [VpnEngineBase] и общая с
/// Windows. Не хватает трёх платформенных вещей, каждая — отдельная задача
/// плана `docs/platforms/ANDROID.md`:
///
///  * задача 21 — `libbox.aar` (sing-box) и `libxray.aar`, собираются через
///    gomobile; без Go в системе их пока негде взять;
///  * задачи 30–37 — `SilentGateVpnService` с `PlatformInterface`, колбэком
///    `OpenTun` и согласием `VpnService.prepare()`;
///  * задача 32 — мост `MethodChannel`/`EventChannel` между этим классом и
///    сервисом.
///
/// До тех пор подключение честно сообщает, что не реализовано. Это осознанно:
/// молчаливая заглушка (статус «Подключено» без туннеля) была бы прямой ложью
/// о состоянии VPN — худшее, что может сделать такой клиент.
///
/// Всё остальное приложение при этом полностью рабочее: импорт подписки,
/// список серверов, настройки, локализация, хранилища.
class AndroidEngine extends VpnEngineBase {
  AndroidEngine({super.ports});

  @override
  Future<void> startSession() async {
    setStatus(
      VpnConnectionState.error,
      message: 'Подключение на Android ещё не реализовано: не хватает ядер '
          '(libbox/libXray) и VpnService. Остальное приложение работает — '
          'можно импортировать подписку и смотреть серверы.',
    );
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  Future<void> platformCleanup() async {}
}
