import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/state/service_check_controller.dart';

/// ПОЧЕМУ АВТОПРОГОН ПРОВЕРОК НЕ СОСТОЯЛСЯ — ОБЯЗАНО БЫТЬ НАЗВАНО.
///
/// ⚠️ ЗАЧЕМ. 02.09.2026 на эмуляторе значки сервисов остались серыми при живом
/// туннеле, и понять причину было НЕЧЕМ: `autoCheckAll` выходит на одном из
/// четырёх гейтов в начале, и все четыре выхода молчаливые — ни строки в
/// журнал, ни признака на экран. Плашка «канал не готов» при этом не
/// появляется: она зажигается ПОЗЖЕ, только когда дело дошло до ожидания
/// канала. То есть ровно в самом частом случае — вышли раньше — человек и
/// разбирающий видят одинаковую пустоту.
///
/// Разница между четырьмя причинами существенная: «туннель не поднят» лечится
/// подключением, «порт ядра ещё не появился» — ожиданием, «проверки выключены»
/// — настройкой, «уже отработал на этом подъёме» вообще не беда.
void main() {
  setUp(() {
    // Ни одна проба наружу не уходит.
    ServiceCheckController.readinessProbe = (_) async => false;
    ServiceCheckController.readinessAttempts = 1;
    ServiceCheckController.readinessDelay = Duration.zero;
    ServiceCheckController.prober = (_, __) async => ServiceCheckOutcome.idle;
  });

  tearDown(() {
    ServiceCheckController.readinessProbe =
        ServiceCheckController.defaultReadinessProbe;
    ServiceCheckController.readinessAttempts = 6;
    ServiceCheckController.readinessDelay = const Duration(seconds: 2);
    ServiceCheckController.prober = ServiceChecker.check;
    ServiceCheckController.onAutoSkip = null;
    ServiceCheckActivity.resetForTests();
  });

  test('до первого вызова причины нет', () {
    final c = ServiceCheckController();
    addTearDown(c.dispose);
    expect(c.autoSkipReason, isNull);
  });

  test('туннель не поднят — причина названа', () async {
    final c = ServiceCheckController();
    addTearDown(c.dispose);
    await c.autoCheckAll(10809, ServiceChecks.services);
    expect(c.autoSkipReason, contains('туннель'));
  });

  test('порт ядра ещё не появился — причина другая', () async {
    final c = ServiceCheckController();
    addTearDown(c.dispose);
    c.setTunnelUp(true);
    await c.autoCheckAll(0, ServiceChecks.services);
    expect(c.autoSkipReason, contains('порт'));
  });

  test('проверки выключены настройкой — причина третья', () async {
    final c = ServiceCheckController();
    addTearDown(c.dispose);
    c.setTunnelUp(true);
    await c.autoCheckAll(10809, const []);
    expect(c.autoSkipReason, contains('выключен'));
  });

  test('⚠️ причина СНИМАЕТСЯ, когда прогон всё-таки пошёл', () async {
    // Иначе строка «туннель не поднят» переживёт подключение и будет врать
    // ровно так же, как молчание, — только увереннее.
    final c = ServiceCheckController();
    addTearDown(c.dispose);
    await c.autoCheckAll(10809, ServiceChecks.services);
    expect(c.autoSkipReason, isNotNull, reason: 'предпосылка: причина есть');

    c.setTunnelUp(true);
    await c.autoCheckAll(10809, ServiceChecks.services);
    expect(c.autoSkipReason, isNull,
        reason: 'прогон дошёл до ожидания канала — выхода на гейте не было');
  });

  test('⚠️ в журнал причина уходит ОДИН раз, а не на каждую перерисовку',
      () async {
    // Главный экран зовёт `autoCheckAll` с КАЖДОГО кадра (счётчики тикают раз
    // в секунду). Строка на каждый вызов забила бы журнал сотнями одинаковых
    // записей и утопила бы в них всё остальное — то есть лечение оказалось бы
    // хуже болезни.
    final said = <String>[];
    ServiceCheckController.onAutoSkip = said.add;
    final c = ServiceCheckController();
    addTearDown(c.dispose);

    for (var i = 0; i < 5; i++) {
      await c.autoCheckAll(10809, ServiceChecks.services);
    }
    expect(said, hasLength(1), reason: 'пять одинаковых вызовов — одна запись');

    // А вот СМЕНА причины — это новость, и она обязана попасть в журнал.
    c.setTunnelUp(true);
    await c.autoCheckAll(0, ServiceChecks.services);
    expect(said, hasLength(2));
    expect(said.last, contains('порт'));
  });
}
