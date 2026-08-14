import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_cleanup.dart';

/// Деинсталлятор не имеет права ронять ЧУЖОЙ VPN.
///
/// `AppCleanup.runHeadless` гасил ядра через `taskkill /F /IM xray.exe /T` —
/// по ИМЕНИ ОБРАЗА, то есть по всей машине. Имена `xray.exe` и `sing-box.exe`
/// носят Happ, v2rayTun, NekoBox и ещё десяток клиентов: удаление SilentGate
/// обрывало живой туннель соседней программы, и человек не связывал пропавший
/// интернет с удалением ДРУГОГО приложения.
///
/// Здесь два эшелона проверки:
///  1. поведение шва (`ownCoreDir`/`killOwnCores`): что уходит в общий отбор
///     своего/чужого и когда не уходит ничего;
///  2. страж по исходникам: гашения по имени образа не должно быть НИГДЕ в
///     `lib/` — ни здесь, ни в скопированном отсюда коде следующей платформы.
void main() {
  group('AppCleanup.ownCoreDir', () {
    test('папка ядер завершается разделителем — иначе совпадёт соседняя', () {
      final dir = AppCleanup.ownCoreDir(assetDir: r'C:\Program Files\SilentGate');
      expect(dir, r'C:\Program Files\SilentGate\');

      // ⚠️ Ради чего разделитель: `CoreCleanup.sweepOrphans` сравнивает путь
      // процесса ПРЕФИКСОМ строки. Повторяем ровно то сравнение — без
      // завершающего `\` чужая папка с похожим именем прошла бы за свою.
      String path(String p) => p.toLowerCase().replaceAll('/', r'\');
      final ours = path(r'C:\Program Files\SilentGate\xray.exe');
      final foreign = path(r'C:\Program Files\SilentGateFork\xray.exe');
      expect(ours.startsWith(path(dir!)), isTrue);
      expect(foreign.startsWith(path(dir)), isFalse,
          reason: 'чужой клиент в соседней папке принят за свой');
    });

    test('лишние разделители и прямые слэши приводятся к одному виду', () {
      expect(AppCleanup.ownCoreDir(assetDir: r'C:\App\bin\\'), r'C:\App\bin\');
      expect(AppCleanup.ownCoreDir(assetDir: 'C:/App/bin'), r'C:\App\bin\');
    });

    test('пустой источник — берётся следующий', () {
      expect(AppCleanup.ownCoreDir(assetDir: '   ', exeDir: r'D:\SG'),
          r'D:\SG\');
    });

    test('корень диска и голая шара — не «своя папка»', () {
      // Под корнем лежит вся машина: приняв его за свою папку, страж своего
      // и чужого перестал бы что-либо различать.
      expect(AppCleanup.ownCoreDir(assetDir: r'C:\', exeDir: ''), isNull);
      expect(AppCleanup.ownCoreDir(assetDir: 'C:', exeDir: ''), isNull);
      expect(AppCleanup.ownCoreDir(assetDir: r'\\server', exeDir: ''), isNull);
      expect(AppCleanup.ownCoreDir(assetDir: r'\\server\share', exeDir: ''),
          r'\\server\share\');
    });

    test('источников нет — папки нет', () {
      expect(AppCleanup.ownCoreDir(assetDir: '', exeDir: ''), isNull);
    });
  });

  group('AppCleanup.killOwnCores', () {
    test('гасим по НАШЕЙ папке, а не по имени образа', () async {
      final asked = <String>[];
      await AppCleanup.killOwnCores(
        assetDir: r'C:\Program Files\SilentGate\bin',
        sweep: (dir) async => asked.add(dir),
      );
      // Единственный аргумент — папка. Имени образа тут нет и быть не может:
      // отбор процессов делает общий `CoreCleanup.sweepOrphans` по путям.
      expect(asked, [r'C:\Program Files\SilentGate\bin\']);
    });

    test('свою папку не нашли — не гасим НИЧЕГО', () async {
      // Цена ошибки несимметрична: осиротевшее своё ядро подберут при
      // следующем запуске, а чужой убитый туннель не вернуть.
      final asked = <String>[];
      await AppCleanup.killOwnCores(
        assetDir: '',
        exeDir: '',
        sweep: (dir) async => asked.add(dir),
      );
      expect(asked, isEmpty);
    });
  });

  group('страж: по имени образа не гасим нигде в lib/', () {
    /// Выбрасывает строки-комментарии: страж смотрит на КОД, а не на прозу.
    /// Иначе разбор дефекта в doc-комментарии (а он тут есть — про прежний
    /// `taskkill`) сам считался бы нарушением.
    String stripCommentLines(String src) => src
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
        })
        .join('\n');

    /// Описание нарушения, либо null.
    String? imageKillProblem(String source) {
      final src = stripCommentLines(source);
      final lower = src.toLowerCase();
      if (lower.contains('taskkill') &&
          RegExp(r'/IM\b', caseSensitive: false).hasMatch(src)) {
        return 'taskkill по имени образа (/IM) — гасит и чужие клиенты';
      }
      if (lower.contains('stop-process') && lower.contains('-name')) {
        return 'Stop-Process по имени — то же самое средствами PowerShell';
      }
      return null;
    }

    test('исходники lib/ чисты', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.replaceAll(r'\', '/');
        final problem = imageKillProblem(f.readAsStringSync());
        if (problem != null) offenders.add('$rel — $problem');
      }
      expect(offenders, isEmpty,
          reason: 'удаление SilentGate оборвёт чужой живой туннель '
              '(Happ/v2rayTun/NekoBox носят те же имена ядер): $offenders');
    });

    test('страж ловит нарушение — проверено на образцах', () {
      // ⚠️ Страж выше читает `lib/`, и пока там чисто, он зелёный при ЛЮБОЙ
      // своей логике, включая сломанную. Здесь ТА ЖЕ функция гоняется по
      // заведомым образцам — «перестал ловить» видно сразу.
      expect(
          imageKillProblem(
              "await Process.run('taskkill', ['/F', '/IM', image, '/T']);"),
          isNotNull,
          reason: 'ровно тот вызов, что стоял в runHeadless');
      expect(imageKillProblem('Get-Process -Name xray | Stop-Process -Force'),
          isNotNull);
      // Гашение по PID законно: PID получен отбором по НАШЕМУ пути.
      expect(
          imageKillProblem(
              "await Process.run('taskkill', ['/F', '/PID', '\$pid']);"),
          isNull);
      // Разбор прежнего дефекта в комментарии — не дефект.
      expect(imageKillProblem('/// Раньше здесь: taskkill /F /IM xray.exe /T'),
          isNull);
    });
  });
}
