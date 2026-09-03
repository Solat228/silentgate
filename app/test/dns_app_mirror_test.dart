import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// DNS-зеркало правил ПРИЛОЖЕНИЙ обязано совпадать с маршрутами ПОЛЕ В ПОЛЕ.
///
/// Баг, ради которого написан тест: в DNS-правило уезжал ПОЛНЫЙ ПУТЬ в поле
/// `process_name`, где ядро ждёт имя файла. Правило видно в конфиге, ядро его
/// принимает, интерфейс показывает «Туннель» — и оно не совпадает никогда.
/// Найдено сверкой с настоящим конфигом с работающего туннеля, а не тестом:
/// прежние тесты проверяли ЛИШЬ НАЛИЧИЕ правила.
void main() {
  const apps = [
    // «По имени» — в маршрутах уходит в process_name как chrome.exe.
    AppRule(r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        byName: true, action: AppAction.tunnel),
    // «По пути» — в маршрутах уходит в process_path_regex целиком.
    AppRule(r'C:\Telegram Desktop\Telegram.exe', action: AppAction.tunnel),
    AppRule(r'C:\Bank\bank.exe', action: AppAction.direct, allowRealIp: true),
    AppRule('evil.exe', byName: true, action: AppAction.block),
  ];
  const split = SplitTunnelConfig(mode: SplitMode.onlySelected, apps: apps);

  final cfg = jsonDecode(SingboxConfigBuilder(
    options: const TunOptions(serverIps: ['203.0.113.10']),
  ).buildJson(split)) as Map<String, dynamic>;

  List<Map<String, dynamic>> rulesOf(String section, String key) =>
      ((cfg[section] as Map)[key] as List).cast<Map<String, dynamic>>();

  /// Наши собственные бинарники: правило петли живёт ТОЛЬКО в маршрутах и
  /// зеркала в DNS не имеет — их запросы и так уходят напрямую.
  const infra = {'xray.exe', 'sing-box.exe', 'silentgate.exe'};

  /// Все значения матчеров процессов в секции — как множество пар (поле, значение).
  Set<String> processMatchers(List<Map<String, dynamic>> rules) {
    final out = <String>{};
    for (final r in rules) {
      for (final field in ['process_name', 'process_path_regex']) {
        final v = r[field];
        if (v is List) {
          for (final x in v) {
            if (field == 'process_name' && infra.contains(x)) continue;
            out.add('$field=$x');
          }
        }
      }
    }
    return out;
  }

  /// ⚠️ МАТЧЕРЫ СОВПАДАЮТ — А РЕЗОЛВЕР МОГ БЫТЬ ЛЮБОЙ.
  ///
  /// Соседний тест сверяет только МНОЖЕСТВО матчеров и в поле `server` не
  /// смотрит вовсе. Значит подмена резолвера у правила «Прямо» на туннельный
  /// (`dns-proxy`) оставила бы весь прогон зелёным, а имена банковского
  /// клиента уехали бы резолвиться через VPN — при том что пользователь
  /// пометил его «мимо VPN» именно чтобы этого не было.
  ///
  /// Дыру нашла адверсариальная проверка предложения BACKLOG #34 (03.09.2026),
  /// а не прогон тестов: предложение «дать прямому DNS запас» разбирали три
  /// независимых оппонента, и все трое показали, что подмена резолвера здесь
  /// ничем не стережётся.
  String? serverOf(Map<String, dynamic> r) => r['server'] as String?;

  /// Чей это резолвер по правилам маршрутов: direct → локальный, proxy →
  /// туннельный, `exit-X` → свой у выхода.
  String outboundOf(Map<String, dynamic> r) {
    final o = r['outbound'];
    if (o is String) return o;
    if (o is List && o.isNotEmpty) return '${o.first}';
    return '${r['action'] ?? ''}';
  }

  test('⚠️ резолвер зеркалит ВЫХОД правила, а не только его матчер', () {
    final routeByMatcher = <String, String>{};
    for (final r in rulesOf('route', 'rules')) {
      for (final field in ['process_name', 'process_path_regex']) {
        final v = r[field];
        if (v is! List) continue;
        for (final x in v) {
          if (field == 'process_name' && infra.contains(x)) continue;
          routeByMatcher['$field=$x'] = outboundOf(r);
        }
      }
    }
    expect(routeByMatcher, isNotEmpty, reason: 'иначе тест ничего не проверяет');

    // Чего ждём от резолвера при каждом выходе. `reject` (блок) в DNS
    // выражается действием, а не сервером, — его тут не сверяем.
    const want = {'direct': 'dns-local', 'proxy': 'dns-proxy'};

    var checked = 0;
    for (final r in rulesOf('dns', 'rules')) {
      for (final field in ['process_name', 'process_path_regex']) {
        final v = r[field];
        if (v is! List) continue;
        for (final x in v) {
          final key = '$field=$x';
          final out = routeByMatcher[key];
          final expected = want[out];
          if (expected == null) continue;
          checked++;
          expect(serverOf(r), expected,
              reason: 'правило $key идёт в «$out», а имена резолвит через '
                  '«${serverOf(r)}» вместо «$expected»');
        }
      }
    }
    expect(checked, greaterThan(0),
        reason: 'ни одна пара не сверена — тест выродился');
  });

  test('⚠️ каждый упомянутый резолвер ОБЪЯВЛЕН — висячий тег ядро не ловит', () {
    // Урок #21 этого проекта: `sing-box check` принимает ссылку на
    // несуществующий тег с кодом 0 и без единой строки вывода, а трафик
    // такого правила молча уезжает в `route.final`. Для DNS то же самое:
    // сослаться на `dns-fallback`, которого в этой конфигурации нет
    // (он объявляется только при поднятом форвардере), — тихая поломка
    // резолва, и никакой прогон её не заметит.
    final declared = {
      for (final s in ((cfg['dns'] as Map)['servers'] as List))
        (s as Map)['tag'] as String
    };
    expect(declared, isNotEmpty);

    final used = <String>{};
    for (final r in rulesOf('dns', 'rules')) {
      final s = serverOf(r);
      if (s != null) used.add(s);
    }
    final fin = (cfg['dns'] as Map)['final'];
    if (fin is String) used.add(fin);
    // `address_resolver` — такая же ссылка на тег, и такая же молчаливая.
    for (final s in ((cfg['dns'] as Map)['servers'] as List)) {
      final ar = (s as Map)['address_resolver'];
      if (ar is String) used.add(ar);
    }

    expect(used.difference(declared), isEmpty,
        reason: 'в dns.rules/final/address_resolver есть теги, которых нет '
            'в dns.servers');
  });

  test('⚠️ и в режиме с поднятым форвардером — теги те же самые', () {
    // Единственный конфиг наверху не задевает ветку с `dns-fallback` вовсе:
    // при `tunnelDnsForAll: false` она недостижима. А именно там живёт тег,
    // которого в других конфигурациях НЕТ, — то есть ровно тот случай, где
    // висячая ссылка и появилась бы. Проверка без этой ветки была бы
    // проверкой безопасного случая.
    final live = jsonDecode(SingboxConfigBuilder(
      options: const TunOptions(
        serverIps: ['203.0.113.10'],
        tunnelDnsForAll: true,
        fallbackDnsPort: 10814,
      ),
    ).buildJson(split)) as Map<String, dynamic>;

    final dns = live['dns'] as Map;
    final declared = {
      for (final x in (dns['servers'] as List)) (x as Map)['tag'] as String
    };
    expect(declared, contains('dns-fallback'),
        reason: 'форвардер поднят, а его резолвер не объявлен');

    final used = <String>{};
    for (final r in (dns['rules'] as List)) {
      final v = (r as Map)['server'];
      if (v is String) used.add(v);
    }
    final fin = dns['final'];
    if (fin is String) used.add(fin);
    for (final x in (dns['servers'] as List)) {
      final ar = (x as Map)['address_resolver'];
      if (ar is String) used.add(ar);
    }
    expect(used.difference(declared), isEmpty);

    // ⚠️ И ГЛАВНОЕ ПРО ЭТОТ ТЕГ. Форвардер спрашивает ТУННЕЛЬ ПЕРВЫМ
    // (`core/net/dns_fallback_server.dart`), поэтому направить в него
    // правила «Прямо» значит отправить их имена в туннель в исправном
    // случае — то есть сделать ровно то, от чего пользователь их уводил.
    // Разбор — BACKLOG #34.
    for (final r in (dns['rules'] as List)) {
      final m = r as Map;
      final isDirectApp = m['process_path_regex'] is List &&
          '${m['process_path_regex']}'.contains('bank');
      if (isDirectApp) {
        expect(m['server'], isNot('dns-fallback'),
            reason: 'имена приложения «Прямо» уходят резолвиться в туннель');
      }
    }
  });

  test('матчеры процессов в DNS те же, что в маршрутах', () {
    final route = processMatchers(rulesOf('route', 'rules'));
    final dns = processMatchers(rulesOf('dns', 'rules'));

    expect(route, isNotEmpty, reason: 'иначе тест ничего не проверяет');
    expect(dns, route,
        reason: 'разойдись зеркало с маршрутом — DNS отмеченного приложения '
            'уйдёт по `final`, то есть утечёт мимо туннеля');
  });

  test('в process_name лежит ИМЯ, а не путь', () {
    for (final r in rulesOf('dns', 'rules')) {
      for (final n in (r['process_name'] as List? ?? const [])) {
        expect(n, isNot(contains(r'\')),
            reason: 'ядро сравнивает process_name с именем файла: '
                'полный путь не совпадёт никогда');
        expect(n, isNot(contains('/')));
      }
    }
  });

  test('«по пути» попадает в process_path_regex, а не в process_name', () {
    final dns = processMatchers(rulesOf('dns', 'rules'));
    expect(dns.any((m) => m.startsWith('process_path_regex=') && m.contains('Telegram')),
        isTrue);
    expect(dns.contains(r'process_name=C:\Telegram Desktop\Telegram.exe'), isFalse);
    expect(dns.contains('process_name=chrome.exe'), isTrue);
  });

  test('блок приложения в DNS — отказ, а не выбор сервера', () {
    final block = rulesOf('dns', 'rules').firstWhere(
        (r) => (r['process_name'] as List?)?.contains('evil.exe') == true);
    expect(block['action'], 'reject');
    expect(block.containsKey('server'), isFalse);
  });

  test('конфиг принимает НАСТОЯЩЕЕ ядро', () {
    final exe = File('../engine/windows/bin/sing-box.exe');
    if (!exe.existsSync()) {
      markTestSkipped('sing-box.exe не найден — проверка ядром пропущена');
      return;
    }
    final dir = Directory('build/dns-mirror')..createSync(recursive: true);
    final f = File('${dir.path}/dns_app_mirror.json')
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
    final r = Process.runSync(exe.path, ['check', '-c', f.absolute.path]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });
}
