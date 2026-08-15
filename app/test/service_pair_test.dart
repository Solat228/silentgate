import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/service_check_controller.dart';

void main() {
  // Замер «до» — половина сравнения, и его легко потерять: раньше он снимался
  // только вручную, а на экране висел одинокий кружок «через VPN».
  group('ServiceCheckController: замер «до»', () {
    test('автозамер идёт один раз за запуск', () async {
      final c = ServiceCheckController();
      expect(c.hasBaseline, isFalse);
      await c.autoBaseline([ProbeService.google]);
      expect(c.hasBaseline, isTrue, reason: 'первый вызов обязан снять замер');

      final first = c.baselineFor(ProbeService.google).state;
      // Повторный вызов (возврат из настроек, пересборка экрана) не должен
      // гонять пробы заново.
      await c.autoBaseline([ProbeService.youtube]);
      expect(c.baselineFor(ProbeService.youtube).state, ServiceCheckState.idle,
          reason: 'второй автозамер запускаться не должен');
      expect(c.baselineFor(ProbeService.google).state, first);
    });

    test('замер «до» переживает подключение и не смешивается с «через VPN»',
        () async {
      final c = ServiceCheckController();
      await c.checkBaseline([ProbeService.google]);
      final before = c.baselineFor(ProbeService.google).state;
      expect(before, isNot(ServiceCheckState.idle));

      // Подключились и отключились: канал сменился дважды, результаты «через
      // VPN» вычищены оба раза…
      //
      // ⚠️ Здесь стояло `bind('server-1')` / `bind('server-2')` — сброс по
      // ключу ВЫБРАННОГО сервера. Ровно на это владелец и жаловался: клик по
      // строке списка живой туннель не трогает, а вердикты стирал. Такого
      // входа у контроллера больше нет.
      c.setTunnelUp(true);
      c.setTunnelUp(false);
      // …но замер «до» обязан остаться, иначе сравнивать будет не с чем.
      expect(c.baselineFor(ProbeService.google).state, before);
      expect(c.resultFor(ProbeService.google).state, ServiceCheckState.idle);
    });
  });
}
