import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/home_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

/// КНОПКА CONNECT И ТО, ЧТО ВПИСАНО В ЕЁ КРУГ — решение владельца 27.08.2026.
///
/// ⚠️ ОБЪЁМ ЭТОГО ФАЙЛА ОГРАНИЧЕН НАМЕРЕННО. Владелец очертил его дословно:
/// «начни только с кнопки и всего, что вписано в свободное место прямоугольника
/// кнопки; всё остальное — в todo». Раскладка проверок ВОКРУГ кнопки (ряды,
/// колонки по бокам, сетка) уже покрыта `connect_centerpiece_layout_test.dart`
/// на отсутствие переполнения — здесь этот тест НЕ дублируется, здесь только
/// содержимое самого круга: значок питания и подпись таймера сессии.
/// Остальные экраны (панель серверов, карточка сервера, настройки, подписка и
/// баннеры) — в `docs/BACKLOG.md`.
///
/// ⚠️ ПОЧЕМУ КНОПКА СТАЛА ПУБЛИЧНОЙ (`ConnectButton`, а не `_ConnectButton`).
/// `ConnectCenterpiece` принимает готовую кнопку СНАРУЖИ именно ради тестов —
/// но прежние стражи (`connect_centerpiece_layout_test.dart`) подставляли туда
/// пустой `SizedBox`-заглушку: им было важно место вокруг кнопки, а не то, что
/// внутри нЕё. Этому стражу важно ровно содержимое круга, и подставлять сюда
/// СВОЮ копию значка и таймера — та же ошибка, на которой уже обжигались с
/// колонками проверок (см. шапку `service_checks_row.dart`): копия зеленеет,
/// пока настоящий виджет расходится с ней. Приватность в Dart — по файлу, и
/// другого способа поднять настоящий `_ConnectButton` из отдельного теста нет.
/// Переименование НЕ меняет поведение ни на бит — только имя класса.
///
/// ⚠️ ПОЧЕМУ НАБОР ИЗ 14 СЕРВИСОВ. Кнопка не рисует сервисы сама, но на
/// раскладках `sides`/`grid` весь блок (кнопка + обе колонки) сжимается ОДНИМ
/// `FittedBox`-множителем (см. `ServiceChecksSides`) — чем теснее колонки, тем
/// сильнее сожмётся и сама кнопка. Полный каталог — это САМЫЙ тесный случай,
/// какой вообще бывает у владельца; страж на неполном наборе не поймал бы
/// сжатие, которое проявляется только при разросшемся каталоге.
void main() {
  /// Те же одиннадцать ходовых разрешений, что и в
  /// `connect_centerpiece_layout_test.dart` — комментарии по каждому смотри там.
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

  /// Порог двухпанельной раскладки (`_twoPaneMinWidth` в `home_screen.dart`) —
  /// ниже него содержимое прокручивается, см. [host].
  const twoPaneMinWidth = 760.0;

  /// Диаметр, который РЕАЛЬНО подставляет `_ConnectPane`: 116 на низком экране
  /// (`context.sg.isShort`, высота < 600 dp), иначе 148. Формула взята из
  /// `home_screen.dart` дословно, а не придумана заново.
  double diameterFor(Size s) => s.height < 600 ? 116.0 : 148.0;

  /// Доля значка от диаметра при подключённом VPN — `56 / 148`, см.
  /// `ConnectButton.build` (`Icon(size: (connected ? 56 : 68) * scale)`,
  /// `scale = d / _baseline`, `_baseline == 148`).
  const iconRatioConnected = 56 / 148;

  /// Та же доля для НЕподключённого состояния (нет таймера, значок крупнее).
  const iconRatioIdle = 68 / 148;

  /// Допуск на отношение значок/диаметр.
  ///
  /// ⚠️ САМО ОТНОШЕНИЕ МАТЕМАТИЧЕСКИ ПОСТОЯННО, а не просто «примерно похоже».
  /// Значок считается как `68*scale` (или `56*scale`), `scale = d/_baseline`, где
  /// `d` — диаметр, переданный `ConnectButton` ДО внешнего сжатия. Раскладки
  /// `sides`/`grid` сжимают весь блок (кнопку и значок разом) ОДНИМ и тем же
  /// `FittedBox`-множителем (`BoxFit.scaleDown` — сохраняет пропорции по
  /// построению). Множитель сокращается в отношении «значок / диаметр» и на
  /// бумаге, и в рендере — отклонение возможно только из-за арифметики с
  /// `double`, поэтому 1 % — очень щедрый запас, а не подогнанное число.
  const ratioTolerance = 0.01;

  /// Допуск на пиксельные сравнения (квадратность, вписанность, центровка).
  ///
  /// Полпикселя — не «подгонка под тест»: устройство рисуется с
  /// `devicePixelRatio = 1.0`, а сложение нескольких `Rect` в разных системах
  /// координат (`FittedBox`, `Center`) даёт погрешность double, но не целый
  /// пиксель. Величина взята из уже принятого в проекте стража
  /// (`connect_centerpiece_layout_test.dart`, `server_tile_layout_test.dart`).
  const px = 0.5;

  /// Движок-пустышка — тот же минимальный набор переопределений, что и в
  /// `auto_config_ui_test.dart`: `AppState` слушает четыре потока движка ещё в
  /// конструкторе, и без них тест падает до первого `pumpWidget`.
  ///
  /// ⚠️ AppState нужен здесь ТОЛЬКО ради `connectedFor` (таймер сессии в
  /// кнопке, `_UptimeLabel`): само хранилище, подписки и `AppPaths` этот тест
  /// не трогает вовсе, поэтому `AppState.init()` не зовётся и боевой каталог
  /// данных изолировать не от чего.

  Widget host(Widget child, {required double width, required AppState state}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ServiceCheckController()),
          ChangeNotifierProvider<AppState>.value(value: state),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            // ⚠️ ПРОКРУТКА — РОВНО ТАМ, ГДЕ ЕЁ ДОБАВЛЯЕТ ПРИЛОЖЕНИЕ (см. warning
            // в шапке `connect_centerpiece_layout_test.dart`). Оборачивать в
            // скролл ВСЁ — значит не заметить переполнение там, где у экрана
            // прокрутки нет вовсе (широкое окно Windows).
            body: width < twoPaneMinWidth
                ? SingleChildScrollView(child: Center(child: child))
                : Center(child: child),
          ),
        ),
      );

  /// `inner` целиком внутри `outer`, с допуском [px] на арифметику double.
  void expectInside(Rect inner, Rect outer, String what, String where) {
    expect(inner.left, greaterThanOrEqualTo(outer.left - px),
        reason: '$where: $what вылез за левый край кнопки');
    expect(inner.top, greaterThanOrEqualTo(outer.top - px),
        reason: '$where: $what вылез за верхний край кнопки');
    expect(inner.right, lessThanOrEqualTo(outer.right + px),
        reason: '$where: $what вылез за правый край кнопки');
    expect(inner.bottom, lessThanOrEqualTo(outer.bottom + px),
        reason: '$where: $what вылез за нижний край кнопки');
  }

  group('⚠️ 11 экранов × 5 раскладок, 14 сервисов — кнопка ПОДКЛЮЧЕНА', () {
    for (final screen in screens.entries) {
      for (final layout in ServiceChecksLayout.values) {
        final where = '${screen.key} / ${layout.name}';
        testWidgets(where, (t) async {
          t.view.physicalSize = screen.value;
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);

          final state = AppState(engine: _FakeEngine())..markUserConnect();
          final diameter = diameterFor(screen.value);

          await t.pumpWidget(host(
            ConnectCenterpiece(
              serverName: '🇩🇪 🚀Германия 2.7 (edge)',
              httpPort: 10809,
              services: ServiceChecks.catalog,
              layout: layout,
              button: Builder(
                builder: (context) => ConnectButton(
                  status: const VpnStatus(VpnConnectionState.connected),
                  diameter: diameter,
                  onTap: () {},
                ),
              ),
            ),
            width: screen.value.width,
            state: state,
          ));
          await t.pump();

          // 1. Нет переполнения ни на одной из 55 комбинаций.
          expect(t.takeException(), isNull,
              reason: '$where: вёрстка переполнилась');

          final buttonRect = t.getRect(find.byType(ConnectButton));

          // 2. Кнопка круглая — ширина равна высоте...
          expect((buttonRect.width - buttonRect.height).abs(), lessThan(px),
              reason: '$where: кнопка не квадратная — кругом быть не может '
                  '(${buttonRect.width} × ${buttonRect.height})');
          // ...и центр совпадает с центром отведённого места. `Center`/
          // `mainAxisAlignment.center` стоят на каждом уровне между кнопкой и
          // экраном (см. [host] и `ConnectCenterpiece`), поэтому центр кнопки
          // обязан совпасть с центром ШИРИНЫ экрана в любой из пяти раскладок.
          expect(buttonRect.center.dx, closeTo(screen.value.width / 2, px),
              reason: '$where: кнопка не по центру (${buttonRect.center.dx} '
                  'вместо ${screen.value.width / 2})');

          // 5. Кнопка не выходит за отведённую ширину экрана.
          expect(buttonRect.left, greaterThanOrEqualTo(-px),
              reason: '$where: кнопка вылезла слева за экран');
          expect(buttonRect.right, lessThanOrEqualTo(screen.value.width + px),
              reason: '$where: кнопка вылезла справа за экран');

          // 4. Диаметр НЕ РАСТЁТ: `BoxFit.scaleDown` (см. `ServiceChecksSides`)
          // структурно не может увеличить ребёнка сверх его собственного
          // размера — только сжать. Кнопка крупнее заявленного диаметра
          // означала бы, что где-то в цепочке появилось растягивание.
          expect(buttonRect.width, lessThanOrEqualTo(diameter + px),
              reason: '$where: кнопка стала крупнее положенных $diameter px');

          // 3. Значок питания вписан в круг.
          final iconRect = t.getRect(find.descendant(
              of: find.byType(ConnectButton),
              matching: find.byIcon(Icons.power_settings_new)));
          expectInside(iconRect, buttonRect, 'значок питания', where);

          // 3. Подпись таймера вписана в круг (кнопка "подключена" — она
          // обязана быть на экране).
          final labelFinder = find.descendant(
              of: find.byType(ConnectButton), matching: find.byType(Text));
          expect(labelFinder, findsOneWidget,
              reason: '$where: подпись таймера не нарисовалась');
          expectInside(t.getRect(labelFinder), buttonRect, 'таймер сессии', where);

          // 4. Пропорциональность: значок/диаметр — то же самое число на
          // любом экране и в любой раскладке (см. комментарий к
          // [ratioTolerance] — отклонение возможно только из-за double).
          final ratio = iconRect.width / buttonRect.width;
          expect(ratio, closeTo(iconRatioConnected, ratioTolerance),
              reason: '$where: значок не масштабируется вместе с кругом '
                  '($ratio вместо $iconRatioConnected)');
        });
      }
    }
  });

  group('⚠️ Широкое окно: раскладка `sides` не должна повисать островом', () {
    /// Баг владельца (29.08.2026): на растянутом окне колонки и кнопка
    /// рисовались НАТУРАЛЬНЫМ (не зависящим от ширины окна) размером и
    /// центрировались одним куском — вся лишняя ширина уходила в поля СНАРУЖИ
    /// блока, а не доставалась содержимому. Проверяем именно ЭТО: сколько
    /// реальной ширины окна занял блок «колонки + кнопка», а не просто
    /// отсутствие переполнения (оно уже покрыто выше и остаётся зелёным даже
    /// на баге — крошечный остров посередине тоже не переполняется).
    ///
    /// Два широких окна — не совпадение: у порога с потолком добавки к зазору
    /// (`_gapExtraCap` в `ServiceChecksSides`) доля ширины закономерно падает
    /// по мере роста окна (в знаменателе становится больше, а числитель
    /// упирается в потолок). Порог теста подобран так, чтобы держаться ниже
    /// более тесного из двух случаев (1920×1080) с запасом, а не подогнан под
    /// каждое окно отдельно.
    const wideScreens = <Size>[
      Size(1400, 900),
      Size(1920, 1080),
    ];

    /// ⚠️ ПОЧЕМУ ИМЕННО 0.35. До правки блок занимал фиксированные 392 px
    /// независимо от окна — это 28 % от 1400 и 20 % от 1920. Порог в 35 %
    /// заведомо выше обоих старых чисел (баг не может случайно пройти тест) и
    /// одновременно ниже худшего нового случая (1920×1080 даёт ≈37 %, см.
    /// расчёт в шапке группы) — то есть порог проверяет РОСТ, а не подогнан
    /// под конкретный пиксель.
    const minOccupiedFraction = 0.35;

    for (final screen in wideScreens) {
      testWidgets('${screen.width.toInt()}×${screen.height.toInt()}',
          (t) async {
        t.view.physicalSize = screen;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        final state = AppState(engine: _FakeEngine())..markUserConnect();
        const diameter = 148.0; // высота окна >= 600 — не "короткий" случай.

        await t.pumpWidget(host(
          ConnectCenterpiece(
            serverName: '🇩🇪 🚀Германия 2.7 (edge)',
            httpPort: 10809,
            services: ServiceChecks.catalog,
            layout: ServiceChecksLayout.sides,
            button: Builder(
              builder: (context) => ConnectButton(
                status: const VpnStatus(VpnConnectionState.connected),
                diameter: diameter,
                onTap: () {},
              ),
            ),
          ),
          width: screen.width,
          state: state,
        ));
        await t.pump();

        expect(t.takeException(), isNull,
            reason: '${screen.width}×${screen.height}: вёрстка переполнилась');

        final rowRect =
            t.getRect(find.byKey(const ValueKey('serviceChecksSidesRow')));
        final fraction = rowRect.width / screen.width;
        expect(fraction, greaterThanOrEqualTo(minOccupiedFraction),
            reason: '${screen.width}×${screen.height}: блок «колонки + '
                'кнопка» занял только ${(fraction * 100).toStringAsFixed(1)} % '
                'ширины окна (${rowRect.width} из ${screen.width}) — похоже на '
                'прежний маленький остров посреди пустоты');

        // Кнопка при этом остаётся заявленного диаметра, а не раздувается
        // вместе с блоком — раскладка вокруг неё двигается, а не она сама.
        final buttonRect = t.getRect(find.byType(ConnectButton));
        expect(buttonRect.width, closeTo(diameter, 0.5),
            reason: '${screen.width}×${screen.height}: диаметр кнопки '
                'изменился (${buttonRect.width} вместо $diameter)');
      });
    }
  });

  group('Границы: кнопка БЕЗ подключения — только значок, без таймера', () {
    /// Не весь матрикс 11×5 — сюда крайние случаи из главной группы уже
    /// доказали структурную безопасность формулы (см. шапку файла), здесь
    /// нужно только убедиться, что БЕЗ таймера содержимое ведёт себя так же:
    /// самый тесный телефон (ряды, значок крупнее — 68, а не 56) и самое
    /// широкое окно (колонки по бокам, где работает внешний `FittedBox`).
    for (final e in [
      (screen: const Size(320, 568), layout: ServiceChecksLayout.rows),
      (screen: const Size(880, 680), layout: ServiceChecksLayout.sides),
    ]) {
      testWidgets(
          '${e.screen.width.toInt()}×${e.screen.height.toInt()} / ${e.layout.name}',
          (t) async {
        t.view.physicalSize = e.screen;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        final state = AppState(engine: _FakeEngine());
        final diameter = diameterFor(e.screen);
        final where = '${e.screen} / ${e.layout.name} (без подключения)';

        await t.pumpWidget(host(
          ConnectCenterpiece(
            serverName: null,
            httpPort: 0,
            services: ServiceChecks.catalog,
            layout: e.layout,
            button: Builder(
              builder: (context) => ConnectButton(
                status: const VpnStatus(VpnConnectionState.disconnected),
                diameter: diameter,
                onTap: () {},
              ),
            ),
          ),
          width: e.screen.width,
          state: state,
        ));
        await t.pump();

        expect(t.takeException(), isNull, reason: '$where: вёрстка переполнилась');

        final buttonRect = t.getRect(find.byType(ConnectButton));
        expect((buttonRect.width - buttonRect.height).abs(), lessThan(px),
            reason: '$where: кнопка не квадратная');

        // Таймера нет вовсе — VPN не подключен, `_UptimeLabel` не строится.
        expect(
            find.descendant(
                of: find.byType(ConnectButton), matching: find.byType(Text)),
            findsNothing,
            reason: '$where: таймер нарисовался без подключения');

        final iconRect = t.getRect(find.descendant(
            of: find.byType(ConnectButton),
            matching: find.byIcon(Icons.power_settings_new)));
        expectInside(iconRect, buttonRect, 'значок питания', where);

        final ratio = iconRect.width / buttonRect.width;
        expect(ratio, closeTo(iconRatioIdle, ratioTolerance),
            reason: '$where: значок не масштабируется вместе с кругом '
                '($ratio вместо $iconRatioIdle)');
      });
    }

    testWidgets('идёт подключение — спиннер вписан в круг, не значок',
        (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final state = AppState(engine: _FakeEngine());

      await t.pumpWidget(host(
        ConnectCenterpiece(
          serverName: null,
          httpPort: 0,
          services: ServiceChecks.catalog,
          layout: ServiceChecksLayout.rows,
          button: Builder(
            builder: (context) => ConnectButton(
              status: const VpnStatus(VpnConnectionState.connecting),
              diameter: diameterFor(const Size(320, 568)),
              onTap: () {},
            ),
          ),
        ),
        width: 320,
        state: state,
      ));
      await t.pump();

      expect(t.takeException(), isNull);
      final buttonRect = t.getRect(find.byType(ConnectButton));
      final spinnerRect = t.getRect(find.descendant(
          of: find.byType(ConnectButton),
          matching: find.byType(CircularProgressIndicator)));
      expectInside(spinnerRect, buttonRect, 'индикатор подключения',
          'подключение, 320×568');
    });
  });
}

class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();

  @override
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
