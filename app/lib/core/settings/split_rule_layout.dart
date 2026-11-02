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

/// Ключ свёрнутой виртуальной группы поддоменов без явного корневого правила:
/// `vgroup:example.com`.
String virtualGroupNodeKey(String domain) => 'vgroup:${domain.toLowerCase()}';

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

  /// Сколько РЕАЛЬНО присутствующих предков у домена в этой подгруппе
  /// (включая виртуальную группу, если в списке >= 2 братских поддоменов).
  final int depth;

  /// Сколько строк под этой (все уровни). Ноль — сворачивать нечего.
  final int descendants;

  /// Узел свёрнут: его потомки в выдачу не попали.
  final bool collapsed;

  /// Первая строка нового корневого домена — по ней рисуется разделитель.
  final bool newGroup;

  /// Виртуальный заголовок группы для >= 2 поддоменов одного корневого домена,
  /// когда сам корневой домен в правила не добавлен.
  final bool isVirtualGroup;

  const SiteTreeRow({
    required this.site,
    required this.depth,
    required this.descendants,
    required this.collapsed,
    required this.newGroup,
    this.isVirtualGroup = false,
  });

  /// Ключ узла для сворачивания ([siteNodeKey] либо [virtualGroupNodeKey]).
  String get nodeKey =>
      isVirtualGroup ? virtualGroupNodeKey(site.domain) : siteNodeKey(site);
}

/// Дерево сайтов ОДНОЙ подгруппы. [sites] — в порядке на диске (старые
/// первыми). [collapsed] — ключи [siteNodeKey] / [virtualGroupNodeKey]
/// свёрнутых узлов.
///
/// ⚠️ РОДИТЕЛЬ — БЛИЖАЙШИЙ ПРЕДОК, КОТОРЫЙ ЕСТЬ В СПИСКЕ, а не вычисленный
/// корень для одиночки. `xtls.github.com` без `github.com` и без соседей по
/// `github.com` в списке — самостоятельная строка: отступ, приклеенный к
/// чужому соседу сверху, владелец однажды прочитал как «поддомен настроен не
/// туда» и пошёл искать поломку в конфиге.
///
/// Если же в одной подгруппе лежат >= 2 сиротских поддомена ОДНОГО корневого
/// домена (`a.example.com` и `b.example.com` без `example.com`), над ними
/// синтезируется виртуальная группа `example.com` ([SiteTreeRow.isVirtualGroup]),
/// чтобы родственные поддомены не разлетались по разным концам списка.
///
/// Порядок: ветка, в которой есть самое свежее правило, — выше. Так только что
/// добавленный поддомен виден сверху вместе со своим родителем, а родитель
/// по-прежнему стоит над потомками.
List<SiteTreeRow> siteTreeRows(List<SiteRule> sites,
    {Set<String> collapsed = const {}}) {
  final realCount = sites.length;
  if (realCount == 0) return const [];

  // Домен → индекс записи, которая станет родителем для его поддоменов.
  // Одинаковый домен с разными портами: родителем берём запись без порта, а
  // при её отсутствии — самую раннюю. Записи с одним доменом — соседи.
  final byDomain = <String, int>{};
  for (var i = 0; i < realCount; i++) {
    final d = sites[i].domain.toLowerCase();
    final prev = byDomain[d];
    if (prev == null || (sites[prev].port != null && sites[i].port == null)) {
      byDomain[d] = i;
    }
  }

  // Находим сиротские поддомены (у которых нет реального предка в списке).
  // Если у одного `baseDomain` набирается >= 2 таких сиротских домена и сам
  // `baseDomain` отсутствует в `byDomain`, создаём для них виртуальный корень.
  final orphanDomainsByBase = <String, Set<String>>{};
  for (var i = 0; i < realCount; i++) {
    final d = sites[i].domain.toLowerCase();
    final base = baseDomain(d).toLowerCase();
    if (d == base || !base.contains('.') || byDomain.containsKey(base)) {
      continue;
    }
    var hasAncestorBetween = false;
    final parts = d.split('.');
    for (var k = 1; k < parts.length; k++) {
      final cand = parts.sublist(k).join('.');
      if (cand == base) break;
      if (byDomain.containsKey(cand)) {
        hasAncestorBetween = true;
        break;
      }
    }
    if (!hasAncestorBetween) {
      (orphanDomainsByBase[base] ??= <String>{}).add(d);
    }
  }

  final allNodes = <SiteRule>[...sites];
  final actionFallback = sites.first.action;
  for (final entry in orphanDomainsByBase.entries) {
    if (entry.value.length >= 2 && !byDomain.containsKey(entry.key)) {
      final idx = allNodes.length;
      allNodes.add(SiteRule(entry.key, action: actionFallback));
      byDomain[entry.key] = idx;
    }
  }

  final n = allNodes.length;
  final parent = List<int?>.filled(n, null);
  for (var i = 0; i < n; i++) {
    final parts = allNodes[i].domain.toLowerCase().split('.');
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

  // Свежесть ветки — наибольший индекс РЕАЛЬНОГО правила в ней
  // (индекс = порядок добавления). Виртуальный узел собственной свежести и
  // веса в счётчике правил не имеет.
  final newest = List<int>.filled(n, -1);
  final size = List<int>.filled(n, 0);
  int walk(int i) {
    final isReal = i < realCount;
    var best = isReal ? i : -1;
    var count = isReal ? 1 : 0;
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
    final isVirtual = i >= realCount;
    final node = allNodes[i];
    final key =
        isVirtual ? virtualGroupNodeKey(node.domain) : siteNodeKey(node);
    final hasKids = children[i].isNotEmpty;
    final isCollapsed = hasKids && collapsed.contains(key);
    final base = depth == 0 ? baseDomain(node.domain).toLowerCase() : null;
    final desc = isVirtual ? size[i] : size[i] - 1;
    out.add(SiteTreeRow(
      site: node,
      depth: depth,
      descendants: desc,
      collapsed: isCollapsed,
      newGroup: depth == 0 && prevBase != null && prevBase != base,
      isVirtualGroup: isVirtual,
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

/// Принадлежат ли два домена к одному семейству (одинаковый домен, предок /
/// поддомен друг друга или общий регистрируемый [baseDomain]).
bool isSameDomainFamily(String domainA, String domainB) {
  final a = normalizeDomain(domainA);
  final b = normalizeDomain(domainB);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b || a.endsWith('.$b') || b.endsWith('.$a')) return true;
  final ba = baseDomain(a).toLowerCase();
  final bb = baseDomain(b).toLowerCase();
  final aParts = ba.split('.').where((p) => p.isNotEmpty).toList();
  if (aParts.length < 2 || aParts.last.length < 2) return false;
  return ba == bb;
}

/// Подходит ли правило сайта под поисковый ввод в поле «Добавить сайт».
///
/// Оставляет домены, похожие на введённый (подстрока в любую сторону или общее
/// доменное семейство [isSameDomainFamily]), и скрывает посторонние.
bool siteMatchesSearch(SiteRule rule, String rawQuery) {
  final trimmed = rawQuery.trim().toLowerCase();
  if (trimmed.isEmpty) return true;

  final qDomain = normalizeDomain(rawQuery);
  final qPort = extractPort(rawQuery) ??
      (trimmed.startsWith(':') ? int.tryParse(trimmed.substring(1)) : null);
  final d = rule.domain.toLowerCase();

  if (qDomain.isEmpty) {
    if (qPort != null) return rule.port == qPort;
    return rule.label.toLowerCase().contains(trimmed);
  }

  final domainMatch = d.contains(qDomain) ||
      qDomain.contains(d) ||
      (qDomain.contains('.') && isSameDomainFamily(d, qDomain));
  if (!domainMatch) return false;
  if (qPort != null && rule.port != null && rule.port != qPort) {
    return false;
  }
  return true;
}

/// Отфильтровать правила сайтов по живому вводу в поле «Добавить сайт»,
/// сохраняя исходный порядок на диске.
List<SiteRule> filterSiteRules(List<SiteRule> sites, String rawQuery) {
  if (rawQuery.trim().isEmpty) return sites;
  return [
    for (final s in sites)
      if (siteMatchesSearch(s, rawQuery)) s,
  ];
}

/// Ключи свёрнутых групп/узлов, которые нужно раскрыть, чтобы сайт [domain]
/// ([port]) и его доменное семейство стали видимы в списке.
List<String> expandCollapsedForSite({
  required List<String> currentCollapsed,
  required List<SiteRule> allSites,
  required String domain,
  required AppAction action,
}) {
  final remove = <String>{
    splitGroupKey('sites', action),
    virtualGroupNodeKey(baseDomain(domain)),
  };
  final lower = domain.toLowerCase();
  for (final s in allSites) {
    final sd = s.domain.toLowerCase();
    if (sd == lower || lower.endsWith('.$sd') || isSameDomainFamily(sd, lower)) {
      remove.add(siteNodeKey(s));
      remove.add(splitGroupKey('sites', s.action));
      remove.add(virtualGroupNodeKey(baseDomain(sd)));
    }
  }
  return currentCollapsed.where((k) => !remove.contains(k)).toList();
}

/// Переключить ключ в наборе свёрнутого. Возвращает новый отсортированный
/// список: порядок на диске стабилен, и файл настроек не «дышит» от кликов.
List<String> toggleCollapsedKey(List<String> current, String key) {
  final set = current.toSet();
  if (!set.remove(key)) set.add(key);
  return set.toList()..sort();
}
