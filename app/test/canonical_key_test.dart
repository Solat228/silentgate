import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/subscription/xray_json_subscription.dart';

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

    test('⚠️ НАПИСАНИЕ КЛЮЧА ЗАФИКСИРОВАНО — по нему лежат данные на диске', () {
      // Этот тест краснеет от ЛЮБОЙ смены формы идентификатора — в том числе от
      // «улучшения» вида «давайте собирать настоящую ss://-ссылку». Собирать
      // можно, но тогда к правке обязана прилагаться миграция сохранённых
      // ключей: у владельца на диске уже лежат пин, ручная правка и результат
      // пинга ровно в этом написании, а вывести из него метод и пароль нельзя —
      // их в идентификаторе никогда не было.
      const ss = VpnServer(
          protocol: 'shadowsocks',
          remark: 'SS 1',
          address: 'a.example',
          port: 8388,
          id: 'pw',
          encryption: 'aes-256-gcm',
          rawLink: '');
      expect(ss.buildShareLink(), 'shadowsocks://a.example:8388#SS%201');
      const vm = VpnServer(
          protocol: 'vmess',
          remark: 'VM',
          address: 'v.example',
          port: 443,
          id: 'uuid',
          rawLink: '');
      expect(vm.buildShareLink(), 'vmess://v.example:443#VM');
    });
  });

  group('Круг «панель → ключ → разбор» для КАЖДОГО протокола подписки', () {
    // ⚠️ ЧТО ЗДЕСЬ ПРОВЕРЯЕТСЯ И ПОЧЕМУ ПРЕЖНЕГО СТРАЖА НЕ ХВАТАЛО.
    //
    // Прежняя группа спрашивала у панельного узла ровно два свойства: ключ
    // непустой и равен сам себе. Обратный путь она не пробовала НИ РАЗУ — а
    // сломан был именно он. Панель владельца отдаёт XRAY_JSON, значит все
    // серверы рождаются через `XrayJsonSubscription.fromOutbound` с
    // `rawLink: ''`, и ключ достраивает запасная ветка `buildShareLink()`. Для
    // vmess и shadowsocks она выдаёт `vmess://5.6.7.8:443#Имя` и
    // `shadowsocks://1.2.3.4:8388#Имя`, а разбор таких строк не знал вовсе:
    // схемы `shadowsocks://` в нём не было (только `ss://`), `vmess://` требует
    // base64-тела и падает.
    //
    // Дальше потеря становилась необратимой: `AppState._serverFromStoredLink`
    // возвращал null, `whereType<VpnServer>()` молча выбрасывал узел, а
    // ближайшее сохранение пинов писало на диск уже усечённый список. Пин с
    // ручной правкой при этом оставался навсегда — снять его было нечем.
    //
    // Поэтому круг проверяется для ВСЕХ протоколов, которые панель может
    // прислать, а не для тех, где он и так замыкался.
    final panelOutbounds = <String, Map<String, dynamic>>{
      'vless': {
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': 'vl.example',
              'port': 443,
              'users': [
                {'id': uuid, 'encryption': 'none', 'flow': 'xtls-rprx-vision'}
              ],
            }
          ],
        },
        'streamSettings': {
          'network': 'tcp',
          'security': 'reality',
          'realitySettings': {
            'serverName': 'a.example.org',
            'fingerprint': 'chrome',
            'publicKey': 'KEY',
            'shortId': 'ab',
          },
        },
      },
      'trojan': {
        'tag': 'proxy',
        'protocol': 'trojan',
        'settings': {
          'servers': [
            {'address': 'tj.example', 'port': 443, 'password': 'pw'}
          ],
        },
        'streamSettings': {
          'network': 'grpc',
          'security': 'tls',
          'tlsSettings': {'serverName': 'a.example.org', 'fingerprint': 'chrome'},
          'grpcSettings': {
            'serviceName': 'svc',
            'authority': 'auth.example.org',
          },
        },
      },
      'shadowsocks': {
        'tag': 'proxy',
        'protocol': 'shadowsocks',
        'settings': {
          'servers': [
            {
              'address': 'ss.example',
              'port': 8388,
              'method': 'chacha20-ietf-poly1305',
              'password': 'pw',
            }
          ],
        },
        'streamSettings': {'network': 'tcp', 'security': 'none'},
      },
      'vmess': {
        'tag': 'proxy',
        'protocol': 'vmess',
        'settings': {
          'vnext': [
            {
              'address': 'vm.example',
              'port': 443,
              'users': [
                {'id': uuid, 'alterId': 0, 'security': 'auto'}
              ],
            }
          ],
        },
        'streamSettings': {
          'network': 'ws',
          'security': 'tls',
          'tlsSettings': {'serverName': 'a.example.org'},
          'wsSettings': {
            'path': '/ws',
            'headers': {'Host': 'cdn.example.com'},
          },
        },
      },
      'hysteria2': {
        'tag': 'proxy',
        'protocol': 'hysteria',
        'settings': {'address': 'hy.example', 'port': 443, 'version': 2},
        'streamSettings': {
          'security': 'tls',
          'tlsSettings': {'serverName': 'a.example.org'},
          'hysteriaSettings': {
            'auth': 'pw',
            'obfs': {'type': 'salamander', 'password': 'op'},
          },
        },
      },
    };

    panelOutbounds.forEach((name, out) {
      test('$name: ключ читает тот же код, что его пишет', () {
        final made = XrayJsonSubscription.fromOutbound(out, remark: 'Узел $name');
        expect(made, isNotNull, reason: 'панель прислала узел — он обязан собраться');
        final s = made!;
        expect(s.key, isNotEmpty);

        final back = ShareLinkParser.tryParse(s.key);
        expect(back, isNotNull,
            reason: 'ключ, который не читается обратно, = узел исчезает после '
                'перезапуска (AppState._serverFromStoredLink → null → '
                'whereType<VpnServer>() выбрасывает молча)');
        expect(back!.key, s.key, reason: 'круг обязан замкнуться байт в байт');
        expect(back.protocol, s.protocol);
        expect(back.address, s.address);
        expect(back.port, s.port);
        expect(back.remark, s.remark,
            reason: 'по имени узел опознаёт человек и диф подписки');
        expect(back.identityKey, s.identityKey);

        // И ещё круг: повторное чтение ничего не сдвигает.
        expect(ShareLinkParser.tryParse(back.key)!.key, s.key);
        expect(ShareLinkParser.canonicalKey(s.key), s.key);
      });
    });

    test('узлы одного протокола не сливаются в один ключ', () {
      final a = XrayJsonSubscription.fromOutbound(
          panelOutbounds['shadowsocks']!, remark: 'SS 1')!;
      final b = XrayJsonSubscription.fromOutbound(
          panelOutbounds['shadowsocks']!, remark: 'SS 2')!;
      expect(a.key, isNot(b.key),
          reason: 'иначе пинг, пин и правка снова пишутся друг поверх друга');
    });
  });

  group('Старые ключи с диска обязаны продолжать находиться', () {
    // Лечение, теряющее данные, хуже болезни: в этом написании у владельца уже
    // лежат пины, ручные правки и результаты пинга.
    for (final legacy in const <String>[
      'shadowsocks://a.example:8388#SS%201',
      'vmess://v.example:443#VM',
      'shadowsocks://[2001:db8::1]:8388#IPv6',
      'vmess://v.example:443', // имя пустое — тоже законный идентификатор
    ]) {
      test('ключ не переписывается: $legacy', () {
        expect(ShareLinkParser.canonicalKey(legacy), legacy,
            reason: 'переписали ключ — осиротили всё, что по нему лежит');
        final s = ShareLinkParser.tryParse(legacy);
        expect(s, isNotNull, reason: 'иначе узел не восстановится с диска');
        expect(s!.key, legacy);
      });
    }

    test('чужая строка узлом не притворяется', () {
      // Идентификатор принимается ровно в том виде, в каком его пишет сборка;
      // всё остальное обязано остаться неразобранным, иначе `parseSubscriptionBody`
      // начнёт делать «серверы» из посторонних строк подписки.
      for (final junk in const <String>[
        'https://example.com:443',
        'socks://127.0.0.1:1080',
        'shadowsocks://a.example', // без порта
        'shadowsocks://user@a.example:8388', // с учётными данными
        'shadowsocks://a.example:8388/path',
        'shadowsocks://a.example:8388?plugin=obfs',
        'shadowsocks://a.example:0#N', // порт 0 — это не узел
        // ⚠️ Неканоническое написание имени ловит ТОЛЬКО обратная сборка:
        // шаблон такую строку пропускает. Прими её — и у одного узла стало бы
        // два ключа, то есть ровно та болезнь, ради которой этот файл заведён.
        'shadowsocks://a.example:8388#SS 1',
        'vmess://', // пустое тело
      ]) {
        expect(ShareLinkParser.tryParse(junk), isNull, reason: junk);
      }
    });

    test('⚠️ регистр хоста НЕ нормализуется — иначе ключ теряется', () {
      // Идентификатор строится из адреса, как его прислала панель. Разбери его
      // через `Uri` — хост уехал бы в нижний регистр, обратная сборка перестала
      // бы совпадать, и приложение отвергло бы СОБСТВЕННЫЙ ключ.
      const legacy = 'shadowsocks://SS.Example:8388#N';
      final s = ShareLinkParser.tryParse(legacy);
      expect(s, isNotNull);
      expect(s!.key, legacy);
      expect(s.address, 'SS.Example');
    });

    test('настоящая ss://-ссылка по-прежнему разбирается своим кодом', () {
      // Ветка идентификатора не должна перехватывать нормальные ссылки.
      const link = 'ss://YWVzLTI1Ni1nY206cHc@a.example:8388#SS';
      final s = ShareLinkParser.tryParse(link);
      expect(s, isNotNull);
      expect(s!.protocol, 'shadowsocks');
      expect(s.encryption, 'aes-256-gcm');
      expect(s.id, 'pw');
      expect(s.key, link, reason: 'у настоящей ссылки ключ — она сама');
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