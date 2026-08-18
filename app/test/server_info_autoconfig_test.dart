import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/i18n/enum_labels.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';
import 'package:silentgate/data/results_store.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/ui/widgets/server_autoconfig_card.dart';

/// Блок автонастройки в карточке сервера (п.4 владельца, 17.08.2026).
///
/// Прогон автонастройки уже знал про каждый сервер, ЧТО через него работает, и
/// хранил это между запусками (`ResultsStore.autoConfig`), но на экране
/// «Информация о сервере» этих данных не было вовсе.
///
/// ⚠️ Главное, что стережёт этот файл, — ТРЕТЬЕ состояние сервиса. Мишень из
/// `CandidateResult.geoBlocked` открывается через сервер, но недоступна в
/// стране его выхода: зелёный обманул бы того, кто искал именно ChatGPT, а
/// красный оболгал бы исправный сервер. Проверяем не «блок нарисовался», а что
/// геоблок ОТЛИЧИМ и от прошедшего, и от непрошедшего.
void main() {
  final l = AppLocalizationsRu();

  const linkA = 'vless://00000000-0000-0000-0000-000000000000@a.example:443'
      '?type=tcp&security=none#Alpha';
  const linkB = 'vless://11111111-1111-1111-1111-111111111111@b.example:443'
      '?type=tcp&security=none#Bravo';

  late Directory tmp;

  setUp(() {
    // ⚠️ Свой каталог данных обязателен: под FLUTTER_TEST боевой `%APPDATA%`
    // не отдаётся вовсе — предохранитель поставлен после того, как тест
    // переписал `subscriptions.json` владельца.
    tmp = Directory.systemTemp.createTempSync('sg_srvinfo_ac_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() {
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  VpnServer server(String link) => ShareLinkParser.tryParse(link)!;

  AutoConfigResult result(
    VpnServer s, {
    Map<ProbeService, bool> passed = const {},
    Set<ProbeService> geoBlocked = const {},
    double? mbps,
    int? sharePercent,
  }) {
    const variant = OutboundVariant(fragment: true);
    return AutoConfigResult(
      server: s,
      variant: variant,
      detail: CandidateResult(
        server: s,
        variant: variant,
        passed: passed,
        avgLatencyMs: 120,
        geoBlocked: geoBlocked,
      ),
      measuredAt: DateTime.now().subtract(const Duration(minutes: 5)),
      mbps: mbps,
      sharePercent: sharePercent,
    );
  }

  /// Контроллер, поднятый ИЗ ХРАНИЛИЩА, а не набитый руками: именно этим путём
  /// данные попадают в приложение после перезапуска, и проверять надо его.
  Future<AutoConfigController> controllerWith(
      List<AutoConfigResult> found) async {
    await ResultsStore.autoConfig.save([for (final r in found) r.toJson()]);
    final ctrl = AutoConfigController();
    await ctrl.init();
    return ctrl;
  }

  Widget host(AutoConfigController ctrl, VpnServer s) =>
      ChangeNotifierProvider<AutoConfigController>.value(
        value: ctrl,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServerAutoConfigCard(server: s),
            ),
          ),
        ),
      );

  /// Значок состояния в плашке сервиса — то, чем состояния и различаются на
  /// экране. Берём по ключу: рядом стоит бренд-иконка, а у сервиса без
  /// скачанного фавикона она тоже `Icon` (глобус-заглушка).
  IconData iconOf(WidgetTester tester, ProbeService s) => tester
      .widget<Icon>(find.byKey(Key('srvInfoAcState-${s.name}')))
      .icon!;

  group('Блок появляется только при сохранённом результате', () {
    testWidgets('прогона по этому серверу не было — честная строка, не пустота',
        (tester) async {
      late AutoConfigController ctrl;
      // Результат есть, но ПО ДРУГОМУ серверу: заодно ловим поиск по имени
      // вместо ключа — у владельца четыре подписки с одинаковыми названиями.
      await tester.runAsync(() async {
        ctrl = await controllerWith([
          result(server(linkB), passed: const {ProbeService.youtube: true}),
        ]);
      });

      await tester.pumpWidget(host(ctrl, server(linkA)));
      await tester.pump();

      expect(find.byKey(const Key('srvInfoAutoNone')), findsOneWidget);
      expect(find.text(l.srvInfoAutoNever), findsOneWidget);
      expect(find.byKey(const Key('srvInfoAcSvc-youtube')), findsNothing,
          reason: 'чужой замер в карточке сервера — это ложь про сервер');
      expect(find.byKey(const Key('srvInfoAutoVariant')), findsNothing);
    });

    testWidgets('результат есть — дата замера, вариация и плашки сервисов',
        (tester) async {
      late AutoConfigController ctrl;
      await tester.runAsync(() async {
        ctrl = await controllerWith([
          result(server(linkA), passed: const {
            ProbeService.youtube: true,
            ProbeService.chatgpt: true,
            ProbeService.discord: false,
          }),
        ]);
      });

      await tester.pumpWidget(host(ctrl, server(linkA)));
      await tester.pump();

      expect(find.byKey(const Key('srvInfoAutoNone')), findsNothing);
      expect(find.text(l.srvInfoAutoHint), findsOneWidget);
      // Момент замера — общим форматом приложения, а не своей копией.
      expect(find.text(l.pingMeasuredAt(l.momentMinutesAgo(5))), findsOneWidget);
      expect(
          find.text(l.autoVariant(
              outboundVariantLabel(l, const OutboundVariant(fragment: true)))),
          findsOneWidget);

      for (final s in [
        ProbeService.youtube,
        ProbeService.chatgpt,
        ProbeService.discord,
      ]) {
        expect(find.byKey(Key('srvInfoAcSvc-${s.name}')), findsOneWidget,
            reason: 'сервис ${s.label} проверялся — он обязан быть на экране');
      }
      // Мишени, которых в прогоне не было, не выдумываем.
      expect(find.byKey(const Key('srvInfoAcSvc-telegram')), findsNothing);
    });
  });

  group('Геоблок — своё состояние, а не «зелёный» и не «красный»', () {
    testWidgets('три сервиса — три разных значка и пояснение к геоблоку',
        (tester) async {
      late AutoConfigController ctrl;
      await tester.runAsync(() async {
        ctrl = await controllerWith([
          result(
            server(linkA),
            passed: const {
              ProbeService.youtube: true,
              ProbeService.chatgpt: true,
              ProbeService.discord: false,
            },
            // ChatGPT ОТВЕТИЛ (passed == true), но регион не поддерживается.
            geoBlocked: const {ProbeService.chatgpt},
          ),
        ]);
      });

      await tester.pumpWidget(host(ctrl, server(linkA)));
      await tester.pump();

      final ok = iconOf(tester, ProbeService.youtube);
      final geo = iconOf(tester, ProbeService.chatgpt);
      final fail = iconOf(tester, ProbeService.discord);

      // ⚠️ ГЛАВНАЯ ПРОВЕРКА ФАЙЛА. До этой правки геоблок нигде в карточке не
      // жил, а самый вероятный способ «добавить его быстро» — показать как
      // обычный пройденный сервис: `passed[chatgpt] == true`, и зелёная
      // галочка получается сама собой. Тогда владелец, искавший ChatGPT,
      // выбрал бы по карточке сервер, на котором ChatGPT не работает.
      expect(geo, isNot(ok),
          reason: 'геоблок нельзя показывать как прошедший сервис');
      expect(geo, isNot(fail),
          reason: 'сервер исправен — красный оболгал бы его целиком');
      expect(ok, isNot(fail));

      // Одного цвета мало: он говорит «что-то не так», но не говорит, менять
      // сервер или сервис.
      expect(find.byKey(const Key('srvInfoAutoGeo')), findsOneWidget);
      expect(find.text(l.srvInfoAutoGeoNote('ChatGPT')), findsOneWidget);
    });

    testWidgets('без геоблока пояснения нет', (tester) async {
      late AutoConfigController ctrl;
      await tester.runAsync(() async {
        ctrl = await controllerWith([
          result(server(linkA),
              passed: const {ProbeService.youtube: true}),
        ]);
      });

      await tester.pumpWidget(host(ctrl, server(linkA)));
      await tester.pump();

      expect(find.byKey(const Key('srvInfoAutoGeo')), findsNothing,
          reason: 'плашка без повода пугает на ровном месте');
      expect(iconOf(tester, ProbeService.youtube), Icons.check_circle);
    });
  });

  group('Скорость показывается только когда её мерили', () {
    testWidgets('замер есть — мегабайты и доля своего канала', (tester) async {
      late AutoConfigController ctrl;
      await tester.runAsync(() async {
        ctrl = await controllerWith([
          result(server(linkA),
              passed: const {ProbeService.youtube: true},
              mbps: 42.5,
              sharePercent: 80),
        ]);
      });

      await tester.pumpWidget(host(ctrl, server(linkA)));
      await tester.pump();

      final text =
          tester.widget<Text>(find.byKey(const Key('srvInfoAutoSpeed'))).data!;
      // 42,5 Мбит/с хранения = 5,3 МБ/с показа: пишем мегабайты, храним
      // мегабиты (см. ServerSpeed.megabytesPerSecond).
      expect(text, contains('5.3'));
      // ⚠️ Доля канала обязательна рядом со скоростью: 5 МБ/с — это отлично
      // на канале 50 и скверно на канале 300.
      expect(text, contains(l.autoSpeedShare(80)));
    });

    testWidgets('замера не было — строки скорости нет', (tester) async {
      late AutoConfigController ctrl;
      await tester.runAsync(() async {
        ctrl = await controllerWith([
          result(server(linkA), passed: const {ProbeService.youtube: true}),
        ]);
      });

      await tester.pumpWidget(host(ctrl, server(linkA)));
      await tester.pump();

      expect(find.byKey(const Key('srvInfoAutoSpeed')), findsNothing,
          reason: 'нулевая скорость и «не мерили» — разные новости');
    });
  });

  group('Выбор записи — по ключу и по свежести', () {
    test('чужой сервер не отдаётся', () {
      final a = server(linkA);
      final b = server(linkB);
      expect(ServerAutoConfigCard.resultFor([result(b)], a), isNull);
      expect(ServerAutoConfigCard.resultFor([result(b), result(a)], a)?.server.key,
          a.key);
    });

    test('первая запись по ключу и есть самая свежая', () {
      // `AutoConfigController.start` кладёт итог свежего прогона В НАЧАЛО
      // списка. Порядок — единственный признак свежести, который у нас есть.
      final a = server(linkA);
      final fresh = result(a, mbps: 99);
      final stale = result(a, mbps: 1);
      expect(ServerAutoConfigCard.resultFor([fresh, stale], a)?.mbps, 99);
    });
  });
}
