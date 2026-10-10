import 'split_tunnel.dart';

/// Раскладка списков раздельного туннелирования для показа: подгруппы по
/// действию, порядок «новые сверху», дерево поддоменов и сворачивание.
///
/// ⚠️ ТОЛЬКО ОТОБРАЖЕНИЕ. Порядок правил на диске не меняется: новое правило
/// по-прежнему дописывается в КОНЕЦ списка, а «сверху» оно оказывается лишь
/// здесь, разворотом. Переставлять сами правила нельзя: подпись раздельного
/// туннелирования сравнивается целиком и решает, нужно ли переподключаться,
/// и перестановка порвала бы живой туннель на ровном месте. Плюс текстовый
/// экспорт остаётся в порядке добавления, и импорт «Заменить всё» из него
/// возвращает ту же картину.
///
/// Чистый Dart без виджетов: раскладку проверяют тесты, а не глаз.

/// Порядок подгрупп — решение владельца 11.10.2026: Туннель, Прямо, Блок.
const splitActionOrder = [AppAction.tunnel, AppAction.direct, AppAction.block];

/// Ключ свёрнутой подгруппы в [AppSettings.splitCollapsed]: `apps:tunnel`,
/// `sites:block`. Имя значения enum, а не подпись: подпись переводится, и
/// смена языка молча разворачивала бы всё.
String splitGroupKey(String list, AppAction action) => '$list:${action.name}';

/// Ключ свёрнутого узла дерева сайтов: `site:example.com|443`. Пара
/// (домен, порт) уникальна в списке, поэтому действие в ключ не входит.
String siteNodeKey(SiteRule s) =>
    'site:${s.domain.toLowerCase()}|${s.port ?? ''}';

/// Правила, разложенные по действию в порядке [splitActionOrder]. Внутри
/// подгруппы — новые сверху (список на диске идёт в порядке добавления).
/// Пустые подгруппы не возвращаются: заголовок без строк — лишний шум.
List<({AppAction action, List<T> rules})> groupRulesByAction<T>(
    List<T> rules, AppAction Function(T) actionOf) {
  return [
    for (final a in splitActionOrder)
      if (rules.any((r) => actionOf(r) == a))
        (
          action: a,
          rules: [
            for (final r in rules.reversed)
              if (actionOf(r) == a) r
          ],
        ),
  ];
}

/// Строка дерева сайтов.
class SiteTreeRow {
  final SiteRule site;

  /// Сколько РЕАЛЬНО присутствующих предков у домена в этой подгруппе.
  final int depth;

  /// Сколько строк под этой (все уровни). Ноль — сворачивать нечего.
  final int descendants;

  /// Узел свёрнут: его потомки в выдачу не попали.
  final bool collapsed;

  /// Первая строка нового корневого домена — по ней рисуется разделитель.
  final bool newGroup;

  const SiteTreeRow({
    required this.site,
    required this.depth,
    required this.descendants,
    required this.collapsed,
    required this.newGroup,
  });
}

/// Дерево сайтов ОДНОЙ подгруппы. [sites] — в порядке на диске (старые
/// первыми). [collapsed] — ключи [siteNodeKey] свёрнутых узлов.
///
/// ⚠️ РОДИТЕЛЬ — БЛИЖАЙШИЙ ПРЕДОК, КОТОРЫЙ ЕСТЬ В СПИСКЕ, а не вычисленный
/// корень. `xtls.github.com` без `github.com` в списке — самостоятельная
/// строка: отступ, приклеенный к соседу сверху, владелец однажды прочитал как
/// «поддомен настроен не туда» и пошёл искать поломку в конфиге.
///
/// Порядок: ветка, в которой есть самое свежее правило, — выше. Так только что
/// добавленный поддомен виден сверху вместе со своим родителем, а родитель
/// по-прежнему стоит над потомками.
List<SiteTreeRow> siteTreeRows(List<SiteRule> sites,
    {Set<String> collapsed = const {}}) {
  final n = sites.length;
  // Домен → индекс записи, которая станет родителем для его поддоменов.
  // Одинаковый домен с разными портами: родителем берём запись без порта, а
  // при её отсутствии — самую раннюю. Записи с одним доменом — соседи.
  final byDomain = <String, int>{};
  for (var i = 0; i < n; i++) {
    final d = sites[i].domain.toLowerCase();
    final prev = byDomain[d];
    if (prev == null || (sites[prev].port != null && sites[i].port == null)) {
      byDomain[d] = i;
    }
  }

  final parent = List<int?>.filled(n, null);
  for (var i = 0; i < n; i++) {
    final parts = sites[i].domain.toLowerCase().split('.');
    for (var k = 1; k < parts.length; k++) {
      final p = byDomain[parts.sublist(k).join('.')];
      if (p != null && p != i) {
        parent[i] = p;
        break;
      }
    }
  }

  final children = List.generate(n, (_) => <int>[]);
  final roots = <int>[];
  for (var i = 0; i < n; i++) {
    final p = parent[i];
    if (p == null) {
      roots.add(i);
    } else {
      children[p].add(i);
    }
  }

  // Свежесть ветки — наибольший индекс в ней (индекс = порядок добавления).
  final newest = List<int>.filled(n, -1);
  final size = List<int>.filled(n, 0);
  int walk(int i) {
    var best = i;
    var count = 1;
    for (final c in children[i]) {
      final b = walk(c);
      if (b > best) best = b;
      count += size[c];
    }
    newest[i] = best;
    size[i] = count;
    return best;
  }

  for (final r in roots) {
    walk(r);
  }
  int byNewest(int a, int b) => newest[b].compareTo(newest[a]);
  roots.sort(byNewest);
  for (final c in children) {
    c.sort(byNewest);
  }

  final out = <SiteTreeRow>[];
  String? prevBase;
  void emit(int i, int depth) {
    final key = siteNodeKey(sites[i]);
    final hasKids = children[i].isNotEmpty;
    final isCollapsed = hasKids && collapsed.contains(key);
    final base = depth == 0 ? baseDomain(sites[i].domain).toLowerCase() : null;
    out.add(SiteTreeRow(
      site: sites[i],
      depth: depth,
      descendants: size[i] - 1,
      collapsed: isCollapsed,
      newGroup: depth == 0 && prevBase != null && prevBase != base,
    ));
    if (depth == 0) prevBase = base;
    if (isCollapsed) return;
    for (final c in children[i]) {
      emit(c, depth + 1);
    }
  }

  for (final r in roots) {
    emit(r, 0);
  }
  return out;
}

/// Переключить ключ в наборе свёрнутого. Возвращает новый отсортированный
/// список: порядок на диске стабилен, и файл настроек не «дышит» от кликов.
List<String> toggleCollapsedKey(List<String> current, String key) {
  final set = current.toSet();
  if (!set.remove(key)) set.add(key);
  return set.toList()..sort();
}
