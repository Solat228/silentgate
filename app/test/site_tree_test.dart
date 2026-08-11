import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/ui/split_tunnel_screen.dart';

/// Дерево сайтов в раздельном туннелировании.
///
/// ⚠️ ПОЧЕМУ ЭТО ВАЖНО, ХОТЯ ОТОБРАЖЕНИЕ НИЧЕГО НЕ МАРШРУТИЗИРУЕТ.
///
/// Владелец увидел в списке `xtls.github.com` с отступом сразу под
/// `dnsleaktest.com` и прочитал это как «поддомен настроен не туда». Маршруты
/// строятся отдельно и были верны, но человек пошёл искать поломку в конфиге —
/// то есть неверная картинка стоила разбора на ровном месте. Отступ обязан
/// означать РОДСТВО, а не «у домена больше трёх частей».
void main() {
  List<({SiteRule site, int depth, bool newGroup})> tree(List<String> domains) =>
      SplitTunnelScreen.debugSortedSites(
          [for (final d in domains) SiteRule(d, action: AppAction.tunnel)]);

  int depthOf(List<({SiteRule site, int depth, bool newGroup})> t, String d) =>
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
      // Промежуточного `b.example.com` в списке нет — ступеньки в пустоту быть
      // не должно, иначе она читается как пропущенная строка.
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
  });

  group('Границы групп видны', () {
    test('первая строка новой группы помечена', () {
      final t = tree(['github.io', 'xtls.github.io', 'dnsleaktest.com']);
      // Порядок — по корневому домену: сначала dnsleaktest.com, затем github.io.
      expect(t.first.newGroup, isFalse, reason: 'перед первой группой разделять нечего');
      final marks = {for (final e in t) e.site.domain: e.newGroup};
      expect(marks['github.io'], isTrue,
          reason: 'без разделителя группы читаются как один список');
      expect(marks['xtls.github.io'], isFalse,
          reason: 'поддомен — та же группа, разделитель разорвал бы её');
    });

    test('одна группа — ни одного разделителя', () {
      final t = tree(['example.com', 'a.example.com', 'b.example.com']);
      expect(t.where((e) => e.newGroup), isEmpty);
    });
  });

  group('Порядок: предок ВСЕГДА выше своего потомка', () {
    // ⚠️ Обе проверки ниже — из настоящих находок, а не выдуманные случаи.
    test('голый публичный суффикс не уезжает под своего потомка', () {
      // `co.uk` и `bbc.co.uk` имеют РАЗНЫЙ baseDomain, и прежняя сортировка
      // считала их чужими: потомок вставал ВЫШЕ предка, да ещё в другой группе.
      final t = tree(['co.uk', 'bbc.co.uk']);
      final order = [for (final e in t) e.site.domain];
      expect(order, ['co.uk', 'bbc.co.uk']);
      expect(depthOf(t, 'bbc.co.uk'), 1);
    });

    test('глубокий поддомен не прилипает к чужому соседу', () {
      // Сортировка по ЧИСЛУ меток — обход в ширину: `x.a.example.com`
      // оказывался ПОСЛЕ `b.example.com` и читался как его потомок.
      final t = tree([
        'example.com',
        'a.example.com',
        'b.example.com',
        'x.a.example.com',
      ]);
      final order = [for (final e in t) e.site.domain];
      expect(order, [
        'example.com',
        'a.example.com',
        'x.a.example.com',
        'b.example.com',
      ]);
      expect(depthOf(t, 'x.a.example.com'), 2);
    });

    test('предок раньше потомка — на произвольном наборе', () {
      final domains = [
        'z.example.com', 'example.com', 'a.example.com', 'co.uk',
        'bbc.co.uk', 'news.bbc.co.uk', 'github.io', 'xtls.github.io',
        'dnsleaktest.com',
      ];
      final order = [for (final e in tree(domains)) e.site.domain];
      for (final child in domains) {
        for (final parent in domains) {
          if (child == parent) continue;
          if (!child.endsWith('.$parent')) continue;
          expect(order.indexOf(parent), lessThan(order.indexOf(child)),
              reason: '$parent обязан стоять выше своего потомка $child');
        }
      }
    });
  });

  group('Порядок', () {
    test('корень идёт выше своих поддоменов', () {
      final t = tree(['z.example.com', 'example.com', 'a.example.com']);
      final order = [for (final e in t) e.site.domain];
      expect(order.first, 'example.com');
      expect(order.indexOf('a.example.com'), lessThan(order.indexOf('z.example.com')));
    });

    test('двухуровневые суффиксы не считаются корнем', () {
      // `co.uk` сам по себе не сайт: корнем обязан быть `example.co.uk`.
      expect(baseDomain('sub.example.co.uk'), 'example.co.uk');
      final t = tree(['example.co.uk', 'sub.example.co.uk']);
      expect(depthOf(t, 'sub.example.co.uk'), 1);
    });
  });
}
