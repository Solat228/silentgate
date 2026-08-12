import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';

/// Ключ сервера обязан быть КАНОНИЧЕСКИМ.
///
/// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТОТ ФАЙЛ СУЩЕСТВУЕТ, СТОИЛ ПОЛЬЗОВАТЕЛЮ ДАННЫХ.
/// Ключ сервера — это его share-ссылка, и по ней же лежат пин, ручная правка и
/// результат пинга. Один и тот же gRPC-сервер приходит в двух написаниях:
/// имя сервиса бывает `serviceName=`, а бывает `path=`. Разбор понимал оба,
/// сборка писала одно — и ключ зависел от того, каким форматом ответила панель
/// (Remnawave выбирает его по `User-Agent`).
///
/// Измерено на живых данных владельца 13.08.2026: из 374 сохранённых
/// результатов пинга 273 осиротели, 190 из них — gRPC.
void main() {
  const host = 'example.com';
  const uuid = '00000000-0000-0000-0000-000000000000';

  String vlessGrpc({required String serviceParam, String? mode}) =>
      'vless://$uuid@$host:443?type=grpc&security=reality&encryption=none'
      '&sni=a.example.org&fp=chrome&pbk=KEY&sid=ab'
      '&$serviceParam=my-service${mode == null ? '' : '&mode=$mode'}'
      '#Москва%201.%20GRPC';

  group('Два написания одного сервера дают ОДИН ключ', () {
    test('serviceName= и path= неразличимы', () {
      final a = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'serviceName'));
      final b = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'));
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.key, b!.key,
          reason: 'иначе при смене формата подписки теряются пины и пинги');
    });

    test('⚠️ БЕЗ канонизации ключи РАЗНЫЕ — это и был дефект', () {
      // Прямое доказательство, что тест выше не «зелёный всегда»:
      // `tryParseRaw` — разбор без приведения ключа, ровно прежнее поведение.
      final a = ShareLinkParser.tryParseRaw(vlessGrpc(serviceParam: 'serviceName'));
      final b = ShareLinkParser.tryParseRaw(vlessGrpc(serviceParam: 'path'));
      expect(a!.key, isNot(b!.key),
          reason: 'один сервер, два ключа — отсюда и потеря 273 результатов');
    });

    test('имя сервиса при этом не потеряно', () {
      final a = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'serviceName'));
      expect(a!.path, 'my-service');
      expect(a.network, 'grpc');
    });

    test('ключ отличается, если сервер ДЕЙСТВИТЕЛЬНО другой', () {
      final a = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'));
      final b = ShareLinkParser.tryParse(
          vlessGrpc(serviceParam: 'path').replaceFirst('my-service', 'other'));
      expect(a!.key, isNot(b!.key),
          reason: 'канонизация не должна склеивать разные серверы');
    });
  });

  group('Повторный разбор ничего не меняет', () {
    // Если ключ не идемпотентен, он «плавает» при каждом перезапуске — и данные
    // теряются даже без участия панели.
    for (final link in <String>[
      'vless://$uuid@$host:443?type=tcp&security=reality&encryption=none'
          '&sni=a.example.org&fp=chrome&pbk=KEY&sid=ab#Сервер',
      'vless://$uuid@$host:443?type=ws&security=tls&encryption=none'
          '&host=cdn.example.com&path=/ws#WS',
      'trojan://pass@$host:443?type=tcp&security=tls&sni=a.example.org#Trojan',
      'hysteria2://pass@$host:443?sni=a.example.org&obfs=salamander'
          '&obfs-password=p#HY2',
    ]) {
      test('идемпотентность: ${link.split('#').last}', () {
        final once = ShareLinkParser.tryParse(link);
        expect(once, isNotNull, reason: 'ссылка должна разбираться');
        final twice = ShareLinkParser.tryParse(once!.key);
        expect(twice, isNotNull);
        expect(twice!.key, once.key);
      });
    }

    test('gRPC с mode= тоже устойчив', () {
      final once =
          ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'serviceName', mode: 'gun'));
      final twice = ShareLinkParser.tryParse(once!.key);
      expect(twice!.key, once.key);
    });
  });

  group('canonicalKey — то, чем чинятся сохранённые данные', () {
    test('приводит старый ключ к новому', () {
      final old = vlessGrpc(serviceParam: 'serviceName');
      final now = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'))!.key;
      expect(ShareLinkParser.canonicalKey(old), now);
    });

    test('неразобранную строку возвращает как есть — чужое не выбрасываем', () {
      const junk = 'panel://Авто (YouTube)';
      expect(ShareLinkParser.canonicalKey(junk), junk);
    });

    test('уже канонический ключ не меняется', () {
      final k = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'))!.key;
      expect(ShareLinkParser.canonicalKey(k), k);
    });
  });

  group('Тождество сервера для дифа подписки', () {
    test('одинаковые адрес, порт и имя — один сервер, даже при разных полях', () {
      final a = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'))!;
      final b = ShareLinkParser.tryParse(
          vlessGrpc(serviceParam: 'path').replaceFirst('fp=chrome', 'fp=firefox'))!;
      expect(a.identity, b.identity,
          reason: 'смена отпечатка — это правка сервера, а не другой сервер');
    });

    test('разный порт — разные серверы', () {
      final a = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'))!;
      final b = ShareLinkParser.tryParse(
          vlessGrpc(serviceParam: 'path').replaceFirst(':443?', ':8443?'))!;
      expect(a.identity, isNot(b.identity));
    });
  });
}

/// Тождество сервера для дифа: «тот же узел», а не «та же строка».
extension on VpnServer {
  String get identity => identityKey;
}
