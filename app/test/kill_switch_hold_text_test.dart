import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// KILL SWITCH ОБЯЗАН ГОВОРИТЬ, ЧТО ИМЕННО ОН ДЕРЖИТ.
///
/// ⚠️ ЖИВОЙ ПРОГОН В VM 02.09.2026. Подключение к Германии, правило «сайт →
/// Эстония», правило «сайт → Прямо». Убит `xray` (= Германия умерла). Журнал:
/// «Kill switch: ТРАФИК ЗАБЛОКИРОВАН до восстановления связи». А по факту в эту
/// же секунду Эстония и «Прямо» отвечали как ни в чём не бывало: TUN-ядро
/// (`sing-box`) живо, адаптер на месте, и удерживается ровно то, что шло в
/// основной туннель. Владелец прочитал ту же строку у себя как «мне вырубили
/// интернет» — и был неправ ровно настолько, насколько врала строка.
///
/// Разница между «весь трафик» и «только основной туннель» — не оттенок: от неё
/// зависит, бросится ли человек выключать VPN, чтобы вернуть себе Telegram.
void main() {
  group('killSwitchHoldText: что именно удерживается', () {
    test('TUN жив → держится только основной туннель, выходы и «Прямо» работают',
        () {
      final t = VpnEngineBase.killSwitchHoldText(
          tunnelStillUp: true, mode: CaptureMode.tun);
      expect(t, contains('основного туннеля'));
      expect(t, contains('другие выходы'));
      expect(t, contains('Прямо'));
      expect(t.toUpperCase(), isNot(contains('ВЕСЬ ТРАФИК')),
          reason: 'при живом TUN «весь трафик» — ложь, проверено живьём');
    });

    test('системный прокси → держится всё, что ходит через прокси', () {
      final t = VpnEngineBase.killSwitchHoldText(
          tunnelStillUp: false, mode: CaptureMode.systemProxy);
      expect(t, contains('прокси'));
    });

    test('TUN-ядро тоже умерло → держится весь трафик, и это честно', () {
      // Здесь уже нечему разбирать имена сайтов: sing-box мёртв, адаптер
      // снят, WFP держит всё, кроме своих бинарей и адресов серверов.
      final t = VpnEngineBase.killSwitchHoldText(
          tunnelStillUp: false, mode: CaptureMode.tun);
      expect(t, contains('весь'));
    });
  });

  group('проводка: строка в журнале берётся из killSwitchHoldText', () {
    late Directory tmp;
    late String logPath;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('sg_hold_text_');
      logPath = '${tmp.path}${Platform.pathSeparator}app.log';
      await AppLog.useFileForTest(logPath);
    });

    tearDown(() async {
      await AppLog.resetFileForTest();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('⚠️ при живом TUN журнал больше не пишет «ТРАФИК ЗАБЛОКИРОВАН»',
        () async {
      final e = _TunAliveEngine();
      await e.connectWith(
          '{}',
          ConnectionOptions(
              settings: AppSettings.defaults.copyWith(
                  killSwitch: true,
                  seamlessKeepTun: false,
                  captureMode: CaptureMode.tun)),
          [_server('a')]);

      expect(await e.scheduleRetry('канал не пропускает трафик'), isTrue);
      await AppLog.resetFileForTest();
      final log = File(logPath).readAsStringSync();

      expect(log, contains('Kill switch'));
      expect(log, contains('основного туннеля'),
          reason: 'строка обязана называть ОБЪЁМ удержания');
      expect(log, isNot(contains('ТРАФИК ЗАБЛОКИРОВАН')),
          reason: 'капслок «весь трафик» при живом TUN — то самое враньё');
    });
  });
}

VpnServer _server(String name) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: '$name.example.com',
      port: 443,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://x@$name.example.com:443#$name',
    );

/// Движок, у которого TUN пережил смерть прокси-ядра — ровно то, что было в
/// VM: `sing-box` жив, умер только `xray`.
class _TunAliveEngine extends VpnEngineBase {
  @override
  bool get liveCaptureKept => true;

  @override
  Future<void> startSession() async {
    final gen = newGeneration();
    if (isStale(gen)) return;
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  Future<void> platformCleanup() async {}
}
