import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/windows/support_report.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/logs_screen.dart';

/// ГЛАВНЫЙ СТРАЖ ЗАДАНИЯ 4.2: КРАСИВЫЙ ПОКАЗ НЕ ПИШЕТ В ЖУРНАЛ НИ ОДНОГО
/// СИМВОЛА — И НЕ УРЕЗАЕТ ТО, ЧТО УХОДИТ ПОДДЕРЖКЕ.
///
/// Владелец сформулировал требование дословно: «преобразование в красивые логи
/// должно происходить не добавлением в логи пометок в текст», и «поддержке логи
/// уходят нормальными». То есть файл, который уезжает в чат поддержки, обязан
/// остаться ровно таким, каким его написали, — а вся красота живёт в отрисовке.
///
/// ⚠️ СВЕРКА ПОБАЙТНАЯ, А НЕ СТРОКОВАЯ. Строковая прошла бы через
/// `utf8.decode(..., allowMalformed: true)` и скрыла бы ровно ту порчу, ради
/// которой сверка и делается.
///
/// ⚠️ И СВЕРЯЕМСЯ С БАЙТАМИ ФАЙЛА, А НЕ С ДАРТОВОЙ КОНСТАНТОЙ. Прежняя
/// редакция сравнивала копию с константой `cleanApp`, подобранной так, что обе
/// ломающие равенство операции оказывались пустыми: ни одного ESC-байта, ни
/// одного зарегистрированного адреса. Такой тест зелен и тогда, когда снятие
/// ANSI и маскировка адресов удалены вовсе. Здесь образец ГРЯЗНЫЙ, адрес
/// [node] — зарегистрированный, и эталон читается из файла ПОСЛЕ показа.
///
/// ⚠️ ПОЛОЖИТЕЛЬНАЯ ПОЛОВИНА ДОКАЗАТЕЛЬСТВА ЖИВЁТ ЗДЕСЬ ЖЕ, и это не
/// формальность: «файл не изменился» проходит и тогда, когда на экране не
/// нарисовано ВООБЩЕ НИЧЕГО. Удалить одну половину, оставив другую, должно
/// бросаться в глаза.
///
/// Стоимость кадра стережёт отдельный файл — `log_window_perf_test.dart`.
void main() {
  late Directory tmp;
  late String appLogPath;
  late String tunLogPath;

  final esc = String.fromCharCode(0x1b);
  final localZone = formatZoneOffset(DateTime.now().timeZoneOffset);

  /// ⚠️ ТОЛЬКО TEST-NET (RFC 5737). Настоящих адресов ни в коде, ни в
  /// тестах не пишем; этот адрес РЕГИСТРИРУЕТСЯ в реестре — иначе проверка
  /// маскировки снова прошла бы по пустому месту.
  const node = '198.51.100.7';

  /// Образец НАШЕГО журнала — чистый UTF-8 без управляющих байт и без
  /// зарегистрированных адресов: на нём проверяется, что отчёт вкладывает файл
  /// знак в знак.
  const cleanApp = '04.08.2026 01:23:33 [INFO] подписка получена, серверов 12\n'
      '04.08.2026 01:23:34 [DEBUG] пинг узла адрес №3:443 — 87 мс\n'
      '04.08.2026 01:23:35 [WARN] сервер не ответил\n'
      '04.08.2026 01:23:36 [ERROR] Ошибка: не удалось подключиться\n'
      '#0      main (package:silentgate/main.dart:52:5)\n'
      '  … ещё 4 строк\n'
      '2026-08-04T01:23:37.123456 строка старого формата\n'
      'чужая строка второй копии приложения\n';

  /// Образец со ВСЕМИ ловушками сразу: ESC-байты (в `app.log` они попадают
  /// вместе с сырым хвостом вывода ядра, `engine_base.dart:1697`), НУЛЕВОЙ байт
  /// (уже случавшаяся порча файла, её считает `AppLog.statOf`), заведомо битый
  /// байт чужой кодировки, ОТКРЫТЫЙ адрес узла и строки формата ЯДРА внутри
  /// тела нашей записи — ровно так их пишет `engine_base.onCoreDied`.
  Uint8List dirtyApp() {
    final b = BytesBuilder();
    b.add(utf8.encode(cleanApp));
    b.add(utf8.encode('04.08.2026 01:23:38 [ERROR] $esc[31mсбой$esc[0m\n'));
    b.add(utf8.encode('04.08.2026 01:23:39 [INFO] байт чужой кодировки: '));
    b.addByte(0x82);
    b.add(utf8.encode('\n'));
    b.add(utf8.encode('04.08.2026 01:23:40 [INFO] нулевой байт: '));
    b.addByte(0x00);
    b.add(utf8.encode('\n'));
    b.add(utf8.encode('04.08.2026 01:23:41 [ERROR] Последние строки вывода '
        'sing-box:\n'));
    b.add(utf8.encode('+0700 2026-08-11 02:09:08 ERROR dial tcp $node:443\n'));
    return b.toBytes();
  }

  /// Лог ядра: наши служебные строки, сырой формат sing-box с ANSI, строка
  /// харнесса вообще без метки времени, наш отказ БЕЗ префикса «--- » и строка
  /// с ОТКРЫТЫМ адресом узла — та самая, которой в логе ядра больше всего.
  String coreFixture() => '--- запуск sing-box 2026-08-11T02:09:10.184221: '
      'sing-box.exe run -c config.json\n'
      '$localZone 2026-08-11 02:09:08 $esc[36mINFO$esc[0m router: тест\n'
      '$localZone 2026-08-11 02:09:09 $esc[31mERROR$esc[0m dial failed\n'
      '$localZone 2026-08-11 02:09:11 ERROR dial tcp $node:443: i/o timeout\n'
      'warn found 0 outbounds\n'
      'НЕ УДАЛОСЬ ЗАПУСТИТЬ sing-box: Ошибка 2\n';

  /// Хвостовые переводы строк — ровно так, как их режет экран (и `\r` тоже).
  String trimNl(String s) {
    var end = s.length;
    while (end > 0 &&
        (s.codeUnitAt(end - 1) == 0x0a || s.codeUnitAt(end - 1) == 0x0d)) {
      end--;
    }
    return s.substring(0, end);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_render_');
    AppPaths.overrideRoot(tmp);
    appLogPath = '${tmp.path}${Platform.pathSeparator}app.log';
    tunLogPath = '${tmp.path}${Platform.pathSeparator}singbox.log';
    await AppLog.useFileForTest(appLogPath);
    LogsScreen.debugSkipInitialLoad = true;
    // ⚠️ БЕЗ ЭТОЙ СТРОКИ ПРОВЕРКИ МАСКИ НИЧЕГО НЕ ПРОВЕРЯЮТ. Реестр в работе
    // наполняется адресами всех узлов подписки (`app_state.dart:932`); пустой
    // реестр делает `SensitiveAddresses.mask` тождественной функцией, и тест
    // «адрес не уехал» проходит просто потому, что маскировать нечего.
    SensitiveAddresses.remember(node);
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

  /// Нажать кнопку и ДОЖДАТЬСЯ её реального ввода-вывода: «Копировать» теперь
  /// читает ФАЙЛ (см. ниже), то есть `tap()` только запускает `Future`.
  ///
  /// ⚠️ ЖДЁМ УСЛОВИЯ, А НЕ ФИКСИРОВАННОЙ ПАУЗЫ. Пауза «на глазок» — это
  /// тест, который зеленеет и краснеет от загрузки машины: ровно этот тест на
  /// 50 мс проходил в одиночку и падал в общем прогоне.
  Future<void> tapIo(WidgetTester tester, Finder finder,
      {required bool Function() until}) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      for (var i = 0; i < 200 && !until(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
  }

  /// Полный цикл показа: обе вкладки построены, опрошены и отрисованы.
  Future<AppLocalizations> showBothTabs(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.runAsync(() => LogsScreen.debugPollOnce!());
    await tester.pump();
    final l = AppLocalizations.of(tester.element(find.byType(LogsScreen)));
    await tester.tap(find.text(l.logsTabTun));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => LogsScreen.debugPollOnce!());
    await tester.pump();
    return l;
  }

  List<String> copyCatcher(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    return copied;
  }

  group('Файл после показа', () {
    testWidgets('⚠️ app.log и singbox.log ПОБАЙТНО прежние', (tester) async {
      await tester.runAsync(() async {
        await File(appLogPath).writeAsBytes(dirtyApp(), flush: true);
        await File(tunLogPath).writeAsString(coreFixture(), flush: true);
      });
      late Uint8List appBefore;
      late Uint8List tunBefore;
      late DateTime appModifiedBefore;
      await tester.runAsync(() async {
        appBefore = await File(appLogPath).readAsBytes();
        tunBefore = await File(tunLogPath).readAsBytes();
        appModifiedBefore = await File(appLogPath).lastModified();
      });

      await showBothTabs(tester);
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        final appAfter = await File(appLogPath).readAsBytes();
        final tunAfter = await File(tunLogPath).readAsBytes();
        expect(appAfter.length, appBefore.length);
        expect(appAfter, appBefore,
            reason: 'отрисовка дописала в журнал приложения');
        expect(tunAfter, tunBefore, reason: 'отрисовка дописала в лог ядра');
        // Дополнение, а не основа доказательства: на NTFS точность и момент
        // обновления времени файла не гарантированы.
        expect(await File(appLogPath).lastModified(), appModifiedBefore);
      });
    });

    testWidgets('⚠️ statOf не поехал: строки и нулевые байты те же',
        (tester) async {
      // Именно эти числа печатаются в отчёте в секции «[Логи на диске]», и по
      // ним отслеживают возврат порчи файла нулями. Начни отрисовка дописывать
      // — поедут они первыми.
      await tester.runAsync(
          () => File(appLogPath).writeAsBytes(dirtyApp(), flush: true));
      late LogFileStat before;
      await tester.runAsync(
          () async => before = await LogMaintenance.statOf(File(appLogPath)));

      await showBothTabs(tester);
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        final after = await LogMaintenance.statOf(File(appLogPath));
        expect(after.bytes, before.bytes);
        expect(after.lines, before.lines);
        expect(after.zeros, before.zeros);
        expect(before.zeros, 1, reason: 'образец обязан содержать нулевой байт');
      });
    });
  });

  group('Что уходит поддержке', () {
    testWidgets(
        '⚠️ КОПИРОВАНИЕ вкладки «Приложение» = БАЙТЫ ФАЙЛА, а не окно показа',
        (tester) async {
      // 5000 строк — заведомо больше окна показа: возьми копия экранный
      // буфер, поддержка получила бы обрезок, и заметить это было бы нечем.
      final many = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        many.writeln('04.08.2026 01:23:33 [INFO] строка $i');
      }
      await tester.runAsync(() async {
        final b = BytesBuilder();
        b.add(utf8.encode(many.toString()));
        b.add(dirtyApp());
        await File(appLogPath).writeAsBytes(b.toBytes(), flush: true);
      });
      final copied = copyCatcher(tester);

      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugPollOnce!());
      await tester.pump();
      final l = AppLocalizations.of(tester.element(find.byType(LogsScreen)));
      await tapIo(tester, find.text(l.logsCopy),
          until: () => copied.isNotEmpty);

      expect(copied, hasLength(1));
      late String fileText;
      await tester.runAsync(() async => fileText = utf8.decode(
          await File(appLogPath).readAsBytes(),
          allowMalformed: true));

      // ⚠️ ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ПЕРВЫМ: образец обязан быть грязным,
      // иначе обе ломающие равенство операции — пустая работа.
      expect(fileText.contains(esc), isTrue, reason: 'в файле есть ESC-байты');
      expect(fileText.contains(node), isTrue,
          reason: 'в файле есть открытый адрес узла');
      expect(fileText.split('\n').length, greaterThan(5000));

      final expected = stripAnsiSequences(
          SensitiveAddresses.mask(trimNl(fileText)));
      expect(utf8.encode(copied.single), utf8.encode(expected),
          reason: 'в буфер должны уходить ДАННЫЕ ФАЙЛА, а не показ: кусок, '
              'выделенный владельцем, обязан находиться поиском в присланном '
              'app.log');
      expect(copied.single.contains(esc), isFalse, reason: 'ESC снят');
      expect(copied.single.contains(node), isFalse,
          reason: 'ЗДЕСЬ БЫЛА БЫ УТЕЧКА: адрес узла в буфере обмена');
      expect(copied.single, contains('адрес №'));
      expect(copied.single.split('\n').length, greaterThan(5000),
          reason: 'окно показа НЕ должно урезать копию');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ КОПИРОВАНИЕ вкладки «TUN» = то же, что кладёт в отчёт '
        'SupportReport.maskCoreLog', (tester) async {
      final many = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        many.writeln('$localZone 2026-08-11 02:09:08 INFO строка $i');
      }
      await tester.runAsync(() => File(tunLogPath)
          .writeAsString('$many${coreFixture()}', flush: true));
      final copied = copyCatcher(tester);

      final l = await showBothTabs(tester);
      await tapIo(tester, find.text(l.logsCopy),
          until: () => copied.isNotEmpty);

      expect(copied, hasLength(1));
      late String fileText;
      await tester.runAsync(() async => fileText = utf8.decode(
          await File(tunLogPath).readAsBytes(),
          allowMalformed: true));

      expect(fileText.contains(esc), isTrue);
      expect(fileText.contains(node), isTrue);

      // ⚠️ СВЕРКА С ОТЧЁТОМ, А НЕ С ПЕРЕПИСАННОЙ ЗДЕСЬ ФОРМУЛОЙ. Разойдись
      // порядок действий (маска ПОВЕРХ причёсывания) — присланный кусок
      // перестал бы совпадать с присланным отчётом, причём молча.
      expect(copied.single, trimNl(SupportReport.maskCoreLog(fileText)));
      expect(copied.single.contains(esc), isFalse);
      expect(copied.single.contains(node), isFalse,
          reason: 'ЗДЕСЬ БЫЛА УТЕЧКА: лог ядра называет боевой узел в каждой '
              'строке dial tcp, а маски на этой вкладке не было вовсе');
      expect(copied.single.split('\n').length, greaterThan(5000),
          reason: 'окно показа НЕ должно урезать копию');

      await tester.pumpWidget(const SizedBox());
    });

    test('⚠️ раздел [app.log] отчёта ПОБАЙТНО равен содержимому файла',
        () async {
      await File(appLogPath).writeAsString(cleanApp, flush: true);
      await File(tunLogPath).writeAsString(coreFixture(), flush: true);

      final dump = await AppLog.dump();
      expect(utf8.encode(dump), utf8.encode(cleanApp),
          reason: 'то, что вкладывается в отчёт, — сам файл, знак в знак');

      final path = await SupportReport.generate(
        settings: const AppSettings(),
        ctx: const SupportContext(
          statusLine: 'Отключено',
          subscriptionUrl: null,
          serverCount: 0,
          activeServer: '—',
          activeCore: 'sing-box',
          header: 'Отчёт SilentGate\n',
        ),
      );
      final report = await File(path).readAsString();

      expect(report.contains(dump), isTrue,
          reason: 'журнал вложен в отчёт дословно, без единой правки');
      expect(
          report,
          contains('04.08.2026 01:23:33 [INFO] подписка получена, серверов 12'),
          reason: 'строка обязана дойти до поддержки в исходном виде');
      // Отрисовка НИЧЕГО не добивает пробелами и не ставит своих меток.
      expect(report.contains('[DEBUG]  '), isFalse);
      expect(report.contains('[INFO ]'), isFalse);
      for (final glyph in ['✖', '▲', '▸', '●']) {
        expect(report.contains(glyph), isFalse, reason: glyph);
      }
    });

    test('лог ядра в отчёте причёсан, но не украшен', () async {
      await File(appLogPath).writeAsString(cleanApp, flush: true);
      await File(tunLogPath).writeAsString(coreFixture(), flush: true);
      final path = await SupportReport.generate(
        settings: const AppSettings(),
        ctx: const SupportContext(
          statusLine: 'Отключено',
          subscriptionUrl: null,
          serverCount: 0,
          activeServer: '—',
          activeCore: 'sing-box',
          header: 'Отчёт SilentGate\n',
        ),
      );
      final report = await File(path).readAsString();

      expect(report.contains(esc), isFalse,
          reason: 'ESC-байты — те самые «utf приколы»');
      expect(report, contains('2026-08-11 02:09:08 $localZone INFO router: тест'),
          reason: 'отчёт продолжает жить на своём tidySingboxLog — '
              'формат его секций правка показа не трогает');
      expect(report.contains(node), isFalse,
          reason: 'адрес узла в отчёте маскируется');
      // ⚠️ Файл лога при этом не изменился.
      expect(await File(tunLogPath).readAsString(), coreFixture());
    });
  });

  group('Положительная половина: показ действительно раскрашен', () {
    testWidgets('⚠️ без неё «файл не изменился» проходит и при пустом экране',
        (tester) async {
      await tester.runAsync(
          () => File(appLogPath).writeAsBytes(dirtyApp(), flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugPollOnce!());
      await tester.pump();

      final theme = Theme.of(tester.element(find.byType(LogsScreen)));
      final shown = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(shown.data, isNull, reason: 'текст рисуется спанами, а не строкой');
      final span = shown.textSpan!;

      // Ошибка — красным.
      Color? errorColor;
      span.visitChildren((s) {
        if (s is TextSpan && s.text == '[ERROR] ') {
          errorColor = s.style?.color;
          return false;
        }
        return true;
      });
      expect(errorColor, theme.colorScheme.error);

      // И при этом ни одна строка не потеряна и не украшена: показанный текст
      // равен файлу после снятия ANSI и наложения маски адресов.
      late String fileText;
      await tester.runAsync(() async => fileText = utf8.decode(
          await File(appLogPath).readAsBytes(),
          allowMalformed: true));
      expect(
          span.toPlainText(),
          SensitiveAddresses.mask(
              stripAnsiSequences(fileText).replaceAll(RegExp(r'[\n\r]+$'), '')));
      expect(span.toPlainText().contains(node), isFalse);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ строки формата ЯДРА внутри app.log НЕ переписываются',
        (tester) async {
      // Их пишет `engine_base.onCoreDied` телом НАШЕЙ записи («Последние
      // строки вывода sing-box:» и следом сам хвост). Разобрав их как строки
      // ядра, показ переставил бы в них дату и синтезировал скобки — то есть
      // переписал бы тело чужой записи.
      await tester.runAsync(
          () => File(appLogPath).writeAsBytes(dirtyApp(), flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugPollOnce!());
      await tester.pump();

      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText();
      expect(text, contains('+0700 2026-08-11 02:09:08 ERROR dial tcp'),
          reason: 'тело нашей записи показывается дословно');
      expect(text.contains('11.08.2026 02:09:08 [ERROR] dial tcp'), isFalse,
          reason: 'ЗДЕСЬ БЫЛА ПЕРЕПИСЬ: дата тела записи переставлялась, '
              'а вокруг уровня появлялись скобки, которых в файле нет');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ ЕДИНЫЙ ВИД: вкладка TUN показывает наш формат времени',
        (tester) async {
      await tester.runAsync(
          () => File(tunLogPath).writeAsString(coreFixture(), flush: true));
      final l = await showBothTabs(tester);
      expect(l.logsTabTun, isNotEmpty);

      final shown = tester.widget<SelectableText>(find.byType(SelectableText));
      final text = shown.textSpan!.toPlainText();
      expect(text, contains('11.08.2026 02:09:08 [INFO] router: тест'),
          reason: 'соседние вкладки обязаны читаться как один источник');
      expect(text.contains(esc), isFalse);
      expect(text.contains('2026-08-11 02:09:08'), isFalse,
          reason: 'формат ядра приведён к нашему, а не наоборот');
      expect(text.contains('$localZone 2026'), isFalse,
          reason: 'своё смещение зоны — то самое «чё за +700» — не показываем');
      // Наши строки третьего формата и харнесс без метки не потеряны.
      expect(text, contains('--- запуск sing-box'));
      expect(text, contains('warn found 0 outbounds'));
      expect(text, contains('НЕ УДАЛОСЬ ЗАПУСТИТЬ sing-box: Ошибка 2'));

      // ⚠️ И АДРЕС УЗЛА ЗАМАСКИРОВАН. До 30.08.2026 этой вкладке маска не
      // накладывалась вовсе, а тест этого не замечал: в фикстуре не было ни
      // одного зарегистрированного адреса.
      expect(text.contains(node), isFalse,
          reason: 'адрес своего узла уезжал на экран открытым');
      expect(text, contains('адрес №'));

      await tester.pumpWidget(const SizedBox());
    });
  });
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

/// ⚠️ ПОВТОРЯЕТ `RotatingLog.tail` ДОСЛОВНО, В ТОМ ЧИСЛЕ ОТСУТСТВИЕ
/// ХВОСТОВОГО ПЕРЕВОДА СТРОКИ. Прежний фейк возвращал текст С ним — и потому
/// шов «первый показ → первый прирост» не воспроизводился ни в одном тесте.
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
