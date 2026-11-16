import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// СТРАЖ СБОРКИ STORE-ВАРИАНТА В CI (заявка MS6, подпись SignPath).
///
/// ⚠️ РАДИ ЧЕГО. Store-вариант собирается двумя путями: руками через
/// `build-exe.bat` и на раннере GitHub через `.github/workflows/build.yml` +
/// `tools/stage-release.ps1`. Батник на раннере не запустить (junction, путь к
/// Flutter владельца, `pause`), поэтому раскладка файлов продублирована — и
/// разойтись она может молча: сборка из CI отличалась бы от проверенной в VM.
/// Здесь сверяется то, что обязано совпадать, плюс требования SignPath
/// (метаданные «SilentGate», свои исходники ядра, никакой самопубликации).
void main() {
  final workflow = File('../.github/workflows/build.yml');
  final exeBat = File('../build-exe.bat');
  final stage = File('../tools/stage-release.ps1');
  final buildCore = File('../tools/build-xraycore.ps1');
  final fetchXray = File('../tools/fetch-xray.ps1');
  final iss = File('../installer/silentgate.iss');
  final runnerRc = File('windows/runner/Runner.rc');
  final goMod = File('../engine/xraycore/go.mod');
  final winres = File('../engine/xraycore/winres/winres.json');

  // Батник в cp866, но всё, что сверяется, — ASCII: latin1 его не портит.
  String bat() => latin1.decode(exeBat.readAsBytesSync());

  group('workflow', () {
    test('собирает тот же Store-вариант, что build-exe.bat', () {
      final wf = workflow.readAsStringSync();
      expect(wf, contains('--dart-define=SILENTGATE_STORE=msstore'));
      expect(wf, contains('--dart-define=SILENTGATE_NO_TUN=true'));
      // В батнике значения подставляются из переменных окружения.
      expect(bat(), contains('--dart-define=SILENTGATE_STORE=%SILENTGATE_STORE%'));
      expect(bat(), contains('--dart-define=SILENTGATE_NO_TUN=true'));
      expect(wf, contains('/DSetupSuffix=-msstore /DNoTun'));
      expect(wf, contains('stage-release.ps1 -NoTun'));
      expect(wf, contains('build-xraycore.ps1'));
    });

    test('ничего не публикует сам и не просит прав на запись', () {
      final wf = workflow.readAsStringSync();
      // Прежний build.yml по тегу v* сам создавал релиз — выпуски делает
      // публикатор руками, и тег от него не должен запускать выкладку.
      expect(wf, isNot(contains('action-gh-release')));
      expect(wf, isNot(contains('tags:')));
      expect(wf, isNot(contains('contents: write')));
      expect(wf, contains('contents: read'));
    });

    test('репетиция подписи не трогает flutter_windows.dll', () {
      // Чужую готовую сборку SignPath не подпишет; если репетиция подпишет её,
      // CI покажет картину, которой в настоящей подписи не будет.
      expect(workflow.readAsStringSync(),
          contains("Where-Object { \$_.Name -ne 'flutter_windows.dll' }"));
    });
  });

  group('раскладка файлов', () {
    List<String> batCores({required bool noTun}) {
      final re = noTun
          ? RegExp(r'if defined SILENTGATE_NO_TUN set "CORES=([^"]+)"')
          : RegExp(r'^set "CORES=([^"]+)"', multiLine: true);
      final m = re.firstMatch(bat());
      expect(m, isNotNull, reason: 'не найден список CORES в build-exe.bat');
      return m!.group(1)!.split(' ')..sort();
    }

    List<String> ps1Cores({required bool noTun}) {
      final src = stage.readAsStringSync();
      final blocks = RegExp(r"@\(([^)]*)\)").allMatches(src).toList();
      // Первые два массива — состав без драйвера и с драйвером.
      final raw = blocks[noTun ? 0 : 1].group(1)!;
      return RegExp(r"'([^']+)'").allMatches(raw).map((m) => m.group(1)!).toList()
        ..sort();
    }

    test('без драйвера — те же ядра, что в build-exe.bat', () {
      expect(ps1Cores(noTun: true), batCores(noTun: true));
    });

    test('с драйвером — те же ядра, что в build-exe.bat', () {
      expect(ps1Cores(noTun: false), batCores(noTun: false));
    });

    test('без драйвера его файлы убираются из Release', () {
      final src = stage.readAsStringSync();
      for (final f in ['sing-box.exe', 'wintun.dll', 'LICENSE-wintun.txt', 'LICENSE-singbox.txt']) {
        expect(src, contains(f));
      }
    });
  });

  group('метаданные (SignPath: «product name = имя проекта»)', () {
    test('silentgate.exe', () {
      final rc = runnerRc.readAsStringSync();
      expect(rc, contains('VALUE "ProductName", "SilentGate"'));
      expect(rc, contains('VALUE "CompanyName", "SilentGate"'));
      expect(rc, isNot(contains('lol.silentgate')));
      expect(rc, isNot(contains('All rights reserved')),
          reason: 'клиент под GPL-3.0');
    });

    test('ядро Xray', () {
      final info = (jsonDecode(winres.readAsStringSync())
          as Map)['RT_VERSION']['#1']['0000']['info']['0409'] as Map;
      expect(info['ProductName'], 'SilentGate');
      expect(info['CompanyName'], 'SilentGate');
      expect(info['OriginalFilename'], 'xray.exe',
          reason: 'приложение ищет ядро по имени xray.exe (XrayPaths.locate)');
    });

    test('установщик', () {
      expect(iss.readAsStringSync(), contains('VersionInfoProductName={#MyAppName}'));
    });
  });

  test('своё ядро и геобазы — одной версии Xray-core', () {
    // Геобазы и текст лицензии берутся из официального архива (fetch-xray),
    // ядро собирается из go.mod. Разные версии = базы не от того ядра.
    final ver = RegExp(r"\$ver = '(\d+)\.(\d+)\.(\d+)'")
        .firstMatch(fetchXray.readAsStringSync())!;
    final mod = RegExp(r'github\.com/xtls/xray-core v1\.(\d\d)(\d\d)(\d\d)\.0')
        .firstMatch(goMod.readAsStringSync())!;
    expect([for (var i = 1; i <= 3; i++) int.parse(mod.group(i)!)],
        [for (var i = 1; i <= 3; i++) int.parse(ver.group(i)!)]);
    // Скрипт сборки проверяет ответ ядра той же версией.
    expect(buildCore.readAsStringSync(), contains(r'-notmatch "^Xray $([regex]::Escape($xrayVer)) "'));
  });

  test('dartjni.dll не едет в Windows-поставку', () {
    // Пакет jni нужен только path_provider_android; на Windows эта DLL —
    // лишний PE, который SignPath не подпишет (MS6). Исключение и стирание
    // старой копии живут в CMake, иначе Inno забрал бы её из Release.
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final remove = cmake.indexOf(r'list(REMOVE_ITEM PLUGIN_BUNDLED_LIBRARIES "$<TARGET_FILE:jni>")');
    final install = cmake.indexOf(r'install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"');
    expect(remove, greaterThan(-1));
    expect(remove, lessThan(install), reason: 'исключать до install(FILES)');
    expect(cmake, contains(r'file(REMOVE \"${INSTALL_BUNDLE_LIB_DIR}/dartjni.dll\")'));
  });

  test('деинсталлятор подписывается в два прохода только по запросу', () {
    final src = iss.readAsStringSync();
    final block = RegExp(r'#ifdef SignUninstallerDir([\s\S]*?)#endif').firstMatch(src);
    expect(block, isNotNull);
    expect(block!.group(1), contains('SignedUninstaller=yes'));
    expect(block.group(1), contains('SignedUninstallerDir={#SignUninstallerDir}'));
    // Вне блока подписи деинсталлятора нет: обычная сборка без сертификата
    // иначе упала бы на «нужна подпись».
    final outside = src.replaceFirst(block.group(0)!, '');
    expect(outside, isNot(contains('SignedUninstaller=')));
  });
}
