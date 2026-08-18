import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/widgets/ping_gate.dart';

/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА, РАДИ КОТОРОЙ ЭТОТ ФАЙЛ И НАПИСАН: включил все 14
/// сервис-чипов на Windows и получил «всё сломалось и НЕ ПИНГУЕТСЯ С САМОГО
/// НАЧАЛА после включения VPN».
///
/// Складывалось это из трёх независимо разумных решений:
///  1. автопрогон уходил `Future.wait`'ом по ВСЕМУ списку — четырнадцать проб в
///     ОДИН порт живого ядра в одну миллисекунду (а на Windows в режиме по
///     умолчанию туда же смотрит системный прокси всей машины);
///  2. отметка «этот подъём отработан» ставилась ДО проб, поэтому одна
///     неудачная пачка закрывала автопроверку навсегда — до переподключения;
///  3. при неудачном ожидании готовности канала пачка всё равно запускалась, и
///     человек видел 14 красных кружков, то есть «через VPN не работает ничего».
///
/// Ни один из 1500 тестов этого увидеть не мог: каждая часть по отдельности
/// выглядит правильной, а считать ПИК ОДНОВРЕМЕННЫХ проб никто не пробовал.
void main() {
  final l = AppLocalizationsRu();
  late Directory tmp;

  /// Сколько проб идёт прямо сейчас и сколько их было максимум одновременно.
  late int active;
  late int peak;
  late int calls;
  late int readinessCalls;
  late bool channelUsable;

  /// Что подменённая проба возвращает (нужно там, где важен ПРОВАЛ замера).
  late ServiceCheckOutcome outcome;

  setUp(() {
    // Пинг пишет результаты на диск — свой каталог обязателен, боевой
    // %APPDATA% тесты не трогают.
    tmp = Directory.systemTemp.createTempSync('sg_svc_load_');
    AppPaths.overrideRoot(tmp);

    active = 0;
    peak = 0;
    calls = 0;
    readinessCalls = 0;
    channelUsable = true;
    outcome = const ServiceCheckOutcome(ServiceCheckState.ok, latencyMs: 12);

    ServiceCheckActivity.resetForTests();
    ServiceCheckController.readinessDelay = Duration.zero;
    ServiceCheckController.readinessAttempts = 2;
    // Паузу между автоповторами в тесте ждать нечего: проверяем правило, а не
    // часы. Ограничение числа повторов задаётся отдельно, где оно проверяется.
    ServiceCheckController.autoRetryDelay = Duration.zero;
    ServiceCheckController.readinessProbe = (port) async {
      readinessCalls++;
      return channelUsable;
    };
    ServiceCheckController.prober = (port, s) async {
      calls++;
      active++;
      if (active > peak) peak = active;
      // Настоящая проба идёт до ~16 с; здесь достаточно любой задержки, лишь бы
      // пробы могли наложиться друг на друга — иначе пик всегда был бы единицей
      // и тест ничего бы не стерёг.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      active--;
      return outcome;
    };
  });

  tearDown(() async {
    // Дать досчитать фоновым цепочкам: `check` уходит в запись без await, и
    // снятая раньше времени подмена каталога отправила бы её резолвить путь
    // заново.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ServiceCheckController.readinessAttempts = 6;
    ServiceCheckController.readinessDelay = const Duration(seconds: 2);
    ServiceCheckController.readinessProbe =
        ServiceCheckController.defaultReadinessProbe;
    ServiceCheckController.prober = ServiceChecker.check;
    ServiceCheckController.autoRetryDelay = const Duration(seconds: 20);
    ServiceCheckController.autoRetryLimit = 2;
    ServiceCheckController.baselineCatchUpCooldown = const Duration(seconds: 60);
    ServiceCheckActivity.resetForTests();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── 1. Пачка не уходит разом ───────────────────────────────────────────────
  group('Пробы сервисов идут пулом, а не всей пачкой', () {
    test('⚠️ ГЛАВНОЕ: 14 сервисов не уходят в один порт одновременно', () async {
      // ⚠️ Падает на старом поведении: там `Future.wait` по всему списку давал
      // пик 14 — ровно столько соединений в порт живого ядра в одну
      // миллисекунду. Именно на этом «всё сломалось» у владельца.
      final c = ServiceCheckController();
      c.setTunnelUp(true);
      await c.autoCheckAll(10809, ProbeService.values);

      expect(calls, ProbeService.values.length,
          reason: 'проверить обязаны всех — ограничение про темп, не про состав');
      expect(peak, lessThanOrEqualTo(ServiceCheckController.concurrency),
          reason: 'потолок одновременных проб в ОДИН живой порт');
      expect(peak, greaterThan(1),
          reason: 'последовательный прогон четырнадцати проб по ~16 с '
              'растянулся бы на минуты — пул, а не очередь');
      c.dispose();
    });

    test('замер «до» тоже пулом — пачка приходится на момент отключения VPN',
        () async {
      final c = ServiceCheckController();
      await c.checkBaseline(ProbeService.values);
      expect(calls, ProbeService.values.length);
      expect(peak, lessThanOrEqualTo(ServiceCheckController.concurrency));
      c.dispose();
    });
  });

  // ── 2. Эпоха тратится по факту прогона ─────────────────────────────────────
  group('Неудача не сжигает единственный автопрогон подъёма', () {
    test('⚠️ ГЛАВНОЕ: канал не готов — проб нет, но повтор возможен', () async {
      // ⚠️ Падает на старом поведении дважды: (1) при неудачном ожидании пробы
      // всё равно уходили — 14 красных кружков вместо честного «канал не
      // готов»; (2) отметка стояла ДО проб, поэтому второй заход не делал уже
      // ничего — «не пингуется с самого начала и дальше висит».
      final c = ServiceCheckController();
      channelUsable = false;
      c.setTunnelUp(true);
      await c.autoCheckAll(10809, ProbeService.values);

      expect(calls, 0,
          reason: 'в канал, который не ответил ни разу, пачку не гоним');
      expect(c.channelNotReady, isTrue,
          reason: 'у отказа обязано быть своё состояние, а не 14 красных '
              'кружков — их человек читает как «VPN не работает ни с чем»');
      for (final s in ProbeService.values) {
        expect(c.resultFor(s).state, ServiceCheckState.idle);
      }

      // Ядро встало (в бою — через несколько секунд).
      channelUsable = true;
      await c.autoCheckAll(10809, ProbeService.values);
      expect(calls, ProbeService.values.length,
          reason: 'ЗДЕСЬ ЭПОХА СГОРАЛА АВАНСОМ: до переподключения проверка '
              'больше не запускалась НИКОГДА');
      expect(c.channelNotReady, isFalse);
      c.dispose();
    });

    test('состоявшийся прогон эпоху тратит — перерисовки его не повторяют',
        () async {
      final c = ServiceCheckController();
      c.setTunnelUp(true);
      await c.autoCheckAll(10809, const [ProbeService.youtube]);
      expect(calls, 1);
      // Главный экран зовёт это с каждой перерисовки — раз в секунду.
      for (var i = 0; i < 5; i++) {
        await c.autoCheckAll(10809, const [ProbeService.youtube]);
      }
      expect(calls, 1, reason: 'один подъём — один автопрогон');
      c.dispose();
    });

    test('автоповторы ограничены, а кнопка повтора работает всегда', () async {
      // Без ограничения лечение было бы хуже болезни: `autoCheckAll` зовут с
      // каждой перерисовки, и в мёртвый канал полетел бы бесконечный поток проб.
      ServiceCheckController.autoRetryLimit = 1;
      final c = ServiceCheckController();
      channelUsable = false;
      c.setTunnelUp(true);

      await c.autoCheckAll(10809, const [ProbeService.youtube]); // неудача 1
      await c.autoCheckAll(10809, const [ProbeService.youtube]); // неудача 2
      final spent = readinessCalls;
      expect(spent, greaterThan(0));
      await c.autoCheckAll(10809, const [ProbeService.youtube]); // отброшена
      expect(readinessCalls, spent,
          reason: 'потолок автоповторов исчерпан — дальше только по просьбе '
              'человека');

      // Человек видит плашку «канал не готов» и жмёт «повторить».
      channelUsable = true;
      await c.retryAutoCheck(10809, const [ProbeService.youtube]);
      expect(calls, 1, reason: 'ручной повтор обязан пробиваться через потолок');
      c.dispose();
    });

    test('новый подъём стирает историю неудач прошлого', () async {
      ServiceCheckController.autoRetryLimit = 0;
      final c = ServiceCheckController();
      channelUsable = false;
      c.setTunnelUp(true);
      await c.autoCheckAll(10809, const [ProbeService.youtube]);
      expect(c.channelNotReady, isTrue);

      // Переподключились: у нового канала своя судьба.
      c.setTunnelUp(false);
      c.setTunnelUp(true);
      expect(c.channelNotReady, isFalse);
      channelUsable = true;
      await c.autoCheckAll(10809, const [ProbeService.youtube]);
      expect(calls, 1);
      c.dispose();
    });
  });

  // ── 3. Гейт пинга ──────────────────────────────────────────────────────────
  group('Пинг и проверка сервисов не лезут в один порт', () {
    const settings = AppSettings();
    // hysteria2 — нарочно: у него нет TCP-фазы (QUIC), поэтому прогон уходит
    // сразу в харнесс и ни одного сокета наружу тест не открывает.
    const hy2 = VpnServer(
      protocol: 'hysteria2',
      remark: 'Альфа',
      address: 'a.example',
      port: 443,
      id: 'pass',
      rawLink: 'hysteria2://pass@a.example:443#Альфа',
    );

    test('признак у голых значений: причина названа своя', () {
      final g = PingGate.from(
          pinging: false,
          measuringSpeed: false,
          hasTargets: true,
          servicesChecking: true);
      expect(g.allowed, isFalse);
      expect(g.blocker, PingBlocker.servicesChecking);
      expect(g.reason(l), isNotNull);
      expect(g.reason(l), isNotEmpty);
    });

    test('⚠️ ГЛАВНОЕ: гейт закрыт И исполнитель отказывает — одинаково',
        () async {
      // ⚠️ Падает на старом поведении: причины не существовало вовсе, кнопка
      // была живой, а прогон начинался поверх пачки проб сервисов.
      final hold = Completer<ServiceCheckOutcome>();
      ServiceCheckController.prober = (port, s) => hold.future;
      final c = ServiceCheckController();
      final harness = _GateHarness();
      final probe = ProbeController(harnessFactory: () => harness);

      expect(PingGate.of(probe).allowed, isTrue, reason: 'до прогона — можно');

      c.setTunnelUp(true);
      final run = c.autoCheckAll(10809, const [
        ProbeService.youtube,
        ProbeService.google,
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(probe.serviceChecksRunning, isTrue);
      expect(PingGate.of(probe).blocker, PingBlocker.servicesChecking,
          reason: 'гейт обязан назвать ровно ту причину, по которой откажет '
              'исполнитель');

      // Исполнитель отказывает молча — вот это и проверяем.
      final refused = probe.pingAll([hy2], settings);
      expect(probe.running, isFalse);
      expect(probe.resultFor(hy2).outcome, PingOutcome.untested,
          reason: 'начавшийся прогон сразу пометил бы сервер «проверяю»');
      expect(harness.starts, 0, reason: 'второе ядро поверх пачки не поднимаем');
      await refused;

      hold.complete(const ServiceCheckOutcome(ServiceCheckState.ok));
      await run;

      // Пачка кончилась — порт свободен, и пинг обязан пойти.
      expect(probe.serviceChecksRunning, isFalse);
      expect(PingGate.of(probe).allowed, isTrue);
      final ok = probe.pingAll([hy2], settings);
      expect(probe.running, isTrue,
          reason: 'иначе гейт закрывал бы пинг навсегда');
      harness.release();
      await ok;
      c.dispose();
    });

    test('упавшая пачка отметку занятости не оставляет', () async {
      // Иначе исключение внутри прогона закрыло бы пинг до перезапуска.
      ServiceCheckController.prober = (port, s) async => throw StateError('бум');
      final c = ServiceCheckController();
      final probe = ProbeController(harnessFactory: _GateHarness.new);
      c.setTunnelUp(true);
      await expectLater(
          c.autoCheckAll(10809, const [ProbeService.youtube]), throwsStateError);
      expect(probe.serviceChecksRunning, isFalse);
      expect(PingGate.of(probe).allowed, isTrue);
      c.dispose();
    });
  });

  // ── 4. Догон замера «до» на мигающем канале ────────────────────────────────
  group('Мигание канала не повторяет пачку прямых проб', () {
    test('⚠️ ГЛАВНОЕ: окно переподключения даёт один догон, а не по одному '
        'на каждое окно', () async {
      // ⚠️ Падает на старом поведении: `setTunnelUp(false)` — это ЛЮБОЙ переход
      // в «не подключено» (сторож канала, kill switch, смена сети), и на каждый
      // уходила новая пачка прямых проб. Замер при этом проваливается (трафика
      // нет), провал не кэшируется — значит и просьба остаётся, и пачка
      // повторяется бесконечно.
      ServiceCheckController.baselineCatchUpCooldown =
          const Duration(seconds: 30);
      outcome = const ServiceCheckOutcome(ServiceCheckState.fail);
      final c = ServiceCheckController();

      c.setTunnelUp(true);
      await c.ensureBaseline(const [ProbeService.steam]);
      expect(calls, 0, reason: 'через туннель замер «до» снимать нельзя');

      // Первое отключение — догон идёт сразу: обычное «нажал Отключить» не
      // должно ждать конца окна.
      c.setTunnelUp(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);

      // Дальше канал мигает: вверх-вниз, вверх-вниз…
      for (var i = 0; i < 5; i++) {
        c.setTunnelUp(true);
        c.setTunnelUp(false);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(calls, 1,
          reason: 'шторм прямых проб на КАЖДОМ окне переподключения');
      expect(c.baselineWanted, contains(ProbeService.steam),
          reason: 'провал не считается измеренной величиной — просьба жива');
      c.dispose();
    });
  });
}

/// Харнесс, который ЗАВИСАЕТ на старте, пока его не отпустят: прогон живёт
/// ровно столько, сколько нужно тесту, и ни один сокет наружу не открывается.
class _GateHarness implements ProbeHarness {
  final _gate = Completer<void>();
  int starts = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    starts++;
    await _gate.future;
    return _GateHandle();
  }

  @override
  bool get supportsProxyRequests => true;
}

/// Порт не отдаём вовсе (-1 = «второе ядро не поднялось»): для потребителя это
/// штатный случай, а тест остаётся без сетевых обращений.
class _GateHandle implements HarnessHandle {
  @override
  String get proxyUser => harnessProxyUser;

  @override
  String get proxyPassword => 'secret';

  @override
  int proxyPortFor(int index) => -1;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}
