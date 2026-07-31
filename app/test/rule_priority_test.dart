import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Приоритет правил. Модель владельца: сайты > приложения > режим > правила
/// панели. Порядок здесь не вкусовой — sing-box берёт ПЕРВОЕ совпадение.
void main() {
  List<Map<String, dynamic>> rules(Map<String, dynamic> c) =>
      ((c['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> build(SplitTunnelConfig split, {bool noRealIp = false}) =>
      SingboxConfigBuilder(
        options: TunOptions(noRealIp: noRealIp, serverIps: const ['203.0.113.1']),
      ).buildMap(split);

  int idxDomain(List<Map<String, dynamic>> r, String d) =>
      r.indexWhere((x) => (x['domain_suffix'] as List?)?.contains(d) == true);
  int idxProcess(List<Map<String, dynamic>> r, String p) =>
      r.indexWhere((x) => (x['process_name'] as List?)?.contains(p) == true);

  test('по умолчанию сайт сильнее приложения', () {
    final r = rules(build(const SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: [AppRule('tg.exe', byName: true, action: AppAction.tunnel)],
      sites: [SiteRule('nalog.ru', action: AppAction.direct)],
    )));
    expect(idxDomain(r, 'nalog.ru'), lessThan(idxProcess(r, 'tg.exe')),
        reason: 'правило про конкретный сайт конкретнее, чем про всё приложение');
  });

  test('галочка переворачивает приоритет для ОДНОГО приложения', () {
    final r = rules(build(const SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: [
        AppRule('tg.exe',
            byName: true, action: AppAction.tunnel, overrideSites: true),
        AppRule('other.exe', byName: true, action: AppAction.tunnel),
      ],
      sites: [SiteRule('nalog.ru', action: AppAction.direct)],
    )));
    expect(idxProcess(r, 'tg.exe'), lessThan(idxDomain(r, 'nalog.ru')),
        reason: 'приложение с галочкой обязано стоять ВЫШЕ доменных правил');
    expect(idxDomain(r, 'nalog.ru'), lessThan(idxProcess(r, 'other.exe')),
        reason: 'остальные приложения остаются ниже сайтов');
  });

  test('приложение попадает ровно в одну группу — дублей нет', () {
    final r = rules(build(const SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: [
        AppRule('tg.exe',
            byName: true, action: AppAction.tunnel, overrideSites: true),
      ],
    )));
    final hits = r.where((x) =>
        (x['process_name'] as List?)?.contains('tg.exe') == true).length;
    expect(hits, 1);
  });

  test('блок сайта выше всего пользовательского', () {
    final r = rules(build(const SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: [
        AppRule('tg.exe',
            byName: true, action: AppAction.tunnel, overrideSites: true),
      ],
      sites: [SiteRule('ads.example', action: AppAction.block)],
    )));
    expect(idxDomain(r, 'ads.example'), lessThan(idxProcess(r, 'tg.exe')),
        reason: 'заблокированное не должно спасаться приоритетом приложения');
  });

  test('«мои правила важнее панели» по умолчанию включено', () {
    expect(const AppSettings().myRulesOverridePanel, isTrue,
        reason: 'иначе правило «Туннель» молча не сработает на панельном сервере');
  });

  test('переопределение переживает сохранение настроек', () {
    const rule = AppRule('tg.exe', byName: true, overrideSites: true);
    expect(AppRule.fromJson(rule.toJson()).overrideSites, isTrue);
    // Старые правила без поля своего смысла не меняют.
    expect(AppRule.fromJson({'path': 'a.exe'}).overrideSites, isFalse);
  });
}
