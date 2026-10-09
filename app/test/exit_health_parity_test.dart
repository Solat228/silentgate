import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/singbox/exit_outbounds.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/engine/engine_base.dart';

/// СТОРОЖ ВЫХОДОВ ОБЯЗАН БЫТЬ ВООРУЖЁН НА ОБЕИХ ПЛАТФОРМАХ.
///
/// ⚠️ ЗАЧЕМ СТРАЖ ИМЕННО ТАКОЙ. В этом проекте уже дважды случалось, что код
/// написан и не вызывается: связки провайдеров без `lazy: false` (локальный API
/// не работал ни разу ни при каких настройках) и виджет группировки сервисов,
/// который существовал и не был подключён. Оба раза юнит-тесты были зелёными —
/// они проверяли САМ КОД, а не его вызов.
///
/// Здесь то же самое место: `startExitHealth` живёт в базе и сам себя не
/// позовёт. Забудь его платформа — выходы останутся без присмотра ровно так же,
/// как было до правки, и ни один тест логики этого не заметит.
void main() {
  String read(String rel) {
    final f = File(rel);
    expect(f.existsSync(), isTrue, reason: 'страж читает исходник: $rel');
    return f.readAsStringSync();
  }

  test('⚠️ обе платформы вооружают сторож выходов', () {
    for (final path in const [
      'lib/engine/windows/windows_engine.dart',
      'lib/engine/android/android_engine.dart',
    ]) {
      expect(read(path), contains('startExitHealth('),
          reason: '$path не вооружает сторож выходов — выходы этой платформы '
              'останутся без присмотра');
    }
  });

  test('⚠️ обе платформы его гасят', () {
    // Не погасив, оставим таймер опрашивать Clash API мёртвого ядра: он либо
    // будет вечно получать отказ и сыпать заметками о «мёртвых» выходах,
    // которых уже нет, либо достучится до ядра СЛЕДУЮЩЕЙ сессии.
    for (final path in const [
      'lib/engine/windows/windows_engine.dart',
      'lib/engine/android/android_engine.dart',
    ]) {
      expect(read(path), contains('stopExitHealth()'),
          reason: '$path не гасит сторож выходов');
    }
  });

  test('реализация одна на обе платформы — в базе, а не у каждой своя', () {
    // Разъехавшиеся копии — отдельный класс бед: правку вносят в одну, вторая
    // тихо остаётся со старым поведением.
    final base = read('lib/engine/engine_base.dart');
    expect(base, contains('void startExitHealth('));
    for (final path in const [
      'lib/engine/windows/windows_engine.dart',
      'lib/engine/android/android_engine.dart',
    ]) {
      expect(read(path), isNot(contains('void startExitHealth(')),
          reason: '$path завёл свою копию сторожа вместо общей');
    }
  });

  test('теги берутся из конфига и только `exit-`', () {
    // Панельный профиль «Авто» и незнакомый протокол в конфиг не попадают —
    // сторожить их нечего. А инфраструктурные outbound-ы (`direct`, `proxy`,
    // `dns-out`) — не выходы, и проба по ним ничего не значит.
    final tags = VpnEngineBase.exitTagsOf(const [
      {'tag': 'proxy', 'type': 'vless'},
      {'tag': 'exit-1a2b3c', 'type': 'vless'},
      {'tag': 'direct', 'type': 'direct'},
      {'tag': 'exit-9f8e7d', 'type': 'trojan'},
      {'type': 'block'},
    ]);
    expect(tags, ['exit-1a2b3c', 'exit-9f8e7d']);
  });

  test('⚠️ гейт живого канала ПЕРЕДАЁТСЯ, а не просто существует', () {
    // Тот же класс бед, что уже ловили трижды: параметр добавлен, тесты на
    // него зелёные, а в приложении он не передан — и поведение прежнее.
    // `mainChannelAlive` необязателен ИМЕННО поэтому опасен: забудь его, и
    // сторож молча вернётся к объявлению мёртвыми всех выходов разом.
    expect(read('lib/engine/engine_base.dart'), contains('mainChannelAlive:'),
        reason: 'движок не передаёт гейт живого канала сторожу выходов');
  });

  group('⚠️ группа с запасным путём: сторожится группа, пробуется сервер', () {
    // Журнал владельца 08.10.2026: каждый отказ выхода — две строки, вторая
    // под сырым тегом «exit-987faff6-node». И 16 эпизодов «снова отвечает
    // (промахов было 3)»: после переключения на запас проба через группу мерила
    // уже общий туннель, а группу обратно не возвращал никто.
    final server = ShareLinkParser.tryParse(
        'vless://00000000-0000-0000-0000-000000000000@203.0.113.10:443'
        '?type=tcp&security=none&encryption=none#DE')!;
    final outbounds = ExitOutbounds.build(
      servers: {server.key: server},
      fallbackTag: 'proxy',
    ).outbounds;
    final group = exitTagFor(server.key);

    test('внутренний узел группы выходом не считается', () {
      expect(VpnEngineBase.exitTagsOf(outbounds), [group]);
    });

    test('проба группы идёт через её сервер, тег — из того же места', () {
      expect(VpnEngineBase.exitProbeTagsOf(outbounds),
          {group: exitNodeTagFor(group)});
      expect(outbounds.map((o) => o['tag']), contains(exitNodeTagFor(group)),
          reason: 'построитель кладёт сервер ровно под этот тег');
    });

    test('без запасного пути группы нет — проба по тегу выхода', () {
      final plain =
          ExitOutbounds.build(servers: {server.key: server}).outbounds;
      expect(VpnEngineBase.exitTagsOf(plain), [group]);
      expect(VpnEngineBase.exitProbeTagsOf(plain), isEmpty);
    });

    test('восстановление ВОЗВРАЩАЕТ группу на сервер', () {
      expect(read('lib/engine/engine_base.dart'),
          contains('selectExitMember(tag, node)'),
          reason: 'без возврата трафик правила остаётся в чужой стране '
              'до переподключения');
    });
  });

  test('пустой конфиг — пустой список, сторож не вооружится', () {
    expect(VpnEngineBase.exitTagsOf(const []), isEmpty);
  });
}
