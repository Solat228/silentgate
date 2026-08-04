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
