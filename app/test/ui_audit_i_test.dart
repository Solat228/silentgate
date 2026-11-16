import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';

/// Находки аудита 25.10.2026, I (интерфейс).
///
/// Три места живут внутри виджетов, которые тестом целиком не поднять без
/// проверки помех на настоящей машине (`NetworkInterface.list`, процессы
/// хоста) — стережём текст, как `core_audit_h_test`.
String _src(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _body(String src, String from, String to) {
  final start = src.indexOf(from);
  expect(start, greaterThanOrEqualTo(0), reason: 'не найдено: $from');
  final end = src.indexOf(to, start + from.length);
  return src.substring(start, end < 0 ? src.length : end);
}

void main() {
  test('⚠️ диалог приложения правит АКТУАЛЬНОЕ правило, а не исходное', () {
    final dialog = _body(_src('lib/ui/split_tunnel_screen.dart'),
        'Future<void> _appDialog(', 'Future<void> _siteDialog(');
    // После смены «по имени / по пути» ключ правила другой: правка по
    // исходному `rule` больше не находит элемент и теряется молча.
    expect(dialog, isNot(contains('_updateApp(c, rule')));
    expect(dialog, isNot(contains('_setAppServer(c, rule')));
    expect(dialog, contains('current = current.copyWith(byName: b)'));
  });

  test('⚠️ «Подключить» в автонастройке не выключает живой VPN', () {
    final card = _body(_src('lib/ui/auto_config_screen.dart'),
        'state.applyAutoConfigResult(', 'Navigator.of(context).pop()');
    expect(card, contains('state.reconnect(settings)'),
        reason: 'toggleConnection на живом канале — это отключение');
  });

  test('⚠️ двойное нажатие Connect глотается на время проверки помех', () {
    final src = _src('lib/ui/widgets/connect_guard.dart');
    final fn = _body(src, 'Future<void> connectWithConflictCheck(',
        'Future<void> _checkThenConnect(');
    final guard = fn.indexOf('if (_checkInFlight) return;');
    final check = fn.indexOf('_checkThenConnect(context');
    expect(guard, greaterThan(0));
    expect(guard, lessThan(check));
    expect(fn, contains('_checkInFlight = false'),
        reason: 'флаг обязан сниматься в finally, иначе кнопка умрёт');
  });

  group('⚠️ правка vmess/ss переживает перезапуск (ссылка пересобрана)', () {
    test('vmess', () {
      final src = ShareLinkParser.tryParse(VpnServer(
        protocol: 'vmess',
        remark: 'V',
        address: '203.0.113.9',
        port: 443,
        id: '00000000-0000-0000-0000-00000000000a',
        network: 'ws',
        security: 'tls',
        path: '/a',
        rawLink: '',
      ).buildEditedLink())!;
      final edited = src.copyWith(
          remark: 'V2', port: 8443, path: '/b', sni: 'cdn.example');
      final back = ShareLinkParser.tryParse(edited.buildEditedLink())!;
      expect(back.protocol, 'vmess');
      expect(back.remark, 'V2');
      expect(back.port, 8443);
      expect(back.path, '/b');
      expect(back.sni, 'cdn.example');
      expect(back.network, 'ws');
      expect(back.security, 'tls');
      expect(back.id, src.id);
    });

    // Ревью 29.10.2026, L16: `fp` не писался в ссылку vmess и не читался из
    // неё — отпечаток uTLS пропадал после перезапуска.
    test('vmess: отпечаток uTLS переживает перезапуск', () {
      const base = VpnServer(
        protocol: 'vmess',
        remark: 'V',
        address: '203.0.113.9',
        port: 443,
        id: '00000000-0000-0000-0000-00000000000a',
        network: 'ws',
        security: 'tls',
        rawLink: '',
      );
      final back = ShareLinkParser.tryParse(
          base.copyWith(fingerprint: 'firefox').buildEditedLink())!;
      expect(back.fingerprint, 'firefox');
      // Без отпечатка поле не появляется пустым.
      final plain = ShareLinkParser.tryParse(base.buildEditedLink())!;
      expect(plain.fingerprint, isNull);
    });

    test('ss, в том числе узел панели без ссылки', () {
      const panel = VpnServer(
        protocol: 'shadowsocks',
        remark: 'S',
        address: '2001:db8::5',
        port: 8388,
        id: 'old',
        encryption: 'aes-256-gcm',
        rawLink: '',
      );
      final edited = panel.copyWith(id: 'new-pass', port: 9000);
      final back = ShareLinkParser.tryParse(edited.buildEditedLink())!;
      expect(back.protocol, 'shadowsocks');
      expect(back.id, 'new-pass');
      expect(back.encryption, 'aes-256-gcm');
      expect(back.address, '2001:db8::5');
      expect(back.port, 9000);
      expect(back.remark, 'S');
    });
  });

  test('⚠️ меню подписок показывает safeTitle (title несёт токен)', () {
    final src = _src('lib/ui/widgets/subscription_switcher.dart');
    expect(src, isNot(contains('p.title')));
  });

  test('⚠️ журнал TUN на экране маскирует адреса', () {
    final src = _src('lib/ui/tun_settings_screen.dart');
    expect(src, contains('SensitiveAddresses.mask(await platform.tunLog'));
  });

  test('⚠️ «Обновить» у заглушки сервера не хвалит неудачу', () {
    final src = _src('lib/ui/widgets/server_tile.dart');
    expect(src, contains('final ok = await state.refreshSubscription();'));
  });

  test('⚠️ HWID не копируется, пока не прочитан', () {
    final tile = _body(_src('lib/ui/settings_screen.dart'),
        'class _HwidTileState', 'const _supportChat');
    expect(tile, contains('onPressed: snap.hasData'));
  });
}
