import 'dart:async';

import '../models/vpn_server.dart';
import '../net/socks5_http_bridge.dart';
import '../platform/app_log.dart';
import '../probe/probe_harness.dart';
import '../xray/harness_config_builder.dart';
import '../xray/outbound_variant.dart';
import 'whitelist_bypass_helper.dart';

/// Хендл временного подключения к комнате БС для реального пинга, замера
/// скорости и определения выходного IP-адреса ЧЕРЕЗ сам звонок.
class WhitelistRelayProbeHandle implements HarnessHandle {
  final int _httpPort;
  final String _user;
  final String _password;
  final HarnessHandle? _innerHarness;
  final LocalHttpToSocksBridge? _bridge;
  final WhitelistBypassProcess? _bypass;

  /// `true`, если процесс релея запустился, но не смог войти в комнату или
  /// поднять WebRTC-канал (комната закрыта, таймаут сигнализации и т.д.).
  /// Отличается от «нечем измерить» (`_httpPort == 0 && !relayFailed`).
  final bool relayFailed;

  const WhitelistRelayProbeHandle._({
    required int httpPort,
    required String user,
    required String password,
    this.relayFailed = false,
    HarnessHandle? innerHarness,
    LocalHttpToSocksBridge? bridge,
    WhitelistBypassProcess? bypass,
  })  : _httpPort = httpPort,
        _user = user,
        _password = password,
        _innerHarness = innerHarness,
        _bridge = bridge,
        _bypass = bypass;

  factory WhitelistRelayProbeHandle.untested() =>
      const WhitelistRelayProbeHandle._(
        httpPort: 0,
        user: '',
        password: '',
        relayFailed: false,
      );

  factory WhitelistRelayProbeHandle.failed() =>
      const WhitelistRelayProbeHandle._(
        httpPort: -1,
        user: '',
        password: '',
        relayFailed: true,
      );

  /// Для тестовых дублей с готовым локальным HTTP-прокси.
  factory WhitelistRelayProbeHandle.forTest({
    required int httpPort,
    required String user,
    required String password,
    Future<void> Function()? onStop,
  }) =>
      _TestWhitelistRelayProbeHandle(
        httpPort: httpPort,
        user: user,
        password: password,
        onStop: onStop,
      );

  @override
  int proxyPortFor(int index) {
    if (index != 0) return -1;
    final inner = _innerHarness;
    if (inner != null) return inner.proxyPortFor(0);
    return _httpPort;
  }

  @override
  String get proxyUser => _innerHarness?.proxyUser ?? _user;

  @override
  String get proxyPassword => _innerHarness?.proxyPassword ?? _password;

  @override
  Future<int?> delayMs(int index) async {
    if (index != 0) return null;
    return _innerHarness?.delayMs(0);
  }

  @override
  Future<void> stop() async {
    try {
      await _bridge?.stop();
    } catch (_) {}
    try {
      await _innerHarness?.stop();
    } catch (_) {}
    try {
      await _bypass?.stop();
    } catch (_) {}
  }
}

class _TestWhitelistRelayProbeHandle extends WhitelistRelayProbeHandle {
  final Future<void> Function()? _onStop;

  _TestWhitelistRelayProbeHandle({
    required super.httpPort,
    required super.user,
    required super.password,
    Future<void> Function()? onStop,
  })  : _onStop = onStop,
        super._();

  @override
  Future<void> stop() async {
    await _onStop?.call();
    await super.stop();
  }
}

/// Поднимает изолированный экземпляр `whitelist-bypass` на свободном локальном
/// порту, входит в звонок и предоставляет защищённый паролем HTTP-прокси
/// поверх этого звонка.
abstract final class WhitelistRelayProbe {
  static Future<WhitelistRelayProbeHandle> start(
    VpnServer server, {
    OutboundVariant variant = OutboundVariant.none,
    HarnessRealism realism = HarnessRealism.none,
    ProbeHarness Function()? harnessFactory,
    bool Function()? abort,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (abort?.call() ?? false) {
      return WhitelistRelayProbeHandle.untested();
    }

    final exe = await WhitelistBypassProcess.resolveExecutablePath();
    if (exe == null) {
      AppLog.w(
        'Проба БС «${server.displayName}»: бинарник whitelist-bypass не найден',
      );
      return WhitelistRelayProbeHandle.untested();
    }

    final socksPort = await allocateLoopbackPort();
    final bypass = WhitelistBypassProcess();

    try {
      AppLog.i(
        'Проба БС «${server.displayName}»: вход в звонок '
        '(${server.whitelistPlatform ?? "bs"}, SOCKS5 127.0.0.1:$socksPort)...',
      );
      await bypass.start(
        server: server,
        socksPort: socksPort,
        executablePath: exe,
        timeout: timeout,
        abort: abort,
      );
      if (abort?.call() ?? false) {
        await bypass.stop();
        return WhitelistRelayProbeHandle.untested();
      }
    } catch (e) {
      await bypass.stop();
      if (abort?.call() ?? false) {
        return WhitelistRelayProbeHandle.untested();
      }
      AppLog.w('Проба БС «${server.displayName}»: вход в звонок не удался - $e');
      return WhitelistRelayProbeHandle.failed();
    }

    // Одиночная ссылка `whitelist://` (VK / Телемост / WB Stream / DION / Bitrix / Blink):
    // поверх локального SOCKS5 релея поднимаем защищённый паролем HTTP-прокси-мост
    // в самом процессе приложения (работает одинаково на Windows и Android).
    if (server.isWhitelistBypass) {
      try {
        final bridge = await LocalHttpToSocksBridge.start(socksPort: socksPort);
        return WhitelistRelayProbeHandle._(
          httpPort: bridge.port,
          user: bridge.user,
          password: bridge.password,
          bridge: bridge,
          bypass: bypass,
        );
      } catch (e) {
        await bypass.stop();
        AppLog.w('Проба БС «${server.displayName}»: мост прокси не поднялся - $e');
        return WhitelistRelayProbeHandle.untested();
      }
    }

    // Нода панели Remnawave (`VLESS + WS /sgbs?...`): поверх SOCKS5 звонка
    // поднимаем Xray-харнесс с привязкой `whitelistRelayPort: socksPort`.
    if (harnessFactory == null) {
      await bypass.stop();
      return WhitelistRelayProbeHandle.untested();
    }

    try {
      final inner = await harnessFactory().start([
        HarnessEntry(
          key: server.key,
          server: server,
          variant: variant,
          realism: realism,
          whitelistRelayPort: socksPort,
        ),
      ]);
      return WhitelistRelayProbeHandle._(
        httpPort: inner.proxyPortFor(0),
        user: inner.proxyUser,
        password: inner.proxyPassword,
        innerHarness: inner,
        bypass: bypass,
      );
    } catch (e) {
      await bypass.stop();
      AppLog.w('Проба БС «${server.displayName}»: харнесс поверх звонка не поднялся - $e');
      return WhitelistRelayProbeHandle.untested();
    }
  }
}
