import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

void main() {
  group('ShareLinkParser', () {
    test('парсит vless+reality', () {
      const link =
          'vless://11111111-2222-3333-4444-555555555555@example.com:443'
          '?type=tcp&security=reality&pbk=PUBKEY&fp=chrome&sni=www.microsoft.com'
          '&sid=abcd&flow=xtls-rprx-vision&encryption=none#RU-1';
      final s = ShareLinkParser.tryParse(link);
      expect(s, isNotNull);
      expect(s!.protocol, 'vless');
      expect(s.address, 'example.com');
      expect(s.port, 443);
      expect(s.security, 'reality');
      expect(s.publicKey, 'PUBKEY');
      expect(s.flow, 'xtls-rprx-vision');
      expect(s.remark, 'RU-1');
    });

    test('парсит trojan', () {
      const link = 'trojan://secret@host.net:8443?security=tls&sni=host.net#T1';
      final s = ShareLinkParser.tryParse(link);
      expect(s, isNotNull);
      expect(s!.protocol, 'trojan');
      expect(s.id, 'secret');
      expect(s.security, 'tls');
    });

    test('игнорирует мусор', () {
      expect(ShareLinkParser.tryParse('not a link'), isNull);
    });
  });

  group('XrayConfigBuilder', () {
    test('строит валидный конфиг с proxy-outbound и api-inbound', () {
      final s = ShareLinkParser.tryParse(
        'vless://uuid@example.com:443?type=tcp&security=reality&pbk=K&sni=a.com&encryption=none#S',
      )!;
      final map = const XrayConfigBuilder().buildMap(s);
      final inbounds = map['inbounds'] as List;
      final outbounds = map['outbounds'] as List;
      expect(inbounds.any((i) => i['tag'] == 'api'), isTrue);
      expect(outbounds.first['tag'], 'proxy');
      expect(outbounds.first['protocol'], 'vless');
    });
  });
}
