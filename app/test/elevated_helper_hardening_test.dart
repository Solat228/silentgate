import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/tun_helper.dart';
import 'package:silentgate/engine/windows/xray_paths.dart';

/// Помощник TUN работает с правами администратора, а всё, что он читает из
/// окружения пользователя и `%APPDATA%`, может подсунуть процесс без прав
/// (аудит 25.10.2026, D2).
void main() {
  test('поиск для помощника не смотрит ни в переменную, ни в текущий каталог',
      () {
    final trusted = XrayPaths.candidates(trusted: true);
    final exeDir = File(Platform.resolvedExecutable).parent.path.toLowerCase();
    const devTail = r'\engine\windows\bin\xray.exe';
    for (final c in trusted) {
      final low = c.toLowerCase();
      // Либо рядом с exe, либо dev-раскладка в одном из ПРЕДКОВ каталога exe.
      final root = low.endsWith(devTail)
          ? low.substring(0, low.length - devTail.length)
          : low.endsWith(r'\xray\xray.exe')
              ? File(low).parent.parent.path
              : File(low).parent.path;
      expect(exeDir.startsWith(root), isTrue, reason: c);
    }
    final env = Platform.environment['SILENTGATE_XRAY'];
    if (env != null && env.isNotEmpty) {
      expect(trusted, isNot(contains(env)));
    }
  });

  test('конфиг для ядра помощника теряет поля, пишущие файлы', () {
    final raw = jsonEncode({
      'log': {'level': 'info', 'output': r'C:\Windows\System32\x.dll'},
      'experimental': {
        'cache_file': {'enabled': true, 'path': r'C:\Windows\x'},
        'clash_api': {
          'external_controller': '127.0.0.1:10813',
          'secret': 's',
          'external_ui': r'C:\Windows',
          'external_ui_download_url': 'https://example.com/ui.zip',
          'external_ui_download_detour': 'direct',
        },
      },
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
      ],
    });
    final out =
        jsonDecode(TunHelper.sanitizeElevatedConfig(raw)) as Map<String, dynamic>;
    expect(out['log'], {'level': 'info'});
    final exp = out['experimental'] as Map;
    expect(exp.containsKey('cache_file'), isFalse);
    expect(exp['clash_api'],
        {'external_controller': '127.0.0.1:10813', 'secret': 's'});
    expect(out['outbounds'], isNotEmpty);
  });

  test('конфиг без этих разделов проходит как есть', () {
    final raw = jsonEncode({
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
      ]
    });
    expect(jsonDecode(TunHelper.sanitizeElevatedConfig(raw)), jsonDecode(raw));
  });

  test('помощник запускает ядро с конфигом из stdin и доверенным путём', () {
    final src =
        File('lib/engine/windows/tun/tun_helper.dart').readAsStringSync();
    expect(src, contains("['run', '-c', 'stdin']"));
    expect(src, isNot(contains("['run', '-c', configPath]")));
    expect(src, isNot(contains('XrayPaths.locate()')));
    expect(src, contains('sanitizeElevatedConfig('));
  });
}
