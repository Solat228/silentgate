import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/system_proxy.dart';

/// Отключение VPN возвращает системный прокси, каким он был ДО подключения
/// (MS1, решение владельца 19.10.2026).
///
/// До 1.17.0 снятие только выключало прокси: у человека с корпоративным
/// прокси или Fiddler после отключения VPN его настройка оказывалась
/// выключенной, а адрес — нашим.
///
/// ⚠️ РЕЕСТР НЕ ТРОГАЕТСЯ: `reg.exe` подменён моделью реестра в памяти.
void main() {
  late Map<String, String> reg;
  late List<List<String>> calls;
  late Directory tmp;

  const key =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// Модель `reg.exe` поверх [reg]: `query`, `add`, `delete`.
  void arm() {
    calls = [];
    SystemProxy.runner = (exe, args) async {
      calls.add(args);
      final name = args[args.indexOf('/v') + 1];
      switch (args.first) {
        case 'query':
          final v = reg[name];
          if (v == null) return ProcessResult(0, 1, '', 'not found');
          final type = name == 'ProxyEnable' ? 'REG_DWORD' : 'REG_SZ';
          return ProcessResult(
              0, 0, '\r\nHKEY_CURRENT_USER\\...\r\n    $name    $type    $v\r\n\r\n', '');
        case 'add':
          final d = args[args.indexOf('/d') + 1];
          reg[name] = name == 'ProxyEnable' ? '0x$d' : d;
          return ProcessResult(0, 0, '', '');
        case 'delete':
          if (reg.remove(name) == null) return ProcessResult(0, 1, '', '');
          return ProcessResult(0, 0, '', '');
      }
      return ProcessResult(0, 1, '', '');
    };
  }

  setUp(() {
    reg = {};
    arm();
    tmp = Directory.systemTemp.createTempSync('sg_proxy_restore_');
    SystemProxy.markerPathOverride =
        '${tmp.path}${Platform.pathSeparator}proxy.lock';
  });

  tearDown(() {
    SystemProxy.resetRunnerForTests();
    SystemProxy.markerPathOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('чужой включённый прокси возвращается целиком', () async {
    reg = {
      'ProxyEnable': '0x1',
      'ProxyServer': '192.0.2.10:3128',
      'ProxyOverride': '*.corp.example;<local>',
    };
    expect(await SystemProxy.set('127.0.0.1:10809'), isTrue);
    expect(reg['ProxyServer'], '127.0.0.1:10809');
    expect(await SystemProxy.clear(), isTrue);
    expect(reg, {
      'ProxyEnable': '0x1',
      'ProxyServer': '192.0.2.10:3128',
      'ProxyOverride': '*.corp.example;<local>',
    });
    expect(File(SystemProxy.markerPathOverride!).existsSync(), isFalse);
  });

  test('прокси не было — после снятия значений нет, прокси выключен', () async {
    await SystemProxy.set('127.0.0.1:10809');
    await SystemProxy.clear();
    expect(reg['ProxyEnable'], '0x0');
    expect(reg.containsKey('ProxyServer'), isFalse,
        reason: 'нашего адреса после отключения быть не должно');
    expect(reg.containsKey('ProxyOverride'), isFalse);
  });

  test('выключенный чужой адрес остаётся выключенным, но адрес возвращается',
      () async {
    reg = {'ProxyEnable': '0x0', 'ProxyServer': '192.0.2.10:8888'};
    await SystemProxy.set('127.0.0.1:10809');
    await SystemProxy.clear();
    expect(reg['ProxyEnable'], '0x0');
    expect(reg['ProxyServer'], '192.0.2.10:8888');
  });

  test('⚠️ повторный set не затирает снимок нашим же адресом', () async {
    reg = {'ProxyEnable': '0x1', 'ProxyServer': '192.0.2.10:3128'};
    await SystemProxy.set('127.0.0.1:10809');
    // Смена сервера / переподключение: set поверх живого.
    await SystemProxy.set('127.0.0.1:10809');
    await SystemProxy.clear();
    expect(reg['ProxyServer'], '192.0.2.10:3128');
    expect(reg['ProxyEnable'], '0x1');
  });

  test('⚠️ авария: снимок в маркере, следующий запуск возвращает прежнее',
      () async {
    reg = {'ProxyEnable': '0x1', 'ProxyServer': '192.0.2.10:3128'};
    await SystemProxy.set('127.0.0.1:10809');
    // Процесс умер — следующий запуск видит маркер.
    await SystemProxy.recoverIfDirty();
    expect(reg['ProxyServer'], '192.0.2.10:3128');
    expect(reg['ProxyEnable'], '0x1');
  });

  test('наш адрес, включённый без маркера, не считается «прежним»', () async {
    // Прошлый запуск упал, а маркер пропал (чистка %TEMP%): вернуть трафик
    // на мёртвый порт = оставить машину без интернета.
    reg = {'ProxyEnable': '0x1', 'ProxyServer': '127.0.0.1:10809'};
    await SystemProxy.set('127.0.0.1:10809');
    await SystemProxy.clear();
    expect(reg['ProxyEnable'], '0x0');
    expect(reg.containsKey('ProxyServer'), isFalse);
  });

  test('маркер старого формата: просто выключаем, как раньше', () async {
    File(SystemProxy.markerPathOverride!).writeAsStringSync('127.0.0.1:10809');
    reg = {'ProxyEnable': '0x1', 'ProxyServer': '127.0.0.1:10809'};
    await SystemProxy.recoverIfDirty();
    expect(reg['ProxyEnable'], '0x0');
    expect(calls.where((c) => c.first == 'add').length, 1);
  });

  group('разбор вывода reg query', () {
    test('строка, DWORD, пустое значение', () {
      const out = '\r\nHKEY_CURRENT_USER\\Software\r\n'
          '    ProxyServer    REG_SZ    192.0.2.10:3128\r\n'
          '    ProxyEnable    REG_DWORD    0x1\r\n'
          '    ProxyOverride    REG_SZ    \r\n';
      expect(SystemProxy.parseRegValue(out, 'ProxyServer'), '192.0.2.10:3128');
      expect(SystemProxy.parseRegValue(out, 'ProxyEnable'), '0x1');
      expect(SystemProxy.parseRegValue(out, 'ProxyOverride'), '');
      expect(SystemProxy.parseRegValue(out, 'AutoConfigURL'), isNull);
      expect(SystemProxy.parseRegDword('0x1'), 1);
      expect(SystemProxy.parseRegDword('0x0'), 0);
      expect(SystemProxy.parseRegDword('мусор'), isNull);
    });

    test('ключ в выводе не путается со значением', () {
      // Строка ключа содержит «Internet Settings», но не «ProxyServer REG_».
      expect(
          SystemProxy.parseRegValue('$key\r\n', 'ProxyServer'), isNull);
    });
  });
}
