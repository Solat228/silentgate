import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// Стражи против двух находок ревью 01.08.2026. Обе одного рода: состояние
/// выглядит правильным, а защита при этом не работает.
void main() {
  group('Подхваченный туннель получает сессию', () {
    // Было: `adoptRunningTunnel` ставит «Подключено», но сессии НЕ создаёт —
    // конфиг остался в умершем изоляте. А `scheduleRetry` выходит первой же
    // строкой `session == null`, ещё ДО проверки autoReconnect. Значит после
    // возврата в приложение (штатный сценарий Android) не срабатывали ни
    // автопереподключение, ни kill switch — при включённых галочках в UI.
    test('без сессии повтор не планируется — это и был дефект', () async {
      final e = _FakeEngine()..pretendAdopted();
      expect(await e.scheduleRetry('обрыв'), isFalse,
          reason: 'воспроизводим прежнее поведение: сессии нет — защиты нет');
    });

    test('после armAdoptedSession повтор планируется', () async {
      final e = _FakeEngine()..pretendAdopted();
      await e.armAdoptedSession(
        [_server('a')],
        const ConnectionOptions(
            settings: AppSettings(autoReconnect: true, killSwitch: true)),
      );
      expect(await e.scheduleRetry('обрыв'), isTrue,
          reason: 'сессия восстановлена — автозащита снова в силе');
    });

    test('выключенное автопереподключение уважается и после восстановления',
        () async {
      final e = _FakeEngine()..pretendAdopted();
      await e.armAdoptedSession(
        [_server('a')],
        const ConnectionOptions(settings: AppSettings(autoReconnect: false)),
      );
      expect(await e.scheduleRetry('обрыв'), isFalse,
          reason: 'восстановление сессии не должно включать чужую настройку');
    });

    test('живую сессию не подменяем реконструкцией', () async {
      final e = _FakeEngine();
      await e.connectWith('{"живой":1}', const ConnectionOptions(),
          [_server('live')]);
      await e.armAdoptedSession([_server('other')], const ConnectionOptions());
      expect(e.sessionConfig, '{"живой":1}');
    });

    test('на отключённом движке восстанавливать нечего', () async {
      final e = _FakeEngine();
      await e.armAdoptedSession([_server('a')], const ConnectionOptions());
      expect(e.sessionConfig, isNull);
    });
  });

  group('Настройка «мои правила важнее панели» требует переподключения', () {
    // Было: поле запекается в конфиг (rerouteDirectThroughVpn), но в списке
    // requiresReconnect его не было — пользователь щёлкал галочку при живом
    // соединении, конфиг оставался прежним, и даже подсказки не приходило.
    test('смена значения видна как требующая переподключения', () {
      const a = AppSettings(myRulesOverridePanel: true);
      const b = AppSettings(myRulesOverridePanel: false);
      expect(a.requiresReconnect(b), isTrue);
    });

    test('одинаковые настройки переподключения не требуют', () {
      const a = AppSettings(myRulesOverridePanel: true);
      expect(a.requiresReconnect(const AppSettings(myRulesOverridePanel: true)),
          isFalse);
    });
  });

  group('Kill switch держит трафик до вмешательства', () {
    // Было: попыток ровно 8 (~112 c), дальше scheduleRetry возвращал false,
    // вызывающий шёл в cleanup(), а тот снимает захват — и трафик шёл открыто
    // под реальным IP без ограничения по времени. Обещание «не выпущу трафик
    // мимо VPN» действовало две минуты. Решение владельца: держать до
    // вмешательства человека.
    Future<_FakeEngine> armed({required bool killSwitch}) async {
      final e = _FakeEngine();
      await e.connectWith(
        '{}',
        ConnectionOptions(
            settings: AppSettings(autoReconnect: true, killSwitch: killSwitch)),
        [_server('a')],
      );
      return e;
    }

    test('с kill switch попытки не заканчиваются', () async {
      final e = await armed(killSwitch: true);
      // Заведомо больше прежнего предела в 8.
      for (var i = 0; i < VpnEngineBase.maxAttempts + 5; i++) {
        expect(await e.scheduleRetry('обрыв $i'), isTrue,
            reason: 'на попытке $i защита сдалась бы и открыла трафик');
        e.settleRetry();
      }
    });

    test('без kill switch предел прежний', () async {
      final e = await armed(killSwitch: false);
      var ok = 0;
      for (var i = 0; i < VpnEngineBase.maxAttempts + 3; i++) {
        if (!await e.scheduleRetry('обрыв $i')) break;
        ok++;
        e.settleRetry();
      }
      expect(ok, lessThanOrEqualTo(VpnEngineBase.maxAttempts),
          reason: 'вечные попытки без блокировки трафика смысла не имеют');
    });

    test('статус сообщает, что трафик заблокирован', () async {
      final e = await armed(killSwitch: true);
      await e.scheduleRetry('обрыв');
      expect(e.status.blocking, isTrue,
          reason: 'по этому признаку работают уведомление и подсказка трея');
      expect(e.status.message, contains('заблокирован'));
    });

    test('восстановление снимает признак блокировки', () async {
      final e = await armed(killSwitch: true);
      await e.scheduleRetry('обрыв');
      expect(e.status.blocking, isTrue);
      e.markConnected();
      e.setStatus(VpnConnectionState.connected);
      expect(e.status.blocking, isFalse);
    });
  });

}

VpnServer _server(String tag) => VpnServer(
      protocol: 'vless',
      remark: tag,
      address: '203.0.113.10',
      port: 443,
      id: '00000000-0000-0000-0000-000000000001',
      encryption: 'none',
      rawLink: 'vless://00000000-0000-0000-0000-000000000001@203.0.113.10:443'
          '?encryption=none&type=tcp#$tag',
    );

/// Движок без платформы: нужен только жизненный цикл сессии из базы.
class _FakeEngine extends VpnEngineBase {
  String? get sessionConfig => session?.configJson;

  /// Ровно то, что делает `AndroidEngine.adoptRunningTunnel`: статус
  /// «подключено» при отсутствующей сессии.
  void pretendAdopted() {
    markConnected();
    setStatus(VpnConnectionState.connected);
  }

  @override
  Future<void> startSession() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  Future<void> platformCleanup() async {}

  /// Отменить отложенную попытку: в тесте нас интересует РЕШЕНИЕ «повторять или
  /// сдаться», а не сам повтор — таймер иначе держал бы тест открытым.
  void settleRetry() => cancelRetryTimer();
}
