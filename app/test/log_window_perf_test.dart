import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/app.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/core/platform/log_work_counters.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/log_line_style.dart';
import 'package:silentgate/ui/logs_screen.dart';

/// СТОРОЖ СТОИМОСТИ КАДРА — И ЭТОТ, В ОТЛИЧИЕ ОТ ПРЕЖНЕГО, ДЕЙСТВИТЕЛЬНО
/// КРАСНЕЕТ.
///
/// ⚠️ ЧТО БЫЛО НЕ ТАК С ПРЕЖНИМ. Он крутил пять `tester.pump(16 мс)` и
/// сравнивал счётчик разобранных строк до и после. Пустой `pump` НЕ помечает
/// виджет грязным: `build()` не выполнялся ВООБЩЕ, счётчик не двигался, и тест
/// был зелен при ЛЮБОЙ стоимости кадра — в том числе при возврате разбора всего
/// буфера в каждый кадр, ради чего он и был написан. Здесь виджет помечается
/// грязным явно (`markNeedsBuild`), а первым утверждением каждого замера идёт
/// ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: «кадр действительно построен, работа действительно
/// выполнена».
///
/// ⚠️ НИ ОДНОГО УТВЕРЖДЕНИЯ «УЛОЖИЛИСЬ В N МИЛЛИСЕКУНД». Абсолютные
/// миллисекунды под headless-движком `flutter_test` и на живой машине разные.
/// Утверждаются только ОТНОШЕНИЯ, измеренные в одном процессе, и структурные
/// факты: сколько строк разобрано, сколько спанов в дереве, сколько РАЗНЫХ
/// объектов `TextStyle`, сколько раз спросили систему о часовом поясе.
void main() {
  late Directory tmp;
  late String appLogPath;
  late String tunLogPath;

  final light = buildAppTheme(Brightness.light);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_window_');
    AppPaths.overrideRoot(tmp);
    appLogPath = '${tmp.path}${Platform.pathSeparator}app.log';
    tunLogPath = '${tmp.path}${Platform.pathSeparator}singbox.log';
    await AppLog.useFileForTest(appLogPath);
    LogsScreen.debugSkipInitialLoad = true;
    registerPlatformServices(PlatformServices(
      appCatalog: _FakeAppCatalog(),
      appIcons: _FakeAppIcons(),
      coreVersions: _FakeCoreVersions(),
      tunLog: _FakeTunLog(tunLogPath),
      privileges: _FakePrivileges(),
      support: _FakeSupport(),
    ));
  });

  tearDown(() async {
    LogsScreen.debugSkipInitialLoad = false;
    await AppLog.resetFileForTest();
    AppPaths.resetForTests();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Widget host() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<SettingsController>(
          create: (_) => SettingsController(),
          child: const LogsScreen(),
        ),
      );

  String corpus(int lines) {
    final b = StringBuffer();
    for (var i = 0; i < lines; i++) {
      // Смесь: наш формат, формат ядра со смещением зоны и кадр стека.
      switch (i % 3) {
        case 0:
          b.writeln('04.08.2026 01:23:33 [INFO] строка $i');
          break;
        case 1:
          b.writeln('+0700 2026-08-11 02:09:08 INFO router: строка $i');
          break;
        default:
          b.writeln('#$i      main (package:silentgate/main.dart:52:5)');
      }
    }
    return b.toString();
  }

  /// Один КАДР, построенный по-настоящему: виджет помечается грязным, иначе
  /// `pump()` не вызовет `build()` вовсе (см. шапку файла).
  Future<_FrameCost> measureFrame(WidgetTester tester) async {
    final parsed = LogWorkCounters.parsedLines;
    final spans = LogWorkCounters.builtSpans;
    final zone = LogWorkCounters.zoneLookups;
    final tidy = LogWorkCounters.tidyCalls;
    tester.element(find.byType(LogsScreen)).markNeedsBuild();
    await tester.pump();
    return _FrameCost(
      parsed: LogWorkCounters.parsedLines - parsed,
      spans: LogWorkCounters.builtSpans - spans,
      zone: LogWorkCounters.zoneLookups - zone,
      tidy: LogWorkCounters.tidyCalls - tidy,
    );
  }

  int spansInTree(WidgetTester tester) {
    var n = 0;
    tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .visitChildren((s) {
      n++;
      return true;
    });
    return n;
  }

  Future<_FrameCost> costForFile(WidgetTester tester, int lines) async {
    await tester.runAsync(
        () => File(appLogPath).writeAsString(corpus(lines), flush: true));
    await tester.pumpWidget(host());
    await tester.runAsync(() => LogsScreen.debugPollOnce!());
    await tester.pump();
    return measureFrame(tester);
  }

  group('⚠️ Стоимость кадра не зависит от размера буфера', () {
    testWidgets('50 000 строк и 200 000 строк стоят кадру ОДИНАКОВО',
        (tester) async {
      final small = await costForFile(tester, 50000);
      await tester.pumpWidget(const SizedBox());

      // ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ №1: кадр действительно построен и работа
      // действительно сделана. Без этой пары строк весь тест — пустышка.
      expect(small.parsed, greaterThan(0),
          reason: 'markNeedsBuild обязан был вызвать build(); если здесь ноль, '
              'значит тест снова ничего не измеряет');
      expect(small.spans, greaterThan(0));

      final big = await costForFile(tester, 200000);
      expect(big.parsed, small.parsed,
          reason: 'в кадре разбирается ОКНО, а не буфер: вчетверо больший файл '
              'обязан стоить кадру ровно столько же');
      expect(big.spans, small.spans);

      // ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ №2: тот же разбор по ВСЕМУ буферу (как было до
      // окна) действительно стоит на два порядка дороже — значит равенство
      // выше добыто окном, а не тем, что счётчик сломан.
      late String fileText;
      await tester.runAsync(
          () async => fileText = await File(appLogPath).readAsString());
      final before = LogWorkCounters.parsedLines;
      buildLogSpan(fileText, light, localZoneOffset: Duration.zero);
      final whole = LogWorkCounters.parsedLines - before;
      expect(whole, greaterThan(big.parsed * 50),
          reason: 'контроль: разбор всего буфера обязан быть дорогим');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('спанов в абзаце — константа окна, а не доля файла',
        (tester) async {
      await costForFile(tester, 50000);
      final small = spansInTree(tester);
      await tester.pumpWidget(const SizedBox());

      await costForFile(tester, 200000);
      final big = spansInTree(tester);

      expect(small, greaterThan(0), reason: 'контроль: спаны в дереве есть');
      expect(big, small,
          reason: 'ЗДЕСЬ БЫЛО 209 971 СПАНОВ В ОДНОМ АБЗАЦЕ: раскладка такого '
              'абзаца стоила от 2 секунд до минуты на кадр');
      expect(big, lessThan(6000),
          reason: 'колено раскладки намерено на 6 583 спанах — окно обязано '
              'сидеть под ним');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ зону спрашиваем у системы РАЗ на проход, а не на строку',
        (tester) async {
      // ⚠️ ИМЕННО НА ВКЛАДКЕ «TUN»: только там разбирается формат ядра, а
      // смещение зоны спрашивается только для него. Замерь мы вкладку
      // «Приложение» — счётчик стоял бы на нуле по совсем другой причине, и
      // тест был бы зелен при любой цене.
      await tester.runAsync(
          () => File(tunLogPath).writeAsString(corpus(50000), flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugPollOnce!());
      await tester.pump();
      final l = AppLocalizations.of(tester.element(find.byType(LogsScreen)));
      await tester.tap(find.text(l.logsTabTun));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final cost = await measureFrame(tester);
      expect(cost.parsed, greaterThan(0), reason: 'контроль: кадр построен');
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText();
      expect(text, contains('[INFO] router:'),
          reason: 'контроль: в окне ЕСТЬ строки формата ядра — иначе зону '
              'спрашивать не для чего, и ноль ниже ничего не значит');
      expect(cost.zone, lessThanOrEqualTo(1),
          reason: 'DateTime.now().timeZoneOffset — системный вызов ценой '
              '~3.7 мкс; на строку это было 224-230 мс из 447 мс кадра');

      // ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: счётчик рабочий — без переданного смещения
      // каждая строка формата ядра идёт к системе сама.
      const core = '+0700 2026-08-11 02:09:08 INFO router: тест';
      final before = LogWorkCounters.zoneLookups;
      for (var i = 0; i < 100; i++) {
        parseLogLine(core);
      }
      expect(LogWorkCounters.zoneLookups - before, 100,
          reason: 'контроль: счётчик zoneLookups действительно считает');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ tidySingboxLog в кадре не участвует вовсе', (tester) async {
      await tester.runAsync(() async {
        await File(appLogPath).writeAsString(corpus(200), flush: true);
        await File(tunLogPath).writeAsString(corpus(200), flush: true);
      });
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugPollOnce!());
      await tester.pump();
      final l = AppLocalizations.of(tester.element(find.byType(LogsScreen)));
      await tester.tap(find.text(l.logsTabTun));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final cost = await measureFrame(tester);
      expect(cost.parsed, greaterThan(0), reason: 'контроль: кадр построен');
      expect(cost.tidy, 0,
          reason: 'причёсывание лога ядра — самое дорогое, что стояло в '
              'кадре: split + две регулярки + join по всему буферу');

      // ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: счётчик рабочий — «Копировать» его двигает,
      // потому что копия причёсывается ровно так же, как отчёт поддержки.
      final before = LogWorkCounters.tidyCalls;
      await tester.runAsync(() async {
        await tester.tap(find.text(l.logsCopy));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(LogWorkCounters.tidyCalls, greaterThan(before),
          reason: 'контроль: счётчик tidyCalls действительно считает');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ спан собирается только для ВИДИМОЙ вкладки', (tester) async {
      // Открыта вкладка «Приложение»; лог ядра сперва пуст, потом полон.
      // Начни скрытая вкладка разбираться — стоимость кадра удвоится.
      await tester.runAsync(
          () => File(appLogPath).writeAsString(corpus(3000), flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugPollOnce!());
      await tester.pump();

      final alone = await measureFrame(tester);
      expect(alone.parsed, greaterThan(0), reason: 'контроль: кадр построен');
      expect(spansInTree(tester), greaterThan(0));

      await tester.runAsync(() async {
        await File(tunLogPath).writeAsString(corpus(3000), flush: true);
        await LogsScreen.debugPollOnce!();
      });
      await tester.pump();

      final both = await measureFrame(tester);
      expect(both.parsed, alone.parsed,
          reason: 'скрытая вкладка не должна разбираться вовсе: в build() '
              'экрана собирались спаны ОБЕИХ, а раскладывалась одна — '
              'половина кадра уходила в никуда');

      // И наоборот: переключились — считается ТА вкладка, что видна.
      await tester.tap(find.text(
          AppLocalizations.of(tester.element(find.byType(LogsScreen)))
              .logsTabTun));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final tun = await measureFrame(tester);
      expect(tun.parsed, alone.parsed,
          reason: 'вкладка «TUN» полна тем же числом строк');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('окно показывает ХВОСТ: последние строки на экране, первых нет',
        (tester) async {
      await costForFile(tester, 50000);
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText();
      expect(text, contains('строка 49998'),
          reason: 'конец лога — то, ради чего экран и открывают');
      expect(text.contains('строка 0\n'), isFalse,
          reason: 'голова окна срезана — иначе окна нет');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('⚠️ Объектов стиля — единицы на тему, а не по одному на строку', () {
    test('в собранном спане не больше 18 РАЗНЫХ объектов TextStyle', () {
      final lines = List.generate(
          3000, (i) => '04.08.2026 01:23:33 [INFO] строка $i');
      final span = buildLogSpanForLines(lines, light,
          localZoneOffset: Duration.zero);
      final distinct = Set<TextStyle>.identity();
      span.visitChildren((s) {
        if (s is TextSpan && s.style != null) distinct.add(s.style!);
        return true;
      });
      expect(distinct.length, greaterThan(0), reason: 'контроль: стили есть');
      expect(distinct.length, lessThanOrEqualTo(18),
          reason: 'свежий TextStyle на каждую строку стоил ×2.4 на раскладке: '
              '1 МиБ = 801-835 мс общим объектом против 1961-2005 мс своим');
    });

    test('⚠️ ключ таблицы — сама тема, а не её яркость', () {
      // Смена seed-цвета яркость НЕ меняет; ключ по `brightness` отдавал бы
      // цвета от прошлой темы — молча и навсегда.
      final light2 = buildAppTheme(Brightness.light);
      final dark = buildAppTheme(Brightness.dark);

      final a = logMessageStyle(LogSeverity.info, light);
      expect(identical(logMessageStyle(LogSeverity.info, light), a), isTrue,
          reason: 'на той же теме объект обязан переиспользоваться');
      expect(identical(logMessageStyle(LogSeverity.info, light2), a), isFalse,
          reason: 'другая ThemeData — другая таблица');
      expect(logMessageStyle(LogSeverity.error, dark).color,
          dark.colorScheme.error,
          reason: 'и цвета от НОВОЙ темы, а не от запомненной');
    });

    test('время и зона идут ОДНИМ спаном, а не двумя', () {
      // Стиль у них один и тот же — второй спан был бы лишним узлом
      // раскладки задаром.
      final span = buildLogSpanForLines(
          ['+0700 2026-08-11 02:09:08 INFO router: тест'], light,
          localZoneOffset: Duration.zero);
      final texts = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.text != null) texts.add(s.text!);
        return true;
      });
      expect(texts.first, '11.08.2026 02:09:08 +0700 ',
          reason: 'метка времени и смещение зоны — один спан');
      expect(texts, hasLength(3), reason: 'время+зона, уровень, сообщение');
    });
  });
}

class _FrameCost {
  const _FrameCost({
    required this.parsed,
    required this.spans,
    required this.zone,
    required this.tidy,
  });
  final int parsed;
  final int spans;
  final int zone;
  final int tidy;
}

class _FakeAppCatalog implements AppCatalog {
  @override
  Future<List<CatalogApp>> list() async => [];
  @override
  bool get supportsManualPick => false;
  @override
  String? cachedLabel(String key) => null;
  @override
  Future<String?> labelFor(String key) async => null;
}

class _FakeAppIcons implements AppIconLoader {
  @override
  Uint8List? cached(String key) => null;
  @override
  bool isCached(String key) => false;
  @override
  Future<Uint8List?> load(String key) async => null;
}

class _FakeCoreVersions implements CoreVersionInfo {
  @override
  Future<String> xray() async => 'test';
}

class _FakeTunLog implements TunLogReader {
  _FakeTunLog(this.path);
  final String path;

  @override
  Future<String> tail({int lines = 400}) async {
    final f = File(path);
    if (!await f.exists()) return '';
    final all = const LineSplitter().convert(await f.readAsString());
    return all.length <= lines
        ? all.join('\n')
        : all.sublist(all.length - lines).join('\n');
  }

  @override
  Future<String> filePath() async => path;
}

class _FakePrivileges implements PrivilegeSetup {
  @override
  bool get isApplicable => false;
  @override
  Future<bool> isConfigured() async => true;
  @override
  Future<bool> configure() async => true;
  @override
  Future<bool> remove() async => true;
}

class _FakeSupport implements SupportReporter {
  @override
  Future<String> generate(
          {required AppSettings settings, required SupportContext ctx}) =>
      Future.value('');
  @override
  Future<void> reveal(String path) async {}
}
