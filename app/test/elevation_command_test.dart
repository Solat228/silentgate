import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/elevation.dart';

/// Команда посредника собирается строкой, поэтому единственная неверная кавычка
/// превращается в «конфиг не найден» уже внутри элевейтнутого хелпера — там,
/// где это выглядит как совсем другая поломка.
void main() {
  test('пути с пробелами приходят одним аргументом', () {
    final cmd = Elevation.psCommand(
      r'C:\Program Files\SilentGate\silentgate.exe',
      r'--tun "C:\Users\Иван Петров\AppData\Roaming\SilentGate\cfg.json" '
          r'"C:\Users\Иван Петров\AppData\Roaming\SilentGate\tun_stop"',
    );
    expect(cmd, contains(r"-FilePath 'C:\Program Files\SilentGate\silentgate.exe'"));
    expect(cmd, contains(r"'--tun','C:\Users\Иван Петров"));
    // Кавычки из исходной строки внутрь аргумента попасть не должны.
    expect(cmd.contains('"'), isFalse);
  });

  test('апостроф в пути экранируется удвоением', () {
    // Учётка вида O'Brien — путь с апострофом ломает одинарные кавычки PowerShell.
    final cmd = Elevation.psCommand("C:\\Users\\O'Brien\\app.exe", '--tun "a b"');
    expect(cmd, contains("'C:\\Users\\O''Brien\\app.exe'"));
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

  test('без аргументов -ArgumentList не пишется (пустой список — ошибка PS)', () {
    expect(Elevation.psCommand('x.exe', '').contains('-ArgumentList'), isFalse);
  });

  test('скрытое окно по умолчанию', () {
    expect(Elevation.psCommand('x.exe', '-a'), contains('-WindowStyle Hidden'));
    expect(Elevation.psCommand('x.exe', '-a', show: true),
        contains('-WindowStyle Normal'));
  });
}
