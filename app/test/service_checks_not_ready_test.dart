import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// ПОЧЕМУ ЗНАЧКИ СЕРЫЕ — ЭТО ОБЯЗАНО БЫТЬ НАПИСАНО СЛОВАМИ, И НА ЛЮБОМ ЭКРАНЕ.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 02.09.2026: «проверка сервисов даёт серые значки, когда
/// VPN работает». Серый кружок рисуется в ДВУХ разных случаях, и отличить их по
/// картинке нельзя вовсе: `idle` («ещё не проверяли») и «канал не ответил, пачку
/// не запускали» дают один и тот же цвет — `_dot` в `service_checks_row.dart`
/// красит всё, кроме ok/geo/fail, в `disabledColor`. То есть ИСПРАВНОЕ поведение
/// (пробы намеренно не пошли в неготовое ядро) выглядит как поломка.
///
/// Объяснение живёт в [ServiceChecksNotReadyBanner] под кнопкой Connect. Здесь
/// проверяется не его существование, а то, что человек его ВИДИТ и может нажать:
/// на всех ходовых разрешениях, включая самое тесное.
///
/// ⚠️ ПОЧЕМУ ВСЕ РАЗРЕШЕНИЯ, А НЕ ОДНО. Полоса с текстом и кнопкой стоит ровно
/// там, где у экрана уже нет запаса по ширине: под кнопкой Connect и рядами из
/// пяти групп. Ряд, который на 428 px выглядит нормально, на 320 px уезжает за
/// край вместе с кнопкой повтора — а в релизной сборке полосы переполнения не
/// рисуются, и пропажа проходит молча. Ровно этим классом дефектов в проекте уже
/// платили: страж был зелёным, а на экране половина элемента была за границей.
void main() {
  /// Те же настоящие разрешения, что в `connect_centerpiece_layout_test`.
  const screens = <String, Size>{
    'iPhone SE 1 (самый тесный)': Size(320, 568),
    'Android 360×640': Size(360, 640),
    'Android 360×800 (самый ходовой)': Size(360, 800),
    'iPhone SE 2/3, 8': Size(375, 667),
    'iPhone 14/15': Size(390, 844),
    'Pixel 7/8': Size(393, 873),
    'Samsung S23': Size(412, 915),
    'iPhone 11/XR': Size(414, 896),
    'iPhone Pro Max': Size(428, 926),
    'планшет, портрет': Size(800, 1280),
    'Windows, минимальное окно': Size(880, 680),
  };

  const button = SizedBox(key: Key('btn'), width: 148, height: 148);

  /// Порог двухпанельной раскладки из `home_screen.dart` — ниже него
  /// `_ConnectPane` прокручивается, выше держится распорками.
  const twoPaneMinWidth = 760.0;

  Widget host(ServiceCheckController ctrl, Widget child,
          {required double width}) =>
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<ServiceCheckController>.value(
          value: ctrl,
          child: Scaffold(
            body: width < twoPaneMinWidth
                ? SingleChildScrollView(child: Center(child: child))
                : Center(child: child),
          ),
        ),
      );

  /// Довести контроллер до состояния «канал не ответил, пачку не запускали».
  ///
  /// Через настоящий [ServiceCheckController.autoCheckAll], а не подстановкой
  /// поля: правило «когда показывать плашку» обязано спрашивать тот же код, что
  /// решает «запускать ли пробы», иначе экран и исполнитель разойдутся.
  Future<ServiceCheckController> notReady(WidgetTester t) async {
    final c = ServiceCheckController();
    c.setTunnelUp(true);
    // ⚠️ ЧЕРЕЗ runAsync, А НЕ ПРОСТО await. Внутри `testWidgets` время
    // фиктивное: `Future.delayed` в ожидании готовности канала сам не
    // истекает, и прогон вставал намертво на первом же разрешении — без
    // единой строки о причине. Настоящий `autoCheckAll` здесь нужен (правило
    // показа обязано спрашивать тот же код, что решает запуск проб), значит
    // нужен и настоящий ход времени.
    await t.runAsync(() => c.autoCheckAll(10809, ServiceChecks.catalog));
    return c;
  }

  setUp(() {
    // Канал молчит, ждать нечего: без этого один прогон занял бы полминуты
    // реального времени, а проверяется здесь вёрстка, а не таймауты.
    ServiceCheckController.readinessProbe = (_) async => false;
    ServiceCheckController.readinessAttempts = 1;
    ServiceCheckController.readinessDelay = Duration.zero;
    // Пробы сервисов до дела не доходят, но подмена обязательна: боевая
    // реализация полезла бы в сеть, если правило вдруг сломается.
    ServiceCheckController.prober = (_, __) async => ServiceCheckOutcome.idle;
  });

  tearDown(() {
    ServiceCheckController.readinessProbe =
        ServiceCheckController.defaultReadinessProbe;
    ServiceCheckController.readinessAttempts = 6;
    ServiceCheckController.readinessDelay = const Duration(seconds: 2);
    ServiceCheckController.prober = ServiceChecker.check;
    ServiceCheckActivity.resetForTests();
  });

  group('⚠️ «Канал не готов» видно и нажимается на всех экранах', () {
    for (final e in screens.entries) {
      testWidgets('${e.key} — причина написана словами, повтор доступен',
          (t) async {
        t.view.physicalSize = e.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        final ctrl = await notReady(t);
        addTearDown(ctrl.dispose);
        expect(ctrl.channelNotReady, isTrue,
            reason: 'предпосылка теста: пачка не состоялась');

        await t.pumpWidget(host(
          ctrl,
          ConnectCenterpiece(
            serverName: '🇩🇪 🚀Германия 2.7 (edge)',
            httpPort: 10809,
            button: button,
            services: ServiceChecks.catalog,
          ),
          width: e.value.width,
        ));
        await t.pump();

        expect(t.takeException(), isNull,
            reason: '${e.key}: вёрстка плашки переполнилась');

        final l = AppLocalizations.of(
            t.element(find.byType(ConnectCenterpiece)));

        // 1. Причина названа СЛОВАМИ. Серый кружок сам по себе не отличим от
        //    «ещё не проверяли», и молчание тут равно вранью.
        expect(find.text(l.serviceChecksChannelNotReady), findsOneWidget,
            reason: '${e.key}: причина серых значков не написана');

        // 2. Повтор доступен и ЦЕЛИКОМ на экране. Кнопка, наполовину уехавшая
        //    за край, в релизе просто обрезается — нажать её нечем.
        final retry = find.byKey(const Key('serviceChecksRetry'));
        expect(retry, findsOneWidget, reason: '${e.key}: нет кнопки повтора');
        final r = t.getRect(retry);
        expect(r.left, greaterThanOrEqualTo(0),
            reason: '${e.key}: кнопка повтора уехала за левый край');
        expect(r.right, lessThanOrEqualTo(e.value.width),
            reason: '${e.key}: кнопка повтора уехала за правый край');
        expect(r.width, greaterThan(0));

        // 3. И сама плашка не шире экрана — иначе текст обрезан.
        final banner = t.getSize(find.byType(ServiceChecksNotReadyBanner));
        expect(banner.width, lessThanOrEqualTo(e.value.width),
            reason: '${e.key}: плашка шире экрана');
      });
    }
  });

  group('Границы состояния', () {
    testWidgets('пока пачка не провалилась — плашки нет', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final ctrl = ServiceCheckController();
      addTearDown(ctrl.dispose);
      await t.pumpWidget(host(
        ctrl,
        const ConnectCenterpiece(
          serverName: null,
          httpPort: 10809,
          button: button,
          services: ServiceChecks.services,
        ),
        width: 360,
      ));
      await t.pump();

      expect(find.byKey(const Key('serviceChecksRetry')), findsNothing,
          reason: 'обычный `idle` — не повод объявлять канал сломанным');
    });

    testWidgets('⚠️ нажатие «Повторить» действительно гоняет пробу заново',
        (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      var probes = 0;
      ServiceCheckController.readinessProbe = (_) async {
        probes++;
        return false;
      };

      final ctrl = await notReady(t);
      addTearDown(ctrl.dispose);
      final before = probes;

      await t.pumpWidget(host(
        ctrl,
        const ConnectCenterpiece(
          serverName: null,
          httpPort: 10809,
          button: button,
          services: ServiceChecks.services,
        ),
        width: 360,
      ));
      await t.pump();

      await t.tap(find.byKey(const Key('serviceChecksRetry')));
      await t.pumpAndSettle();

      // ⚠️ Именно счётчик проб, а не «плашка мигнула»: пауза перед
      // автоматическим повтором (20 с) и потолок попыток обязаны сниматься
      // нажатием — иначе кнопка есть, а нажатие не делает ничего.
      expect(probes, greaterThan(before),
          reason: 'кнопка повтора не дошла до исполнителя');
    });
  });
}
