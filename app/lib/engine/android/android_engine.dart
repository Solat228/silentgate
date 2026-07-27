import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/platform/app_log.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/singbox/singbox_outbound_factory.dart';
import '../engine_base.dart';

/// Движок Android: туннель поднимает `libbox` (sing-box) внутри
/// `SilentGateVpnService`.
///
/// Платформо-независимая половина (сессия, поколения, автовосстановление,
/// выбор конфига и ядра) живёт в [VpnEngineBase] и общая с Windows. Здесь
/// остаётся только мост к нативному сервису.
///
/// Дескриптор туннеля передаётся инверсией управления: ядро зовёт
/// `PlatformInterface.openTun`, сервис строит `VpnService.Builder` и
/// возвращает fd. Подробности — `tools/build-android-cores.md`.
///
/// ## Как выбирается ядро
///
/// Ровно как на Windows — через `configFor` в базе: полный конфиг (правка
/// пользователя или панельный профиль «Авто» с `balancers`/`burstObservatory`)
/// поднимает Xray, а туннель заворачивает трафик в его локальный SOCKS.
/// Обычный сервер sing-box обслуживает сам, и тогда промежуточный SOCKS не
/// нужен: outbound встраивается прямо в конфиг туннеля.
///
/// Оба ядра живут в ОДНОМ AAR: раздельные gomobile-библиотеки конфликтуют
/// общим Go-рантаймом (`go.Seq`), и собрать их вместе иначе нельзя
/// (`tools/build-android-cores.md`).
class AndroidEngine extends VpnEngineBase {
  AndroidEngine({super.ports}) {
    _events.receiveBroadcastStream().listen(_onNativeEvent);
  }

  static const _channel = MethodChannel('lol.silentgate/vpn');
  static const _events = EventChannel('lol.silentgate/vpn_events');

  /// Идёт ли сейчас наш собственный подъём: нужно, чтобы не принять
  /// подтверждение «сервис запущен» за неожиданное падение.
  bool _starting = false;

  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;

    final gen = newGeneration();
    bool aborted() => isStale(gen);

    setStatus(VpnConnectionState.connecting);

    try {
      // Ядро выбирается ровно так же, как на Windows (configFor в базе):
      // полный конфиг (правка пользователя или панельный профиль «Авто») —
      // всегда Xray; обычный сервер sing-box поднимает сам.
      final cfg = configFor(session.servers.first, session.options);
      final viaXray = cfg.core == ProxyCore.xray &&
          !SingboxOutboundFactory.supports(session.servers.first);

      final serverIps = await resolveServerIps(session.servers);
      if (aborted()) return;

      // Когда сервер поднимает Xray, туннель заворачивает трафик в его
      // локальный SOCKS — как на Windows. Когда справляется sing-box, лишний
      // переход не нужен, и outbound встраивается прямо в конфиг туннеля.
      final tunJson = SingboxConfigBuilder(
        xraySocksPort: ports.socks,
        options: TunOptions.fromSettings(
          session.options.settings,
          serverIps: serverIps,
          android: true,
        ),
        proxyOutbound: viaXray
            ? null
            : SingboxOutboundFactory.build(session.servers.first),
      ).buildJson(session.options.split);

      if (aborted()) return;

      _starting = true;
      await _channel.invokeMethod<void>('start', {
        'config': tunJson,
        if (viaXray) 'xray_config': cfg.json,
      });
      _starting = false;

      // Пользователь мог отключиться, пока шло согласие на VPN.
      if (aborted()) {
        await _channel.invokeMethod<void>('stop');
        return;
      }

      markConnected();
      setStatus(VpnConnectionState.connected);
    } on PlatformException catch (e) {
      _starting = false;
      // Отказ в согласии — не ошибка подключения, а решение пользователя:
      // повторять его автоматически бессмысленно.
      final wasAborted = aborted();
      await cleanup();
      if (wasAborted) return;
      if (e.code == 'consent_denied') {
        setStatus(VpnConnectionState.error, message: e.message);
        return;
      }
      if (await scheduleRetry('не удалось подключиться: ${e.message}')) return;
      setStatus(VpnConnectionState.error, message: e.message);
    } catch (e) {
      _starting = false;
      final wasAborted = aborted();
      await cleanup();
      if (wasAborted) return;
      if (await scheduleRetry('не удалось подключиться: $e')) return;
      setStatus(VpnConnectionState.error, message: '$e');
    }
  }

  /// Событие от сервиса: туннель поднялся, упал или его отобрала система.
  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final running = event['running'] == true;
    final error = (event['error'] as String?)?.trim();

    if (running || _starting) return;
    if (!status.isConnected && status.state != VpnConnectionState.connecting) {
      return;
    }

    // Сюда попадает и onRevoke (другой VPN перехватил туннель) — пути,
    // которого на Windows нет вовсе.
    AppLog.e('VPN-сервис остановился: ${error ?? 'без причины'}');

    // Текст из нативного слоя ОБЯЗАН доехать до пользователя. Без этого
    // подключение просто «вылетало» молча, и причину нельзя было назвать
    // даже по логам приложения.
    unawaited(_reportStop(error));
  }

  Future<void> _reportStop(String? error) async {
    if (error == null || error.isEmpty) {
      await onCoreDied(0);
      return;
    }
    // Причина известна — показываем её вместо безымянного «ядро остановилось».
    // Повторять попытку смысла нет: конфиг тот же, результат будет тот же.
    await cleanup();
    setStatus(VpnConnectionState.error, message: error);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    // keepCapture (kill switch) на Android означало бы «держать fd открытым
    // без ядра». libbox владеет дескриптором сам, поэтому раздельной остановки
    // тут нет: сервис гасится целиком. Роль kill switch отдана системному
    // Always-on + «блокировать соединения без VPN».
    await _stopService();
  }

  @override
  Future<void> platformCleanup() async => _stopService();

  Future<void> _stopService() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      AppLog.w('Не удалось остановить VPN-сервис: $e');
    }
  }
}
