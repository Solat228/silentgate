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

  group('Оба пути создания сервера дают ОДИН ключ', () {
    // ⚠️ Сервер рождается ДВУМЯ путями: разбором ссылки из текстовой подписки и
    // сборкой из панельного XRAY_JSON. Если пути расходятся, ключ «дышит»
    // между сессиями — и данные по нему осиротевают на каждом цикле
    // «перезапуск → обновление подписки». Проверяем на протоколах, где сборка
    // пишет поля, которые разбор раньше пропускал.
    test('trojan поверх gRPC переживает круг разбор→сборка', () {
      const link = 'trojan://pw@tj.example.com:443?type=grpc&security=tls'
          '&sni=a.example.org&path=svc&authority=auth.example.org&mode=gun#T';
      final once = ShareLinkParser.tryParse(link);
      expect(once, isNotNull);
      final twice = ShareLinkParser.tryParse(once!.key);
      expect(twice!.key, once.key,
          reason: 'разбор trojan пропускал authority/mode — ключ менялся сам');
      expect(once.authority, 'auth.example.org',
          reason: 'поле должно не только сохраняться в ключе, но и читаться');
    });

    test('hysteria2 с отпечатком переживает круг', () {
      const link = 'hysteria2://pass@hy.example:443?sni=a.example.org&fp=chrome#H';
      final once = ShareLinkParser.tryParse(link);
      final twice = ShareLinkParser.tryParse(once!.key);
      expect(twice!.key, once.key,
          reason: 'fp разбирался, но не писался — ключ терял его на каждом чтении');
    });
  });

  group('Панельный сервер без ссылки', () {
    test('⚠️ ключ НЕ пустой — иначе все такие серверы делят один', () {
      // Из панельного XRAY_JSON сервер приходит без ссылки. Раньше
      // buildShareLink возвращал для vmess/ss пустую строку, и ВСЕ они
      // получали ключ «»: пинг, пин и правка писались друг поверх друга, а
      // после перезапуска сервер исчезал вместе с сохранённым.
      const a = VpnServer(
          protocol: 'shadowsocks',
          remark: 'SS 1',
          address: 'a.example',
          port: 8388,
          id: 'pw',
          rawLink: '');
      const b = VpnServer(
          protocol: 'shadowsocks',
          remark: 'SS 2',
          address: 'b.example',
          port: 8388,
          id: 'pw',
          rawLink: '');
      expect(a.buildShareLink(), isNotEmpty);
      expect(a.buildShareLink(), isNot(b.buildShareLink()),
          reason: 'разные узлы обязаны различаться ключом');
    });

    test('ключ стабилен между запусками', () {
      const s = VpnServer(
          protocol: 'vmess',
          remark: 'VM',
          address: 'v.example',
          port: 443,
          id: 'uuid',
          rawLink: '');
      expect(s.buildShareLink(), s.buildShareLink());
    });
  });

  group('Профиль «Авто …» опознаётся по имени', () {
    VpnServer profile({required String node, required int port}) => VpnServer(
          protocol: 'vless',
          remark: '🎬 Авто (YouTube)',
          address: node,
          port: port,
          id: 'uuid',
          rawLink: 'panel://auto',
          rawPanelConfig: '{"outbounds":[],"routing":{"balancers":[]}}',
        );

    test('⚠️ смена узла внутри балансировщика НЕ делает профиль новым', () {
      // Адрес и порт профиля берутся у ПЕРВОГО узла внутри, а панель их
      // перетасовывает. Считай тождество по адресу — и профиль на каждом
      // обновлении выглядел бы «удалён и добавлен»: ровно та жалоба, ради
      // которой диф и переписывался.
      final a = profile(node: 'node-7.example', port: 443);
      final b = profile(node: 'node-31.example', port: 8443);
      expect(a.identityKey, b.identityKey);
    });

    test('разные профили всё же различаются', () {
      final a = profile(node: 'n.example', port: 443);
      const b = VpnServer(
        protocol: 'vless',
        remark: '🤖 Авто (ChatGPT)',
        address: 'n.example',
        port: 443,
        id: 'uuid',
        rawLink: 'panel://auto2',
        rawPanelConfig: '{"outbounds":[]}',
      );
      expect(a.identityKey, isNot(b.identityKey));
    });

    test('обычный сервер по-прежнему опознаётся по адресу', () {
      final a = ShareLinkParser.tryParse(vlessGrpc(serviceParam: 'path'))!;
      expect(a.identityKey, contains(host),
          reason: 'правило про имя касается ТОЛЬКО профилей панели');
    });
  });
}

/// Тождество сервера для дифа: «тот же узел», а не «та же строка».
extension on VpnServer {
  String get identity => identityKey;
}