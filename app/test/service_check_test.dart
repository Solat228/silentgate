import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

void main() {
  group('Каталог сервисов (#6.1)', () {
    test('у всех сервисов есть проба доступности (endpointFor)', () {
      for (final s in ProbeService.values) {
        expect(AutoConfigCatalog.endpointFor(s), isNotNull,
            reason: 'нет endpoint для ${s.name}');
      }
    });

    test('гео-проба только у ИИ-сервисов (geoGated)', () {
      for (final s in ProbeService.values) {
        final geo = AutoConfigCatalog.geoEndpointFor(s);
        expect(geo != null, s.geoGated,
            reason: 'geoGated и наличие гео-пробы разошлись у ${s.name}');
      }
    });

    test('у каждого сервиса есть домен и имя', () {
      for (final s in ProbeService.values) {
        expect(s.label, isNotEmpty);
        expect(s.domain, contains('.'));
      }
    });
  });

  group('Гео-валидаторы', () {
    test('OpenAI: заблокирован только по маркеру unsupported_country', () {
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.chatgpt)!;
      expect(geo.blocked(403, '{"error":"unsupported_country"}'), isTrue);
      expect(geo.blocked(200, '{"error":"unsupported_country"}'), isTrue);
      expect(geo.blocked(200, '{"ok":true}'), isFalse);
      // Голый 403 (Cloudflare/WAF/бот-челлендж на доступном регионе) — НЕ гео-блок.
      expect(geo.blocked(403, 'Just a moment... attention required'), isFalse);
    });

    test('Claude/Gemini: 451 или текст, но не голый 403', () {
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.claude)!;
      expect(geo.blocked(451, ''), isTrue); // юридический гео-блок
      expect(geo.blocked(200, 'Claude is not available in your country'), isTrue);
      expect(geo.blocked(200, "This app isn't available here"), isTrue);
      expect(geo.blocked(200, 'Welcome to Claude'), isFalse);
      // Голый 403 (rate-limit/челлендж) на доступном регионе — НЕ гео-блок.
      expect(geo.blocked(403, 'cloudflare rate limited'), isFalse);
    });

    test('Gemini: типографская апострофа U+2019 в «isn’t available» ловится', () {
      // Google/Anthropic ставят фигурную апострофу — раньше ASCII-шаблон её не брал.
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.gemini)!;
      expect(geo.blocked(200, 'Gemini isn’t available in your country yet'),
          isTrue);
    });
  });

  group('Дефолтный набор сервисов автонастройки (#6.3.1)', () {
    test('по умолчанию — YouTube, ChatGPT, Telegram', () {
      expect(AppSettings.defaults.autoConfigServices, {
        ProbeService.youtube,
        ProbeService.chatgpt,
        ProbeService.telegram,
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Жалоба владельца: «прекрати каждый раз при перевыборе сервера
  // перепроверять работоспособность уже рабочего сервиса. Он должен обновляться
  // только если юзер САМ жмёт на этот сервис или при включении VPN, при
  // отключении работоспособность через сервер должна отключиться».
  //
  // ⚠️ Половина правила держится не тестом, а ТИПАМИ: у контроллера больше нет
  // ни одного входа, куда можно было бы передать выбранный сервер
  // ([ServiceCheckController.setTunnelUp] принимает bool), и `ServiceChecksColumn`
  // больше не принимает `epoch`. Прежнюю ошибку теперь нельзя написать.
  // ───────────────────────────────────────────────────────────────────────────
  group('Когда сервисы перепроверяются', () {
    /// Сколько раз каждый сервис проверили с момента [reset].
    late Map<ProbeService, int> probed;
    late ServiceCheckController ctrl;

    setUp(() {
      probed = {};
      ctrl = ServiceCheckController();
      // Ноль попыток — ожидание готовности канала не делает НИ ОДНОГО сетевого
      // запроса и сразу отдаёт «эпоха не менялась». Правило «когда прогонять»
      // к сети отношения не имеет.
      ServiceCheckController.readinessAttempts = 0;
      ServiceCheckController.readinessDelay = Duration.zero;
      ServiceCheckController.prober = (port, s) async {
        probed[s] = (probed[s] ?? 0) + 1;
        return ServiceCheckOutcome(
            port > 0 ? ServiceCheckState.ok : ServiceCheckState.fail,
            latencyMs: 42);
      };
    });

    tearDown(() {
      ServiceCheckController.readinessAttempts = 6;
      ServiceCheckController.readinessDelay = const Duration(seconds: 2);
      ServiceCheckController.prober = ServiceChecker.check;
      ctrl.dispose();
    });

    int totalProbes() => probed.values.fold(0, (a, b) => a + b);

    test('счётчик подъёмов растёт ТОЛЬКО на смене состояния канала', () {
      expect(ctrl.tunnelUp, isFalse);
      final start = ctrl.session;
      ctrl.setTunnelUp(false); // экран перерисовался, VPN как был выключен
      expect(ctrl.session, start, reason: 'состояние не менялось');

      ctrl.setTunnelUp(true);
      final up = ctrl.session;
      expect(up, greaterThan(start));
      expect(ctrl.tunnelUp, isTrue);
      for (var i = 0; i < 3; i++) {
        ctrl.setTunnelUp(true);
      }
      expect(ctrl.session, up,
          reason: 'подъём один — сколько бы раз экран об этом ни сообщил');

      ctrl.setTunnelUp(false);
      expect(ctrl.session, greaterThan(up),
          reason: 'канал умер — это новая эпоха, вердикты прошлой к ней '
              'не относятся');
    });

    test('подъём туннеля прогоняет все сервисы РОВНО один раз', () async {
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      expect(probed.keys.toSet(), ServiceChecks.services.toSet(),
          reason: 'колонок две, а прогон один — обе половины обязаны попасть');
      expect(totalProbes(), ServiceChecks.services.length);
      expect(ctrl.resultFor(ProbeService.youtube).state, ServiceCheckState.ok);
    });

    test('перерисовка экрана не гоняет пробы заново', () async {
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      final after = totalProbes();
      // Главный экран зовёт это на КАЖДОЙ перерисовке: счётчики трафика тикают
      // раз в секунду, и «эпоха» пересчитывается вместе с ними.
      for (var i = 0; i < 5; i++) {
        ctrl.setTunnelUp(true);
        await ctrl.autoCheckAll(10809, ServiceChecks.services);
      }
      expect(totalProbes(), after,
          reason: 'один подъём — один автопрогон, иначе чипы бегают по кругу');
    });

    test('нулевой порт не съедает единственный автопрогон подъёма', () async {
      ctrl.setTunnelUp(true);
      // Статус «Подключено» уже есть, порт активного ядра — ещё нет.
      await ctrl.autoCheckAll(0, ServiceChecks.services);
      expect(totalProbes(), 0);
      // Порт появился на следующей перерисовке — прогон обязан состояться.
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      expect(totalProbes(), ServiceChecks.services.length,
          reason: 'отметка «подъём отработан», поставленная на нуле, отменяла '
              'автопрогон навсегда — до следующего переподключения');
    });

    test('отключение гасит колонку «через VPN», замер «без VPN» остаётся',
        () async {
      // Замер «до» снимается напрямую (порт 0) и к каналу не привязан.
      await ctrl.check(ProbeService.youtube, 0);
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      expect(ctrl.resultFor(ProbeService.youtube).state, ServiceCheckState.ok);

      ctrl.setTunnelUp(false);
      for (final s in ServiceChecks.services) {
        expect(ctrl.resultFor(s).state, ServiceCheckState.idle,
            reason: 'результат через мёртвый канал показывать как '
                'действующий нельзя — сервиса «через VPN» больше нет');
      }
      expect(ctrl.baselineFor(ProbeService.youtube).state,
          ServiceCheckState.fail,
          reason: 'замер «без VPN» ни к какому каналу не привязан и обязан '
              'пережить отключение — иначе сравнивать будет не с чем');
      expect(ctrl.hasBaseline, isTrue);
    });

    test('переподключение — новый подъём, значит новый автопрогон', () async {
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      final first = totalProbes();
      ctrl.setTunnelUp(false);
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      expect(totalProbes(), first * 2,
          reason: 'канал новый — вердикты старого к нему не относятся');
    });

    test('тап пользователя проверяет всегда, сколько бы раз ни нажали',
        () async {
      ctrl.setTunnelUp(true);
      await ctrl.autoCheckAll(10809, ServiceChecks.services);
      final before = probed[ProbeService.telegram]!;
      await ctrl.check(ProbeService.telegram, 10809);
      await ctrl.check(ProbeService.telegram, 10809);
      expect(probed[ProbeService.telegram], before + 2);
    });

    test('результат, доехавший после смерти канала, не пишется', () async {
      // Проба идёт до ~16 с; за это время туннель успевает упасть.
      final gate = Completer<ServiceCheckOutcome>();
      ServiceCheckController.prober = (port, s) => gate.future;
      ctrl.setTunnelUp(true);
      final pending = ctrl.check(ProbeService.google, 10809);
      expect(ctrl.resultFor(ProbeService.google).state,
          ServiceCheckState.checking);
      ctrl.setTunnelUp(false);
      gate.complete(const ServiceCheckOutcome(ServiceCheckState.ok));
      await pending;
      expect(ctrl.resultFor(ProbeService.google).state, ServiceCheckState.idle,
          reason: 'зелёный кружок на выключенном VPN — вердикт о канале, '
              'которого уже нет');
    });

    test('замер «без VPN» пишется даже если туннель умер во время пробы',
        () async {
      final gate = Completer<ServiceCheckOutcome>();
      ServiceCheckController.prober = (port, s) => gate.future;
      ctrl.setTunnelUp(true);
      final pending = ctrl.check(ProbeService.google, 0); // напрямую
      ctrl.setTunnelUp(false);
      gate.complete(const ServiceCheckOutcome(ServiceCheckState.ok));
      await pending;
      expect(ctrl.baselineFor(ProbeService.google).state, ServiceCheckState.ok,
          reason: 'проба шла мимо VPN — состояние туннеля на неё не влияет');
    });
  });
}
