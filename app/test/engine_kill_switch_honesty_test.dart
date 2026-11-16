import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/status_text.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

class _FakeEngine extends VpnEngineBase {
  /// Держит ли «платформа» захват между попытками.
  bool holding = true;

  @override
  bool killSwitchHolding(EngineSession session) => holding;

  @override
  Future<bool?> directInternetAvailable() async => true;

  @override
  Future<void> startSession() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  Future<void> platformCleanup() async {}
}

VpnServer _server() => const VpnServer(
      protocol: 'vless',
      remark: 'a',
      address: 'a.example.com',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@a.example.com:443#a',
    );

ConnectionOptions _ks() => ConnectionOptions(
    settings: AppSettings.defaults
        .copyWith(autoReconnect: true, killSwitch: true, seamlessKeepTun: false));

/// Ревью 29.10.2026.
void main() {
  group('H4: kill switch без захвата не говорит «заблокировано»', () {
    test('захват держится — статус блокировки', () async {
      final e = _FakeEngine();
      await e.connectWith('{}', _ks(), [_server()]);
      expect(await e.scheduleRetry('обрыв'), isTrue);
      expect(e.status.blocking, isTrue);
      expect(e.status.text, isA<StatusReconnectBlocked>());
      await e.disconnect();
    });

    test('захват потерян — честный статус и трей не красный', () async {
      final e = _FakeEngine();
      await e.connectWith('{}', _ks(), [_server()]);
      expect(await e.scheduleRetry('обрыв'), isTrue);
      expect(e.status.blocking, isTrue);

      e.holding = false; // туннель на повторе не поднялся
      e.dropPendingRetry(); // иначе второй вызов — «тот же обрыв»
      expect(await e.scheduleRetry('TUN не поднялся'), isTrue);
      expect(e.status.blocking, isFalse);
      expect(e.status.text, isA<StatusReconnectUnprotected>());
      // Следующая попытка шлёт «Подключение…» — признак не должен вернуться.
      e.setStatus(VpnConnectionState.connecting);
      expect(e.status.blocking, isFalse);
      await e.disconnect();
    });
  });

  group('L12: ошибка после «Отключить»', () {
    test('ошибка поверх «Отключено» не ставится', () async {
      final e = _FakeEngine();
      await e.connectWith('{}', _ks(), [_server()]);
      await e.disconnect();
      e.setStatus(VpnConnectionState.error, message: 'трафик не идёт');
      expect(e.status.state, VpnConnectionState.disconnected);
    });

    test('после нового подключения ошибка снова видна', () async {
      final e = _FakeEngine();
      await e.connectWith('{}', _ks(), [_server()]);
      await e.disconnect();
      await e.connectWith('{}', _ks(), [_server()]);
      e.setStatus(VpnConnectionState.error, message: 'отказ');
      expect(e.status.state, VpnConnectionState.error);
      await e.disconnect();
    });
  });
}
