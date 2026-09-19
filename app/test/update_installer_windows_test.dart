import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/update/update_installer.dart';
import 'package:silentgate/core/update/update_installer_fake.dart';
import 'package:silentgate/core/update/update_installer_windows.dart';

/// Установщик внутри приложения (Windows): решение «можно ли ставить сами»,
/// разбор реестра, аргументы тихой установки, запуск и разбор итога на
/// следующем старте.
///
/// ⚠️ Ни один тест здесь НЕ ЗАПУСКАЕТ установщик и не читает настоящий реестр:
/// вывод `reg query` и запуск процесса подменяются инъекцией. Файлы живут во
/// временном каталоге через `AppPaths.overrideRoot` — боевой `%APPDATA%` под
/// тестами не отдаётся вовсе (см. память `tests-must-not-touch-real-appdata`).
void main() {
  // Вывод `reg query` таким, каким его печатает Windows: пустая строка,
  // полное имя ключа, значение с четырьмя пробелами отступа, пустая строка.
  String regOut(String location, {String indent = '    ', String type = 'REG_SZ'}) =>
      '\r\n'
      'HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\'
      '{B7F3B2A1-5C2E-4E7A-9F1D-51E4C0DE0001}_is1\r\n'
      '${indent}InstallLocation$indent$type$indent$location\r\n'
      '\r\n';

  const cyrillicDir = r'C:\Users\Иван Петров\AppData\Local\Programs\Silent Gate';

  group('parseRegSz', () {
    test('значение с пробелами и кириллицей в пути берётся целиком', () {
      final out = regOut('$cyrillicDir\\');
      expect(parseRegSz(out, 'InstallLocation'), '$cyrillicDir\\');
    });

    test('разный отступ: табуляция и одиночные пробелы', () {
      expect(parseRegSz(regOut(r'C:\SG\', indent: '\t'), 'InstallLocation'),
          r'C:\SG\');
      expect(parseRegSz(regOut(r'C:\SG\', indent: ' '), 'InstallLocation'),
          r'C:\SG\');
    });

    test('имя значения сравнивается без учёта регистра', () {
      expect(parseRegSz(regOut(r'C:\SG\'), 'installlocation'), r'C:\SG\');
    });

    test('чужое значение с похожим именем не подходит', () {
      const out = '\r\nHKEY_CURRENT_USER\\X\r\n'
          '    InstallLocationOld    REG_SZ    C:\\Old\\\r\n\r\n';
      expect(parseRegSz(out, 'InstallLocation'), isNull);
    });

    test('нет значения, пустой вывод, пустое значение → null', () {
      expect(parseRegSz('', 'InstallLocation'), isNull);
      expect(parseRegSz('ERROR: The system was unable to find the specified '
              'registry key or value.', 'InstallLocation'),
          isNull);
      expect(parseRegSz(regOut(''), 'InstallLocation'), isNull);
    });

    test('другой тип значения (REG_EXPAND_SZ) не принимается за REG_SZ', () {
      // Inno пишет InstallLocation как REG_SZ; значение с переменными
      // окружения внутри без раскрытия сравнивать с путём exe бессмысленно.
      expect(parseRegSz(regOut(r'C:\SG\', type: 'REG_EXPAND_SZ'), 'InstallLocation'),
          isNull);
    });

    test('концевые пробелы значения срезаются, внутренние — нет', () {
      final out = regOut('C:\\Silent Gate\\   ');
      expect(parseRegSz(out, 'InstallLocation'), r'C:\Silent Gate\');
    });
  });

  group('WindowsInstallState.detect', () {
    WindowsInstallState detect({
      String? reg,
      String exe = r'C:\Users\User\AppData\Local\Programs\SilentGate\silentgate.exe',
      bool portable = false,
      bool isolated = false,
      bool elevated = false,
    }) =>
        WindowsInstallState.detect(
          regQueryOutput: reg,
          exePath: exe,
          portable: portable,
          isolated: isolated,
          elevated: elevated,
        );

    const installed = r'C:\Users\User\AppData\Local\Programs\SilentGate\';

    test('ready: каталог из реестра совпадает с каталогом exe', () {
      final s = detect(reg: regOut(installed));
      expect(s.capability, InstallCapability.ready);
      expect(s.installLocation, installed);
    });

    test('ready: сравнение не зависит от регистра, слэшей и хвостового «\\»', () {
      // Реестр — как записал Inno; exe — как отдал `Platform.resolvedExecutable`.
      expect(
          detect(
                  reg: regOut(r'c:\users\user\appdata\local\programs\silentgate'),
                  exe: r'C:\Users\User\AppData\Local\Programs\SilentGate\silentgate.exe')
              .capability,
          InstallCapability.ready);
      expect(
          detect(
                  reg: regOut('C:/Users/User/AppData/Local/Programs/SilentGate/'),
                  exe: r'C:\Users\User\AppData\Local\Programs\SilentGate\silentgate.exe')
              .capability,
          InstallCapability.ready);
    });

    test('ready: путь с пробелами и кириллицей', () {
      final s = detect(reg: regOut('$cyrillicDir\\'), exe: '$cyrillicDir\\silentgate.exe');
      expect(s.capability, InstallCapability.ready);
      expect(s.installLocation, '$cyrillicDir\\');
    });

    test('locationMismatch: exe запущен не из установленного каталога', () {
      final s = detect(reg: regOut(installed), exe: r'D:\Portable\SilentGate\silentgate.exe');
      expect(s.capability, InstallCapability.locationMismatch);
      // Каталог из реестра остаётся в состоянии: интерфейс объяснит, где
      // установленная копия.
      expect(s.installLocation, installed);
    });

    test('notInstalled: реестр пуст, вывод пуст или без InstallLocation', () {
      expect(detect(reg: null).capability, InstallCapability.notInstalled);
      expect(detect(reg: '').capability, InstallCapability.notInstalled);
      expect(detect(reg: 'ERROR: The system was unable to find the specified registry key or value.')
              .capability,
          InstallCapability.notInstalled);
      expect(detect(reg: null).installLocation, isNull);
    });

    test('portable: метка рядом с exe перевешивает всё остальное', () {
      // Портативная копия установленной не относится, даже если случайно
      // лежит в том же каталоге.
      expect(detect(reg: regOut(installed), portable: true).capability,
          InstallCapability.portable);
      expect(detect(reg: regOut(installed), portable: true, isolated: true, elevated: true)
              .capability,
          InstallCapability.portable);
    });

    test('isolated: SILENTGATE_PORT_OFFSET — копия заведена, чтобы не мешать', () {
      expect(detect(reg: regOut(installed), isolated: true).capability,
          InstallCapability.isolated);
      expect(detect(reg: regOut(installed), isolated: true, elevated: true).capability,
          InstallCapability.isolated);
    });

    test('elevated: возвышенное приложение установщик не запускает', () {
      // PrivilegesRequired=lowest, путь к exe читается из HKCU: запуск из-под
      // администратора превратил бы строку реестра в повышение прав.
      expect(detect(reg: regOut(installed), elevated: true).capability,
          InstallCapability.elevated);
    });
  });

  group('buildSetupArgs', () {
    const loc = r'C:\Users\User\AppData\Local\Programs\SilentGate\';
    const log = r'C:\Users\User\AppData\Roaming\SilentGate\updates\install-1.14.1.log';

    test('ровно те токены, в том порядке, без кавычек', () {
      expect(
        buildSetupArgs(installLocation: loc, logPath: log, forceQuit: false, allowDowngrade: false),
        [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/NOCANCEL',
          r'/DIR=C:\Users\User\AppData\Local\Programs\SilentGate',
          '/LOG=$log',
        ],
      );
    });

    test('/FORCEQUIT перед /DIR, /FORCEDOWNGRADE — последним', () {
      expect(
        buildSetupArgs(installLocation: loc, logPath: log, forceQuit: true, allowDowngrade: true),
        [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/NOCANCEL',
          '/FORCEQUIT',
          r'/DIR=C:\Users\User\AppData\Local\Programs\SilentGate',
          '/LOG=$log',
          '/FORCEDOWNGRADE',
        ],
      );
    });

    test('пробелы и кириллица в путях — без кавычек: их ставит Process.start', () {
      const cyrLog = r'C:\Users\Иван Петров\AppData\Roaming\SilentGate\updates\install-1.14.1.log';
      final args = buildSetupArgs(
          installLocation: '$cyrillicDir\\', logPath: cyrLog, forceQuit: true, allowDowngrade: false);
      for (final a in args) {
        expect(a, isNot(contains('"')), reason: 'кавычка в токене: $a');
      }
      expect(args, contains('/DIR=$cyrillicDir'));
      expect(args, contains('/LOG=$cyrLog'));
    });

    test('⚠️ хвостовой «\\» у /DIR срезается, корень диска — нет', () {
      // Dart при пробеле в аргументе оборачивает его в кавычки и УДВАИВАЕТ
      // хвостовые обратные слэши по правилам C-рантайма. Inno разбирает
      // командную строку по правилам Delphi (ParamStr), где обратный слэш
      // ничего не экранирует, — и получил бы каталог с «\\» на конце.
      expect(setupDirArgument(r'C:\Program Files\Silent Gate\'), r'C:\Program Files\Silent Gate');
      expect(setupDirArgument(r'C:\Program Files\Silent Gate\\'), r'C:\Program Files\Silent Gate');
      expect(setupDirArgument(r'C:\SG'), r'C:\SG');
      expect(setupDirArgument(r'C:\'), r'C:\');
      expect(setupDirArgument(r'C:/SG/'), r'C:\SG');
    });
  });

  group('Декодирование вывода reg.exe', () {
    test('⚠️ reg.exe печатает в OEM-кодировке, а не в ANSI (проверено на хосте)', () {
      // Живой замер 20.09.2026: `reg query` отдаёт «версия» байтами
      // a2 a5 e0 e1 a8 ef (cp866), а systemEncoding Dart читает их как cp1251
      // → «ўҐабЁп». Путь с кириллицей в имени пользователя превращался бы в
      // мусор, и КАЖДЫЙ русский пользователь получал бы locationMismatch.
      const bytes = [0xa2, 0xa5, 0xe0, 0xe1, 0xa8, 0xef];
      expect(latin1.decode(bytes), isNot('версия'), reason: 'самопроверка теста');
      expect(decodeOemBytes(bytes), 'версия');
    }, skip: !Platform.isWindows || oemCodePage() != 866
        ? 'OEM-страница хоста не 866 — ожидание неприменимо'
        : false);

    test('ASCII-вывод декодируется как есть', () {
      final out = regOut(r'C:\SG\');
      expect(decodeOemBytes(ascii.encode(out)), out);
    });

    test('пустой ввод → пустая строка', () {
      expect(decodeOemBytes(const []), '');
    });
  });

  group('Журнал установщика', () {
    test('UTF-8 с BOM: маркер срезается, кириллица цела', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Строка один\r\nСтрока два\r\n')];
      expect(decodeInstallLog(bytes), 'Строка один\r\nСтрока два\r\n');
    });

    test('UTF-8 без BOM', () {
      expect(decodeInstallLog(utf8.encode('Готово')), 'Готово');
    });

    test('UTF-16LE с BOM', () {
      const text = 'Установка';
      final bytes = <int>[0xFF, 0xFE];
      for (final c in text.codeUnits) {
        bytes.add(c & 0xff);
        bytes.add(c >> 8);
      }
      expect(decodeInstallLog(bytes), text);
    });

    test('ANSI (не UTF-8) не роняет разбор — latin1 как запасной', () {
      // Байты cp1251 — недопустимый UTF-8; строгий decode бросил бы исключение.
      const bytes = [0xC3, 0xEE, 0xF2, 0xEE, 0xE2, 0xEE];
      expect(() => utf8.decode(bytes), throwsFormatException, reason: 'самопроверка');
      expect(decodeInstallLog(bytes), latin1.decode(bytes));
    });

    test('хвост: последние строки, не больше лимита символов', () {
      final lines = List.generate(100, (i) => 'line $i');
      final tail = logTail(lines.join('\r\n'), maxLines: 5);
      expect(tail.split('\n'), ['line 95', 'line 96', 'line 97', 'line 98', 'line 99']);
      final capped = logTail('x' * 100, maxChars: 10);
      expect(capped.length, 10);
    });
  });

  group('PendingInstall', () {
    test('toJson/fromJson — обратимы, время в UTC', () {
      final p = PendingInstall(
        version: '1.14.1',
        startedAt: DateTime.utc(2026, 9, 20, 10, 30),
        exePath: r'C:\u\updates\SilentGateSetup-1.14.1.exe',
        logPath: r'C:\u\updates\install-1.14.1.log',
      );
      final back = PendingInstall.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.version, p.version);
      expect(back.startedAt, p.startedAt);
      expect(back.exePath, p.exePath);
      expect(back.logPath, p.logPath);
    });

    test('tryParse: мусор и неполный объект → null, не исключение', () {
      expect(PendingInstall.tryParse('не json'), isNull);
      expect(PendingInstall.tryParse('{"version":"1.0.0"}'), isNull);
      expect(PendingInstall.tryParse('[]'), isNull);
    });

    test('isStale — строго старше 24 часов', () {
      final started = DateTime.utc(2026, 9, 20);
      final p = PendingInstall(version: '1', startedAt: started, exePath: 'a', logPath: 'b');
      expect(p.isStale(started.add(const Duration(hours: 23, minutes: 59))), isFalse);
      expect(p.isStale(started.add(const Duration(hours: 24, minutes: 1))), isTrue);
    });
  });

  group('WindowsUpdateInstaller: файлы', () {
    late Directory tmp;
    late Directory staging;
    const installed = r'C:\Users\User\AppData\Local\Programs\SilentGate\';
    const exe = r'C:\Users\User\AppData\Local\Programs\SilentGate\silentgate.exe';

    /// Установщик с полностью подменённым окружением: реестр отвечает
    /// [reg], процесс «запускает» [start], возвышения/портативности нет.
    WindowsUpdateInstaller make({
      String? reg = '',
      ProcessStarter? start,
      DateTime Function()? clock,
      bool portable = false,
    }) =>
        WindowsUpdateInstaller(
          regQuery: () async => reg ?? regOut(installed),
          start: start ?? (_, __) async {},
          exePath: exe,
          portable: portable,
          isolated: false,
          isElevated: () => false,
          clock: clock,
        );

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('sg_upd_inst_');
      AppPaths.overrideRoot(tmp);
      staging = await make().stagingDir();
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    File pendingFile() => File('${staging.path}${Platform.pathSeparator}${PendingInstall.fileName}');

    Future<File> writePending({
      required String version,
      required DateTime startedAt,
      String? exeName,
      String? logName,
    }) async {
      final sep = Platform.pathSeparator;
      final p = PendingInstall(
        version: version,
        startedAt: startedAt,
        exePath: '${staging.path}$sep${exeName ?? 'SilentGateSetup-$version.exe'}',
        logPath: '${staging.path}$sep${logName ?? 'install-$version.log'}',
      );
      final f = pendingFile();
      await f.writeAsString(jsonEncode(p.toJson()));
      return f;
    }

    test('stagingDir — updates внутри корня данных, создаётся сам', () {
      expect(staging.path, '${tmp.path}${Platform.pathSeparator}updates');
      expect(staging.existsSync(), isTrue);
    });

    group('reconcileAfterStart', () {
      test('нет pending.json → null', () async {
        expect(await make().reconcileAfterStart(currentVersion: '1.14.1'), isNull);
      });

      test('updated: версия совпала — exe и журнал удалены, pending.json тоже', () async {
        await writePending(version: '1.14.1', startedAt: DateTime.now().toUtc());
        final exeF = File('${staging.path}${Platform.pathSeparator}SilentGateSetup-1.14.1.exe')
          ..writeAsBytesSync([1, 2, 3]);
        final logF = File('${staging.path}${Platform.pathSeparator}install-1.14.1.log')
          ..writeAsStringSync('ok');

        final r = await make().reconcileAfterStart(currentVersion: '1.14.1');

        expect(r?.outcome, PendingOutcome.updated);
        expect(r?.pending.version, '1.14.1');
        expect(r?.logTail, isNull);
        expect(exeF.existsSync(), isFalse);
        expect(logF.existsSync(), isFalse);
        expect(pendingFile().existsSync(), isFalse);
      });

      test('failed: версия не та — хвост журнала, журнал остаётся, pending.json удалён',
          () async {
        await writePending(
            version: '1.14.1',
            startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)));
        final logF = File('${staging.path}${Platform.pathSeparator}install-1.14.1.log');
        // Как пишет Inno: UTF-8 с BOM.
        logF.writeAsBytesSync([
          0xEF, 0xBB, 0xBF,
          ...utf8.encode('2026-09-20 Log opened.\r\n'
              '2026-09-20 Автозакрытие: помощник вернул 10\r\n'
              '2026-09-20 Отказ: SilentGate подключён к VPN.\r\n'),
        ]);

        final r = await make().reconcileAfterStart(currentVersion: '1.14.0');

        expect(r?.outcome, PendingOutcome.failed);
        expect(r?.logTail, contains('Отказ: SilentGate подключён к VPN.'));
        expect(r?.logTail, isNot(contains('\uFEFF')), reason: 'BOM в хвосте');
        expect(logF.existsSync(), isTrue, reason: 'журнал нужен кнопке «Показать журнал»');
        expect(pendingFile().existsSync(), isFalse);
      });

      test('failed без журнала: logTail null, исключения нет', () async {
        await writePending(version: '1.14.1', startedAt: DateTime.now().toUtc());
        final r = await make().reconcileAfterStart(currentVersion: '1.14.0');
        expect(r?.outcome, PendingOutcome.failed);
        expect(r?.logTail, isNull);
        expect(pendingFile().existsSync(), isFalse);
      });

      test('stale: старше 24 часов и версия не та', () async {
        final now = DateTime.utc(2026, 9, 20, 12);
        await writePending(
            version: '1.14.1', startedAt: now.subtract(const Duration(hours: 25)));
        final r = await make(clock: () => now).reconcileAfterStart(currentVersion: '1.14.0');
        expect(r?.outcome, PendingOutcome.stale);
        expect(pendingFile().existsSync(), isFalse);
      });

      test('версия совпала спустя сутки — всё равно updated, а не stale', () async {
        final now = DateTime.utc(2026, 9, 20, 12);
        await writePending(
            version: '1.14.1', startedAt: now.subtract(const Duration(hours: 48)));
        final r = await make(clock: () => now).reconcileAfterStart(currentVersion: '1.14.1');
        expect(r?.outcome, PendingOutcome.updated);
      });

      test('битый pending.json → null и файл удалён', () async {
        pendingFile().writeAsStringSync('{"version": ');
        expect(await make().reconcileAfterStart(currentVersion: '1.14.1'), isNull);
        expect(pendingFile().existsSync(), isFalse);
      });
    });

    group('launch', () {
      late File setup;
      late String sha;

      setUp(() async {
        setup = File('${staging.path}${Platform.pathSeparator}SilentGateSetup-1.14.1.exe');
        setup.writeAsBytesSync(List.generate(1000, (i) => i & 0xff));
        sha = await Sha256.ofFile(setup);
      });

      test('⚠️ хэш изменился после проверки — установщик НЕ стартует, pending.json нет',
          () async {
        var started = false;
        final inst = make(reg: null, start: (_, __) async => started = true);
        // Файл подменили между проверкой и запуском (TOCTOU).
        setup.writeAsBytesSync(List.generate(1000, (i) => (i + 1) & 0xff));

        await expectLater(
          inst.launch(setup, version: '1.14.1', expectedSha256: sha),
          throwsA(isA<UpdateInstallException>()),
        );
        expect(started, isFalse);
        expect(pendingFile().existsSync(), isFalse);
      });

      test('хэш совпал — запуск с аргументами buildSetupArgs и pending.json', () async {
        String? exePath;
        List<String>? args;
        final before = DateTime.now().toUtc();
        final inst = make(
          reg: null,
          start: (e, a) async {
            exePath = e;
            args = a;
          },
        );

        await inst.launch(setup,
            version: '1.14.1', expectedSha256: sha.toUpperCase(), forceQuit: true);

        final logPath = '${staging.path}${Platform.pathSeparator}install-1.14.1.log';
        expect(exePath, setup.path);
        expect(
            args,
            buildSetupArgs(
                installLocation: installed,
                logPath: logPath,
                forceQuit: true,
                allowDowngrade: false));

        final p = PendingInstall.tryParse(pendingFile().readAsStringSync());
        expect(p, isNotNull);
        expect(p!.version, '1.14.1');
        expect(p.exePath, setup.path);
        expect(p.logPath, logPath);
        expect(p.startedAt.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
      });

      test('allowDowngrade прокидывается в /FORCEDOWNGRADE', () async {
        List<String>? args;
        final inst = make(reg: null, start: (_, a) async => args = a);
        await inst.launch(setup,
            version: '1.13.0', expectedSha256: sha, allowDowngrade: true);
        expect(args, contains(SetupArgs.forceDowngrade));
        expect(args, isNot(contains(SetupArgs.forceQuit)));
      });

      test('не ready (портативная копия) — отказ до всякого запуска', () async {
        var started = false;
        final inst = make(reg: null, portable: true, start: (_, __) async => started = true);
        await expectLater(
          inst.launch(setup, version: '1.14.1', expectedSha256: sha),
          throwsA(isA<UpdateInstallException>()
              .having((e) => e.message, 'message', contains('portable'))),
        );
        expect(started, isFalse);
        expect(pendingFile().existsSync(), isFalse);
      });

      test('процесс не запустился — pending.json не остаётся', () async {
        final inst = make(reg: null, start: (_, __) async => throw const ProcessException('x', []));
        await expectLater(
          inst.launch(setup, version: '1.14.1', expectedSha256: sha),
          throwsA(isA<UpdateInstallException>()),
        );
        expect(pendingFile().existsSync(), isFalse);
      });
    });

    group('purgeStaging', () {
      test('чистит всё, кроме файлов сохраняемой версии и pending.json', () async {
        final sep = Platform.pathSeparator;
        final keepExe = File('${staging.path}${sep}SilentGateSetup-1.14.1.exe')..writeAsStringSync('a');
        final keepLog = File('${staging.path}${sep}install-1.14.1.log')..writeAsStringSync('b');
        final oldExe = File('${staging.path}${sep}SilentGateSetup-1.14.0.exe')..writeAsStringSync('c');
        final part = File('${staging.path}${sep}SilentGateSetup-1.14.2.exe.part')..writeAsStringSync('d');
        final sub = Directory('${staging.path}${sep}junk')..createSync();
        await writePending(version: '1.14.1', startedAt: DateTime.now().toUtc());

        await make().purgeStaging(keepVersion: '1.14.1');

        expect(keepExe.existsSync(), isTrue);
        expect(keepLog.existsSync(), isTrue);
        expect(oldExe.existsSync(), isFalse);
        expect(part.existsSync(), isFalse);
        expect(sub.existsSync(), isFalse);
        expect(pendingFile().existsSync(), isTrue, reason: 'pending.json — забота reconcile');
      });

      test('без keepVersion удаляет все файлы версий', () async {
        final sep = Platform.pathSeparator;
        final a = File('${staging.path}${sep}SilentGateSetup-1.14.1.exe')..writeAsStringSync('a');
        final b = File('${staging.path}${sep}install-1.14.1.log')..writeAsStringSync('b');
        await make().purgeStaging();
        expect(a.existsSync(), isFalse);
        expect(b.existsSync(), isFalse);
        expect(staging.existsSync(), isTrue);
      });

      test('каталога ещё нет — не падает', () async {
        staging.deleteSync(recursive: true);
        await make().purgeStaging();
      });
    });

    test('capability — через инъецированный реестр', () async {
      expect(await make(reg: null).capability(), InstallCapability.ready);
      expect(await make(reg: '').capability(), InstallCapability.notInstalled);
      expect(await make(reg: regOut(r'D:\Other\')).capability(),
          InstallCapability.locationMismatch);
    }, skip: Platform.isWindows ? false : 'на других ОС capability() всегда unsupported');
  });

  group('FakeUpdateInstaller', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_upd_fake_');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('записывает вызовы и отдаёт настроенные ответы', () async {
      final fake = FakeUpdateInstaller(staging: tmp)
        ..capabilityResult = InstallCapability.portable
        ..pendingResult = PendingResult(
          outcome: PendingOutcome.failed,
          pending: PendingInstall(
              version: '1.14.1', startedAt: DateTime.now(), exePath: 'e', logPath: 'l'),
          logTail: 'tail',
        );

      expect(await fake.capability(), InstallCapability.portable);
      expect((await fake.stagingDir()).path, tmp.path);

      final f = File('${tmp.path}${Platform.pathSeparator}x.exe')..writeAsStringSync('x');
      await fake.launch(f, version: '1.14.1', expectedSha256: 'abc', forceQuit: true);
      expect(fake.launches.single.file.path, f.path);
      expect(fake.launches.single.version, '1.14.1');
      expect(fake.launches.single.expectedSha256, 'abc');
      expect(fake.launches.single.forceQuit, isTrue);
      expect(fake.launches.single.allowDowngrade, isFalse);

      final r = await fake.reconcileAfterStart(currentVersion: '1.14.0');
      expect(r?.outcome, PendingOutcome.failed);
      expect(fake.reconcileCalls, ['1.14.0']);
      // Ответ одноразовый: на втором старте pending.json уже нет.
      expect(await fake.reconcileAfterStart(currentVersion: '1.14.0'), isNull);

      await fake.purgeStaging(keepVersion: '1.14.1');
      expect(fake.purgeCalls, ['1.14.1']);
    });

    test('launchError — отказ запуска по сценарию теста', () async {
      final fake = FakeUpdateInstaller(staging: tmp)
        ..launchError = const UpdateInstallException('нет');
      await expectLater(
        fake.launch(File('${tmp.path}/x.exe'), version: '1', expectedSha256: 'a'),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(fake.launches, isEmpty, reason: 'несостоявшийся запуск не записывается');
    });
  });
}
