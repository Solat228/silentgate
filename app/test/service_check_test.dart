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

    test('⚠️ Claude: гео берётся из API, а не с сайта', () {
      // ЗАМЕР 19.08.2026 ИЗ РФ (сервис недоступен): `https://claude.ai/` отдаёт
      // 403 с заголовком `Cf-Mitigated: challenge` и страницей на 5357 байт —
      // это БОТ-ПРОВЕРКА Cloudflare, про страну там нет ни слова. Прежняя проба
      // била именно туда и не могла сработать никогда: владелец видел Claude
      // зелёным там, где он не работает.
      //
      // У API ответ машинный: гео-проверка идёт ДО авторизации, поэтому из
      // закрытой страны приходит 403 «forbidden / Request not allowed», а из
      // открытой — 401 с требованием ключа.
      final geo = AutoConfigCatalog.geoEndpointFor(ProbeService.claude)!;
      expect(geo.url, contains('api.anthropic.com'),
          reason: 'сайт под Cloudflare для гео-пробы непригоден');

      expect(
          geo.blocked(403,
              '{"error":{"type":"forbidden","message":"Request not allowed"}}'),
          isTrue,
          reason: 'ровно этот ответ замерен из закрытой страны');

      // 401 — сервис доступен, просто нет ключа. Это НЕ гео-блок.
      expect(
          geo.blocked(401,
              '{"error":{"type":"authentication_error","message":"x-api-key"}}'),
          isFalse);

      // ⚠️ Голый 403 без машинной сигнатуры — бот-проверка, а не страна.
      expect(geo.blocked(403, 'Just a moment... cloudflare'), isFalse,
          reason: 'иначе бот-проверка на доступном регионе выдаст себя за гео');
    });

    test('⚠️ у Gemini гео-пробы нет — и это честно', () {
      // Замер 19.08.2026: страница одинакова всюду, 200 и 805 КБ без признака
      // страны. Пустая проба честнее сломанной — см. `geoGated`.
      expect(AutoConfigCatalog.geoEndpointFor(ProbeService.gemini), isNull);
      expect(ProbeService.gemini.geoGated, isFalse,
          reason: 'иначе чип обещал бы проверку, которой нет');
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
      // ⚠️ ПРОБУ ГОТОВНОСТИ ПОДМЕНЯЕМ, А НЕ ОБНУЛЯЕМ ЧИСЛО ПОПЫТОК.
      //
      // Раньше здесь стояло `readinessAttempts = 0`, и это означало «проверку
      // пропустить, идти дальше». С 1.9.0 смысл другой: непройденная проверка
      // означает «канал не готов», и пробы в мёртвый канал больше НЕ уходят —
      // иначе человек видел четырнадцать красных кружков и читал их как «VPN не
      // работает». Обнулённые попытки стали значить «не готов», и все прогоны
      // этой группы давали ноль проб.
      //
      // Здесь проверяется правило «КОГДА прогонять», к сети оно отношения не
      // имеет — поэтому готовность объявляем достигнутой, не делая запросов.
      ServiceCheckController.readinessProbe = (_) async => true;
      ServiceCheckController.readinessAttempts = 1;
      ServiceCheckController.readinessDelay = Duration.zero;
      ServiceCheckController.prober = (port, s) async {
        probed[s] = (probed[s] ?? 0) + 1;
        return ServiceCheckOutcome(
            port > 0 ? ServiceCheckState.ok : ServiceCheckState.fail,
            latencyMs: 42);
      };
    });

    tearDown(() {
      ServiceCheckController.readinessProbe =
          ServiceCheckController.defaultReadinessProbe;
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
