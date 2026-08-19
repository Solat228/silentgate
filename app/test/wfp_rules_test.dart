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
    bool allowDhcp = true,
    int? luid,
  }) =>
      KillSwitchPlan(
        allowServerIps: serverIps,
        allowOwnBinaries: allowOwn,
        ownBinaryPaths: ownBinaries,
        allowLoopback: allowLoopback,
        allowLan: allowLan,
        allowDhcpAndNdp: allowDhcp,
        blockedAppPaths: blockedApps,
        blockAll: blockAll,
        tunnelInterfaceLuid: luid,
      );

  WfpRule named(List<WfpRule> rules, String fragment) =>
      rules.firstWhere((r) => r.name.contains(fragment),
          orElse: () => throw StateError('нет правила со словом «$fragment»'));

  group('⚠️ ЛЕСТНИЦА ВЕСОВ — это и есть логика kill switch', () {
    test('общий блок легче КАЖДОГО разрешения', () {
      // Общий блок обязан пробиваться любым разрешением: иначе туннель,
      // loopback и свои бинари окажутся отрезаны, и человек останется без сети
      // вместо защиты.
      final rules = buildWfpRules(plan(
        ownBinaries: const [r'C:\sg\silentgate.exe'],
        luid: 42,
      ));
      final blanket = named(rules, 'блокировать весь трафик');
      expect(blanket.weight, WfpWeights.block);
      for (final r in rules.where((r) => !r.isBlock)) {
        expect(r.weight, greaterThan(blanket.weight),
            reason: '«${r.name}» не перекроет общий блок');
      }
    });

    test('⚠️ блок DNS ТЯЖЕЛЕЕ локальной сети — ради этого он и заведён', () {
      // Иначе запрос к роутеру проходит, и провайдер видит все домены, пока
      // туннель лежит между попытками. Это не мелочь: интерфейс в это время
      // обещает защиту.
      expect(WfpWeights.blockDns, greaterThan(WfpWeights.lan));
    });

    test('⚠️ блок DNS ЛЕГЧЕ туннеля, своих бинарей и loopback', () {
      // Иначе он зарубил бы DNS внутри туннеля (то есть весь интернет),
      // резолв панели нашим клиентом и локальный резолвер ядра.
      expect(WfpWeights.blockDns, lessThan(WfpWeights.tunnelInterface));
      expect(WfpWeights.blockDns, lessThan(WfpWeights.ownBinaries));
      expect(WfpWeights.blockDns, lessThan(WfpWeights.loopback));
    });

    test('⚠️ блок приложения ТЯЖЕЛЕЕ локальной сети', () {
      // Приложение, которому мы закрыли сеть, иначе продолжало бы ходить к
      // роутеру — а там и резолвер, и чей-нибудь прокси.
      expect(WfpWeights.blockApp, greaterThan(WfpWeights.lan));
    });

    test('блок приложения ЛЕГЧЕ туннеля и loopback', () {
      // Заблокированное приложение обязано продолжать работать ЧЕРЕЗ VPN и
      // через локальный прокси ядра — блокируется выход мимо туннеля, а не
      // приложение целиком.
      expect(WfpWeights.blockApp, lessThan(WfpWeights.tunnelInterface));
      expect(WfpWeights.blockApp, lessThan(WfpWeights.loopback));
    });

    test('вес каждого правила укладывается в диапазон FWP_UINT8', () {
      for (final r in buildWfpRules(plan(luid: 1))) {
        expect(r.weight, inInclusiveRange(0, WfpWeights.max),
            reason: '«${r.name}»: вес вне 0…15 — ядро отвергнет фильтр');
      }
    });
  });

  group('⚠️ Инварианты, нарушение которых открывает всё', () {
    test('НИ ОДНО разрешение не идёт без условий', () {
      // Разрешающий фильтр без условий выпускает наружу ВСЁ и обесценивает
      // блокировку целиком. Право не иметь условий есть только у общего блока.
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

    test('у каждого правила есть хотя бы один слой', () {
      for (final r in buildWfpRules(plan(luid: 1))) {
        expect(r.layers, isNotEmpty, reason: '«${r.name}» никуда не встанет');
      }
    });

    test('блокировать нечего — не трогаем систему вовсе', () {
      expect(buildWfpRules(plan(blockAll: false)), isEmpty,
          reason: 'поднимать сессию и подслой не из-за чего');
    });
  });

  group('Что закрываем', () {
    test('«всё через VPN» — общий блок без условий на четыре слоя', () {
      final b = named(buildWfpRules(plan()), 'блокировать весь трафик');
      expect(b.conditions, isEmpty);
      expect(b.layers.length, 4,
          reason: 'без слоёв V6 утечка просто уйдёт по IPv6');
    });

    test('⚠️ блок DNS: порт 53 по UDP ИЛИ TCP, только исходящие', () {
      final d = named(buildWfpRules(plan()), 'блок DNS');
      expect(d.isBlock, isTrue);
      expect(d.layers, [WfpLayers.aleAuthConnectV4, WfpLayers.aleAuthConnectV6],
          reason: 'входящих соединений на 53-й порт у клиента не бывает');
      // Повтор поля «протокол» — это «или» по правилам самого WFP.
      expect(d.conditions.length, 3);
      expect(d.conditions[0].field, same(WfpConditions.ipRemotePort));
      expect(d.conditions[0].number, 53);
      expect(d.conditions[1].field, same(WfpConditions.ipProtocol));
      expect(d.conditions[1].number, IpProto.udp);
      expect(d.conditions[2].field, same(WfpConditions.ipProtocol));
      expect(d.conditions[2].number, IpProto.tcp);
    });

    test('⚠️ блока DNS НЕТ в режиме «только отмеченные»', () {
      // Там неотмеченные приложения обязаны работать как обычно — включая их
      // DNS. Общий запрет резолва сломал бы ровно то, что пользователь просил
      // не трогать.
      final rules = buildWfpRules(plan(
        blockAll: false,
        blockedApps: const [r'C:\app\one.exe'],
      ));
      expect(rules.where((r) => r.name.contains('блок DNS')), isEmpty);
    });

    test('⚠️ «только отмеченные» — режем ТОЛЬКО туннельные приложения', () {
      // Решение владельца 19.08.2026 (школа Mullvad): исключение из туннеля
      // остаётся исключением и из блокировки.
      final rules = buildWfpRules(plan(
        blockAll: false,
        blockedApps: const [r'C:\app\one.exe', r'C:\app\two.exe'],
      ));
      final blocks = rules.where((r) => r.isBlock).toList();
      expect(blocks.length, 2);
      for (final b in blocks) {
        expect(b.conditions.single.kind, WfpValueKind.appId);
        expect(b.conditions.single.field, same(WfpConditions.aleAppId));
        expect(b.weight, WfpWeights.blockApp);
      }
      expect(blocks.map((b) => b.conditions.single.path),
          [r'C:\app\one.exe', r'C:\app\two.exe']);
    });

    test('при полной блокировке приложения по отдельности не перечисляются',
        () {
      final rules = buildWfpRules(plan(blockedApps: const [r'C:\app\one.exe']));
      // ⚠️ Ищем по ВЕСУ, а не по слову «блок» в названии: блок DNS называется
      // так же и в полной блокировке он как раз обязан быть.
      expect(rules.where((r) => r.weight == WfpWeights.blockApp), isEmpty,
          reason: 'общий блок уже покрывает их — второе правило лишнее');
      expect(rules.where((r) => r.conditions.any((c) => c.path.isNotEmpty)),
          isEmpty,
          reason: 'пути приложений в полной блокировке не перечисляются');
    });
  });

  group('Что оставляем открытым', () {
    test('⚠️ адреса серверов разрешены ВСЕГДА', () {
      // Иначе туннель не поднимется заново: ядру некуда постучаться, и
      // блокировка станет вечной — сама себя не снимет.
      final rules = buildWfpRules(plan(
        serverIps: {'203.0.113.10', '198.51.100.7'},
      ));
      final servers = rules.where((r) => r.name.contains('сервер')).toList();
      expect(servers.length, 2);
      for (final s in servers) {
        expect(s.conditions.single.field, same(WfpConditions.ipRemoteAddress));
        expect(s.conditions.single.number, 32, reason: 'маска целиком');
      }
    });

    test('⚠️ сервер по IPv6 уходит на слои V6, а не V4', () {
      final s = named(buildWfpRules(plan(serverIps: {'2001:db8::1'})), 'сервер');
      expect(s.conditions.single.kind, WfpValueKind.v6Net);
      expect(s.conditions.single.number, 128);
      expect(s.layers, WfpLayers.v6,
          reason: 'правило на чужом семействе просто не сработает');
    });

    test('⚠️ интерфейс туннеля появляется только вместе с LUID', () {
      // Адаптера в момент первого подъёма не существует — его создаёт ядро,
      // которое ещё не запущено. Выдуманный LUID разрешил бы ЧУЖОЙ интерфейс.
      final r = named(buildWfpRules(plan(luid: 0x1234)), 'интерфейс туннеля');
      expect(r.conditions.single.kind, WfpValueKind.u64);
      expect(r.conditions.single.number, 0x1234);
      expect(r.conditions.single.field, same(WfpConditions.ipLocalInterface));

      expect(
          buildWfpRules(plan())
              .where((r) => r.name.contains('интерфейс туннеля')),
          isEmpty);
    });

    test('withTunnelLuid достраивает план, ничего больше не меняя', () {
      final before = plan(ownBinaries: const [r'C:\sg\one.exe']);
      final after = before.withTunnelLuid(99);
      expect(after.tunnelInterfaceLuid, 99);
      expect(after.allowServerIps, before.allowServerIps);
      expect(after.ownBinaryPaths, before.ownBinaryPaths);
      expect(after.blockAll, before.blockAll);
      expect(buildWfpRules(after).length, buildWfpRules(before).length + 1);
    });

    test('loopback разрешается по флагу, а не по адресу', () {
      // По адресу пришлось бы перечислять 127.0.0.0/8 и ::1 и всё равно
      // промахнуться мимо соединений, которые ядро считает локальными.
      final r = named(buildWfpRules(plan()), 'loopback');
      expect(r.conditions.single.field, same(WfpConditions.flags));
      expect(r.conditions.single.matchType, WfpConst.matchFlagsAnySet);
      expect(r.conditions.single.number, WfpConst.conditionFlagIsLoopback);
    });

    test('свои бинари: без списка путей правило не строится', () {
      expect(
          buildWfpRules(plan(ownBinaries: const []))
              .where((r) => r.name.contains('свой')),
          isEmpty);
      final own = named(
          buildWfpRules(plan(ownBinaries: const [r'C:\sg\sing-box.exe'])),
          'свой');
      expect(own.name, contains('sing-box.exe'), reason: 'имя, а не весь путь');
      expect(own.conditions.single.path, r'C:\sg\sing-box.exe');
    });

    test('локальная сеть отключается целиком', () {
      expect(
          buildWfpRules(plan(allowLan: true))
              .where((r) => r.name.contains('локальная'))
              .length,
          lanNets.length);
      expect(
          buildWfpRules(plan(allowLan: false))
              .where((r) => r.name.contains('локальная')),
          isEmpty);
    });

    test('loopback отключается отдельно от остального', () {
      expect(
          buildWfpRules(plan(allowLoopback: false))
              .where((r) => r.name.contains('loopback')),
          isEmpty);
    });
  });

  group('⚠️ DHCP и соседи IPv6 — иначе машина теряет адрес', () {
    test('живут НЕЗАВИСИМО от разрешения локальной сети', () {
      // Аренда истекает и во время блокировки. Запретив продление, мы оставим
      // человека без адреса и ПОСЛЕ снятия защиты.
      final rules = buildWfpRules(plan(allowLan: false));
      expect(rules.where((r) => r.name.contains('DHCP')).length, 4);
      expect(rules.where((r) => r.name.contains('соседи IPv6')).length, 5);
    });

    test('отключаются своим переключателем', () {
      final rules = buildWfpRules(plan(allowDhcp: false));
      expect(rules.where((r) => r.name.contains('DHCP')), isEmpty);
      expect(rules.where((r) => r.name.contains('соседи')), isEmpty);
    });

    test('⚠️ ответ DHCP разрешён БЕЗ условия по адресу отправителя', () {
      // При первой аренде своего адреса ещё нет, а адрес сервера заранее не
      // известен — условие по адресу сделало бы правило неработающим.
      final r = named(buildWfpRules(plan()), 'DHCPv4 ответ');
      expect(r.layers, [WfpLayers.aleAuthRecvAcceptV4]);
      expect(r.conditions.any((c) => c.field == WfpConditions.ipRemoteAddress),
          isFalse);
      expect(r.conditions.map((c) => c.number), [IpProto.udp, 68, 67]);
    });

    test('⚠️ тип ICMPv6 задаётся полем ЛОКАЛЬНОГО ПОРТА', () {
      // Так устроен сам WFP: замер показал, что ICMP_TYPE и IP_LOCAL_PORT —
      // один и тот же GUID. Правило без протокола ICMPv6 совпало бы с обычным
      // UDP-трафиком на порт 133.
      final r = named(buildWfpRules(plan()), 'ICMPv6 135');
      expect(r.layers, WfpLayers.v6);
      expect(r.conditions[0].field, same(WfpConditions.ipProtocol));
      expect(r.conditions[0].number, IpProto.icmpV6);
      expect(r.conditions[1].field, same(WfpConditions.ipLocalPortOrIcmpType));
      expect(r.conditions[1].number, 135);
    });
  });

  group('⚠️ Мусор во входных данных не имеет права снять защиту', () {
    test('битый адрес сервера пропускается, остальные правила целы', () {
      // Одна опечатка не должна обрушить ВЕСЬ набор: без набора нет и
      // блокировки, то есть защита отключилась бы целиком и молча.
      final rules = buildWfpRules(plan(
        serverIps: {'не-адрес', '203.0.113.10', ''},
      ));
      expect(rules.where((r) => r.name.contains('блокировать весь')).length, 1);
      expect(rules.where((r) => r.name.contains('сервер')).length, 1);
    });

    test('пустой список серверов не мешает блоку встать', () {
      final rules = buildWfpRules(plan(serverIps: const {}));
      expect(rules.where((r) => r.name.contains('блокировать весь')).length, 1,
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
      const expected = 4 + // общий блок
          2 + // блок DNS (только исходящие)
          4 + // loopback
          4 + // свой бинарь
          4 + // интерфейс туннеля
          2 + // сервер v4
          4 + // DHCPv4 запрос+ответ (по одному слою) и DHCPv6 запрос+ответ
          10 + // пять правил соседей IPv6 по два слоя
          16; // шесть локальных сетей v4 по 2 и две v6 по 2
      expect(total, expected);
    });
  });
}
