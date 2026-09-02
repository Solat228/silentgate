import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/log_line.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/core/platform/singbox_log_format.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/logs_screen.dart';

/// Экран логов 29.08.2026 — решения владельца:
///  * шапка — «значок + слово», видимые без наведения, кнопки «Обновить» нет;
///  * копирование и удаление ТЕКУЩЕГО лога — в правом верхнем углу самой
///    области лога;
///  * «Очистить все логи» спрашивает, что именно чистить;
///  * слежение за концом лога приостанавливается, как только прокрутили прочь,
///    и возобновляется, когда вернулись к концу.
///
/// ⚠️ ВИДЖЕТ-ТЕСТЫ — НА НАСТОЯЩЕМ ЭКРАНЕ. Копия вёрстки не поймала бы
/// рассинхрон между тем, что рисует `LogsScreen`, и тем, что решил владелец.
///
/// ⚠️ ЛЮБОЙ РЕАЛЬНЫЙ ДИСКОВЫЙ ВВОД-ВЫВОД — ТОЛЬКО ЧЕРЕЗ [WidgetTester.runAsync].
/// Тело `testWidgets` целиком крутится в поддельном времени; голый `await` на
/// `File`/на кнопке, которая внутри читает или пишет файл, не завершается
/// НИКОГДА — тест просто висит до тайм-аута рантайма без единой подсказки,
/// где именно он встал (см. `geo_bases_ui_test.dart`, тот же урок).
void main() {
  late Directory tmp;
  late String appLogPath;
  late String tunLogPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_logs_ui_');
    AppPaths.overrideRoot(tmp);
    appLogPath = '${tmp.path}${Platform.pathSeparator}app.log';
    tunLogPath = '${tmp.path}${Platform.pathSeparator}singbox.log';
    await AppLog.useFileForTest(appLogPath);
    // Своя `_load()` экрана стартует из `initState` ДО того, как тест успел
    // бы обернуть что-либо в `runAsync`, — реальный ввод-вывод там подвисает
    // навсегда и держит файл открытым (см. комментарий у самого флага).
    // Экраны в этих тестах наполняются через `LogsScreen.debugPollOnce`.
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

  /// Собрать экран и заполнить его содержимым через тестовый хук
  /// [LogsScreen.debugPollOnce] — надёжнее, чем ждать своей же `_load()`
  /// экрана: та стартует внутри `initState`, то есть ДО того, как тест успел
  /// бы обернуть её в `runAsync`, и её результат неопределён.
  Future<AppLocalizations> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.runAsync(() => LogsScreen.debugPollOnce!());
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(LogsScreen)));
  }

  /// Нажать кнопку/плитку и дать её РЕАЛЬНОМУ асинхронному коду внутри
  /// `onPressed` реально доработать: сам `tap()` его не ждёт, он только
  /// запускает `Future`. Дальше — `pump()` СНАРУЖИ `runAsync` (внутри него
  /// он запрещён), чтобы вписать в разметку результат `setState`.
  Future<void> tapAndSettleIo(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  testWidgets('шапка: «Настройки логов» и «Очистить все логи», без «Обновить»',
      (tester) async {
    final l = await pumpScreen(tester);

    expect(find.text(l.logsSettingsLabel), findsOneWidget);
    expect(find.text(l.logsClearAllLabel), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing,
        reason: 'кнопка обновления удалена вовсе — лог обновляется сам');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'в области каждой вкладки — копирование и удаление ИМЕННО этого лога',
      (tester) async {
    final l = await pumpScreen(tester);

    // Вкладка «Приложение» открыта по умолчанию.
    expect(find.text(l.logsCopy), findsOneWidget);
    expect(find.text(l.logsDeleteCurrentLabel), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget,
        reason: 'кнопка копирования переехала из шапки — в шапке её больше нет');

    await tester.tap(find.text(l.logsTabTun));
    await tester.pump();

    expect(find.text(l.logsCopy), findsOneWidget);
    expect(find.text(l.logsDeleteCurrentLabel), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«Удалить этот лог» стирает только текущую вкладку',
      (tester) async {
    await tester.runAsync(() async {
      await File(appLogPath).writeAsString('строка приложения\n');
      await File(tunLogPath).writeAsString('строка ядра\n');
    });
    final l = await pumpScreen(tester);

    await tapAndSettleIo(tester, find.text(l.logsDeleteCurrentLabel));

    await tester.runAsync(() async {
      // AppLog в этом тесте не открывался вызовами `AppLog.i/w/e`, поэтому
      // `AppLog.fileOpened == false`, и «Удалить этот лог» убирает файл
      // целиком, а не обрезает поток, — тот же механизм проверен отдельно
      // в log_cleanup_categories_test.dart.
      expect(await File(appLogPath).exists(), isFalse,
          reason: 'app.log удалён кнопкой текущей (открытой) вкладки');
      expect(await File(tunLogPath).readAsString(), 'строка ядра\n',
          reason: 'TUN-лог кнопка соседней вкладки не трогает');
    });

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '«Очистить все логи»: снятая галочка — файл цел, отмеченная — удалён',
      (tester) async {
    final proxyLogPath =
        '${tmp.path}${Platform.pathSeparator}singbox_proxy.log';
    await tester.runAsync(() async {
      await File(appLogPath).writeAsString('a' * 10);
      await File(tunLogPath).writeAsString('b' * 20);
      await File(proxyLogPath).writeAsString('c' * 30);
    });
    final l = await pumpScreen(tester);

    await tapAndSettleIo(tester, find.text(l.logsClearAllLabel));

    // Порядок галочек в диалоге: приложение, TUN, прокси-ядро, отчёты.
    final checkboxes = find.byType(CheckboxListTile);
    expect(checkboxes, findsNWidgets(4));
    // Снимаем галочку с TUN-лога — он единственный, кто должен уцелеть.
    await tester.tap(checkboxes.at(1));
    await tester.pump();

    await tapAndSettleIo(tester, find.text(l.logsClearConfirm));

    await tester.runAsync(() async {
      expect(await File(appLogPath).exists(), isFalse,
          reason: 'лог приложения был отмечен — удалён');
      expect(await File(tunLogPath).exists(), isTrue,
          reason: 'галочку с TUN-лога сняли — файл цел');
      expect(await File(proxyLogPath).exists(), isFalse,
          reason: 'лог прокси-ядра остался отмеченным — удалён');
    });

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'слежение: прокрутка прочь от конца ставит на паузу, возврат — снимает',
      (tester) async {
    final many = List.generate(200, (i) => 'строка $i').join('\n');
    await tester.runAsync(() => File(tunLogPath).writeAsString('$many\n'));
    final l = await pumpScreen(tester);

    await tester.tap(find.text(l.logsTabTun));
    // Переключение вкладки анимировано (TabController по умолчанию — 300 мс),
    // и «доехать до конца» на только что показанной вкладке экран решает
    // тоже НЕ сразу первым кадром — несколько тактов даём на то и другое.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(scroll.hasClients, isTrue);
    final bottom = scroll.position.maxScrollExtent;
    expect(bottom, greaterThan(0),
        reason: 'без прокручиваемого контента тест ничего не проверяет');
    expect(scroll.offset, bottom,
        reason: 'изначально слежение включено — экран сам встал в конец');

    // Прокрутили прочь от конца — слежение должно приостановиться.
    scroll.jumpTo(0);
    await tester.pump();

    await tester.runAsync(() async {
      await File(tunLogPath)
          .writeAsString('$many\nновая строка после паузы\n');
      await LogsScreen.debugPollOnce!();
    });
    await tester.pump();

    expect(scroll.offset, 0,
        reason: 'слежение стоит на паузе — новая строка не должна была '
            'сдёрнуть прокрутку');

    // Вернулись к концу — слежение возобновляется.
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();

    await tester.runAsync(() async {
      await File(tunLogPath).writeAsString(
          '$many\nновая строка после паузы\nи ещё одна после возврата\n');
      await LogsScreen.debugPollOnce!();
    });
    await tester.pump();

    expect(scroll.offset, scroll.position.maxScrollExtent,
        reason: 'слежение снова включено — экран должен был уехать в конец');

    await tester.pumpWidget(const SizedBox());
  });

  // ── Красивый показ (задание 4.1/4.2, 5.3) ───────────────────────────────
  //
  // ⚠️ ТЕСТ СЛЕЖЕНИЯ ВЫШЕ ОСТАЛСЯ БЕЗ ЕДИНОЙ ПРАВКИ — И ЭТО ЧАСТЬ
  // ДОКАЗАТЕЛЬСТВА, А НЕ СОВПАДЕНИЕ. Он достаёт контроллер как
  // `tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView))`
  // и требует `scroll.offset == maxScrollExtent` ТОЧНО: любой ленивый список
  // (или просто второй `SingleChildScrollView` в дереве) уронил бы его сразу.
  // Понадобилась ему правка — значит вёрстка поехала, и это ранний сигнал.

  testWidgets('текст лога рисуется СПАНАМИ, а не одной строкой',
      (tester) async {
    await tester.runAsync(() => File(appLogPath)
        .writeAsString('04.08.2026 01:23:33 [ERROR] сбой\n'));
    await pumpScreen(tester);

    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(shown.data, isNull);
    expect(shown.textSpan, isNotNull);
    expect(shown.textSpan!.toPlainText(), '04.08.2026 01:23:33 [ERROR] сбой');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('⚠️ буфер вкладки «TUN» = текст отчёта поддержки, а не показ',
      (tester) async {
    // На этой вкладке показ и данные РАСХОДЯТСЯ намеренно: на экране дата
    // ядра переписана в наш вид ради единого вида двух вкладок, а в буфер
    // уходит ровно то, что вкладывается в отчёт (`SupportReport.maskCoreLog`
    // строится на том же `tidySingboxLog`) — иначе присланный кусок нельзя
    // было бы сопоставить с присланным файлом.
    final esc = String.fromCharCode(0x1b);
    final zone = formatZoneOffset(DateTime.now().timeZoneOffset);
    final raw = '$zone 2026-08-11 02:09:08 $esc[36mINFO$esc[0m router: тест\n';
    await tester.runAsync(() => File(tunLogPath).writeAsString(raw));

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

    final l = await pumpScreen(tester);
    await tester.tap(find.text(l.logsTabTun));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // ⚠️ ЛИШНИЙ КАДР ОБЯЗАТЕЛЕН: первый кадр с содержимым показывает текст
    // одним спаном, без разбора (ради мгновенного открытия экрана —
    // `logs_screen.dart`, `_colorReady`). Наш формат времени приезжает
    // следующим кадром вместе с раскраской.
    await tester.pump();

    // На экране — наш формат времени, без зоны и без ESC.
    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(shown.textSpan!.toPlainText(),
        '11.08.2026 02:09:08 [INFO] router: тест');

    // ⚠️ «Копировать» читает ФАЙЛ (иначе окно показа урезало бы то,
    // что уходит поддержке), поэтому нажатию нужен настоящий ввод-вывод.
    await tapAndSettleIo(tester, find.text(l.logsCopy));

    expect(copied, hasLength(1));
    expect(copied.single, tidySingboxLog(raw).trimRight());
    expect(copied.single.contains(esc), isFalse,
        reason: 'ESC-байты — те самые «utf приколы», поддержке они не нужны');

    await tester.pumpWidget(const SizedBox());
  });

  group('⚠️ Шов между первым показом и первым приростом', () {
    // ⚠️ ЗДЕСЬ ЗОВЁТСЯ НАСТОЯЩАЯ `_load()` — через
    // `LogsScreen.debugLoadOnce`. Без неё шов не воспроизводится вовсе:
    // стартовое смещение задаёт именно она, а `debugSkipInitialLoad` (нужный,
    // чтобы реальный ввод-вывод не подвисал в поддельном времени) её
    // отменяет. Прежние тесты наполняли экран только приростом с нуля — и
    // потому склейку не видели.
    Future<String> shownText(WidgetTester tester) async {
      final l = AppLocalizations.of(tester.element(find.byType(LogsScreen)));
      await tester.tap(find.text(l.logsTabTun));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      return tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText();
    }

    testWidgets(
        '⚠️ ПЕРВЫЙ показ вкладки TUN маскирует адреса, а не только прирост',
        (tester) async {
      // ⚠️ ЛОВУШКА, НА КОТОРОЙ ЗДЕСЬ УЖЕ ОБОЖГЛИСЬ: при ПУСТОМ реестре
      // `SensitiveAddresses.mask` — тождественная функция, и тест на фикстуре
      // без единого зарегистрированного адреса зелен независимо от того, есть
      // маскировка в коде или нет. Поэтому адрес регистрируется явно.
      //
      // Проверять надо именно ПЕРВУЮ загрузку: прирост идёт через `_apply`, где
      // маска была, а `_load` брала хвост журнала ядра напрямую у платформы —
      // и `TunHelper.tailLog`, и `RotatingLog.tail` отдают файл как есть. То
      // есть открытый адрес узла показывался ровно там, куда человек смотрит,
      // открыв экран, и висел там до среза окна — на спокойном ядре всю сессию.
      SensitiveAddresses.remember('198.51.100.7');
      await tester.runAsync(() => File(tunLogPath).writeAsString(
          '04.08.2026 01:23:33 [INFO] router: dial tcp 198.51.100.7:443\n',
          flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugLoadOnce!());
      await tester.pump();

      final text = await shownText(tester);
      expect(text, isNot(contains('198.51.100.7')),
          reason: 'настоящий адрес узла на экране — это утечка, а строки '
              '«dial tcp <адрес>» самые частые в журнале ядра');
      expect(text, contains('443'),
          reason: 'маскируется адрес, а не вся строка: без порта и текста '
              'запись станет бесполезной для разбора');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('файл кончается переводом строки: две строки, а не одна',
        (tester) async {
      await tester.runAsync(() => File(tunLogPath)
          .writeAsString('04.08.2026 01:23:33 [INFO] первая\n', flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugLoadOnce!());
      await tester.pump();

      await tester.runAsync(() async {
        await File(tunLogPath).writeAsString(
            '04.08.2026 01:23:34 [INFO] вторая\n',
            mode: FileMode.append,
            flush: true);
        await LogsScreen.debugPollOnce!();
      });
      await tester.pump();

      final text = await shownText(tester);
      expect(text.split('\n'), [
        '04.08.2026 01:23:33 [INFO] первая',
        '04.08.2026 01:23:34 [INFO] вторая',
      ], reason: 'ЗДЕСЬ БЫЛА СКЛЕЙКА: смещение указывало на байт ПОСЛЕ '
          'перевода строки, а показанный хвост его не содержал — метка '
          'времени новой записи уезжала в середину предыдущей');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('файл оборван посреди строки: обрывок не показан и не потерян',
        (tester) async {
      await tester.runAsync(() => File(tunLogPath).writeAsString(
          '04.08.2026 01:23:33 [INFO] первая\n04.08.2026 01:23:34 [INFO] вт',
          flush: true));
      await tester.pumpWidget(host());
      await tester.runAsync(() => LogsScreen.debugLoadOnce!());
      await tester.pump();

      expect(await shownText(tester), '04.08.2026 01:23:33 [INFO] первая',
          reason: 'недописанную строку показывать нельзя: следующий кусок '
              'приклеился бы к ней вторым куском той же строки');

      await tester.runAsync(() async {
        await File(tunLogPath)
            .writeAsString('орая\n', mode: FileMode.append, flush: true);
        await LogsScreen.debugPollOnce!();
      });
      await tester.pump();

      expect((await shownText(tester)).split('\n'), [
        '04.08.2026 01:23:33 [INFO] первая',
        '04.08.2026 01:23:34 [INFO] вторая',
      ], reason: 'дописанная строка обязана прийти целиком');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('⚠️ Окно показа и чужая прокрутка', () {
    // Экран держит не весь лог, а его хвост (см. `_windowLines`). Срез головы
    // обязан считаться с тем, кто прокрутил прочь от конца: сдвинь мы у него
    // содержимое — он потерял бы место, которое читает.
    Future<ScrollController> openTun(WidgetTester tester) async {
      final l = AppLocalizations.of(tester.element(find.byType(LogsScreen)));
      await tester.tap(find.text(l.logsTabTun));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      return tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
    }

    String shown(WidgetTester tester) => tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();

    testWidgets('в слежении окно режет голову, а хвост остаётся на экране',
        (tester) async {
      final many = List.generate(
              5000, (i) => '04.08.2026 01:23:34 [INFO] строка $i')
          .join('\n');
      await tester.runAsync(
          () => File(tunLogPath).writeAsString('$many\n', flush: true));
      await pumpScreen(tester);
      final scroll = await openTun(tester);

      final text = shown(tester);
      expect(text, contains('строка 4999'), reason: 'конец лога виден');
      expect(text.contains('строка 0\n'), isFalse,
          reason: 'голова окна срезана — иначе окна нет');
      expect(scroll.offset, scroll.position.maxScrollExtent,
          reason: 'срез не должен ломать слежение за концом');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('⚠️ на паузе слежения голову НЕ режем', (tester) async {
      // Человек прокрутил прочь и читает; срез сдвинул бы содержимое под ним.
      final head = List.generate(
              1000, (i) => '04.08.2026 01:23:34 [INFO] старая $i')
          .join('\n');
      await tester.runAsync(
          () => File(tunLogPath).writeAsString('$head\n', flush: true));
      await pumpScreen(tester);
      final scroll = await openTun(tester);

      scroll.jumpTo(0);
      await tester.pump();

      // ⚠️ ЧИСЛО ПОДОБРАНО: 1000 + 2000 = 3000 строк. Это БОЛЬШЕ полутора
      // окон (срез в слежении случился бы), но не больше потолка паузы —
      // ровно та вилка, в которой правило «на паузе не режем» и живёт.
      final more = List.generate(
              2000, (i) => '04.08.2026 01:23:35 [INFO] новая $i')
          .join('\n');
      await tester.runAsync(() async {
        await File(tunLogPath)
            .writeAsString('$more\n', mode: FileMode.append, flush: true);
        await LogsScreen.debugPollOnce!();
      });
      await tester.pump();

      final text = shown(tester);
      expect(text, contains('старая 0'),
          reason: 'ЗДЕСЬ БЫЛА БЫ ПОТЕРЯ МЕСТА: срез головы под человеком, '
              'который ушёл от конца и читает');
      expect(text, contains('новая 1999'), reason: 'прирост при этом пришёл');
      expect(scroll.offset, 0,
          reason: 'слежение на паузе — прокрутку не дёргаем');

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('⚠️ вкладка из одних CRLF показывает плашку, а не мусор',
      (tester) async {
    // Прежний `_trimTrailingNewlines` резал только 0x0A: на файле с CRLF
    // оставался одинокий `\r`, вкладка считалась непустой и показывала
    // невидимый мусор вместо «Логи пусты».
    await tester.runAsync(
        () => File(appLogPath).writeAsString('\r\n\r\n', flush: true));
    final l = await pumpScreen(tester);

    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();
    expect(text, l.logsEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('пустая вкладка копируется плашкой, как и раньше',
      (tester) async {
    // Файл есть, но в нём одни переводы строк — их экран срезает и до правки.
    await tester.runAsync(() => File(appLogPath).writeAsString('\n\n'));
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
    final l = await pumpScreen(tester);
    await tapAndSettleIo(tester, find.text(l.logsCopy));

    expect(copied.single, l.logsEmpty,
        reason: 'поведение до правки сохранено — молчаливая пустота в буфере '
            'выглядела бы как «копирование не сработало»');

    await tester.pumpWidget(const SizedBox());
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
/// шов «первый показ → первый прирост» не воспроизводился ни одним тестом,
/// хотя в бою склеивал первую новую строку с последней старой.
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
