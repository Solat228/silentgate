import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/probe_factory.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/ui/widgets/ping_chip.dart';

/// Плашка пинга больше не выдаёт «сервер рабочий» авансом.
///
/// Жалоба владельца, из-за которой всё это писалось: «сервер отъебнул, через VPN
/// не работало НИЧЕГО, автонастройка показывала все тесты красными, а пинг на
/// главной — ЗЕЛЁНЫЙ». Корень: `probe_controller` ставил `working` по признаку
/// «БУДЕТ ли фаза 2», а не «ПРОШЛА ли она», и всё время фазы 2 каждый
/// TCP-ответивший сервер горел зелёным.
///
/// Ни один тест здесь не поднимает VPN: TCP-цели — собственные слушатели на
/// 127.0.0.1, харнесс подменён фейком, наружу не ходим.
void main() {
  late Directory tmp;

  setUp(() {
    // Пинг сохраняет результаты на диск — уводим корень данных в темп, чтобы
    // тест не трогал боевой %APPDATA%\SilentGate.
    tmp = Directory.systemTemp.createTempSync('sg_ping_verify_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Модель ────────────────────────────────────────────────────────────────

  test('verification переживает сохранение (все четыре состояния)', () {
    for (final v in PingVerification.values) {
      final r = PingResult(
        outcome: PingOutcome.ok,
        latencyMs: 42,
        verification: v,
        latencyMethod: PingMethod.tcp,
        measuredAt: DateTime(2026, 8, 12, 10, 30),
      );
      final back = PingResult.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back.verification, v, reason: 'состояние проверки не должно теряться');
      expect(back.latencyMs, 42);
      expect(back.measuredAt, DateTime(2026, 8, 12, 10, 30));
      expect(back.working, v == PingVerification.passed,
          reason: 'working — производный от verification, а не своё поле');
    }
  });

  test('старая запись без verification читается по working', () {
    // Класс багов, на котором проект уже горел: поле пишется, но не читается, и
    // всё сохранённое молча обнуляется при первом же запуске новой версии.
    final passed = PingResult.fromJson({
      'outcome': 'ok',
      'latencyMs': 55,
      'latencyMethod': 'tcp',
      'working': true,
    });
    expect(passed.verification, PingVerification.passed);
    expect(passed.isWorking, isTrue);

    final failed = PingResult.fromJson({
      'outcome': 'ok',
      'latencyMs': 55,
      'working': false,
    });
    expect(failed.verification, PingVerification.failed);
    expect(failed.isWorking, isFalse);

    // Совсем старая запись (поля working в файле ещё не было): у него умолчание
    // было `true`, иначе всё сохранённое стало бы «не проверено».
    final ancient = PingResult.fromJson({'outcome': 'ok', 'latencyMs': 55});
    expect(ancient.verification, PingVerification.passed);

    // Новое поле сильнее старого: при расхождении верим verification.
    final conflict = PingResult.fromJson({
      'outcome': 'ok',
      'verification': 'failed',
      'working': true,
    });
    expect(conflict.verification, PingVerification.failed);
    expect(conflict.working, isFalse);
  });

  test('достижимость и проверка — разные утверждения', () {
    const pending = PingResult(
        outcome: PingOutcome.ok,
        latencyMs: 30,
        verification: PingVerification.pending);
    expect(pending.isOk, isTrue);
    expect(pending.isWorking, isFalse, reason: 'вердикта ещё нет');
    expect(pending.isReachableUnverified, isFalse,
        reason: 'проверка идёт — это не «её не было»');

    const notRun = PingResult(outcome: PingOutcome.ok, latencyMs: 30);
    expect(notRun.isWorking, isFalse);
    expect(notRun.isReachableUnverified, isTrue);
  });

  // ── Прогон пинга ──────────────────────────────────────────────────────────

  test(
      'фаза 1 не объявляет сервер рабочим: до пробы — pending, после провала '
      'харнесса — notRun', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _server('live', listener.port);
    final gate = Completer<void>();
    final ctrl = ProbeController(harnessFactory: () => _FakeHarness(gate.future));

    final run = ctrl.pingAll([server], const AppSettings(pingTwoPhase: true));
    // Фаза 1 закончилась: TCP ответил.
    await _until(() => ctrl.resultFor(server).outcome == PingOutcome.ok);

    final mid = ctrl.resultFor(server);
    expect(mid.verification, PingVerification.pending,
        reason: 'проверка ещё идёт');
    expect(mid.working, isFalse,
        reason: 'ЗДЕСЬ БЫЛ БАГ: сервер объявлялся рабочим авансом');
    expect(mid.isWorking, isFalse);
    expect(mid.latencyMs, isNotNull, reason: 'цифра TCP уже есть');

    gate.complete();
    await run;

    final end = ctrl.resultFor(server);
    expect(end.outcome, PingOutcome.ok);
    expect(end.verification, PingVerification.notRun,
        reason: 'харнесс порта не дал — проверки не было, а не «не прошла»');
    expect(end.latencyMs, isNotNull, reason: 'измеренное число не теряем');
    await listener.close();
  }, skip: proxyProbeSupported ? null : 'фаза 2 есть только там, где есть харнесс');

  test('отмена не превращает непроверенное в failed', () async {
    // Сервер с полным конфигом идёт мимо TCP сразу в фазу 2 — отмена застаёт
    // его в состоянии «меряется», и раньше он сохранялся как мёртвый (n/a).
    final server = _server('full', 20101, rawJsonOverride: '{"outbounds":[]}');
    final ctrl = ProbeController(
        harnessFactory: () => _FakeHarness(Future<void>.value()));

    final run = ctrl.pingAll([server], const AppSettings());
    ctrl.cancel();
    await run;

    final r = ctrl.resultFor(server);
    expect(r.outcome, isNot(PingOutcome.failed),
        reason: 'ЗДЕСЬ БЫЛ БАГ: отменённый прогон красил живые серверы в n/a');
    expect(r.outcome, PingOutcome.untested);
    expect(r.verification, PingVerification.notRun);

    // И на диск выдуманный провал тоже не попадает.
    final saved = File('${tmp.path}${Platform.pathSeparator}ping_results.json');
    if (saved.existsSync()) {
      expect(saved.readAsStringSync().contains(server.key), isFalse,
          reason: 'непроверенное не сохраняется');
    }
  });

  test('отмена посреди проверки не сохраняет авансовый зелёный', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _server('live', listener.port);
    final gate = Completer<void>();
    final ctrl = ProbeController(harnessFactory: () => _FakeHarness(gate.future));

    final run = ctrl.pingAll([server], const AppSettings(pingTwoPhase: true));
    await _until(() => ctrl.resultFor(server).outcome == PingOutcome.ok);
    ctrl.cancel();
    gate.complete();
    await run;

    final r = ctrl.resultFor(server);
    expect(r.verification, PingVerification.notRun,
        reason: 'проверка не завершилась — «проверяю» навсегда тоже нельзя');
    expect(r.working, isFalse, reason: 'на диск не должен уехать зелёный аванс');

    final saved = File('${tmp.path}${Platform.pathSeparator}ping_results.json');
    expect(saved.existsSync(), isTrue);
    final map = jsonDecode(saved.readAsStringSync()) as Map<String, dynamic>;
    expect((map[server.key] as Map)['working'], isFalse);
    expect((map[server.key] as Map)['verification'], 'notRun');
    await listener.close();
  }, skip: proxyProbeSupported ? null : 'фаза 2 есть только там, где есть харнесс');

  test('без двухфазной проверки итог считается по достижимости', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final alive = _server('live', listener.port);
    final deadPort = await _freePort();
    final dead = _server('dead', deadPort);

    final ctrl = ProbeController(
        harnessFactory: () => _FakeHarness(Future<void>.value()));
    await ctrl.pingAll([alive, dead],
        const AppSettings(pingTwoPhase: false, pingTimeoutMs: 1500));

    // ЗДЕСЬ БЫЛ БАГ: `working` ставился как «будет ли фаза 2», а её при
    // выключенной галочке нет — итог ЛЮБОГО прогона был «рабочих 0 из N».
    expect(ctrl.lastSummary, contains('1 из 2'));
    expect(ctrl.lastSummary, isNot(contains('0 из 2')));
    expect(ctrl.lastSummary, contains('доступных'),
        reason: 'проверки не было — «рабочих» обещать нельзя');

    expect(ctrl.resultFor(alive).verification, PingVerification.notRun);
    expect(ctrl.resultFor(alive).isReachableUnverified, isTrue);
    expect(ctrl.resultFor(dead).outcome, PingOutcome.failed);
    await listener.close();
  });

  // ── Плашка ────────────────────────────────────────────────────────────────

  testWidgets('зелёный — только по пройденной проверке', (tester) async {
    // ⚠️ Ровно то, что видел владелец: результат без пройденной проверки.
    // Старый код красил его в зелёный (умолчание working было `true`).
    await _pumpChip(tester,
        const PingResult(outcome: PingOutcome.ok, latencyMs: 50));
    expect(_pillColor(tester, '50 мс'), isNot(Colors.green));
    expect(_pillColor(tester, '50 мс'), Colors.grey);
    expect(_tooltip(tester), contains('не проводилась'));

    await _pumpChip(
        tester,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 50,
            verification: PingVerification.passed));
    expect(_pillColor(tester, '50 мс'), Colors.green);
    expect(_tooltip(tester), contains('прошёл проверку'));
  });

  testWidgets('пока проверка идёт — нейтральный цвет и своя подсказка',
      (tester) async {
    await _pumpChip(
        tester,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 120,
            verification: PingVerification.pending));
    expect(_pillColor(tester, '120 мс'), Colors.grey);
    expect(_tooltip(tester), contains('ещё идёт'));
  });

  testWidgets('провал проверки и мёртвый сервер различимы', (tester) async {
    await _pumpChip(
        tester,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 80,
            verification: PingVerification.failed));
    expect(_pillColor(tester, '80 мс'), Colors.blueGrey);
    expect(_tooltip(tester), contains('не прошла'));

    await _pumpChip(tester, const PingResult(outcome: PingOutcome.failed));
    expect(_tooltip(tester), contains('недоступен'));
  });

  testWidgets('в подсказке видно время замера', (tester) async {
    // Зелёная плашка переживает перезапуск и внешне не отличается от свежей —
    // гасить старые результаты владелец запретил, поэтому показываем время.
    final old = DateTime.now().subtract(const Duration(days: 3));
    await _pumpChip(
        tester,
        PingResult(
          outcome: PingOutcome.ok,
          latencyMs: 50,
          verification: PingVerification.passed,
          measuredAt: old,
        ));
    expect(_tooltip(tester), contains('Замер:'));

    await _pumpChip(tester,
        const PingResult(outcome: PingOutcome.ok, latencyMs: 50));
    expect(_tooltip(tester), isNot(contains('Замер:')),
        reason: 'без времени замера лишней строки быть не должно');
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

VpnServer _server(String name, int port, {String? rawJsonOverride}) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: '127.0.0.1',
      port: port,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink:
          'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:$port#$name',
      rawJsonOverride: rawJsonOverride,
    );

/// Свободный порт: занимаем и сразу отпускаем — по нему TCP-проба честно
/// получит отказ, никуда не выходя из петли.
Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

Future<void> _until(bool Function() cond,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('условие не наступило за ${timeout.inSeconds} с');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Харнесс, который поднимается только после [gate] и порта не даёт (как при
/// упавшем ядре кандидата) — сети не касается вовсе.
class _FakeHarness implements ProbeHarness {
  _FakeHarness(this.gate);
  final Future<void> gate;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    await gate;
    return _FakeHandle();
  }

  @override
  bool get supportsProxyRequests => true;
}

class _FakeHandle implements HarnessHandle {
  @override
  String get proxyUser => '';

  @override
  String get proxyPassword => '';

  @override
  int proxyPortFor(int index) => -1;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}

Future<void> _pumpChip(WidgetTester tester, PingResult result) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: PingChip(result: result))),
  ));
  await tester.pump();
}

Color? _pillColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

String _tooltip(WidgetTester tester) =>
    tester.widget<Tooltip>(find.byType(Tooltip)).message ?? '';
