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
/// ## Чем отличается от Windows
///
/// На Windows ядер два: sing-box держит туннель и заворачивает трафик в
/// локальный SOCKS, где его принимает отдельный процесс Xray. На Android так
/// нельзя — оба ядра там gomobile-библиотеки, а две такие библиотеки в одном
/// приложении конфликтуют общим Go-рантаймом (`go.Seq`). Поэтому ядро одно:
/// sing-box держит и туннель, и сам прокси-outbound, промежуточного SOCKS нет.
///
/// Плата за это — панельные профили «Авто» (готовые Xray-конфиги с
/// `balancers`/`burstObservatory`) на Android пока не работают.
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
      final unsupported =
          session.servers.where((s) => !SingboxOutboundFactory.supports(s));
      if (unsupported.isNotEmpty) {
        // Панельные профили «Авто» — это готовые Xray-конфиги с балансировщиком;
        // sing-box их не разберёт. Честно говорим об этом, а не подключаемся
        // «куда-нибудь».
        await cleanup();
        setStatus(
          VpnConnectionState.error,
          message: 'Профили «Авто» от панели на Android пока не поддерживаются: '
              'они собраны для Xray. Выберите обычный сервер.',
        );
        return;
      }

      // На Android ядро одно: sing-box держит и туннель, и сам прокси-outbound.
      // Промежуточный SOCKS не нужен — это единственное отличие от Windows,
      // и вызвано оно тем, что две gomobile-библиотеки в одном приложении
      // конфликтуют общим Go-рантаймом.
      final tunJson = SingboxConfigBuilder(
        xraySocksPort: ports.socks,
        options: TunOptions.fromSettings(
          session.options.settings,
          serverIps: await resolveServerIps(session.servers),
        ),
        proxyOutbound: SingboxOutboundFactory.build(session.servers.first),
      ).buildJson(session.options.split);

      if (aborted()) return;

      _starting = true;
      await _channel.invokeMethod<void>('start', {'config': tunJson});
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
    final error = event['error'] as String?;

    if (running || _starting) return;
    if (!status.isConnected && status.state != VpnConnectionState.connecting) {
      return;
    }

    // Сюда попадает и onRevoke (другой VPN перехватил туннель) — пути,
    // которого на Windows нет вовсе.
    AppLog.e('VPN-сервис остановился: ${error ?? 'без причины'}');
    unawaited(onCoreDied(0));
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
