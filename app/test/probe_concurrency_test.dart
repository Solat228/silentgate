import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/cancel_token.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/probe_controller.dart';

/// ПРОГОН ЗАМЕРОВ НЕ ИМЕЕТ ПРАВА ЗАВИСНУТЬ НАСМЕРТЬ.
///
/// ⚠️ ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ. `Pool` выдаёт слот по условию `_active < max`.
/// При `max == 0` оно ложно ВСЕГДА: ни одна задача не стартует, `Future.wait`
/// не завершается никогда — а значит не отрабатывает и `finally` в `_pingBatch`.
/// `_running` остаётся `true` до конца жизни процесса, и вместе с ним умирают
/// обе подсистемы: пинг и замер скорости (у второго тот же гейт). «Отменить» не
/// помогает — `cancel()` только ставит флаг, а флаг проверяется ВНУТРИ задачи,
/// которая не начиналась. Снаружи это ровно «нажимаю — ничего не происходит».
///
/// Откуда взяться нулю: `pingConcurrency` в интерфейсе нет вовсе, значение
/// приезжает из `silentgate_settings.json` — то есть из ручной правки, чужой
/// копии настроек или битого файла. Компилятор такое не ловит, а цена — намертво
/// мёртвая проверка серверов без единой строки в журнале.
///
/// Наружу тест не ходит: мишень — закрытый порт на 127.0.0.1.
void main() {
  late Directory tmp;

  setUp(() {
    // Пинг пишет результаты на диск. Боевой %APPDATA% тесты не трогают.
    tmp = Directory.systemTemp.createTempSync('sg_pool_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('⚠️ ГЛАВНОЕ: pingConcurrency = 0 не вешает прогон навсегда', () async {
    final ctrl = ProbeController();
    // Порт 1 на петле закрыт: TCP получает отказ мгновенно, наружу не идём и
    // фазы 2 не будет (двухфазность выключена).
    const dead = VpnServer(
      protocol: 'vless',
      remark: 'dead',
      address: '127.0.0.1',
      port: 1,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:1#dead',
    );

    await ctrl
        .pingAll([dead], const AppSettings(
            pingConcurrency: 0, pingTwoPhase: false, pingTimeoutMs: 500))
        .timeout(const Duration(seconds: 10));

    expect(ctrl.running, isFalse,
        reason: 'прогон завершился — иначе ни пинг, ни скорость больше не '
            'запустятся до перезапуска приложения');
  });

  test('отрицательное значение лечится так же', () async {
    final ctrl = ProbeController();
    const dead = VpnServer(
      protocol: 'vless',
      remark: 'dead',
      address: '127.0.0.1',
      port: 1,
      id: '00000000-0000-0000-0000-000000000000',
      rawLink: 'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:1#dead',
    );
    await ctrl
        .pingAll([dead], const AppSettings(
            pingConcurrency: -4, pingTwoPhase: false, pingTimeoutMs: 500))
        .timeout(const Duration(seconds: 10));
    expect(ctrl.running, isFalse);
  });

  test('нормальное значение по-прежнему ограничивает параллелизм', () {
    // Иначе «починка» свелась бы к отмене самого ограничителя.
    final pool = Pool(2);
    var active = 0;
    var peak = 0;
    final done = <Future<void>>[];
    for (var i = 0; i < 6; i++) {
      done.add(pool.run(() async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
      }));
    }
    return Future.wait(done).then((_) => expect(peak, lessThanOrEqualTo(2)));
  });
}
