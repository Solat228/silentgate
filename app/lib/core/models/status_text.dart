/// Сообщение статуса подключения — код и параметры, а не готовая строка.
///
/// ⚠️ ЗАЧЕМ (ANDROID.md п.19а). `VpnStatus.message` — свободная РУССКАЯ строка,
/// и главный экран печатал её как есть: в девяти языках из десяти человек
/// видел русский текст ровно в момент обрыва или ошибки — когда понять его
/// важнее всего. Переводить построчно нельзя: движок не знает языка
/// интерфейса и знать не должен. Поэтому движок кладёт сюда, ЧТО случилось,
/// а текст подбирает UI (`ui/widgets/status_text_l10n.dart`).
///
/// `VpnStatus.message` остаётся — это русский фолбэк для журнала и отчёта
/// поддержки (они не переводятся) и текст для случаев без кода: сырой вывод
/// ядра, исключение, которое перевести нечем.
sealed class StatusText {
  const StatusText();
}

/// Kill switch держит трафик, впереди очередная попытка.
final class StatusReconnectBlocked extends StatusText {
  final int seconds;
  final int attempt;
  const StatusReconnectBlocked({required this.seconds, required this.attempt});
}

/// Туннель поднят, сторож канала трижды не дождался ответа.
final class StatusTrafficNotFlowing extends StatusText {
  const StatusTrafficNotFlowing();
}

/// Android: человек не подтвердил системный запрос на VPN.
final class StatusVpnConsentDenied extends StatusText {
  const StatusVpnConsentDenied();
}

/// Рядом с приложением нет исполняемого файла ядра.
final class StatusMissingCore extends StatusText {
  /// Имя файла: `xray.exe`, `sing-box.exe`.
  final String file;
  const StatusMissingCore(this.file);
}

/// Локальный порт занят.
final class StatusPortConflict extends StatusText {
  final int port;

  /// Программа, занявшая порт; `null` — определить не удалось.
  final String? holder;

  /// Порт держит наше же ядро от прошлой сессии.
  final bool ownCore;
  const StatusPortConflict(
      {required this.port, this.holder, this.ownCore = false});
}

/// Туннельное ядро перестало отвечать, туннель снят сторожем.
final class StatusTunCoreHung extends StatusText {
  const StatusTunCoreHung();
}

/// Подключение не удалось; [detail] — сырой текст исключения (не переводится).
final class StatusConnectFailed extends StatusText {
  final String detail;
  const StatusConnectFailed(this.detail);
}

/// Ядро завершилось само.
final class StatusCoreStopped extends StatusText {
  /// `Xray` или `sing-box`.
  final String core;
  final int code;
  final CoreStopReason? reason;
  const StatusCoreStopped(
      {required this.core, required this.code, this.reason});
}

/// Причина остановки ядра, вычитанная из его вывода.
sealed class CoreStopReason {
  const CoreStopReason();
}

/// Ядро не смогло занять локальный порт.
final class CoreStopPortBusy extends CoreStopReason {
  final int? port;
  const CoreStopPortBusy(this.port);
}

final class CoreStopFailedToStart extends CoreStopReason {
  const CoreStopFailedToStart();
}

/// Первая строка вывода ядра — как есть, без перевода.
final class CoreStopRaw extends CoreStopReason {
  final String line;
  const CoreStopRaw(this.line);
}
