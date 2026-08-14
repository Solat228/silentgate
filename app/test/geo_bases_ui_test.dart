import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/geo/geo_bases.dart';
import 'package:silentgate/core/geo/geo_bases_controller.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/provider_wiring.dart';
import 'package:silentgate/ui/widgets/geo_bases_section.dart';

/// Интерфейс гео-баз: честность кнопки, согласие на закачку, слова вместо кода
/// в ошибке и то, что контроллер вообще создаётся.
///
/// ⚠️ В СЕТЬ НЕ ХОДИМ НИ РАЗУ. `GeoBasesController` принимает `http.Client`
/// в конструкторе, а `GeoBases` — в `check`/`download`: везде подставляется
/// [MockClient]. Каталог баз и каталог данных подменяются целиком
/// (`GeoBases.overrideDir` + `AppPaths.overrideRoot`), иначе тест писал бы в
/// боевой `engine/windows/bin` разработчика и в его `%APPDATA%`.
void main() {
  late Directory tmp;

  /// Тело, которое [GeoBases.healthOf] признаёт гео-базой: первый байт 0x0A
  /// (protobuf `repeated entry = 1`) и не меньше килобайта.
  List<int> dat(int filler) => [0x0a, ...List.filled(2047, filler & 0xff)];

  Future<void> writeBase(GeoBase b, List<int> body) async {
    final f = await GeoBases.fileOf(b);
    await f.writeAsBytes(body);
  }

  /// Положить обе базы на диск ИЗ-ПОД `testWidgets`.
  ///
  /// ⚠️ ОБЯЗАТЕЛЬНО ЧЕРЕЗ [WidgetTester.runAsync]. Тело `testWidgets` крутится
  /// в поддельном времени, и настоящая запись файла в нём не завершается
  /// НИКОГДА: `await` на ней просто висит, а тест падает по десятиминутному
  /// таймауту — без единой подсказки, где именно он встал. Проверено: ровно на
  /// этом висли четыре теста ниже.
  Future<void> seedBases(WidgetTester tester) => tester.runAsync(() async {
        await writeBase(GeoBase.geoip, dat(1));
        await writeBase(GeoBase.geosite, dat(2));
      });

  /// Сколько раз реально пошли ЗА САМИМ ФАЙЛОМ (а не за его контрольной
  /// суммой). Это и есть мера «поехал ли трафик».
  var fileGets = 0;

  MockClient client({
    required Map<GeoBase, String?> sums,
    Map<GeoBase, List<int>>? remoteBodies,
    int sumStatus = 200,
  }) =>
      MockClient((req) async {
        for (final b in GeoBase.values) {
          if (req.url.toString() == b.sumUrl) {
            final s = sums[b];
            if (s == null || sumStatus != 200) {
              return http.Response('no', sumStatus == 200 ? 404 : sumStatus);
            }
            return http.Response('$s  ${b.fileName}\n', 200);
          }
          if (req.url.toString() == b.url) {
            final body = remoteBodies?[b] ?? dat(0x33);
            // HEAD спрашивает только размер, GET — сам файл; MockClient
            // отдаёт длину тела как Content-Length в обоих случаях.
            if (req.method == 'GET') fileGets++;
            return http.Response.bytes(body, 200);
          }
        }
        return http.Response('unexpected ${req.url}', 500);
      });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_geo_ui_');
    AppPaths.overrideRoot(tmp);
    GeoBases.overrideDir(
        Directory('${tmp.path}${Platform.pathSeparator}geo'));
    fileGets = 0;
  });

  tearDown(() {
    GeoBases.resetForTests();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Состояния кнопки на настоящем контроллере ───────────────────────────
  //
  // Обычный `test`, а не `testWidgets`: там нет FakeAsync, поэтому настоящий
  // дисковый ввод-вывод отрабатывает без плясок с `runAsync`.
  group('GeoAction — четыре вида, а не два', () {
    test('файлов нет → download', () async {
      final c = GeoBasesController(client: client(sums: {}));
      await c.refresh();
      expect(c.action, GeoAction.download);
      c.dispose();
    });

    test('файлы есть, релиз не спрашивали → check (а НЕ update)', () async {
      await writeBase(GeoBase.geoip, dat(1));
      await writeBase(GeoBase.geosite, dat(2));
      final c = GeoBasesController(client: client(sums: {}));
      await c.refresh();
      expect(c.action, GeoAction.check,
          reason: 'пока сумму релиза не спросили, «Обновить» обещало бы '
              'знание, которого нет');
      c.dispose();
    });

    test('спросили релиз, там другое → update + видно что именно', () async {
      await writeBase(GeoBase.geoip, dat(1));
      await writeBase(GeoBase.geosite, dat(2));
      final c = GeoBasesController(
        client: client(
          sums: {
            GeoBase.geoip: Sha256.ofBytes(dat(9)), // не совпадает
            GeoBase.geosite: Sha256.ofBytes(dat(2)), // совпадает
          },
          remoteBodies: {GeoBase.geoip: dat(9)},
        ),
      );
      await c.refresh();
      await c.check();
      expect(c.action, GeoAction.update);
      expect(c.pending, [GeoBase.geoip]);
      expect(c.pendingBytes, 2048);
      expect(fileGets, 0, reason: 'проверка обновлений ничего не качает');
      c.dispose();
    });

    test('спросили релиз, там то же самое → upToDate', () async {
      await writeBase(GeoBase.geoip, dat(1));
      await writeBase(GeoBase.geosite, dat(2));
      final c = GeoBasesController(
        client: client(sums: {
          GeoBase.geoip: Sha256.ofBytes(dat(1)),
          GeoBase.geosite: Sha256.ofBytes(dat(2)),
        }),
      );
      await c.refresh();
      await c.check();
      expect(c.action, GeoAction.upToDate);
      expect(c.pending, isEmpty);
      c.dispose();
    });

    test('файлы удалили после успешной проверки → снова download', () async {
      await writeBase(GeoBase.geoip, dat(1));
      await writeBase(GeoBase.geosite, dat(2));
      final c = GeoBasesController(
        client: client(sums: {
          GeoBase.geoip: Sha256.ofBytes(dat(1)),
          GeoBase.geosite: Sha256.ofBytes(dat(2)),
        }),
      );
      await c.refresh();
      await c.check();
      expect(c.action, GeoAction.upToDate);
      await GeoBases.remove();
      await c.refresh();
      expect(c.action, GeoAction.download,
          reason: '«Обновлений нет» на пустом каталоге — враньё');
      c.dispose();
    });
  });

  // ── Ошибка словами ───────────────────────────────────────────────────────
  group('geoErrorKind — причина словами, а не кодом', () {
    test('нет связи', () {
      expect(
          geoErrorKind(
              "SocketException: Failed host lookup: 'github.com' (OS Error…)"),
          GeoErrorKind.network);
      expect(geoErrorKind('ClientException with SocketException'),
          GeoErrorKind.network);
    });

    test('сервер отказал', () {
      expect(geoErrorKind('HttpException: HTTP 503, uri = https://…'),
          GeoErrorKind.server);
      expect(geoErrorKind('HttpException: HTTP 404, uri = https://…'),
          GeoErrorKind.server);
    });

    test('не записать', () {
      expect(geoErrorKind('нет доступа на запись в C:\\Program Files: …'),
          GeoErrorKind.write);
      expect(
          geoErrorKind('FileSystemException: Permission denied, errno = 13'),
          GeoErrorKind.write);
    });

    test('закачка повредилась', () {
      expect(
          geoErrorKind(
              'geoip.dat: контрольная сумма не совпала — закачка повреждена'),
          GeoErrorKind.corrupt);
      expect(geoErrorKind('geoip.dat: HttpException: получено 12 из 900 байт'),
          GeoErrorKind.corrupt,
          reason: 'оборванная закачка — это повреждение, а не «нет связи»');
    });

    test('что-то ещё — не выдумываем причину', () {
      expect(geoErrorKind('FormatException: неведомое'), GeoErrorKind.other);
    });
  });

  // ── Интерфейс ────────────────────────────────────────────────────────────
  Widget host(GeoBasesController c) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChangeNotifierProvider<GeoBasesController>.value(
            value: c,
            child: const SingleChildScrollView(child: GeoBasesSection()),
          ),
        ),
      );

  /// Собрать раздел и дать отработать настоящему вводу-выводу из `initState`
  /// (проверка прав на запись в каталог).
  ///
  /// ⚠️ Под `testWidgets` дисковые операции не двигаются без [runAsync], а
  /// `pump` внутри `runAsync` запрещён — отсюда именно такой порядок.
  Future<AppLocalizations> pumpSection(
      WidgetTester tester, GeoBasesController c) async {
    await tester.pumpWidget(host(c));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(GeoBasesSection)));
  }

  group('Раздел настроек: кнопка называет то, что сделает', () {
    testWidgets('файлов нет → «Скачать»', (tester) async {
      final c = GeoBasesController(client: client(sums: {}));
      await tester.runAsync(c.refresh);
      final l = await pumpSection(tester, c);

      expect(find.text(l.geoDownload), findsOneWidget);
      expect(find.text(l.geoCheck), findsNothing);
      expect(find.text(l.geoUpdate), findsNothing);
      // Состояние файлов видно, а не только кнопка.
      expect(find.text(l.geoFileMissing), findsNWidgets(2));
      addTearDown(c.dispose);
    });

    testWidgets('файлы есть, релиз не спрашивали → «Проверить обновление»',
        (tester) async {
      await seedBases(tester);
      final c = GeoBasesController(client: client(sums: {}));
      await tester.runAsync(c.refresh);
      final l = await pumpSection(tester, c);

      expect(find.text(l.geoCheck), findsOneWidget);
      expect(find.text(l.geoUpdate), findsNothing,
          reason: 'ровно та жалоба владельца: «обновить» без знания о релизе');
      expect(find.text(l.geoNeverChecked), findsOneWidget);
      addTearDown(c.dispose);
    });

    testWidgets('есть что обновлять → «Обновить» И ВИДНО, ЧТО ИМЕННО',
        (tester) async {
      await seedBases(tester);
      final c = GeoBasesController(
        client: client(
          sums: {
            GeoBase.geoip: Sha256.ofBytes(dat(9)),
            GeoBase.geosite: Sha256.ofBytes(dat(2)),
          },
          remoteBodies: {GeoBase.geoip: dat(9)},
        ),
      );
      await tester.runAsync(c.refresh);
      await tester.runAsync(c.check);
      final l = await pumpSection(tester, c);

      expect(find.text(l.geoUpdate), findsOneWidget);
      expect(
          find.text(l.geoUpdateAvailable(
              'geoip.dat', TrafficStats.formatBytes(2048))),
          findsOneWidget,
          reason: 'состав и размер обязаны быть видны ДО нажатия');
      addTearDown(c.dispose);
    });

    testWidgets('обновлять нечего → так и сказано, ничего не изображаем',
        (tester) async {
      await seedBases(tester);
      final c = GeoBasesController(
        client: client(sums: {
          GeoBase.geoip: Sha256.ofBytes(dat(1)),
          GeoBase.geosite: Sha256.ofBytes(dat(2)),
        }),
      );
      await tester.runAsync(c.refresh);
      await tester.runAsync(c.check);
      final l = await pumpSection(tester, c);

      expect(find.text(l.geoUpToDate), findsOneWidget);
      expect(find.text(l.geoCheckAgain), findsOneWidget);
      expect(find.text(l.geoUpdate), findsNothing);
      expect(find.text(l.geoDownload), findsNothing);
      addTearDown(c.dispose);
    });
  });

  group('Скачивание — только по явному согласию', () {
    testWidgets('нажатие показывает план (что и сколько), а не качает сразу',
        (tester) async {
      final c = GeoBasesController(client: client(sums: {
        GeoBase.geoip: Sha256.ofBytes(dat(0x33)),
        GeoBase.geosite: Sha256.ofBytes(dat(0x33)),
      }));
      await tester.runAsync(c.refresh);
      // Проверку делаем заранее: тогда нажатие ведёт прямо к плану, без
      // дискового ввода-вывода внутри такта интерфейса.
      await tester.runAsync(c.check);
      final l = await pumpSection(tester, c);
      expect(fileGets, 0);

      // ⚠️ НЕ `pumpAndSettle`: пока идёт работа, раздел рисует бесконечную
      // полоску (`LinearProgressIndicator`), и «дождаться покоя» здесь значит
      // ждать вечно — десятиминутный таймаут вместо падения по существу.
      await tester.tap(find.text(l.geoDownload));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l.geoPlanTitle), findsOneWidget);
      expect(find.text(l.geoPlanFiles('geoip.dat, geosite.dat')),
          findsOneWidget);
      expect(find.text(l.geoPlanSize(TrafficStats.formatBytes(4096))),
          findsOneWidget);
      expect(fileGets, 0, reason: 'план показан — ни одного байта ещё не ушло');

      await tester.tap(find.text(l.commonCancel));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(c.outcome, GeoOutcome.declined);
      expect(fileGets, 0,
          reason: 'отказ обязан означать, что закачка НЕ началась');
      addTearDown(c.dispose);
    });

    test('согласие — и только оно — запускает закачку', () async {
      final body = dat(0x33);
      final c = GeoBasesController(client: client(sums: {
        GeoBase.geoip: Sha256.ofBytes(body),
        GeoBase.geosite: Sha256.ofBytes(body),
      }));
      await c.refresh();

      expect(await c.download(confirm: (_) async => false), isFalse);
      expect(fileGets, 0);
      expect(c.outcome, GeoOutcome.declined);

      expect(await c.download(confirm: (_) async => true), isTrue);
      expect(fileGets, 2);
      expect(c.outcome, GeoOutcome.downloaded);
      expect(c.status!.ready, isTrue);
      c.dispose();
    });
  });

  group('Ход и отказ показываются, а не замалчиваются', () {
    testWidgets('во время закачки — полоска и объём, кнопки нет',
        (tester) async {
      final c = _FakeGeo(
        busy: true,
        progress: const GeoProgress(
            base: GeoBase.geoip,
            received: 5 * 1024 * 1024,
            total: 10 * 1024 * 1024,
            index: 0,
            count: 2),
      );
      final l = await pumpSection(tester, c);

      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.5, 0.001));
      expect(
          find.text(l.geoProgressBytes(
              TrafficStats.formatBytes(5 * 1024 * 1024),
              TrafficStats.formatBytes(10 * 1024 * 1024))),
          findsOneWidget);
      expect(find.byType(FilledButton), findsNothing,
          reason: 'молчащая кнопка на минуту хуже отсутствующей');
      addTearDown(c.dispose);
    });

    testWidgets('отказ сервера объяснён словами, код — отдельной строкой',
        (tester) async {
      await seedBases(tester);
      final c = GeoBasesController(
          client: client(sums: {GeoBase.geoip: 'x'}, sumStatus: 503));
      await tester.runAsync(c.refresh);
      await tester.runAsync(c.check);
      final l = await pumpSection(tester, c);

      expect(find.text(l.geoErrorServer), findsOneWidget);
      expect(find.textContaining('503'), findsAtLeastNWidgets(1),
          reason: 'исходный текст нужен поддержке, но не вместо объяснения');
      expect(find.text(l.geoCheck), findsOneWidget,
          reason: 'неудачная проверка не превращается в «обновлений нет»');
      addTearDown(c.dispose);
    });
  });

  // ── Контроллер обязан существовать ───────────────────────────────────────
  group('Провайдер строится БЕЗ единого чтения своего типа', () {
    testWidgets('geoBasesProvider: контроллер создан и прочитал каталог',
        (tester) async {
      var built = false;
      final refreshed = Completer<void>();
      GeoBasesController? made;

      final tree = MultiProvider(
        providers: [
          // ⚠️ ТА ЖЕ функция, что уходит в боевой `runApp` из `main.dart`, а
          // не её копия: уберут `lazy: false` там — покраснеет здесь.
          geoBasesProvider(create: () {
            built = true;
            final c = GeoBasesController(client: client(sums: {}));
            c.addListener(() {
              if (!refreshed.isCompleted) refreshed.complete();
            });
            made = c;
            return c;
          }),
        ],
        // ⚠️ Дерево НИЧЕГО не читает: в этом весь смысл. С ленивым провайдером
        // `create` не позвался бы никогда, и раздел гео-баз оставался бы
        // пустым до первого чтения — тем же способом в 1.4.0 умер локальный API.
        child: const SizedBox.shrink(),
      );

      expect(built, isFalse, reason: 'база для сравнения');
      await tester.pumpWidget(tree);
      expect(built, isTrue);

      // Ждём КОНЦА refresh(), а не «немного»: иначе фоновая цепочка резолвила
      // бы каталог уже после `AppPaths.resetForTests()` в tearDown.
      //
      // ⚠️ ЖДЁМ ЧЕРЕДОВАНИЕМ `runAsync` + `pump`, А НЕ `runAsync(future)`.
      // `refresh()` запущен ВНУТРИ поддельного времени (его завёл `create`
      // провайдера), поэтому его продолжения дремлют в очереди микрозадач
      // теста и разбираются только на `pump`; а само дисковое чтение движется
      // только внутри `runAsync`. Одно без другого — вечное ожидание: голый
      // `await tester.runAsync(() => refreshed.future)` вешал этот тест на все
      // десять минут таймаута.
      for (var i = 0; i < 200 && !refreshed.isCompleted; i++) {
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(refreshed.isCompleted, isTrue,
          reason: 'refresh() обязан досчитать ДО сброса подменного каталога');
      expect(made!.status, isNotNull,
          reason: 'создание без refresh() дало бы «живой», но слепой контроллер');
      expect(made!.status!.dirPath, contains('geo'));
    });
  });
}

/// Контроллер с заданным состоянием: ход закачки настоящей сетью не
/// воспроизвести, а показать полоску нужно.
class _FakeGeo extends GeoBasesController {
  _FakeGeo({bool busy = false, GeoProgress? progress})
      : _busy = busy,
        _progress = progress;

  final bool _busy;
  final GeoProgress? _progress;

  @override
  bool get busy => _busy;

  @override
  bool get checking => false;

  @override
  GeoProgress? get progress => _progress;
}
