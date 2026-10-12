import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/elevation.dart';
import 'package:silentgate/engine/windows/tun/tun_scheduled_task.dart';

/// Команда посредника собирается строкой, поэтому единственная неверная кавычка
/// превращается в «конфиг не найден» уже внутри элевейтнутого хелпера — там,
/// где это выглядит как совсем другая поломка.
void main() {
  /// Обратно из `-EncodedCommand`: base64 от UTF-16LE.
  String decodePs(String b64) {
    final b = base64.decode(b64);
    return String.fromCharCodes([
      for (var i = 0; i + 1 < b.length; i += 2) b[i] | (b[i + 1] << 8),
    ]);
  }

  group('psCommand', () {
    test('⚠️ параметры уходят ОДНОЙ строкой, как есть', () {
      // `Start-Process -ArgumentList` склеивает массив пробелом и ничего не
      // экранирует: путь с пробелом, отданный отдельным элементом, на той
      // стороне снова распадался на два аргумента.
      const params = r'--tun "C:\Users\Иван Петров\AppData\Roaming\SilentGate\cfg.json" '
          r'"C:\Users\Иван Петров\AppData\Roaming\SilentGate\tun_stop"';
      final cmd = Elevation.psCommand(
          r'C:\Program Files\SilentGate\silentgate.exe', params);
      expect(cmd,
          contains(r"-FilePath 'C:\Program Files\SilentGate\silentgate.exe'"));
      expect(cmd, contains("-ArgumentList '$params'"));
    });

    test('апостроф в пути экранируется удвоением', () {
      // Учётка вида O'Brien — путь с апострофом ломает одинарные кавычки PowerShell.
      final cmd =
          Elevation.psCommand("C:\\Users\\O'Brien\\app.exe", "--tun \"O'B\"");
      expect(cmd, contains("'C:\\Users\\O''Brien\\app.exe'"));
      expect(cmd, contains("-ArgumentList '--tun \"O''B\"'"));
    });

    test('разные исходы различимы по коду возврата', () {
      final cmd = Elevation.psCommand('x.exe', '');
      // 1 — пользователь отказал (Win32Exception), 2 — посредник не смог даже
      // попытаться. Слить их в один код нельзя: первый окончателен, второй
      // означает «пробуй другим способом».
      expect(cmd, contains('exit 0'));
      expect(cmd, contains('Win32Exception] { exit 1 }'));
      expect(cmd, contains('catch { exit 2 }'));
    });

    test('с ожиданием: отказ команды (код 3) отличим от отказа в правах', () {
      final cmd = Elevation.psCommand('schtasks.exe', '/Query', wait: true);
      expect(cmd, contains('-Wait -PassThru'));
      expect(cmd, contains(r'if ($p.ExitCode -ne 0) { exit 3 }'));
      expect(Elevation.psCommand('x.exe', '-a'), isNot(contains('-Wait')));
    });

    test('без аргументов -ArgumentList не пишется (пустой список — ошибка PS)', () {
      expect(Elevation.psCommand('x.exe', '').contains('-ArgumentList'), isFalse);
      expect(
          Elevation.psCommand('x.exe', '   ').contains('-ArgumentList'), isFalse);
    });

    test('скрытое окно по умолчанию', () {
      expect(Elevation.psCommand('x.exe', '-a'), contains('-WindowStyle Hidden'));
      expect(Elevation.psCommand('x.exe', '-a', show: true),
          contains('-WindowStyle Normal'));
    });
  });

  group('encodePs / outcomeOfPsExit', () {
    test('кодирование обратимо, кириллица и кавычки целы', () {
      const s = r'''Start-Process 'C:\Иван\a.exe' -ArgumentList '"x y" \"z\"' ''';
      expect(decodePs(Elevation.encodePs(s)), s);
    });

    test('коды посредника → исходы', () {
      expect(Elevation.outcomeOfPsExit(0), ElevationOutcome.ok);
      expect(Elevation.outcomeOfPsExit(1), ElevationOutcome.denied);
      expect(Elevation.outcomeOfPsExit(2), isNull,
          reason: 'посредник не смог — это не отказ, пробуем другой путь');
      expect(Elevation.outcomeOfPsExit(3), ElevationOutcome.commandFailed,
          reason: 'права дали, упала команда — НЕ «UAC отклонён»');
      expect(Elevation.outcomeOfPsExit(-1), ElevationOutcome.denied);
    });
  });

  group('splitArgs — правила CommandLineToArgvW', () {
    test('простые пробелы и табы', () {
      expect(Elevation.splitArgs('a  b\tc'), ['a', 'b', 'c']);
      expect(Elevation.splitArgs(''), isEmpty);
      expect(Elevation.splitArgs('   '), isEmpty);
    });

    test('кавычки снимаются, пробел внутри сохраняется', () {
      expect(Elevation.splitArgs(r'/c "C:\Users\Иван Петров\x.bat"'),
          ['/c', r'C:\Users\Иван Петров\x.bat']);
    });

    test('косые не перед кавычкой — буквально', () {
      expect(Elevation.splitArgs(r'C:\a\b\\c'), [r'C:\a\b\\c']);
    });

    test(r'\" — буквальная кавычка, \\" — косая и разделитель', () {
      expect(Elevation.splitArgs(r'a\"b'), ['a"b']);
      expect(Elevation.splitArgs(r'"a\\" b'), [r'a\', 'b']);
      expect(Elevation.splitArgs(r'a\\\"b'), [r'a\"b']);
    });

    test('пустой аргумент в кавычках сохраняется', () {
      expect(Elevation.splitArgs(r'a "" b'), ['a', '', 'b']);
    });

    test('⚠️ строка schtasks /Create: /TR приходит одной командой с кавычками',
        () {
      // Ровно этот случай ломался: прежний разбор переключался на каждой
      // кавычке и про `\"` не знал. В задачу писалось `\I:\…\silentgate.exe\`,
      // и «Исправить» сдавалось, обвиняя UAC.
      const exe = r'I:\!Backup\!Projects\!VPN\SilentGateApp\app\silentgate.exe';
      const cfg = r'C:\Users\Иван Петров\AppData\Roaming\SilentGate\singbox_tun.json';
      const stop = r'C:\Users\Иван Петров\AppData\Roaming\SilentGate\tun_stop';
      final argv =
          Elevation.splitArgs(TunScheduledTask.createArgs(exe, cfg, stop));
      expect(argv, [
        '/Create',
        '/TN',
        TunScheduledTask.taskName,
        '/TR',
        '"$exe" --tun-task "$cfg" "$stop"',
        '/SC',
        'ONCE',
        '/ST',
        '00:00',
        '/RL',
        'HIGHEST',
        '/F',
      ]);
    });

    test('⚠️ /TR после разбора совпадает с тем, что потом сверяет isCurrent', () {
      // Если они разойдутся, свежесозданная задача будет считаться устаревшей
      // и «Исправить» не закончится никогда.
      const exe = r'C:\Program Files\SilentGate\silentgate.exe';
      const cfg = r'C:\Users\u\AppData\Roaming\SilentGate\singbox_tun.json';
      const stop = r'C:\Users\u\AppData\Roaming\SilentGate\tun_stop';
      final argv =
          Elevation.splitArgs(TunScheduledTask.createArgs(exe, cfg, stop));
      final tr = argv[argv.indexOf('/TR') + 1];
      const expectedArgs = '--tun-task "$cfg" "$stop"';
      expect(tr, '"$exe" $expectedArgs');
      // Так Планировщик раскладывает /TR по тегам задачи.
      final xml = '<Command>$exe</Command>'
          '<Arguments>${expectedArgs.replaceAll('"', '&quot;')}</Arguments>';
      expect(TunScheduledTask.matches(xml, exe, expectedArgs), isTrue);
    });
  });
}
