import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Фаза жизненного цикла помощника TUN для конкретной попытки запуска.
enum TunHelperPhase {
  running('running'),
  coreDied('core_died'),
  exited('exited');

  final String wire;
  const TunHelperPhase(this.wire);

  static TunHelperPhase? fromWire(Object? raw) {
    for (final v in values) {
      if (v.wire == raw) return v;
    }
    return null;
  }
}

/// Причина остановки или отказа помощника TUN (чистый ASCII, без привязки к локали).
enum TunHelperExitReason {
  none('none'),
  killSwitchEngageFailed('killswitch_engage_failed'),
  killSwitchTunnelFailed('killswitch_tunnel_failed'),
  spawnFailed('spawn_failed'),
  coreExited('core_exited'),
  stopped('stopped');

  final String wire;
  const TunHelperExitReason(this.wire);

  /// Отказ не зависит от стека (`system`/`gvisor`/`mixed`) и MTU:
  /// перебирать остальные 8 комбинаций автоподбора на нём бессмысленно.
  bool get isNonTunParameterFailure =>
      this == killSwitchEngageFailed ||
      this == killSwitchTunnelFailed ||
      this == spawnFailed;

  static TunHelperExitReason fromWire(Object? raw) {
    for (final v in values) {
      if (v.wire == raw) return v;
    }
    return none;
  }
}

/// Снимок состояния конкретной попытки запуска помощника TUN ([launchId]).
class TunHelperStateSnapshot {
  final String launchId;
  final TunHelperPhase phase;
  final TunHelperExitReason reason;

  const TunHelperStateSnapshot({
    required this.launchId,
    required this.phase,
    this.reason = TunHelperExitReason.none,
  });

  bool get helperExited => phase == TunHelperPhase.exited;
  bool get coreDied => phase == TunHelperPhase.coreDied;
  bool get failed => helperExited || coreDied;
}

/// Сигнал состояния между элевейтнутым `TunHelper` и непривилегированным
/// `SingboxRouterWindows` через каталог данных (`%APPDATA%\SilentGate`).
///
/// Решает сразу три проблемы без парсинга русских строк в `singbox.log`:
///  1. `_waitUp` мгновенно прерывает 15-секундное ожидание адаптера, если ядро
///     или сам помощник уже завершились на первой секунде.
///  2. Если помощник уже вышел (`phase == exited`, пишется ПОСЛЕ удаления
///     `tun_stop`), роутер не кладёт сиротский `tun_stop`, который на следующем
///     старте висел бы до таймаута `waitStopConsumed`.
///  3. Автоподбор стека и MTU останавливается сразу, если причина отказа
///     (`killSwitchEngageFailed`, `killSwitchTunnelFailed`, `spawnFailed`) не
///     имеет отношения к параметрам TUN.
abstract final class TunHelperState {
  static const launchFileName = 'tun_launch';
  static const stateFileName = 'tun_helper_state.json';

  static String launchPathFor(Directory dir) =>
      '${dir.path}${Platform.pathSeparator}$launchFileName';
  static String statePathFor(Directory dir) =>
      '${dir.path}${Platform.pathSeparator}$stateFileName';

  /// Вызывается роутером ПЕРЕД запуском помощника или `TunReload.request`.
  static String prepareLaunch(Directory dir) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 31)}';
    _delete(statePathFor(dir));
    try {
      File(launchPathFor(dir)).writeAsStringSync(id, flush: true);
    } catch (_) {}
    return id;
  }

  /// Прочитать токен текущей попытки запуска (вызывается помощником).
  static String readLaunchId(Directory dir) {
    try {
      final f = File(launchPathFor(dir));
      if (!f.existsSync()) return '';
      return f.readAsStringSync().trim();
    } catch (_) {
      return '';
    }
  }

  /// Записать текущую фазу помощника. Ошибка записи не имеет права ронять
  /// помощника: файл чисто сигнальный.
  static void write(
    Directory dir, {
    required String launchId,
    required TunHelperPhase phase,
    TunHelperExitReason reason = TunHelperExitReason.none,
  }) {
    if (launchId.isEmpty) return;
    try {
      final payload = jsonEncode(<String, String>{
        'launchId': launchId,
        'phase': phase.wire,
        'reason': reason.wire,
      });
      File(statePathFor(dir)).writeAsStringSync(payload, flush: true);
    } catch (_) {}
  }

  /// Прочитать состояние конкретной попытки [expectedLaunchId].
  /// Возвращает `null`, если ответа от этой попытки ещё нет.
  static TunHelperStateSnapshot? read(Directory dir, String expectedLaunchId) {
    if (expectedLaunchId.isEmpty) return null;
    try {
      final f = File(statePathFor(dir));
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map) return null;
      final id = '${decoded['launchId'] ?? ''}'.trim();
      if (id != expectedLaunchId) return null;
      final phase = TunHelperPhase.fromWire(decoded['phase']);
      if (phase == null) return null;
      final reason = TunHelperExitReason.fromWire(decoded['reason']);
      return TunHelperStateSnapshot(
        launchId: id,
        phase: phase,
        reason: reason,
      );
    } catch (_) {
      return null;
    }
  }

  static void _delete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
