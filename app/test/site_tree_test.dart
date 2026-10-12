import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_rule_layout.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// Раскладка списков раздельного туннелирования: дерево сайтов, подгруппы по
/// действию, порядок «новые сверху» и сворачивание.
///
/// ⚠️ ПОЧЕМУ ЭТО ВАЖНО, ХОТЯ ОТОБРАЖЕНИЕ НИЧЕГО НЕ МАРШРУТИЗИРУЕТ.
///
/// Владелец увидел в списке `xtls.github.com` с отступом сразу под
/// `dnsleaktest.com` и прочитал это как «поддомен настроен не туда». Маршруты
/// строятся отдельно и были верны, но человек пошёл искать поломку в конфиге —
/// то есть неверная картинка стоила разбора на ровном месте. Отступ обязан
/// означать РОДСТВО, а не «у домена больше трёх частей».
void main() {
  // Домены в порядке ДОБАВЛЕНИЯ (как лежат на диске): первый — самый старый.
  List<SiteTreeRow> tree(List<String> domains, {Set<String> collapsed = const {}}) =>
      siteTreeRows(
          [for (final d in domains) SiteRule(d, action: AppAction.tunnel)],
          collapsed: collapsed);

  List<String> order(List<SiteTreeRow> t) => [for (final e in t) e.site.domain];

  int depthOf(List<SiteTreeRow> t, String d) =>
      t.firstWhere((e) => e.site.domain == d).depth;

  group('Отступ означает родство, а не длину имени', () {
    test('поддомен без родителя в списке отступа НЕ получает', () {
      // Ровно случай владельца: `github.com` в списке нет, поэтому
      // `xtls.github.com` — самостоятельная строка, а не чей-то потомок.
      final t = tree(['dnsleaktest.com', 'xtls.github.com']);
      expect(depthOf(t, 'xtls.github.com'), 0,
          reason: 'отступ приклеил бы его к соседу сверху');
      expect(depthOf(t, 'dnsleaktest.com'), 0);
    });

    test('поддомен с родителем в списке отступ получает', () {
      final t = tree(['github.io', 'xtls.github.io']);
      expect(depthOf(t, 'github.io'), 0);
      expect(depthOf(t, 'xtls.github.io'), 1);
    });

    test('глубина считается по РЕАЛЬНЫМ предкам, а не по числу точек', () {
      final t = tree(['example.com', 'a.b.example.com']);
      expect(depthOf(t, 'a.b.example.com'), 1);

      final full = tree(['example.com', 'b.example.com', 'a.b.example.com']);
      expect(depthOf(full, 'b.example.com'), 1);
      expect(depthOf(full, 'a.b.example.com'), 2);
    });

    test('регистр не мешает опознать родителя', () {
      final t = tree(['Example.COM', 'sub.example.com']);
      expect(depthOf(t, 'sub.example.com'), 1);
    });

    test('двухуровневые суффиксы не считаются корнем', () {
      expect(baseDomain('sub.example.co.uk'), 'example.co.uk');
      final t = tree(['example.co.uk', 'sub.example.co.uk']);
      expect(depthOf(t, 'sub.example.co.uk'), 1);
    });

    test('один домен с разными портами — соседи, а не родитель и потомок', () {
      final sites = [
        const SiteRule('example.com', port: 8443, action: AppAction.tunnel),
        const SiteRule('example.com', action: AppAction.tunnel),
        const SiteRule('sub.example.com', action: AppAction.tunnel),
      ];
      final t = siteTreeRows(sites);
      expect([for (final e in t) e.depth], everyElement(lessThan(2)));
      // Родитель поддомена — запись БЕЗ порта.
      final plain = t.indexWhere((e) => e.site.domain == 'example.com' && e.site.port == null);
      final sub = t.indexWhere((e) => e.site.domain == 'sub.example.com');
      expect(sub, plain + 1);
      expect(t[sub].depth, 1);
      expect(t.firstWhere((e) => e.site.port == 8443).depth, 0);
    });
  });

  group('Порядок: новые сверху, предок всегда выше потомка', () {
    test('одиночные сайты — последний добавленный первый', () {
      expect(order(tree(['a.com', 'b.com', 'c.com'])), ['c.com', 'b.com', 'a.com']);
    });

    test('ветка со свежим поддоменом поднимается целиком', () {
      // example.com старше всех, но под ним только что добавили поддомен:
      // новая строка обязана быть видна сверху — вместе с родителем.
      final t = tree(['example.com', 'other.com', 'new.example.com']);
      expect(order(t), ['example.com', 'new.example.com', 'other.com']);
    });

    test('поддомены одного родителя — тоже новые сверху', () {
      final t = tree(['example.com', 'a.example.com', 'b.example.com']);
      expect(order(t), ['example.com', 'b.example.com', 'a.example.com']);
    });

    test('потомок, добавленный РАНЬШЕ родителя, всё равно под ним', () {
      final t = tree(['sub.example.com', 'example.com']);
      expect(order(t), ['example.com', 'sub.example.com']);
      expect(depthOf(t, 'sub.example.com'), 1);
    });

    test('голый публичный суффикс не уезжает под своего потомка', () {
      final t = tree(['bbc.co.uk', 'co.uk']);
      expect(order(t), ['co.uk', 'bbc.co.uk']);
      expect(depthOf(t, 'bbc.co.uk'), 1);
    });

    test('глубокий поддомен не прилипает к чужому соседу', () {
      final t = tree(['example.com', 'a.example.com', 'b.example.com', 'x.a.example.com']);
      final o = order(t);
      // x.a — потомок a, и стоит СРАЗУ под ним, а не под b.
      expect(o.indexOf('x.a.example.com'), o.indexOf('a.example.com') + 1);
      expect(depthOf(t, 'x.a.example.com'), 2);
    });

    test('предок раньше потомка — на произвольном наборе', () {
      final domains = [
        'z.example.com', 'example.com', 'a.example.com', 'co.uk',
        'bbc.co.uk', 'news.bbc.co.uk', 'github.io', 'xtls.github.io',
        'dnsleaktest.com',
      ];
      final o = order(tree(domains));
      expect(o.toSet(), domains.toSet());
      for (final child in domains) {
        for (final parent in domains) {
          if (child == parent || !child.endsWith('.$parent')) continue;
          expect(o.indexOf(parent), lessThan(o.indexOf(child)),
              reason: '$parent обязан стоять выше своего потомка $child');
        }
      }
    });
  });

  group('Границы корневых доменов видны', () {
    test('разделитель перед новым корнем, но не перед первым и не в ветке', () {
      final t = tree(['github.io', 'xtls.github.io', 'dnsleaktest.com']);
      final marks = {for (final e in t) e.site.domain: e.newGroup};
      expect(t.first.newGroup, isFalse, reason: 'перед первой группой разделять нечего');
      expect(marks['github.io'], isTrue);
      expect(marks['xtls.github.io'], isFalse,
          reason: 'поддомен — та же группа, разделитель разорвал бы её');
    });

    test('одна ветка — ни одного разделителя', () {
      final t = tree(['example.com', 'a.example.com', 'b.example.com']);
      expect(t.where((e) => e.newGroup), isEmpty);
    });
  });

  group('Сворачивание поддоменов', () {
    final sites = ['example.com', 'a.example.com', 'x.a.example.com', 'other.com'];

    test('число потомков считается по всем уровням', () {
      final t = tree(sites);
      expect(t.firstWhere((e) => e.site.domain == 'example.com').descendants, 2);
      expect(t.firstWhere((e) => e.site.domain == 'a.example.com').descendants, 1);
      expect(t.firstWhere((e) => e.site.domain == 'other.com').descendants, 0);
    });

    test('свёрнутый узел прячет всю ветку, сам остаётся', () {
      final key = siteNodeKey(const SiteRule('example.com', action: AppAction.tunnel));
      final t = tree(sites, collapsed: {key});
      expect(order(t), ['other.com', 'example.com']);
      expect(t.firstWhere((e) => e.site.domain == 'example.com').collapsed, isTrue);
    });

    test('свернуть можно и средний уровень', () {
      final key = siteNodeKey(const SiteRule('a.example.com', action: AppAction.tunnel));
      final t = tree(sites, collapsed: {key});
      expect(order(t), ['other.com', 'example.com', 'a.example.com']);
    });

    test('пометка на узле без потомков ничего не прячет и не «сворачивает» его', () {
      final key = siteNodeKey(const SiteRule('other.com', action: AppAction.tunnel));
      final t = tree(sites, collapsed: {key});
      expect(t, hasLength(4));
      expect(t.firstWhere((e) => e.site.domain == 'other.com').collapsed, isFalse);
    });

    test('ключ узла не зависит от регистра и различает порт', () {
      expect(siteNodeKey(const SiteRule('Example.COM', action: AppAction.tunnel)),
          siteNodeKey(const SiteRule('example.com', action: AppAction.block)));
      expect(siteNodeKey(const SiteRule('example.com', port: 443, action: AppAction.tunnel)),
          isNot(siteNodeKey(const SiteRule('example.com', action: AppAction.tunnel))));
    });
  });

  group('Подгруппы по действию', () {
    test('порядок Туннель → Прямо → Блок, пустые не показываются', () {
      final rules = [
        const SiteRule('b1.com', action: AppAction.block),
        const SiteRule('t1.com', action: AppAction.tunnel),
        const SiteRule('t2.com', action: AppAction.tunnel),
      ];
      final g = groupRulesByAction(rules, (r) => r.action);
      expect([for (final x in g) x.action], [AppAction.tunnel, AppAction.block]);
      expect([for (final r in g.first.rules) r.domain], ['t2.com', 't1.com'],
          reason: 'внутри подгруппы новые сверху');
    });

    test('приложения раскладываются так же', () {
      final apps = [
        const AppRule('C:/a.exe', action: AppAction.direct),
        const AppRule('C:/b.exe', action: AppAction.tunnel),
        const AppRule('C:/c.exe', action: AppAction.direct),
      ];
      final g = groupRulesByAction(apps, (r) => r.action);
      expect([for (final x in g) x.action], [AppAction.tunnel, AppAction.direct]);
      expect([for (final r in g[1].rules) r.path], ['C:/c.exe', 'C:/a.exe']);
    });

    test('ключи подгрупп не зависят от языка интерфейса', () {
      expect(splitGroupKey('apps', AppAction.tunnel), 'apps:tunnel');
      expect(splitGroupKey('sites', AppAction.block), 'sites:block');
    });
  });

  group('Состояние сворачивания на диске', () {
    test('переключатель ставит и снимает ключ, список отсортирован', () {
      var keys = toggleCollapsedKey(const [], 'sites:block');
      keys = toggleCollapsedKey(keys, 'apps:tunnel');
      expect(keys, ['apps:tunnel', 'sites:block']);
      expect(toggleCollapsedKey(keys, 'apps:tunnel'), ['sites:block']);
    });

    test('переживает JSON и не требует переподключения', () {
      const d = AppSettings();
      expect(d.splitCollapsed, isEmpty);
      final s = AppSettings.fromJson(
          const AppSettings(splitCollapsed: ['apps:direct', 'site:a.com|']).toJson());
      expect(s.splitCollapsed, ['apps:direct', 'site:a.com|']);
      final bad = AppSettings.fromJson({
        'splitCollapsed': ['apps:direct', 3, null],
      });
      expect(bad.splitCollapsed, ['apps:direct']);
      expect(d.requiresReconnect(d.copyWith(splitCollapsed: ['apps:direct'])), isFalse,
          reason: 'нажатие на шеврон не должно рвать туннель');
    });
  });
}
