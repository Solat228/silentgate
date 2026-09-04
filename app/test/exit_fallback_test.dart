import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/singbox/exit_outbounds.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';

/// У ВЫХОДА ПОЯВИЛСЯ ЗАПАСНОЙ ПУТЬ (очередь починок, правка №3).
///
/// ⚠️ ОТКУДА ЗАДАЧА. Исходная просьба владельца 07.08.2026 звучала так:
/// «через USA приложения D, E, F, а также сайт A как fallback». Выходы сделали,
/// а запасного пути у них так и не появилось: на каждый ключ строился ровно
/// один outbound, и отказ выхода означал, что правило просто перестаёт
/// работать. Пользователь при этом видит не «выход умер», а «сайт не
/// открывается» — то есть беду, причину которой назвать нельзя.
///
/// ⚠️ ПОЧЕМУ `selector`, А НЕ `urltest`. Оба поддерживаются ядром (проверено
/// живьём: 64 узла плюс обе группы приняты), но `urltest` пробует КАЖДОГО
/// участника раз в три минуты. На телефоне это несогласованные пробуждения
/// радио — та самая цена, из-за которой в 1.2.0 решили «выход это один сервер».
/// `selector` не пробует никого: он просто помнит выбор и переключается по
/// команде. Команду даёт сторож выходов, который и так уже стучится в Clash API.
void main() {
  VpnServer srv(String name, String addr) => VpnServer(
        remark: name,
        address: addr,
        port: 443,
        protocol: 'vless',
        id: '00000000-0000-4000-8000-000000000000',
        rawLink: 'vless://00000000-0000-4000-8000-000000000000@$addr:443',
      );

  group('⚠️ Запасной путь выхода', () {
    test('у выхода с запасным строится группа, а не голый outbound', () {
      final res = ExitOutbounds.build(
        servers: {'k1': srv('Германия', '203.0.113.10')},
        resolvedIps: const {},
        fallbackTag: 'proxy',
      );
      final tags = [for (final o in res.outbounds) o['tag'] as String];
      expect(tags, contains(exitTagFor('k1')),
          reason: 'правила ссылаются на этот тег — он обязан остаться прежним');

      final group = res.outbounds.firstWhere((o) => o['tag'] == exitTagFor('k1'));
      expect(group['type'], 'selector',
          reason: 'без группы переключать нечего: у outbound-а нет запасного');
      // ⚠️ ПЕРВЫМ — САМ СЕРВЕР. `default` в sing-box берётся из `outbounds[0]`,
      // и перепутанный порядок означал бы, что правило с самого начала ходит
      // через запасной путь, а выбранный пользователем сервер не участвует.
      expect((group['outbounds'] as List).first, isNot('proxy'));
      expect(group['outbounds'], contains('proxy'));
    });

    test('без запасного тега группа не строится', () {
      // Группа из одного участника — лишняя сущность: переключать не на что,
      // а лишний слой в датапути это лишний способ его сломать.
      final res = ExitOutbounds.build(
        servers: {'k1': srv('Германия', '203.0.113.10')},
        resolvedIps: const {},
      );
      final o = res.outbounds.firstWhere((x) => x['tag'] == exitTagFor('k1'));
      expect(o['type'], isNot('selector'));
    });

    test('⚠️ участник группы — НАСТОЯЩИЙ outbound, а не висячий тег', () {
      // `sing-box check` ссылку на несуществующий тег принимает молча (урок
      // #21 этого проекта): конфиг валиден, а трафик уезжает в `route.final`.
      // Поэтому проверяем не «тег упомянут», а «тег объявлен».
      final res = ExitOutbounds.build(
        servers: {'k1': srv('Германия', '203.0.113.10')},
        resolvedIps: const {},
        fallbackTag: 'proxy',
      );
      final declared = {for (final o in res.outbounds) o['tag'] as String};
      final group =
          res.outbounds.firstWhere((o) => o['tag'] == exitTagFor('k1'));
      for (final member in (group['outbounds'] as List).cast<String>()) {
        // `proxy` объявлен не здесь, а в основном конфиге — его пропускаем.
        if (member == 'proxy') continue;
        expect(declared, contains(member),
            reason: 'участник «$member» не объявлен ни одним outbound-ом');
      }
    });

    test('⚠️ запас у выходов правил есть, у портов API — нет', () {
      // Разница намеренная, и без стража её обязательно «починят» по
      // невнимательности: второй вызов выглядит как забытая правка.
      //
      // Выход правила: умер — трафик уходит в общий туннель, рабочее
      // соединение через другую страну полезнее неработающего правила.
      // Порт локального API: скрипт обращается к конкретному номеру именно
      // потому, что ему нужен конкретный сервер, и тихая подмена страны для
      // него хуже честного отказа.
      final src = File('lib/engine/windows/windows_engine.dart');
      expect(src.existsSync(), isTrue);
      final text = src.readAsStringSync();
      expect('fallbackTag:'.allMatches(text).length, 1,
          reason: 'запас должен передаваться РОВНО в одном вызове — том, что '
              'строит выходы правил; портам API он вреден');
      expect(text, contains('ЗДЕСЬ ЗАПАСНОГО ПУТИ НЕТ НАМЕРЕННО'),
          reason: 'причина отсутствия запаса у портов API обязана быть '
              'записана рядом с кодом, иначе её сочтут забытой правкой');
    });

    test('отвергнутый сервер группы не получает', () {
      // Панельный профиль «Авто» выходом не поднимается вовсе (его конфиг
      // разбирает Xray, а выходы разводит sing-box). Строить для него группу
      // значило бы обещать запасной путь там, где нет и основного.
      final auto = VpnServer(
        remark: 'Авто (лучший)',
        address: '',
        port: 0,
        protocol: 'vless',
        id: '',
        rawLink: 'panel://auto',
        rawPanelConfig: '{"outbounds":[]}',
      );
      final res = ExitOutbounds.build(
        servers: {'auto': auto},
        resolvedIps: const {},
        fallbackTag: 'proxy',
      );
      expect(res.skipped.keys, contains('auto'));
      expect([for (final o in res.outbounds) o['tag']],
          isNot(contains(exitTagFor('auto'))));
    });
  });
}
