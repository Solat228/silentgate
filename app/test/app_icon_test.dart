// Проверка извлечения реальной иконки exe (#1): FFI/win32 работает в тестах на хосте.
// VPN не затрагивается — это чтение ресурсов файла.
@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/app_icon_windows.dart';

void main() {
  test('иконка notepad.exe извлекается в валидный PNG', () {
    final png = AppIconWindows.iconPng(r'C:\Windows\System32\notepad.exe');
    expect(png, isNotNull, reason: 'SHGetFileInfo должен вернуть HICON');
    expect(png!.length, greaterThan(100));
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // Кэш: повторный вызов возвращает тот же объект.
    expect(identical(AppIconWindows.iconPng(r'C:\Windows\System32\notepad.exe'), png),
        isTrue);
  });

  test('несуществующий exe → null (заглушка в UI)', () {
    expect(AppIconWindows.iconPng(r'C:\nonexistent\zzz.exe'), isNull);
  });
}
