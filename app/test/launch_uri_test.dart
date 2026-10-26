import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_launcher.dart';
import 'package:silentgate/core/platform/launch_uri.dart';

/// Ссылки на открытие приходят от чужих серверов (`support-url` панели).
/// До 26.10.2026 Windows открывала их через `cmd /c start`, и `&` в ссылке
/// исполнял вторую команду.
class _Recorder implements AppLauncher {
  final opened = <String>[];
  final telegram = <String>[];
  @override
  Future<void> open(String url) async => opened.add(url);
  @override
  Future<void> openTelegram(String url) async => telegram.add(url);
}

void main() {
  group('safeLaunchUri', () {
    test('обычные ссылки проходят', () {
      expect(safeLaunchUri('https://t.me/support'), 'https://t.me/support');
      expect(safeLaunchUri('  http://example.com/a?b=1&c=2 '),
          'http://example.com/a?b=1&c=2');
      expect(safeLaunchUri('tg://resolve?domain=x'), 'tg://resolve?domain=x');
      expect(safeLaunchUri('ms-windows-store://downloadsandupdates'),
          isNotNull);
      expect(safeLaunchUri('mailto:a@example.com'), isNotNull);
    });

    test('⚠️ опасные символы не доходят до системы сырыми', () {
      final s = safeLaunchUri('https://example.com/x"&calc ^|<>')!;
      for (final bad in ['"', ' ', '^', '|', '<', '>']) {
        expect(s, isNot(contains(bad)), reason: 'символ «$bad» обязан стать %XX');
      }
    });

    test('⚠️ чужие схемы и пути отвергаются', () {
      for (final bad in [
        'file:///C:/Windows/System32/calc.exe',
        r'C:\Windows\System32\calc.exe',
        r'\\server\share\x.exe',
        'javascript:alert(1)',
        'ms-settings:',
        'search-ms:query=x',
        'calc',
        'https://',
        '',
        '   ',
      ]) {
        expect(safeLaunchUri(bad), isNull, reason: bad);
      }
    });
  });

  group('UrlOpener', () {
    late _Recorder rec;
    setUp(() => setAppLauncherForTests(rec = _Recorder()));
    tearDown(() => setAppLauncherForTests(null));

    test('пропускает только проверенное', () async {
      await UrlOpener.open('https://example.com/?a&b');
      await UrlOpener.open('file:///C:/x.exe');
      await UrlOpener.openTelegram('https://t.me/x');
      await UrlOpener.openTelegram(r'C:\x.exe');
      expect(rec.opened, ['https://example.com/?a&b']);
      expect(rec.telegram, ['https://t.me/x']);
    });
  });

  test('⚠️ страж: ссылки больше не открываются через cmd', () {
    final src = File('lib/core/platform/app_launcher_windows.dart')
        .readAsStringSync();
    expect(src, isNot(contains("'cmd'")),
        reason: 'cmd разбирает & | ^ в ссылке как команды');
    expect(src, isNot(contains('runInShell: true')));
    final report =
        File('lib/engine/windows/support_report.dart').readAsStringSync();
    expect(report, isNot(contains("'/c', 'start'")));
  });
}
