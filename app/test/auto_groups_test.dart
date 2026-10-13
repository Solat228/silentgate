import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/util/auto_groups.dart';
import 'package:silentgate/core/util/server_groups.dart';
import 'package:silentgate/ui/widgets/server_group_header.dart';

/// Привязка серверов к страновым профилям «Авто» по их внутреннему списку.
/// Решение владельца 10.10.2026: «🇵🇱 🚀Польша» от панели содержит Польшу 1.x и
/// Польшу 2.x — они показываются под ним, а сравнение идёт по самим
/// outbound'ам, «чтобы ничего не перепутать».
void main() {
  const pl = '\u{1F1F5}\u{1F1F1}';
  const de = '\u{1F1E9}\u{1F1EA}';
  const ru = '\u{1F1F7}\u{1F1FA}';
  const uuid = '11111111-2222-3333-4444-555555555555';

  /// Outbound узла: адрес TEST-NET, различие — в sni (как у панели, где на
  /// одном адресе и порту живут разные входы).
  Map<String, Object?> ob(String sni, {String tag = 'proxy', int port = 443}) => {
        'tag': tag,
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': '203.0.113.10',
              'port': port,
              'users': [
                {'id': uuid, 'encryption': 'none'}
              ],
            }
          ],
        },
        'streamSettings': {
          'network': 'tcp',
          'security': 'reality',
          'realitySettings': {'serverName': sni, 'fingerprint': 'chrome'},
        },
      };

  Map<String, Object?> hyOb(String auth, {String tag = 'proxy-hy'}) => {
        'tag': tag,
        'protocol': 'hysteria',
        'settings': {'address': '203.0.113.30', 'port': 8443, 'version': 2},
        'streamSettings': {
          'network': 'hysteria',
          'hysteriaSettings': {'version': 2, 'auth': auth},
        },
      };

  var n = 0;
  VpnServer srv(String remark, Map<String, Object?> outbound) {
    n++;
    return VpnServer(
      protocol: 'vless',
      remark: remark,
      address: '203.0.113.10',
      port: 443,
      id: uuid,
      rawLink: 'vless://$uuid@203.0.113.10:443?n=$n#$n',
      rawOutboundJson: jsonEncode(outbound),
    );
  }

  VpnServer hy(String remark, String password) => VpnServer(
        protocol: 'hysteria2',
        remark: remark,
        address: '203.0.113.30',
        port: 8443,
        id: password,
        rawLink: 'hysteria2://$password@203.0.113.30:8443#${n++}',
      );

  VpnServer profile(String remark, List<Map<String, Object?>> proxies) =>
      VpnServer(
        protocol: 'vless',
        remark: remark,
        address: '203.0.113.20',
        port: 443,
        id: 'x',
        rawLink: 'panel://$remark',
        rawPanelConfig: jsonEncode({
          'outbounds': [
            for (var i = 0; i < proxies.length; i++)
              {...proxies[i], 'tag': 'proxy-$i'},
            {'tag': 'direct', 'protocol': 'freedom'},
            {'tag': 'block', 'protocol': 'blackhole'},
          ],
          'routing': {
            'balancers': [
              {'tag': 'b', 'selector': ['proxy']}
            ]
          },
        }),
      );

  List<int> all(List<VpnServer> s) => [for (var i = 0; i < s.length; i++) i];

  String shape(List<ServerListEntry> e) => e
      .map((x) => switch (x) {
            ServerGroupHeader(country: final c, count: final k) => '[$c×$k]',
            ServerRowEntry(index: final i, auto: final a?) =>
              '<$i×${a.count}${a.collapsed ? '' : ' open'}>',
            ServerRowEntry(index: final i, autoMember: true) => '~$i',
            ServerRowEntry(index: final i, grouped: final g) =>
              g ? '>$i' : '$i',
          })
      .join(' ');

  group('мосты', () {
    // Владелец 13.10.2026: «Мск 2 -> Германия 2 (мост)» оказался под шапкой
    // «🇩🇪 🚀Германия». Привязка не ошиблась: панель действительно положила этот
    // outbound в профиль страны. Но мост — российский вход с выходом в другой
    // стране; под страной выхода он выглядит обычным немецким узлом, а
    // подключение к нему идёт совсем другим путём.
    test('⚠️ мост не прячется под страновой шапкой, даже если он в профиле', () {
      final s = [
        profile('$de 🚀Германия', [ob('a.example'), ob('bridge.example')]),
        srv('$de Германия 1.1', ob('a.example')),
        srv('$ru -> $de Мск 2 -> Германия 2 (мост)', ob('bridge.example')),
      ];
      expect(AutoGroups.compute(s).ownerOf, {1: 0});
    });

    test('признаки моста: слово «мост» или стрелка в названии', () {
      for (final name in [
        'Мск 2 -> Германия 2',
        'Москва → Польша',
        'Германия (Мост)',
        'RU bridge DE',
      ]) {
        expect(AutoGroups.isBridgeName(name), isTrue, reason: name);
      }
      for (final name in ['$de Германия 1.1', 'Мостовая-1 сервер', 'Польша - 2']) {
        expect(AutoGroups.isBridgeName(name), isFalse, reason: name);
      }
    });
  });

  group('сравнение по outbound', () {
    test('совпадает целиком, тег не важен', () {
      final s = [
        profile('$pl Польша', [ob('a.example')]),
        srv('$pl Польша 1.1', ob('a.example', tag: 'proxy')),
      ];
      expect(AutoGroups.compute(s).ownerOf, {1: 0});
    });

    test('⚠️ тот же адрес, порт и uuid, но другой sni — НЕ тот же сервер', () {
      final s = [
        profile('$pl Польша', [ob('a.example')]),
        srv('$pl Польша 1.2', ob('b.example')),
      ];
      expect(AutoGroups.compute(s).ownerOf, isEmpty);
    });

    test('порядок ключей в JSON значения не имеет', () {
      final reversed = Map.fromEntries(ob('a.example').entries.toList().reversed);
      expect(AutoGroups.outboundSignature(reversed),
          AutoGroups.outboundSignature(ob('a.example')));
    });

    test('hysteria2 из ссылки узнаётся по адресу, порту и паролю', () {
      final s = [
        profile('$pl Польша', [ob('a.example'), hyOb('secret')]),
        hy('$pl Польша 1.6 Hysteria2', 'secret'),
        hy('$pl Чужой hy2', 'other'),
      ];
      expect(AutoGroups.compute(s).ownerOf, {1: 0});
    });

    test('служебные outbound\'ы профиля не считаются', () {
      expect(
          AutoGroups.profileSignatures(profile('P', [ob('a')]).rawPanelConfig!),
          hasLength(1));
    });

    test('битый конфиг профиля и битый outbound не роняют разбор', () {
      final s = [
        VpnServer(
            protocol: 'vless',
            remark: 'P',
            address: '203.0.113.20',
            port: 443,
            id: 'x',
            rawLink: 'panel://P',
            rawPanelConfig: '{не json'),
        VpnServer(
            protocol: 'vless',
            remark: 'S',
            address: '203.0.113.10',
            port: 443,
            id: uuid,
            rawLink: 'vless://s',
            rawOutboundJson: '[1,'),
      ];
      expect(AutoGroups.compute(s).isEmpty, isTrue);
    });
  });

  group('кому достаётся сервер', () {
    test('⚠️ общий «Авто» со всеми странами — не группа', () {
      final s = [
        profile('Авто YouTube', [ob('p1'), ob('p2'), ob('d1'), ob('bridge')]),
        profile('$pl Польша', [ob('p1'), ob('p2')]),
        profile('$de Германия', [ob('d1')]),
        srv('$pl Польша 1', ob('p1')),
        srv('$pl Польша 2', ob('p2')),
        srv('$de Германия 1', ob('d1')),
        srv('$ru$de Мост', ob('bridge')),
      ];
      final b = AutoGroups.compute(s);
      expect(b.members, {
        1: [3, 4],
        2: [5],
      });
      // Мост есть только в общем профиле — он остаётся сам по себе и дальше
      // группируется по странам, как раньше.
      expect(b.ownerOf.containsKey(6), isFalse);
    });

    test('маленький вложенный профиль не отнимает группу у страны', () {
      final s = [
        profile('$pl Польша', [ob('p1'), ob('p2'), ob('p3')]),
        profile('$pl Польша игровой', [ob('p3')]),
        srv('$pl Польша 1', ob('p1')),
        srv('$pl Польша 2', ob('p2')),
        srv('$pl Польша 3', ob('p3')),
      ];
      final b = AutoGroups.compute(s);
      // Сервер идёт к самому узкому профилю, где он есть.
      expect(b.members, {
        0: [2, 3],
        1: [4],
      });
    });

    test('одинаковый состав — к стоящему выше', () {
      final s = [
        profile('A', [ob('p1')]),
        profile('B', [ob('p1')]),
        srv('S', ob('p1')),
      ];
      expect(AutoGroups.compute(s).ownerOf, {2: 0});
    });

    test('закреплённые не привязываются', () {
      final s = [
        srv('$pl Pinned', ob('p1')),
        profile('$pl Польша', [ob('p1'), ob('p2')]),
        srv('$pl Польша 2', ob('p2')),
      ];
      expect(AutoGroups.compute(s, skip: {0}).ownerOf, {2: 1});
    });
  });

  group('порядок и строки', () {
    // Как у владельца: «Польша 2» провайдер поставил в самый верх, остальные
    // польские — ниже, между ними мосты.
    List<VpnServer> owner() => [
          srv('$pl Польша 2', ob('p2')), // 0
          profile('$pl Польша', [ob('p1'), ob('p2'), ob('p3')]), // 1
          srv('$ru$de Мост 1', ob('m1')), // 2
          srv('$ru$de Мост 2', ob('m2')), // 3
          srv('$pl Польша 1', ob('p1')), // 4
          srv('$pl Польша 3', ob('p3')), // 5
        ];

    test('серверы встают за своим профилем в порядке провайдера', () {
      final s = owner();
      final b = AutoGroups.compute(s);
      expect(ServerGroups.order(s, all(s), sortByCountry: false, auto: b),
          [1, 0, 4, 5, 2, 3]);
    });

    test('⚠️ группа «Авто» свёрнута по умолчанию', () {
      final s = owner();
      final b = AutoGroups.compute(s);
      final ord = ServerGroups.order(s, all(s), sortByCountry: false, auto: b);
      expect(shape(ServerGroups.build(s, ord, auto: b)), '<1×3> [RU-DE×2] >2 >3');
    });

    test('раскрытая показывает серверы; выбранный виден и в свёрнутой', () {
      final s = owner();
      final b = AutoGroups.compute(s);
      final ord = ServerGroups.order(s, all(s), sortByCountry: false, auto: b);
      final key = ServerGroups.autoGroupKey(s[1]);
      expect(shape(ServerGroups.build(s, ord, auto: b, expandedAuto: {key})),
          '<1×3 open> ~0 ~4 ~5 [RU-DE×2] >2 >3');
      expect(shape(ServerGroups.build(s, ord, auto: b, selected: 4)),
          '<1×3> ~4 [RU-DE×2] >2 >3');
    });

    test('без профиля «Авто» всё как раньше', () {
      final s = [srv('$pl A', ob('a')), srv('$pl B', ob('b'))];
      final b = AutoGroups.compute(s);
      expect(b.isEmpty, isTrue);
      expect(
          shape(ServerGroups.build(
              s, ServerGroups.order(s, all(s), sortByCountry: false, auto: b),
              auto: b)),
          '[PL×2] >0 >1');
    });

    test('разнобой не считает собранные под «Авто»', () {
      final s = owner();
      // Польша 2 сверху и Польша 1 ниже мостов — без привязки разнобой.
      expect(ServerGroups.isJumbled(s), isTrue);
      expect(ServerGroups.isJumbled(s, auto: AutoGroups.compute(s)), isFalse);
    });

    test('сортировка по странам привязанных не трогает', () {
      final s = [
        ...owner(),
        srv('$ru$de Мост 3', ob('m3')), // 6
      ];
      final b = AutoGroups.compute(s);
      expect(ServerGroups.order(s, all(s), sortByCountry: true, auto: b),
          [1, 0, 4, 5, 2, 3, 6]);
    });

    test('шапка «Авто» — строка обычной высоты', () {
      final s = owner();
      final b = AutoGroups.compute(s);
      final e = ServerGroups.build(
          s, ServerGroups.order(s, all(s), sortByCountry: false, auto: b),
          auto: b);
      // <1> 60, [RU-DE] 41, затем строка 2.
      expect(serverEntryTop(e, 1, rowExtent: 60), 0);
      expect(serverEntryTop(e, 2, rowExtent: 60), 60 + 41);
    });

    test('интерфейс: при поиске групп нет, без поиска — привязка', () {
      final s = owner();
      List<ServerListEntry> entries({required bool searching}) =>
          serverListEntries(
            servers: s,
            shown: all(s),
            searching: searching,
            settings: const AppSettings(),
            selected: -1,
            isPinned: (_) => false,
          );
      expect(shape(entries(searching: true)), '0 1 2 3 4 5');
      expect(shape(entries(searching: false)), '<1×3> [RU-DE×2] >2 >3');
    });
  });

  group('кэш', () {
    test('те же объекты — тот же результат, другой сервер — пересчёт', () {
      final s = [
        profile('$pl Польша', [ob('p1')]),
        srv('$pl Польша 1', ob('p1')),
      ];
      final a = AutoGroups.bind(s);
      expect(identical(AutoGroups.bind(List.of(s)), a), isTrue);
      final changed = [s[0], srv('$pl Польша 1', ob('other'))];
      expect(AutoGroups.bind(changed).isEmpty, isTrue);
      expect(identical(AutoGroups.bind(s, skip: {1}), a), isFalse);
    });
  });

  test('настройка: раскрытые группы переживают JSON, переподключения не требуют',
      () {
    const d = AppSettings();
    expect(d.expandedAutoGroups, isEmpty);
    final s = AppSettings.fromJson(
        const AppSettings(expandedAutoGroups: ['auto:P']).toJson());
    expect(s.expandedAutoGroups, ['auto:P']);
    final bad = AppSettings.fromJson({
      ...const AppSettings().toJson(),
      'expandedAutoGroups': ['auto:P', 3, null],
    });
    expect(bad.expandedAutoGroups, ['auto:P']);
    expect(d.requiresReconnect(d.copyWith(expandedAutoGroups: ['auto:P'])),
        isFalse);
  });

  test('оба списка рисуют строку одной обёрткой', () {
    for (final f in ['lib/ui/home_screen.dart', 'lib/ui/servers_screen.dart']) {
      expect(File(f).readAsStringSync(), contains('serverListRow('),
          reason: f);
    }
  });
}
