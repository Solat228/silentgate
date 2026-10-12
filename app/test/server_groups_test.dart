import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/util/server_groups.dart';
import 'package:silentgate/ui/widgets/server_group_header.dart';

/// Группировка серверов по странам. Решения владельца 25.09.2026: порядок
/// провайдера не трогается, две подряд — уже группа, пересортировка — только
/// по настройке, которая видна лишь у перемешанного списка.
void main() {
  var n = 0;
  VpnServer srv(String remark, {String address = '203.0.113.10', int port = 443}) {
    n++;
    return VpnServer(
      protocol: 'vless',
      remark: remark,
      address: address,
      port: port,
      id: '11111111-2222-3333-4444-555555555555',
      rawLink: 'vless://11111111-2222-3333-4444-555555555555'
          '@$address:${port + n}?encryption=none#$n',
    );
  }

  VpnServer panel(String remark) => VpnServer(
        protocol: 'vless',
        remark: remark,
        address: '203.0.113.20',
        port: 443,
        id: 'x',
        rawLink: 'panel://$remark',
        rawPanelConfig: '{"outbounds":[]}',
      );

  const de = '\u{1F1E9}\u{1F1EA}';
  const nl = '\u{1F1F3}\u{1F1F1}';
  const ru = '\u{1F1F7}\u{1F1FA}';

  List<int> all(List<VpnServer> s) => [for (var i = 0; i < s.length; i++) i];

  String shape(List<ServerListEntry> e) => e
      .map((x) => switch (x) {
            ServerGroupHeader(country: final c, count: final k) => '[$c×$k]',
            ServerRowEntry(index: final i, grouped: final g) =>
              g ? '>$i' : '$i',
          })
      .join(' ');

  group('страна сервера', () {
    test('по флагу в имени; мост — два кода', () {
      expect(ServerGroups.countryOf(srv('$de Германия 1')), 'DE');
      expect(ServerGroups.countryOf(srv('$ru$de Мост')), 'RU-DE');
      expect(ServerGroups.countryOf(srv('Без флага')), isNull);
    });

    test('«Авто» и заглушки панели в группы не входят', () {
      expect(ServerGroups.countryOf(panel('$de Авто')), isNull);
      expect(
          ServerGroups.countryOf(srv('$de Оплатите', address: '0.0.0.0', port: 1)),
          isNull);
    });
  });

  group('разнобой', () {
    test('страны блоками — не разнобой, даже по две', () {
      final s = [
        srv('$de A'), srv('$de B'), srv('$nl C'), srv('$nl D'), srv('$ru E'),
      ];
      expect(ServerGroups.isJumbled(s), isFalse);
    });

    test('страна вернулась после другой — разнобой', () {
      final s = [srv('$de A'), srv('$nl B'), srv('$de C')];
      expect(ServerGroups.isJumbled(s), isTrue);
    });

    test('закреплённый сверху того же флага разнобоем не считается', () {
      final s = [srv('$de Pinned'), srv('$nl B'), srv('$de C')];
      expect(ServerGroups.isJumbled(s, pinned: {0}), isFalse);
    });

    test('сервер без флага между двумя одинаковыми — разнобой', () {
      final s = [srv('$de A'), srv('Просто'), srv('$de C')];
      expect(ServerGroups.isJumbled(s), isTrue);
    });
  });

  group('порядок', () {
    test('⚠️ без настройки порядок провайдера не трогается', () {
      final s = [srv('$de A'), srv('$nl B'), srv('$de C')];
      expect(ServerGroups.order(s, all(s), sortByCountry: false), [0, 1, 2]);
    });

    test('сортировка устойчивая: страны в порядке первого появления', () {
      final s = [
        srv('$nl A'), srv('$de B'), srv('$nl C'), srv('$ru D'), srv('$de E'),
      ];
      expect(ServerGroups.order(s, all(s), sortByCountry: true),
          [0, 2, 1, 4, 3]);
    });

    test('закреплённые остаются сверху, серверы без флага — сами по себе', () {
      final s = [
        srv('$de Pin'), srv('$nl A'), srv('Авто'), srv('$de B'), srv('$nl C'),
      ];
      expect(
          ServerGroups.order(s, all(s), sortByCountry: true, pinned: {0}),
          [0, 1, 4, 2, 3]);
    });

    test('сортирует только найденное — индексы исходные', () {
      final s = [srv('$de A'), srv('$nl B'), srv('$de C')];
      expect(ServerGroups.order(s, [1, 2], sortByCountry: true), [1, 2]);
    });
  });

  group('строки списка', () {
    test('две подряд — группа, одиночка — строка', () {
      final s = [srv('$de A'), srv('$de B'), srv('$nl C'), srv('$de D')];
      expect(shape(ServerGroups.build(s, all(s))), '[DE×2] >0 >1 2 3');
    });

    test('свёрнутая группа прячет строки, кроме выбранной', () {
      final s = [srv('$de A'), srv('$de B'), srv('$de C'), srv('$nl D')];
      expect(shape(ServerGroups.build(s, all(s), collapsed: {'DE'})),
          '[DE×3] 3');
      expect(
          shape(ServerGroups.build(s, all(s), collapsed: {'DE'}, selected: 1)),
          '[DE×3] >1 3');
    });

    test('закреплённые в группу не попадают', () {
      final s = [srv('$de Pin'), srv('$de A'), srv('$de B')];
      expect(shape(ServerGroups.build(s, all(s), pinned: {0})),
          '0 [DE×2] >1 >2');
    });

    test('«Авто» разрывает группу', () {
      final s = [srv('$de A'), panel('$de Авто'), srv('$de B')];
      expect(shape(ServerGroups.build(s, all(s))), '0 1 2');
    });

    test('у группы исходные индексы — для подсчётов и флага', () {
      final s = [srv('$nl X'), srv('$de A'), srv('$de B')];
      final h = ServerGroups.build(s, all(s)).whereType<ServerGroupHeader>().single;
      expect(h.indices, [1, 2]);
      expect(h.count, 2);
    });
  });

  group('подпись группы', () {
    test('общее начало без номеров', () {
      expect(
          ServerGroups.labelFor(['$de Германия 1', '$de Германия 2.5'], 'DE'),
          'Германия');
      expect(
          ServerGroups.labelFor(['$de Germany - Fast', '$de Germany - Slow'], 'DE'),
          'Germany');
    });

    test('общего начала нет — код страны', () {
      expect(ServerGroups.labelFor(['$de Berlin', '$de Frankfurt'], 'DE'), 'DE');
    });

    test('одинаковые имена целиком — имя', () {
      expect(ServerGroups.labelFor(['$de Германия', '$de Германия'], 'DE'),
          'Германия');
    });
  });

  group('интерфейс', () {
    test('при поиске групп нет', () {
      final s = [srv('$de A'), srv('$de B')];
      final e = serverListEntries(
        servers: s,
        shown: all(s),
        searching: true,
        settings: const AppSettings(collapsedCountries: ['DE']),
        selected: -1,
        isPinned: (_) => false,
      );
      expect(shape(e), '0 1');
    });

    test('без поиска — свёрнутые группы из настроек', () {
      final s = [srv('$de A'), srv('$de B'), srv('$nl C')];
      final e = serverListEntries(
        servers: s,
        shown: all(s),
        searching: false,
        settings: const AppSettings(collapsedCountries: ['DE']),
        selected: -1,
        isPinned: (_) => false,
      );
      expect(shape(e), '[DE×2] 2');
    });

    test('верх строки учитывает заголовки', () {
      final s = [srv('$de A'), srv('$de B'), srv('$nl C')];
      final e = ServerGroups.build(s, all(s));
      // [DE] 0 1 2 — заголовок 41 (40 + разделитель), строки по 60.
      expect(serverEntryTop(e, 0, rowExtent: 60), 41);
      expect(serverEntryTop(e, 2, rowExtent: 60), 41 + 120);
      expect(serverEntryTop(e, 9, rowExtent: 60), isNull);
    });
  });

  test('настройки: по умолчанию выключено, переживают JSON', () {
    const d = AppSettings();
    expect(d.sortServersByCountry, isFalse);
    expect(d.collapsedCountries, isEmpty);
    final s = AppSettings.fromJson(const AppSettings(
            sortServersByCountry: true, collapsedCountries: ['DE', 'RU-DE'])
        .toJson());
    expect(s.sortServersByCountry, isTrue);
    expect(s.collapsedCountries, ['DE', 'RU-DE']);
    // Битый элемент не роняет разбор.
    final bad = AppSettings.fromJson({
      ...const AppSettings().toJson(),
      'collapsedCountries': ['DE', 5, null],
    });
    expect(bad.collapsedCountries, ['DE']);
  });

  test('раскладка интерфейса не требует переподключения', () {
    const a = AppSettings();
    expect(a.requiresReconnect(a.copyWith(sortServersByCountry: true)), isFalse);
    expect(a.requiresReconnect(a.copyWith(collapsedCountries: ['DE'])), isFalse);
  });

  test('оба списка строят строки одной функцией', () {
    for (final f in ['lib/ui/home_screen.dart', 'lib/ui/servers_screen.dart']) {
      final src = File(f).readAsStringSync();
      expect(src, contains('serverListEntries('), reason: f);
      expect(src, contains('ServerGroupHeaderTile('), reason: f);
    }
  });
}
