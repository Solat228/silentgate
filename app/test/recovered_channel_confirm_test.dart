import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// «СОЕДИНЕНИЕ ВОССТАНОВЛЕНО» — ТОЛЬКО ПОСЛЕ ЖИВОЙ ПРОБЫ.
///
/// ⚠️ Найдено живьём в VM 10.10.2026. Сервер умер, сторож канала признал это и
/// переподключился. Повтор поднял ядро (процесс стартует и при недоступном
/// сервере), движок позвал `markConnected()` — и человек получил «Соединение
/// восстановлено», значок «Подключено», а kill switch снял признак блокировки
/// и красный трей. Через ~2,5 мин сторож снова видел мёртвый канал; после трёх
/// кругов предохранитель умолкал, оставляя «Подключено» на мёртвом канале.
///
/// Теперь платформа спрашивает `confirmRecoveredChannel` перед
/// `markConnected()`. Тесты ниже держат три решения:
///  * нажатие кнопки не проверяется (это сделает сторож, задерживать незачем);
///  * канал, где проба ни разу не проходила, не проверяется (мишени могут
///    быть недоступны из страны выхода — иначе ловушка без интернета);
///  * доказанный канал после восстановления без живой пробы НЕ объявляется
///    восстановленным: попытка уходит в обычный автоповтор.
void main() {
  setUp(() => VpnEngineBase.confirmPause = Duration.zero);
  tearDown(() => VpnEngineBase.confirmPause = const Duration(seconds: 2));

  test('нажатие «Подключить» не ждёт пробы', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(), const []);
    e.nextProbe = () => _Scripted(const [false, false]);

    expect(await e.confirm(), isTrue);
    expect(e.probesMade, 0,
        reason: 'свежее подключение проверяет сторож канала, а не этот путь');
  });

  test('сторож отмечает канал доказанным на удачной пробе, '
      'кнопка «Подключить» это забывает', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(), const []);
    expect(e.channelProven, isFalse);

    await e.prove();
    expect(e.channelProven, isTrue,
        reason: 'без onOk признак не появится никогда — и проверка после '
            'восстановления не включится ни разу');

    await e.disconnect();
    await e.connectWith('{}', _opts(), const []);
    expect(e.channelProven, isFalse,
        reason: 'новое подключение может идти через другой сервер — прошлый '
            'успех о нём ничего не говорит');
  });

  test('канал не доказан — восстановление без пробы', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(), const []);
    await e.dropAndRetry();
    e.nextProbe = () => _Scripted(const [false, false]);

    expect(await e.confirm(), isTrue,
        reason: 'проба здесь могла не проходить НИКОГДА (мишени недоступны из '
            'страны выхода) — иначе вечная ловушка без интернета');
    expect(e.probesMade, 0);
  });

  test('⚠️ ГЛАВНОЕ: доказанный канал молчит после восстановления — '
      '«восстановлено» не объявляется', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(), const []);
    await e.prove();
    await e.dropAndRetry();
    e.retries.clear();
    e.nextProbe = () => _Scripted(const [false, false]);

    expect(await e.confirm(), isFalse,
        reason: 'ЗДЕСЬ БЫЛ БАГ: ядро поднялось — и этого хватало для '
            '«Соединение восстановлено» на мёртвом канале');
    e.cancelRetryTimer();
    expect(e.retries, ['канал не пропускает трафик'],
        reason: 'попытка обязана уйти в обычный автоповтор');
    expect(e.teardowns.last, isTrue,
        reason: 'kill switch: между попытками захват удерживается');
    expect(e.lastProbe!.calls, 2, reason: 'две пробы, а не одна');
  });

  test('без kill switch и с исчерпанными попытками — честная ошибка', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(killSwitch: false), const []);
    await e.prove();
    for (var i = 0; i < VpnEngineBase.maxAttempts; i++) {
      await e.scheduleRetry('обрыв');
      e.cancelRetryTimer();
    }
    e.nextProbe = () => _Scripted(const [false, false]);

    expect(await e.confirm(), isFalse);
    expect(e.status.state, VpnConnectionState.error,
        reason: 'иначе «Подключение…» висит вечно без объяснения');
  });

  test('вторая проба прошла — канал восстановлен', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(), const []);
    await e.prove();
    await e.dropAndRetry();
    e.retries.clear();
    e.nextProbe = () => _Scripted(const [false, true]);

    expect(await e.confirm(), isTrue,
        reason: 'ядро только что поднялось: первая проба может не успеть на '
            'рукопожатие с сервером');
    expect(e.retries, isEmpty);
  });

  test('сессия устарела, пока шла проба — чужое не трогаем', () async {
    final e = _Engine();
    await e.connectWith('{}', _opts(), const []);
    await e.prove();
    await e.dropAndRetry();
    e.retries.clear();
    final teardownsBefore = e.teardowns.length;
    var stale = false;
    e.nextProbe = () => _Scripted(const [false, false], onCall: () {
          stale = true; // человек переподключился, пока висела проба
        });

    expect(await e.confirm(aborted: () => stale), isFalse);
    expect(e.retries, isEmpty,
        reason: 'устаревшая попытка запланировала повтор поверх новой сессии');
    expect(e.teardowns.length, teardownsBefore,
        reason: 'устаревшая попытка погасила ядро новой сессии');
  });
}

ConnectionOptions _opts({bool killSwitch = true}) => ConnectionOptions(
      settings: AppSettings(autoReconnect: true, killSwitch: killSwitch),
    );

class _Scripted extends TunnelHealth {
  _Scripted(this.results, {this.onCall})
      : super(proxyPort: 1, interval: const Duration(milliseconds: 5));

  final List<bool> results;
  final void Function()? onCall;
  int calls = 0;

  @override
  Future<bool> probeOnce() async {
    onCall?.call();
    final r = results[calls.clamp(0, results.length - 1)];
    calls++;
    return r;
  }
}

class _Engine extends VpnEngineBase {
  // Прямой интернет есть: здесь проверяется прежнее поведение (обрыв →
  // переподключение), а не ожидание сети, и в сеть тест ходить не должен.
  @override
  Future<bool?> directInternetAvailable() async => true;

  _Scripted Function()? nextProbe;
  _Scripted? lastProbe;
  int probesMade = 0;
  final List<String> retries = [];
  final List<bool> teardowns = [];

  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) {
    probesMade++;
    final p = (nextProbe ?? () => _Scripted(const [true]))();
    lastProbe = p;
    return p;
  }

  /// Сторож канала прошёл хотя бы одну пробу на этой сессии.
  Future<void> prove() async {
    setStatus(VpnConnectionState.connected);
    nextProbe = () => _Scripted(const [true]);
    startHealthWatch(() => false);
    for (var i = 0; i < 50 && !channelProven; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    stopHealthWatch();
    probesMade = 0;
  }

  /// Канал оборвался, автоповтор запланирован — дальше идёт восстановление.
  Future<void> dropAndRetry() async {
    await scheduleRetry('обрыв');
    cancelRetryTimer();
  }

  Future<bool> confirm({bool Function()? aborted}) =>
      confirmRecoveredChannel(aborted ?? () => false);

  @override
  Future<bool> scheduleRetry(String reason) {
    retries.add(reason);
    return super.scheduleRetry(reason);
  }

  @override
  Future<void> startSession() async {}

  @override
  Future<void> platformCleanup() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    teardowns.add(keepCapture);
  }
}
