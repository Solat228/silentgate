import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/net/speed_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/ping_chip.dart';

/// Скорость сервера в строке списка (план 1.4.2, задача 4).
///
/// Что здесь стережётся, дословно по решению владельца: «сначала выполняется
/// GET-пинг, и если сервер его НЕ проходит, то и скорость проверять не нужно.
/// У таких серверов вместо значений скорости показывай минусы или крестики с
/// пояснением при наведении».
///
/// Ни одна проба наружу не уходит: харнесс и сама закачка подменены фейками,
/// VPN не поднимается.
void main() {
  late Directory tmp;

  setUp(() {
    // Замеры сохраняются на диск — уводим корень данных в темп, чтобы тест не
    // трогал боевой %APPDATA%\SilentGate.
    tmp = Directory.systemTemp.createTempSync('sg_speed_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Модель ────────────────────────────────────────────────────────────────

  test('мерить скорость можно только у прошедшего проверку канала', () {
    const passed = PingResult(
        outcome: PingOutcome.ok,
        latencyMs: 40,
        verification: PingVerification.passed);
    expect(passed.speedMeasurable, isTrue);
    expect(passed.speedBlocked, isFalse);

    // «Проверка не проводилась» — это НЕ разрешение: платить 5–20 МБ подписки
    // за сервер, про который ничего не известно, нельзя.
    const notRun = PingResult(outcome: PingOutcome.ok, latencyMs: 40);
    expect(notRun.speedMeasurable, isFalse);
    expect(notRun.speedBlocked, isFalse,
        reason: 'не мерили — не значит «нельзя»; прочерка тут быть не должно');

    const failedCheck = PingResult(
        outcome: PingOutcome.ok,
        latencyMs: 40,
        verification: PingVerification.failed);
    expect(failedCheck.speedMeasurable, isFalse);
    expect(failedCheck.speedBlocked, isTrue,
        reason: 'вот здесь и нужен прочерк с пояснением');

    const dead = PingResult(outcome: PingOutcome.failed);
    expect(dead.speedMeasurable, isFalse);
    expect(dead.speedBlocked, isTrue);
  });

  test('замер скорости переживает сохранение', () {
    final s = ServerSpeed(
        mbps: 42.5,
        measuredAt: DateTime(2026, 8, 13, 12, 5),
        fromAutoConfig: true);
    final back = ServerSpeed.fromJson(s.toJson());
    expect(back, isNotNull);
    expect(back!.mbps, 42.5);
    expect(back.measuredAt, DateTime(2026, 8, 13, 12, 5));
    expect(back.fromAutoConfig, isTrue);

    // Ноль — это не замер, а мусор: «0.0 МБ/с» в строке читается как результат.
    expect(ServerSpeed.fromJson({'mbps': 0}), isNull);
    expect(ServerSpeed.fromJson(const {}), isNull);
  });

  // ── Гейт по проверке канала ───────────────────────────────────────────────

  test('сервер без пройденной проверки канала в замер не идёт', () async {
    final probe = _controller();
    final calls = _recordDownloads(probe);
    final server = _server('unverified');
    // Пинг прошёл по TCP, проверки через сервер не было.
    probe.setResult(server, const PingResult(outcome: PingOutcome.ok, latencyMs: 30));

    await probe.measureSpeedAll([server], const AppSettings());
    expect(calls, isEmpty,
        reason: 'ЗДЕСЬ ГЕЙТ: непроверенный сервер не должен тратить трафик');
    expect(probe.speedFor(server), isNull);

    // И провалившая проверку — тоже: через неё запрос не прошёл.
    final broken = _server('broken');
    probe.setResult(
        broken,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 30,
            verification: PingVerification.failed));
    await probe.measureSpeedAll([broken], const AppSettings());
    expect(calls, isEmpty);
    expect(probe.speedFor(broken), isNull);

    // Ручной пункт меню («Измерить скорость» у одного сервера) гейт не обходит.
    await probe.measureSpeedOne(broken, const AppSettings());
    expect(calls, isEmpty,
        reason: 'одиночный замер обходит только фильтр «уже измерено»');
  });

  test('сервер с пройденной проверкой меряется, и креды харнесса доезжают',
      () async {
    final probe = _controller();
    final calls = _recordDownloads(probe);
    final server = _server('good');
    probe.setResult(
        server,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 30,
            verification: PingVerification.passed));

    await probe.measureSpeedAll(
        [server], const AppSettings(speedTestSize: SpeedTestSize.light));

    expect(calls.length, 1);
    expect(calls.single.size, SpeedTestSize.light,
        reason: 'размер пробы берётся из настроек пользователя');
    expect(calls.single.port, _fakePort);
    // ⚠️ РОВНО ЭТОТ ДЕФЕКТ УЖЕ БЫЛ: инбаунды харнесса закрыты паролем, и замер
    // без кредов получает 407, а `catch` превращает его в безликое «не
    // удалось» на КАЖДОМ сервере.
    expect(calls.single.user, harnessProxyUser);
    expect(calls.single.password, _fakeSecret);

    expect(probe.speedFor(server)?.mbps, closeTo(24, 0.01));
    expect(probe.speedFor(server)?.fromAutoConfig, isFalse);
    expect(probe.speedSummary, contains('1 из 1'));
  });

  // ── Скорость из автонастройки ─────────────────────────────────────────────

  test('скорость из автонастройки видна сразу и повторно не меряется',
      () async {
    final probe = _controller();
    final calls = _recordDownloads(probe);
    final server = _server('auto');
    probe.setResult(
        server,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 30,
            verification: PingVerification.passed));

    probe.adoptSpeeds({
      server.key: const ServerSpeed(mbps: 88.0, fromAutoConfig: true),
    });
    expect(probe.speedFor(server)?.mbps, 88.0,
        reason: 'за этот замер уже заплачено трафиком подписки');

    await probe.measureSpeedAll([server], const AppSettings());
    expect(calls, isEmpty,
        reason: 'прогон по списку не перемеряет то, что уже известно');
    expect(probe.speedTargets([server]), isEmpty);

    // Ручной замер одного сервера — намеренное действие, его гейт «уже
    // измерено» не касается.
    await probe.measureSpeedOne(server, const AppSettings());
    expect(calls.length, 1);
    expect(probe.speedFor(server)?.mbps, closeTo(24, 0.01));
    expect(probe.speedFor(server)?.fromAutoConfig, isFalse);

    // И обратно затереть ручной замер списком автонастройки нельзя.
    probe.adoptSpeeds({
      server.key: const ServerSpeed(mbps: 88.0, fromAutoConfig: true),
    });
    expect(probe.speedFor(server)?.mbps, closeTo(24, 0.01));
  });

  // ── План прогона по списку ────────────────────────────────────────────────

  test('план прогона считает только тех, кого реально померим', () {
    final probe = _controller();
    final ok = _server('ok');
    final done = _server('done');
    final unverified = _server('unverified');
    const passed = PingResult(
        outcome: PingOutcome.ok,
        latencyMs: 30,
        verification: PingVerification.passed);
    probe.setResult(ok, passed);
    probe.setResult(done, passed);
    probe.setResult(unverified,
        const PingResult(outcome: PingOutcome.ok, latencyMs: 30));
    probe.adoptSpeeds({done.key: const ServerSpeed(mbps: 50)});

    final plan =
        speedRunPlan([ok, done, unverified], probe, SpeedTestSize.light);
    expect(plan.targets.map((s) => s.remark), ['ok']);
    expect(plan.alreadyMeasured, 1);
    expect(plan.bytes, SpeedTestSize.light.bytes,
        reason: 'объём в предупреждении обязан считаться по РЕАЛЬНЫМ мишеням');

    // Никого мерить нельзя — план пуст, и кнопка обязана это увидеть.
    final none = speedRunPlan([unverified], probe, SpeedTestSize.light);
    expect(none.isEmpty, isTrue);
    expect(none.bytes, 0);
  });

  // ── Подтверждение прогона ─────────────────────────────────────────────────

  testWidgets('прогон по списку спрашивает подтверждение', (tester) async {
    final probe = _controller();
    final calls = _recordDownloads(probe);
    final server = _server('good');
    probe.setResult(
        server,
        const PingResult(
            outcome: PingOutcome.ok,
            latencyMs: 30,
            verification: PingVerification.passed));

    await _pumpRunButton(tester, probe, [server]);

    // Отмена: ни одного байта подписки.
    await tester.tap(find.text('Измерить скорость всех'));
    await tester.pumpAndSettle();
    expect(find.text('Замерить скорость?'), findsOneWidget,
        reason: '101 сервер × 5–20 МБ — без вопроса запускать нельзя');
    expect(calls, isEmpty, reason: 'пока диалог открыт, ничего не качается');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'ЗДЕСЬ БЫЛ БЫ ДЕФЕКТ: отмена всё равно мерит');

    // Согласие: прогон идёт.
    await tester.tap(find.text('Измерить скорость всех'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Измерить'));
    await tester.pumpAndSettle();
    expect(calls.length, 1);
  });

  // ── Плашка скорости ───────────────────────────────────────────────────────

  // ⚠️ ЗДЕСЬ БЫЛИ ДВА ТЕСТА ПРО ПРОЧЕРК «—» на месте скорости у сервера,
  // который не прошёл проверку канала, и про `SpeedChip.visible`. Прежнее
  // решение владельца («вместо значений скорости показывай минусы с
  // пояснением») он ОТМЕНИЛ 18.08.2026: прочерков в списке оказалось
  // большинство, и из-за них плашка пинга ужималась в столбик у ВСЕХ строк,
  // хотя скорость не мерили ни у одной. Теперь плашка скорости существует
  // только по факту замера — это выражено типом (`SpeedChip.speed` больше не
  // nullable), а `visible` не нужен вовсе. Страж нового правила и вид строки
  // без замера — `test/ping_chip_layout_test.dart`.

  testWidgets('замер показан цифрой', (tester) async {
    await _pumpSpeedChip(tester, speed: const ServerSpeed(mbps: 24.4));
    expect(find.text('3.0 МБ/с'), findsOneWidget);
  });
}

// ── Вспомогательное ─────────────────────────────────────────────────────────

const _fakePort = 24081;
const _fakeSecret = 'secret42';

VpnServer _server(String name) => VpnServer(
      protocol: 'vless',
      remark: name,
      address: '127.0.0.1',
      port: 443,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink:
          'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:443#$name',
    );

ProbeController _controller() =>
    ProbeController(harnessFactory: () => _FakeHarness());

class _Download {
  _Download(this.size, this.port, this.user, this.password);
  final SpeedTestSize size;
  final int? port;
  final String user;
  final String password;
}

/// Подменяет закачку и записывает, с чем её позвали. Наружу не ходим.
List<_Download> _recordDownloads(ProbeController probe) {
  final calls = <_Download>[];
  probe.speedDownload = ({
    required SpeedTestSize size,
    int? proxyPort,
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    calls.add(_Download(size, proxyPort, proxyUser, proxyPassword));
    return const SpeedResult(
        bitsPerSecond: 24000000, bytes: 5000000, elapsed: Duration(seconds: 2));
  };
  return calls;
}

class _FakeHarness implements ProbeHarness {
  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async => _FakeHandle();

  @override
  bool get supportsProxyRequests => true;
}

class _FakeHandle implements HarnessHandle {
  @override
  String get proxyUser => harnessProxyUser;

  @override
  String get proxyPassword => _fakeSecret;

  @override
  int proxyPortFor(int index) => _fakePort;

  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {}
}

/// Кнопка, вызывающая РОВНО ТУ функцию, что висит на кнопке главного экрана.
Future<void> _pumpRunButton(
    WidgetTester tester, ProbeController probe, List<VpnServer> servers) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                startSpeedRun(context, probe, servers, const AppSettings()),
            child: const Text('Измерить скорость всех'),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpSpeedChip(WidgetTester tester,
    {required ServerSpeed speed}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: SpeedChip(speed: speed))),
  ));
  await tester.pump();
}
