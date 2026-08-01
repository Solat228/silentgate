enum VpnConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// Фаза внутри состояния — чтобы UI отличал обычное подключение от особых
/// длительных этапов (напр. автоподбор стека/MTU TUN) без разбора текста.
enum VpnPhase {
  normal,

  /// Идёт перебор комбинаций стека/MTU туннеля (#8): показываем это отдельным
  /// прогресс-тостом, а не только строкой статуса.
  tunAutotune,
}

/// Текущее состояние туннеля + опциональное сообщение (например, текст ошибки).
class VpnStatus {
  final VpnConnectionState state;
  final String? message;
  final VpnPhase phase;

  /// ⚠️ KILL SWITCH СЕЙЧАС ДЕРЖИТ ТРАФИК: соединения падают, а не текут мимо VPN.
  ///
  /// Отдельный признак, а не разбор текста сообщения: по нему уведомление на
  /// Android и всплывающее окно на Windows объясняют человеку, что пропавший
  /// интернет — это работающая защита, а не поломка. Без такого объяснения
  /// самое естественное действие пользователя — выключить VPN, то есть ровно
  /// то, от чего защита и оберегала.
  final bool blocking;

  const VpnStatus(this.state,
      {this.message, this.phase = VpnPhase.normal, this.blocking = false});

  const VpnStatus.disconnected()
      : state = VpnConnectionState.disconnected,
        message = null,
        phase = VpnPhase.normal,
        blocking = false;

  bool get isConnected => state == VpnConnectionState.connected;
  bool get isBusy =>
      state == VpnConnectionState.connecting ||
      state == VpnConnectionState.disconnecting;

  String get label {
    switch (state) {
      case VpnConnectionState.disconnected:
        return 'Отключено';
      case VpnConnectionState.connecting:
        return 'Подключение…';
      case VpnConnectionState.connected:
        return 'Подключено';
      case VpnConnectionState.disconnecting:
        return 'Отключение…';
      case VpnConnectionState.error:
        return 'Ошибка';
    }
  }
}

/// Отслеживание автоподбора стека/MTU TUN (#8) — источник данных для
/// прогресс-тоста. Чистая, тестируемая машина состояний поверх [VpnStatus]:
/// пока идут статусы фазы [VpnPhase.tunAutotune] (connecting) — идёт подбор;
/// первый нефазовый статус фиксирует момент и исход завершения.
class TunAutotuneTracking {
  final bool running;
  final String? message;
  final DateTime? finishedAt;
  final bool succeeded;

  const TunAutotuneTracking({
    this.running = false,
    this.message,
    this.finishedAt,
    this.succeeded = false,
  });

  /// Следующее состояние по входящему статусу. [now] инъектируется для тестов.
  TunAutotuneTracking next(VpnStatus s, DateTime now) {
    final probing = s.phase == VpnPhase.tunAutotune &&
        s.state == VpnConnectionState.connecting;
    if (probing) {
      return TunAutotuneTracking(
          running: true, message: s.message, succeeded: succeeded);
    }
    if (running) {
      // Итог показываем только для НАСТОЯЩЕГО исхода подбора: connected (успех) /
      // error (неудача). Отмена пользователем (disconnected/disconnecting) — это
      // не «не удалось»: гасим прогресс без тоста-итога.
      final terminal = s.state == VpnConnectionState.connected ||
          s.state == VpnConnectionState.error;
      if (!terminal) {
        return TunAutotuneTracking(
            running: false, finishedAt: finishedAt, succeeded: succeeded);
      }
      return TunAutotuneTracking(
        running: false,
        finishedAt: now,
        succeeded: s.state == VpnConnectionState.connected,
      );
    }
    return this;
  }
}
