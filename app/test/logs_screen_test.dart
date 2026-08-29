import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/platform_services.dart';
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
    final all = await f.readAsString();
    final rows = all.split('\n');
    return rows.length <= lines
        ? all
        : rows.sublist(rows.length - lines).join('\n');
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
