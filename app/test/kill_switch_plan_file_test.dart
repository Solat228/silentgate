import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/kill_switch_plan_file.dart';

/// ПЕРЕДАЧА СОСТАВА БЛОКИРОВКИ ПОМОЩНИКУ TUN.
///
/// ⚠️ ЗАЧЕМ ВООБЩЕ ФАЙЛ. Помощник — отдельный процесс, и знает он ровно то, что
/// лежит на диске. В конфиг sing-box состав не положить (ядро отвергает конфиг
/// целиком из-за одного незнакомого поля), аргументом задачи Планировщика — тоже
/// (она запекает строку запуска один раз, а адреса меняются каждую сессию).
///
/// ⚠️ ЦЕНА ОШИБКИ РАЗНАЯ В ДВЕ СТОРОНЫ, и тесты ниже стерегут обе: потеряли
/// адреса серверов — туннель не переподнимется и блокировка станет вечной;
/// потеряли список приложений — блокировки нет там, где её обещали.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sg_ks_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const token = r'Global\SilentGateAlive-deadbeef';

  Future<void> put({
    bool enabled = true,
    Set<String> ips = const {'203.0.113.10'},
    bool blockAll = true,
    List<String> apps = const [],
    List<String> allowed = const [],
    bool allowLan = true,
    String sessionToken = token,
  }) =>
      KillSwitchPlanFile.write(tmp,
          enabled: enabled,
          sessionToken: sessionToken,
          serverIps: ips,
          blockAll: blockAll,
          blockedAppPaths: apps,
          allowedAppPaths: allowed,
          allowLan: allowLan);

  group('Состав доезжает целиком', () {
    test('адреса серверов и режим блокировки', () async {
      await put(ips: {'203.0.113.10', '198.51.100.7'});
      final p = KillSwitchPlanFile.read(tmp)!;
      expect(p.allowServerIps, {'198.51.100.7', '203.0.113.10'});
      expect(p.blockAll, isTrue);
      expect(p.allowLan, isTrue);
    });

    test('⚠️ список приложений — в том же порядке', () async {
      // Порядок не косметика: правила строятся по нему, и перестановка меняет
      // имена фильтров, по которым потом ищут в `netsh wfp show state`.
      await put(blockAll: false, apps: [r'C:\a\one.exe', r'C:\b\two.exe']);
      final p = KillSwitchPlanFile.read(tmp)!;
      expect(p.blockedAppPaths, [r'C:\a\one.exe', r'C:\b\two.exe']);
      expect(p.blockAll, isFalse);
    });

    test('⚠️ явные исключения «кроме отмеченных» доезжают', () async {
      await put(allowed: [r'C:pp\game.exe']);
      expect(KillSwitchPlanFile.read(tmp)!.allowedAppPaths,
          [r'C:pp\game.exe']);
    });

    test('LUID подставляется читателем, а не берётся из файла', () async {
      // Адаптера в момент записи ещё не существует: его создаёт ядро, которое
      // запустит сам помощник. Он же и спросит LUID.
      await put();
      expect(KillSwitchPlanFile.read(tmp)!.tunnelInterfaceLuid, isNull);
      expect(KillSwitchPlanFile.read(tmp, tunnelLuid: 42)!.tunnelInterfaceLuid,
          42);
    });

    test('свои бинари в файле не передаются', () async {
      // Помощник и есть silentgate.exe, а ядра находит сам. Передавать ему то,
      // что он знает лучше нас, — второй источник правды.
      await put();
      expect(KillSwitchPlanFile.read(tmp)!.ownBinaryPaths, isEmpty);
      expect(KillSwitchPlanFile.read(tmp)!.allowOwnBinaries, isTrue);
    });
  });

  group('⚠️ Любая неясность = блокировки нет', () {
    test('файла нет', () {
      expect(KillSwitchPlanFile.read(tmp), isNull);
    });

    test('⚠️ «не просили» пишется ЯВНО, а не удалением файла', () async {
      // Помощник обязан отличать «блокировать не просили» от «файл потерян».
      await put(enabled: false);
      expect(File(KillSwitchPlanFile.pathFor(tmp)).existsSync(), isTrue);
      expect(KillSwitchPlanFile.read(tmp), isNull);
    });

    test('битый JSON не собирает половину плана', () async {
      File(KillSwitchPlanFile.pathFor(tmp)).writeAsStringSync('{это не json');
      expect(KillSwitchPlanFile.read(tmp), isNull,
          reason: 'полуплан — это либо дыра, либо машина без нужного трафика');
    });

    test('мусор в списках отсеивается, остальное цело', () async {
      File(KillSwitchPlanFile.pathFor(tmp)).writeAsStringSync(
          '{"enabled":true,"serverIps":["203.0.113.10",5,"",null],'
          '"blockAll":true,"blockedAppPaths":[7],"allowLan":false}');
      final p = KillSwitchPlanFile.read(tmp)!;
      expect(p.allowServerIps, {'203.0.113.10'});
      expect(p.blockedAppPaths, isEmpty);
      expect(p.allowLan, isFalse);
    });

    test('⚠️ план от ЧУЖОЙ сессии не применяется', () async {
      // Файл переживает отключение, падение и перезагрузку. Стухшие адреса
      // серверов означают блокировку, из-под которой не переподключиться:
      // ядро стучится к новому серверу, а разрешён старый.
      await put(sessionToken: r'Global\SilentGateAlive-старая');
      expect(KillSwitchPlanFile.read(tmp, expectToken: token), isNull);
      // Тот же файл со СВОИМ токеном читается.
      await put();
      expect(KillSwitchPlanFile.read(tmp, expectToken: token), isNotNull);
    });

    test('без ожидаемого токена сверки нет (совместимость)', () async {
      await put(sessionToken: 'что-угодно');
      expect(KillSwitchPlanFile.read(tmp), isNotNull);
    });

    test('clear убирает файл', () async {
      await put();
      KillSwitchPlanFile.clear(tmp);
      expect(KillSwitchPlanFile.read(tmp), isNull);
      KillSwitchPlanFile.clear(tmp); // повтор безопасен
    });
  });
}
