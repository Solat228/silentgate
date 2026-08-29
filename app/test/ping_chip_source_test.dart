import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/settings/app_settings.dart' show PingMethod;
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/ping_chip.dart';

/// Что показывает плашка пинга, когда замер сделан при поднятом туннеле.
///
/// ⚠️ ДВА ПРАВИЛА, КОТОРЫЕ ЗДЕСЬ ОХРАНЯЮТСЯ:
///  * TCP-цифра, снятая сквозь туннель (1–3 мс у всех подряд), НЕ показывается
///    вовсе — ложное число хуже отсутствующего, причина видна в подсказке;
///  * цифра от ядра ([PingMethod.coreUrl]) — ДРУГАЯ величина (время запроса к
///    тестовому адресу, не TCP до узла), поэтому в общей колонке она обязана
///    нести пометку, а подсказка — называть способ замера.
void main() {
  Future<void> pump(WidgetTester tester, PingResult r) => tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: PingChip(result: r))),
        ),
      );

  String tooltip(WidgetTester tester) =>
      tester.widget<Tooltip>(find.byType(Tooltip)).message!;

  testWidgets('TCP сквозь туннель: числа нет, причина — в подсказке',
      (tester) async {
    await pump(
        tester,
        const PingResult(
          outcome: PingOutcome.ok,
          latencyMs: 2, // ложные «2 мс» локального стека sing-box
          verification: PingVerification.notRun,
          latencyMethod: PingMethod.tcp,
          latencyThroughTunnel: true,
        ));
    expect(find.textContaining('мс'), findsNothing,
        reason: 'ложные миллисекунды показывать нельзя');
    expect(tooltip(tester), contains('Число скрыто'));
  });

  testWidgets('замер ядром: число с пометкой и способ в подсказке',
      (tester) async {
    await pump(
        tester,
        const PingResult(
          outcome: PingOutcome.ok,
          latencyMs: 217,
          proxyRttMs: 217,
          reachableViaProxy: true,
          verification: PingVerification.passed,
          latencyMethod: PingMethod.coreUrl,
        ));
    // Пометка «•» отличает величину от TCP-цифр соседних строк.
    expect(find.text('217 мс •'), findsOneWidget);
    expect(tooltip(tester), contains('самим ядром'));
  });

  testWidgets('провал теста ядром: подсказка называет настоящую причину',
      (tester) async {
    await pump(
        tester,
        const PingResult(
          outcome: PingOutcome.failed,
          verification: PingVerification.failed,
          latencyMethod: PingMethod.coreUrl,
        ));
    expect(tooltip(tester), contains('не смогло открыть тестовый адрес'),
        reason: 'красный от ядра — «трафик не идёт», а не «порт молчит»');
  });

  testWidgets('обычный TCP-замер без туннеля не изменился', (tester) async {
    await pump(
        tester,
        const PingResult(
          outcome: PingOutcome.ok,
          latencyMs: 256,
          verification: PingVerification.passed,
          latencyMethod: PingMethod.tcp,
        ));
    expect(find.text('256 мс'), findsOneWidget);
  });
}
