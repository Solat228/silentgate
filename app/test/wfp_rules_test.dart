import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/wfp_layout.dart';
import 'package:silentgate/engine/windows/wfp_rules.dart';

/// СОСТАВ БЛОКИРОВКИ — ЕДИНСТВЕННОЕ, ЧТО ЗДЕСЬ МОЖНО ПРОВЕРИТЬ ТЕСТОМ.
///
/// ⚠️ ПОЧЕМУ НИ ОДНОГО ВЫЗОВА К СИСТЕМЕ. Фильтры WFP действуют на сеть ВСЕЙ
/// машины, а тесты гоняются на машине владельца, где в это время идёт его
/// работа. Ошибка в таком тесте — не красная строчка, а человек без интернета.
/// Поэтому состав правил вынесен в чистую функцию и разбирается тут, а сами
/// вызовы к ядру — только в изолированной VM, руками.
void main() {
  KillSwitchPlan plan({
    Set<String> serverIps = const {'203.0.113.10'},
    bool blockAll = true,
    List<String> blockedApps = const [],
    List<String> ownBinaries = const [],
    bool allowOwn = true,
    bool allowLoopback = true,
    bool allowLan = true,
    int? luid,
  }) =>
      KillSwitchPlan(
        allowServerIps: serverIps,
        allowOwnBinaries: allowOwn,
        ownBinaryPaths: ownBinaries,
        allowLoopback: allowLoopback,
        allowLan: allowLan,
        blockedAppPaths: blockedApps,
        blockAll: blockAll,
        tunnelInterfaceLuid: luid,
      );

  group('⚠️ Инварианты, нарушение которых открывает или запирает всё', () {
    test('блок ВСЕГДА легче любого разрешения', () {
      // Это и есть логика kill switch: в подслое побеждает бо́льший вес.
      // Разрешение, оказавшееся легче блока, молча перестало бы работать —
      // и человек остался бы без интернета, не поняв почему.
      final rules = buildWfpRules(plan(
        blockedApps: const [r'C:\app\one.exe'],
        blockAll: false,
        ownBinaries: const [r'C:\sg\silentgate.exe'],
        luid: 42,
      ));
      final blocks = rules.where((r) => r.isBlock);
      final permits = rules.where((r) => !r.isBlock);
      expect(blocks, isNotEmpty);
      expect(permits, isNotEmpty);
      final heaviestBlock =
          blocks.map((r) => r.weight).reduce((a, b) => a > b ? a : b);
      final lightestPermit =
          permits.map((r) => r.weight).reduce((a, b) => a < b ? a : b);
      expect(heaviestBlock, lessThan(lightestPermit),
          reason: 'разрешение не перекроет блок — защита превратится в замок');
    });

    test('⚠️ НИ ОДНО разрешение не идёт без условий', () {
      // Разрешающий фильтр без условий выпускает наружу ВСЁ и обесценивает
      // блокировку целиком. Условий нет права не иметь только у блока.
      for (final r in buildWfpRules(plan(
        ownBinaries: const [r'C:\sg\silentgate.exe'],
        luid: 7,
      ))) {
        if (!r.isBlock) {
          expect(r.conditions, isNotEmpty,
              reason: 'разрешение «${r.name}» выпускает наружу всё подряд');
        }
      }
    });

    test('вес каждого правила укладывается в диапазон FWP_UINT8', () {
      for (final r in buildWfpRules(plan(luid: 1))) {
        expect(r.weight, inInclusiveRange(0, WfpWeights.max),
            reason: '«${r.name}»: вес вне 0…15 — ядро отвергнет фильтр');
      }
    });

    test('у каждого правила есть хотя бы один слой', () {
      for (final r in buildWfpRules(plan(luid: 1))) {
        expect(r.layers, isNotEmpty, reason: '«${r.name}» никуда не встанет');
      }
    });

    test('блокировать нечего — не трогаем систему вовсе', () {
      final rules = buildWfpRules(plan(blockAll: false));
      expect(rules, isEmpty,
          reason: 'поднимать сессию и подслой не из-за чего');
    });
  });

  group('Что закрываем', () {
    test('«всё через VPN» — один блок без условий на четыре слоя', () {
      final rules = buildWfpRules(plan());
      final blocks = rules.where((r) => r.isBlock).toList();
      expect(blocks.length, 1);
      expect(blocks.first.conditions, isEmpty);
      expect(blocks.first.layers.length, 4,
          reason: 'без слоёв V6 утечка просто уйдёт по IPv6');
    });

    test('⚠️ «только отмеченные» — режем ТОЛЬКО туннельные приложения', () {
      // Решение владельца 19.08.2026 (школа Mullvad): исключение из туннеля
      // остаётся исключением и из блокировки. Человек сам сказал, что этим
      // приложениям VPN не нужен, — рубить им сеть значит спорить с ним.
      final rules = buildWfpRules(plan(
        blockAll: false,
        blockedApps: const [r'C:\app\one.exe', r'C:\app\two.exe'],
      ));
      final blocks = rules.where((r) => r.isBlock).toList();
      expect(blocks.length, 2);
      for (final b in blocks) {
        expect(b.conditions.single.kind, WfpValueKind.appId);
        expect(b.conditions.single.field, same(WfpConditions.aleAppId));
      }
      expect(blocks.map((b) => b.conditions.single.path),
          [r'C:\app\one.exe', r'C:\app\two.exe']);
    });

    test('при полной блокировке приложения по отдельности не перечисляются',
        () {
      final rules = buildWfpRules(plan(
        blockedApps: const [r'C:\app\one.exe'],
      ));
      expect(rules.where((r) => r.isBlock).length, 1,
          reason: 'общий блок уже покрывает их — второе правило лишнее');
    });
  });

  group('Что оставляем открытым', () {
    test('⚠️ адреса серверов разрешены ВСЕГДА', () {
      // Иначе туннель не поднимется заново: ядру некуда постучаться, и
      // блокировка станет вечной — сама себя не снимет.
      final rules = buildWfpRules(plan(
        serverIps: {'203.0.113.10', '198.51.100.7'},
      ));
      final servers =
          rules.where((r) => r.name.contains('сервер')).toList();
      expect(servers.length, 2);
      for (final s in servers) {
        expect(s.conditions.single.field, same(WfpConditions.ipRemoteAddress));
        expect(s.conditions.single.number, 32, reason: 'маска целиком');
      }
    });

    test('⚠️ сервер по IPv6 уходит на слои V6, а не V4', () {
      final rules = buildWfpRules(plan(serverIps: {'2001:db8::1'}));
      final s = rules.firstWhere((r) => r.name.contains('сервер'));
      expect(s.conditions.single.kind, WfpValueKind.v6Net);
      expect(s.conditions.single.number, 128);
      expect(s.layers, WfpLayers.v6,
          reason: 'правило на чужом семействе просто не сработает');
    });

    test('интерфейс туннеля разрешается по LUID', () {
      final withLuid = buildWfpRules(plan(luid: 0x1234));
      final rule = withLuid.firstWhere((r) => r.name.contains('туннел'));
      expect(rule.conditions.single.kind, WfpValueKind.u64);
      expect(rule.conditions.single.number, 0x1234);
      expect(rule.conditions.single.field, same(WfpConditions.ipLocalInterface));

      final withoutLuid = buildWfpRules(plan());
      expect(withoutLuid.where((r) => r.name.contains('туннел')), isEmpty,
          reason: 'выдуманный LUID разрешил бы ЧУЖОЙ интерфейс');
    });

    test('loopback разрешается по флагу, а не по адресу', () {
      // По адресу пришлось бы перечислять 127.0.0.0/8 и ::1 и всё равно
      // промахнуться мимо соединений, которые ядро считает локальными.
      final r = buildWfpRules(plan())
          .firstWhere((r) => r.name.contains('loopback'));
      expect(r.conditions.single.field, same(WfpConditions.flags));
      expect(r.conditions.single.matchType, WfpConst.matchFlagsAnySet);
      expect(r.conditions.single.number, WfpConst.conditionFlagIsLoopback);
    });

    test('свои бинари: без списка путей правило не строится', () {
      expect(
          buildWfpRules(plan(ownBinaries: const []))
              .where((r) => r.name.contains('свой')),
          isEmpty);
      final rules =
          buildWfpRules(plan(ownBinaries: const [r'C:\sg\sing-box.exe']));
      final own = rules.firstWhere((r) => r.name.contains('свой'));
      expect(own.name, contains('sing-box.exe'), reason: 'имя, а не весь путь');
      expect(own.conditions.single.path, r'C:\sg\sing-box.exe');
    });

    test('локальная сеть отключается целиком', () {
      final on = buildWfpRules(plan(allowLan: true));
      final off = buildWfpRules(plan(allowLan: false));
      expect(on.where((r) => r.name.contains('локальная')).length,
          lanNets.length);
      expect(off.where((r) => r.name.contains('локальная')), isEmpty);
    });

    test('loopback отключается отдельно от остального', () {
      expect(
          buildWfpRules(plan(allowLoopback: false))
              .where((r) => r.name.contains('loopback')),
          isEmpty);
    });
  });

  group('⚠️ Мусор во входных данных не имеет права снять защиту', () {
    test('битый адрес сервера пропускается, остальные правила целы', () {
      // Одна опечатка не должна обрушить ВЕСЬ набор: без набора нет и
      // блокировки, то есть защита отключилась бы целиком и молча.
      final rules = buildWfpRules(plan(
        serverIps: {'не-адрес', '203.0.113.10', ''},
      ));
      expect(rules.where((r) => r.isBlock).length, 1);
      expect(rules.where((r) => r.name.contains('сервер')).length, 1);
    });

    test('пустой список серверов не мешает блоку встать', () {
      final rules = buildWfpRules(plan(serverIps: const {}));
      expect(rules.where((r) => r.isBlock).length, 1,
          reason: 'блокировка нужна и когда адрес сервера ещё не известен');
    });
  });

  group('Сколько фильтров получится', () {
    test('каждое правило разворачивается по числу слоёв', () {
      final rules = buildWfpRules(plan(
        serverIps: {'203.0.113.10'},
        ownBinaries: const [r'C:\sg\silentgate.exe'],
        luid: 5,
      ));
      final total = rules.fold<int>(0, (a, r) => a + r.filterCount);
      // Блок(4) + loopback(4) + туннель(4) + сервер v4(2) + свой бинарь(4)
      // + локальные сети: шесть v4 по 2 и две v6 по 2 = 16.
      expect(total, 4 + 4 + 4 + 2 + 4 + 16);
    });
  });
}
