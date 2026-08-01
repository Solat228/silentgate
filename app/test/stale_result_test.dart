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
}
