import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/settings/split_tunnel_counts.dart';

void main() {
  test('пустой список — все нули', () {
    expect(countAppRules(const []), RuleCounts.empty);
    expect(countSiteRules(const []), RuleCounts.empty);
    expect(RuleCounts.empty.isEmpty, isTrue);
  });

  test('приложения: включённые разложены по действиям', () {
    final c = countAppRules(const [
      AppRule('a.exe', byName: true, action: AppAction.tunnel),
      AppRule('b.exe', byName: true, action: AppAction.tunnel),
      AppRule('c.exe', byName: true, action: AppAction.direct),
      AppRule('d.exe', byName: true, action: AppAction.block),
    ]);
    expect(c.total, 4);
    expect(c.enabled, 4);
    expect(c.disabled, 0);
    expect(c.tunnel, 2);
    expect(c.direct, 1);
    expect(c.block, 1);
  });

  test('⚠️ выключенное правило не попадает в графу своего действия', () {
    // Иначе заголовок обещал бы блокировку, которой в конфиге ядра нет.
    final c = countAppRules(const [
      AppRule('a.exe', byName: true, action: AppAction.block, enabled: false),
      AppRule('b.exe', byName: true, action: AppAction.tunnel),
    ]);
    expect(c.total, 2);
    expect(c.enabled, 1);
    expect(c.disabled, 1);
    expect(c.block, 0);
    expect(c.tunnel, 1);
  });

  test('сайты: выключения нет, все считаются включёнными', () {
    final c = countSiteRules(const [
      SiteRule('a.com', action: AppAction.tunnel),
      SiteRule('b.com', action: AppAction.block),
    ]);
    expect(c.total, 2);
    expect(c.enabled, 2);
    expect(c.disabled, 0);
    expect(c.tunnel, 1);
    expect(c.block, 1);
  });

  test('сумма действий равна числу включённых', () {
    final c = countAppRules(const [
      AppRule('a.exe', byName: true, action: AppAction.tunnel),
      AppRule('b.exe', byName: true, action: AppAction.direct, enabled: false),
      AppRule('c.exe', byName: true, action: AppAction.block),
    ]);
    expect(c.tunnel + c.direct + c.block, c.enabled);
    expect(c.enabled + c.disabled, c.total);
  });
}
