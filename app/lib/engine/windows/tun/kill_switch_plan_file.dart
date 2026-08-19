import 'dart:convert';
import 'dart:io';

import '../wfp_rules.dart';

/// ЧТО БЛОКИРОВАТЬ — ПЕРЕДАЁТСЯ ПОМОЩНИКУ ФАЙЛОМ.
///
/// ⚠️ ПОЧЕМУ ФАЙЛОМ, А НЕ ИНАЧЕ. Помощник TUN — ОТДЕЛЬНЫЙ ПРОЦЕСС, и знает он
/// ровно то, что лежит на диске. Остальные пути закрыты:
///  * **в конфиг sing-box нельзя** — ядро отвергает конфиг ЦЕЛИКОМ из-за одного
///    незнакомого поля, то есть туннель просто не поднимется;
///  * **аргументом задачи Планировщика нельзя** — она запекает строку запуска
///    один раз, при создании, а состав блокировки меняется с каждой сессией
///    (другой сервер — другие адреса).
///
/// ⚠️ ЧЕГО ЗДЕСЬ НЕТ И ПОЧЕМУ:
///  * **пути своих бинарей** — помощник и есть `silentgate.exe`, а ядра он
///    находит сам (`XrayPaths.locate`). Передавать ему то, что он знает лучше
///    нас, значит завести второй источник правды;
///  * **LUID адаптера туннеля** — в момент записи файла адаптера ЕЩЁ НЕ
///    СУЩЕСТВУЕТ: его создаёт ядро, которое запустит сам помощник. Он и
///    спросит LUID, когда адаптер появится (`TunLuid.forAlias`).
class KillSwitchPlanFile {
  static const fileName = 'tun_killswitch.json';

  static String pathFor(Directory supportDir) =>
      '${supportDir.path}${Platform.pathSeparator}$fileName';

  /// Записать состав блокировки. `enabled: false` пишем ЯВНО, а не удаляем
  /// файл: помощник должен отличать «блокировать не просили» от «файл потерян».
  static Future<void> write(
    Directory supportDir, {
    required bool enabled,
    /// ⚠️ ТОКЕН СЕССИИ — ТО ЖЕ ИМЯ МЬЮТЕКСА, ЧТО В `tun_alive`. Без него
    /// помощник не отличает план ЭТОЙ сессии от прошлогоднего: файл переживает
    /// отключение, падение и перезагрузку. Стухшие адреса серверов означают
    /// блокировку, из-под которой не переподключиться.
    required String sessionToken,
    required Set<String> serverIps,
    required bool blockAll,
    required List<String> blockedAppPaths,
    required bool allowLan,
  }) async {
    final map = <String, dynamic>{
      'enabled': enabled,
      'sessionToken': sessionToken,
      'serverIps': serverIps.toList()..sort(),
      'blockAll': blockAll,
      'blockedAppPaths': blockedAppPaths,
      'allowLan': allowLan,
    };
    await File(pathFor(supportDir)).writeAsString(jsonEncode(map));
  }

  /// Прочитать состав. `null` — файла нет, он битый или блокировка не просилась.
  ///
  /// ⚠️ ЛЮБАЯ НЕЯСНОСТЬ ДАЁТ `null`, И ЭТО НАМЕРЕННО. Блокировка, собранная из
  /// полупрочитанного файла, — это либо дыра (потеряли приложения из списка),
  /// либо машина без нужного трафика (потеряли адреса серверов). Второго шанса
  /// спросить у помощника нет: приложение к этому моменту уже могло умереть.
  static KillSwitchPlan? read(Directory supportDir,
      {int? tunnelLuid, String expectToken = ''}) {
    try {
      final f = File(pathFor(supportDir));
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map) return null;
      if (decoded['enabled'] != true) return null;
      // ⚠️ ЧУЖОЙ ИЛИ СТУХШИЙ ПЛАН НЕ ПРИМЕНЯЕМ. Совпадение токена — простейший
      // способ убедиться, что файл написан ТЕМ ЖЕ запуском приложения, чей
      // мьютекс мы держим под наблюдением.
      if (expectToken.isNotEmpty && decoded['sessionToken'] != expectToken) {
        return null;
      }

      final ips = <String>{
        for (final x in (decoded['serverIps'] as List? ?? const []))
          if (x is String && x.isNotEmpty) x,
      };
      final apps = <String>[
        for (final x in (decoded['blockedAppPaths'] as List? ?? const []))
          if (x is String && x.isNotEmpty) x,
      ];
      return KillSwitchPlan(
        allowServerIps: ips,
        allowOwnBinaries: true,
        ownBinaryPaths: const [], // помощник подставит свои сам
        allowLoopback: true,
        allowLan: decoded['allowLan'] == true,
        blockedAppPaths: apps,
        blockAll: decoded['blockAll'] == true,
        tunnelInterfaceLuid: tunnelLuid,
      );
    } catch (_) {
      return null;
    }
  }

  /// Убрать файл — блокировка этой сессии больше не действует.
  static void clear(Directory supportDir) {
    try {
      final f = File(pathFor(supportDir));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
