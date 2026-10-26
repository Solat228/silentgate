import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/network_recovery.dart';
import 'package:silentgate/core/platform/interference_scanner.dart';
import 'package:silentgate/core/platform/port_check.dart';
import 'package:silentgate/engine/windows/process_list_windows.dart';

/// Находки аудита 25.10.2026, H (ядро).
void main() {
  group('ss-ссылки', () {
    String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

    test('SIP002 с base64', () {
      final s = ShareLinkParser.tryParse(
          'ss://${b64('aes-256-gcm:secret')}@203.0.113.7:8388#A')!;
      expect(s.encryption, 'aes-256-gcm');
      expect(s.id, 'secret');
      expect(s.address, '203.0.113.7');
      expect(s.port, 8388);
      expect(s.isUnsupported, isFalse);
    });

    test('SIP002 без base64 (2022-шифры)', () {
      final s = ShareLinkParser.tryParse(
          'ss://2022-blake3-aes-128-gcm:YWJj%3D@203.0.113.7:8388#B')!;
      expect(s.encryption, '2022-blake3-aes-128-gcm');
      expect(s.id, 'YWJj=');
    });

    test('IPv6 в скобках', () {
      final s = ShareLinkParser.tryParse(
          'ss://${b64('aes-128-gcm:p')}@[2001:db8::1]:8388#C')!;
      expect(s.address, '2001:db8::1');
      expect(s.port, 8388);
    });

    test('старый формат целиком в base64', () {
      final s = ShareLinkParser.tryParse(
          'ss://${b64('chacha20-ietf-poly1305:pw@203.0.113.8:443')}#D')!;
      expect(s.encryption, 'chacha20-ietf-poly1305');
      expect(s.address, '203.0.113.8');
      expect(s.port, 443);
    });

    test('⚠️ плагин — сервер помечен неподдерживаемым, а не молча сломан', () {
      final s = ShareLinkParser.tryParse(
          'ss://${b64('aes-256-gcm:pw')}@203.0.113.7:8388/?plugin=obfs-local%3Bobfs%3Dhttp#E')!;
      expect(s.isUnsupported, isTrue);
    });
  });

  group('PortCheck.listeningPid', () {
    const out = '''
  Proto  Local Address          Foreign Address        State           PID
  TCP    127.0.0.1:10808        0.0.0.0:0              LISTENING       4242
  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING       4
  TCP    [::]:10809             [::]:0                 LISTENING       77
  TCP    127.0.0.1:52000        127.0.0.1:1080         ESTABLISHED     99
''';
    test('⚠️ порт 1080 не находится в 10808', () {
      expect(PortCheck.listeningPid(out, 1080), isNull);
    });
    test('точный порт находится', () {
      expect(PortCheck.listeningPid(out, 10808), 4242);
      expect(PortCheck.listeningPid(out, 445), 4);
      expect(PortCheck.listeningPid(out, 10809), 77);
    });
  });

  test('⚠️ батник восстановления сети — не по постоянному пути в %TEMP%', () {
    final p = NetworkRecovery.batPathFor(full: true);
    final parent = File(p).parent.path;
    expect(parent, isNot(Directory.systemTemp.path),
        reason: 'постоянное имя в %TEMP% можно подложить заранее');
    expect(File(p).parent.path, contains('sg_net_'));
  });
  group('InterferenceScanner.pidStillMatches', () {
    const list = [
      RunningProcess(10, 'happ.exe', r'C:\Apps\Happ\happ.exe'),
      RunningProcess(11, 'notepad.exe', r'C:\Windows\notepad.exe'),
    ];
    test('тот же путь — тот же процесс (регистр не важен)', () {
      expect(InterferenceScanner.pidStillMatches(
          10, r'c:\apps\happ\HAPP.exe', list), isTrue);
    });
    test('⚠️ номер у другой программы — не убивать', () {
      expect(InterferenceScanner.pidStillMatches(
          11, r'C:\Apps\Happ\happ.exe', list), isFalse);
    });
    test('процесса нет в списке — null', () {
      expect(InterferenceScanner.pidStillMatches(
          12, r'C:\Apps\Happ\happ.exe', list), isNull);
    });
  });

  test('⚠️ сторож сети перепроверяет паузу после чтения интерфейсов', () {
    // Отпечаток статический, подменить его в тесте нечем — стережём текст.
    final src = File('lib/core/platform/network_watcher.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final tick = src.substring(src.indexOf('Future<void> _tick()'));
    final after = tick.substring(tick.indexOf('final now = await signature();'));
    final guard = after.indexOf('if (_suspended');
    final use = after.indexOf('if (now == _lastSignature)');
    expect(guard, greaterThan(0));
    expect(guard, lessThan(use),
        reason: 'пауза, начатая во время await, обязана гасить такт');
  });
}
