import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Выгружает конфиги сценария пользователя (chrome.exe «Туннель» + сайты
/// «Прямо»/«Туннель»/«Блок») для статической проверки настоящим ядром:
/// `engine/windows/bin/sing-box.exe check -c <файл>`. Туннель НЕ поднимается.
void main() {
  const sites = [
    // Явное разрешение реального IP — иначе защита, стоящая выше всех правил,
    // уведёт эти домены через VPN. Так и задумано: она не перебивается.
    SiteRule('example.org', action: AppAction.direct, allowRealIp: true),
    SiteRule('example.com', action: AppAction.direct, allowRealIp: true),
    SiteRule('bank.ru', action: AppAction.direct),
    SiteRule('example.net', action: AppAction.tunnel),
    SiteRule('ads.example', action: AppAction.block),
    SiteRule('example.com', port: 8443, action: AppAction.direct, allowRealIp: true),
    // Поддомен с ДРУГИМ действием, чем у родителя: такие правила поднимаются
    // выше своих групп, и форму поднятого правила тоже обязано принять ядро.
    SiteRule('secure.example.com', action: AppAction.tunnel),
  ];
  const apps = [
    AppRule(r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        byName: true, action: AppAction.tunnel),
    AppRule(r'C:\Telegram\Telegram.exe', action: AppAction.direct, allowRealIp: true),
    // Блок + «важнее правил сайтов»: раньше это сочетание выпадало из конфига
    // целиком, теперь обязано в нём быть — в том числе с точки зрения ядра.
    AppRule('evil.exe', byName: true, action: AppAction.block, overrideSites: true),
  ];

  final outDir = Directory('build/split-configs')..createSync(recursive: true);

  for (final mode in SplitMode.values) {
    for (final noRealIp in [false, true]) {
      test('конфиг ${mode.name}${noRealIp ? ' + noRealIp' : ''}', () {
        final json = SingboxConfigBuilder(
          options: TunOptions(serverIps: const ['203.0.113.10'], noRealIp: noRealIp),
        ).buildJson(SplitTunnelConfig(mode: mode, apps: apps, sites: sites));

        final name = 'sg_${mode.name}${noRealIp ? '_norealip' : ''}.json';
        File('${outDir.path}/$name').writeAsStringSync(json);

        final cfg = jsonDecode(json) as Map<String, dynamic>;
        final routeRules = (cfg['route'] as Map)['rules'] as List;

        int idx(bool Function(Map<String, dynamic>) f) =>
            routeRules.cast<Map<String, dynamic>>().indexWhere(f);
        bool hasDomain(Map<String, dynamic> r, String d) =>
            (r['domain_suffix'] as List?)?.contains(d) == true;

        final siteIdx = idx((r) => hasDomain(r, 'example.org'));
        final appIdx = idx((r) =>
            (r['process_name'] as List?)?.contains('chrome.exe') == true);

        if (mode == SplitMode.all) {
          // «Всё через VPN» = исключений нет (ровно это обещает интерфейс,
          // пряча списки). Значит и в конфиге пользовательских правил быть
          // не должно — иначе сохранённое «Прямо» молча прорезало бы туннель.
          expect(siteIdx, -1, reason: 'в режиме «всё через VPN» правил сайтов нет');
          expect(appIdx, -1,
              reason: 'в режиме «всё через VPN» правил приложений нет');
          return;
        }

        // Инвариант, ради которого всё затевалось: явное правило сайта решает
        // судьбу трафика ВНУТРИ приложения, помеченного «Туннель».
        expect(siteIdx, greaterThanOrEqualTo(0));
        expect(appIdx, greaterThan(siteIdx),
            reason: 'правило сайта обязано стоять выше правила приложения');
        expect(routeRules[siteIdx]['outbound'], 'direct',
            reason: 'явное «Прямо» не должно уводиться в туннель');
      });
    }
  }
}
