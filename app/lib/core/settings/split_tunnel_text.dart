/// Текстовый список правил раздельного туннелирования: ОДНА СТРОКА — ОДНО
/// ПРАВИЛО.
///
/// ⚠️ ЗАЧЕМ НЕ JSON. Прежний экспорт был JSON-конвертом, и это делало главный
/// сценарий невозможным: человек берёт где-то список доменов, разделённых
/// переводом строки, и хочет влить его КУСКОМ в уже готовый список. С JSON он
/// должен либо вписывать домены по одному в поле «Добавить сайт», либо руками
/// собирать чужой список в объект. Требование владельца — простой список.
///
/// Формат:
/// ```
/// [tunnel]
/// youtube.com
/// sub.example.com:8443 exit="Германия 2"
///
/// [direct]
/// http://old.example.org real-ip
///
/// [block]
/// ads.example.net
/// ```
///
/// ⚠️ КЛЮЧЕВЫЕ СЛОВА ВСЕГДА АНГЛИЙСКИЕ, независимо от языка интерфейса.
/// Решение владельца: списками меняются люди, а интерфейс переведён на десять
/// языков — с переводимыми словами список из чужой локали пришлось бы править
/// руками. Переводится вокруг текста что угодно, сам текст — нет.
///
/// ⚠️ ГОЛАЯ СТРОКА РАВНОСИЛЬНА РУЧНОМУ ВВОДУ В ПОЛЕ. Строка без секции и без
/// хвоста параметров заводит ровно то же правило, что получилось бы, напечатай
/// человек этот домен в поле «Добавить сайт»: правило включено, действие —
/// [SplitTunnelConfig.defaultAction] текущего режима. Это и есть смысл
/// «вставить чужой список»: он обязан работать без правки.
///
/// ⚠️ В ТЕКСТ НЕ ПОПАДАЕТ НИ ОДИН АДРЕС СЕРВЕРА. Выход записывается ИМЕНЕМ
/// (`exit="Германия 2"`), а не ключом: ключ сервера — это share-ссылка, в
/// которой лежит адрес, порт и учётные данные. Экспорт правил — это текст,
/// которым люди меняются в чатах; утечка подписки через него была бы тихой и
/// необратимой. Имя, которому на этой машине нет сервера, читается как `null`
/// (общий туннель) — ровно как исчезнувший из подписки сервер в `fromJson`.
/// Страж — `test/split_tunnel_text_test.dart`.
library;

import 'dart:convert' show LineSplitter;

import 'split_tunnel.dart';

/// Имя секции по действию. Английские слова — см. преамбулу файла.
String _sectionOf(AppAction a) => switch (a) {
      AppAction.tunnel => 'tunnel',
      AppAction.direct => 'direct',
      AppAction.block => 'block',
    };

AppAction? _actionOfSection(String name) => switch (name) {
      'tunnel' => AppAction.tunnel,
      'direct' => AppAction.direct,
      'block' => AppAction.block,
      _ => null,
    };

/// Флаг «правило выключено» (только у приложений: у сайтов галочки нет).
const _kOff = 'off';

/// Флаг «этому правилу «Прямо» разрешено выходить под реальным IP».
const _kRealIp = 'real-ip';

/// Флаг «правило приложения важнее правил по сайтам» ([AppRule.overrideSites]).
const _kBeforeSites = 'before-sites';

/// Префикс параметра выхода: `exit=Германия` либо `exit="Германия 2"`.
const _kExit = 'exit=';

/// Разбитая на токены строка: первый токен — сам домен или программа, дальше
/// флаги. Значение `exit=` может быть в кавычках и содержать пробелы.
({String head, List<String> flags, String? exit})? _splitLine(String line) {
  final tokens = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
      continue;
    }
    if (!quoted && (ch == ' ' || ch == '\t')) {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  if (tokens.isEmpty) return null;

  final head = tokens.first;
  final flags = <String>[];
  String? exit;
  for (final t in tokens.skip(1)) {
    if (t.toLowerCase().startsWith(_kExit)) {
      final v = t.substring(_kExit.length).trim();
      // ⚠️ Пустое `exit=` — это НЕ «общий туннель по просьбе», а опечатка.
      // Разницы в итоге нет (оба дают null), но и выдумывать смысл не из чего.
      if (v.isNotEmpty) exit = v;
      continue;
    }
    flags.add(t.toLowerCase());
  }
  return (head: head, flags: flags, exit: exit);
}

/// Экранирование имени выхода: с пробелом — в кавычках.
String _exitToken(String name) {
  final clean = name.replaceAll('"', '').trim();
  if (clean.isEmpty) return '';
  return clean.contains(' ') ? ' $_kExit"$clean"' : ' $_kExit$clean';
}

/// Что стало со строкой при разборе — для окна предпросмотра.
enum RuleTextLineKind {
  /// Правило разобрано.
  rule,

  /// Заголовок секции `[tunnel]` и т. п.
  section,

  /// Пусто или комментарий (`#`).
  skipped,

  /// Не разобрано: после чистки от схемы и пути не осталось ничего.
  bad,
}

/// Итог разбора текста: правила плюс строки, которые не стали правилами.
class RuleTextParse<T> {
  final List<T> rules;

  /// Строки, в которых ничего не нашлось, — показываются человеку как есть,
  /// чтобы он увидел, что именно пропало. Молчаливая потеря строки в списке на
  /// тысячу доменов неотличима от исправной работы.
  final List<String> badLines;

  const RuleTextParse(this.rules, this.badLines);

  bool get isEmpty => rules.isEmpty;
}

/// Правило, уже лежащее в списке, и то, что пришло на его место.
typedef RuleConflict<T> = ({T current, T incoming});

/// План слияния: что добавится, что уже есть, что спорит.
///
/// ⚠️ Считается ДО применения и показывается человеку. Импорт списка на тысячу
/// строк — операция, которую нельзя отменить одним нажатием, и «применилось
/// что-то» здесь не годится.
class RuleMergePlan<T> {
  /// Записей в списке нет — добавятся.
  final List<T> added;

  /// Такая же запись уже есть — ничего не изменится.
  final List<T> unchanged;

  /// Запись есть, но отличается (чаще всего действием).
  final List<RuleConflict<T>> conflicts;

  const RuleMergePlan(
      {this.added = const [], this.unchanged = const [], this.conflicts = const []});

  bool get isEmpty => added.isEmpty && unchanged.isEmpty && conflicts.isEmpty;

  /// Изменит ли слияние хоть что-то (при выбранном решении по спорам).
  bool changes({required bool overwriteConflicts}) =>
      added.isNotEmpty || (overwriteConflicts && conflicts.isNotEmpty);
}

// ── Сайты ───────────────────────────────────────────────────────────────────

/// Текстовый список правил сайтов.
///
/// [exitNameOf] переводит ключ сервера в ИМЯ (адрес не пишется никогда, см.
/// преамбулу). Вернул `null` — выход в строку не попадает.
String encodeSiteRules(List<SiteRule> sites,
    {String? Function(String serverKey)? exitNameOf}) {
  final out = StringBuffer();
  var first = true;
  for (final action in AppAction.values) {
    final group = sites.where((s) => s.action == action).toList();
    if (group.isEmpty) continue;
    if (!first) out.writeln();
    first = false;
    out.writeln('[${_sectionOf(action)}]');
    for (final s in group) {
      // Схема возвращается в строку, а не уезжает в флаг: `http://site.com` —
      // это ровно то, что человек вводил, и так оно читается обратно.
      out.write(s.insecureScheme ? 'http://${s.label}' : s.label);
      if (s.allowRealIp) out.write(' $_kRealIp');
      final key = s.serverKey;
      if (key != null) {
        final name = exitNameOf?.call(key);
        if (name != null) out.write(_exitToken(name));
      }
      out.writeln();
    }
  }
  return out.toString();
}

/// Разбор текстового списка сайтов.
///
/// [defaultAction] — действие для строк ВНЕ секций (см. преамбулу: голая
/// строка равна ручному вводу). [exitKeyOf] переводит имя выхода в ключ
/// сервера; имя без сервера на этой машине даёт `null` — общий туннель.
RuleTextParse<SiteRule> parseSiteRules(String text,
    {required AppAction defaultAction,
    String? Function(String exitName)? exitKeyOf}) {
  final rules = <SiteRule>[];
  final bad = <String>[];
  final seen = <String>{};
  var action = defaultAction;

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final section = _asSection(line);
    if (section != null) {
      action = section;
      continue;
    }
    final parts = _splitLine(line);
    if (parts == null) continue;

    final domain = normalizeDomain(parts.head);
    if (domain.isEmpty || !domain.contains('.')) {
      // ⚠️ Точка обязательна. Без неё в список сайтов уезжали бы слова из
      // чужого текста — заголовки, пояснения, случайно скопированная строка, —
      // и каждое становилось бы доменным правилом.
      bad.add(line);
      continue;
    }
    final port = extractPort(parts.head);
    // Запись уникальна парой (домен, порт) — как и в списке на экране.
    final id = '$domain|${port ?? ''}';
    if (!seen.add(id)) continue;

    final exitName = parts.exit;
    rules.add(SiteRule(
      domain,
      port: port,
      action: action,
      allowRealIp: parts.flags.contains(_kRealIp),
      insecureScheme: hasInsecureScheme(parts.head),
      serverKey: exitName == null ? null : exitKeyOf?.call(exitName),
    ));
  }
  return RuleTextParse(rules, bad);
}

/// План слияния списка сайтов. Тождество записи — пара (домен, порт).
RuleMergePlan<SiteRule> planSiteMerge(
    List<SiteRule> current, List<SiteRule> incoming) {
  String id(SiteRule s) => '${s.domain.toLowerCase()}|${s.port ?? ''}';
  final have = {for (final s in current) id(s): s};
  final added = <SiteRule>[];
  final unchanged = <SiteRule>[];
  final conflicts = <RuleConflict<SiteRule>>[];
  for (final s in incoming) {
    final old = have[id(s)];
    if (old == null) {
      added.add(s);
    } else if (_sameSite(old, s)) {
      unchanged.add(s);
    } else {
      conflicts.add((current: old, incoming: s));
    }
  }
  return RuleMergePlan(
      added: added, unchanged: unchanged, conflicts: conflicts);
}

bool _sameSite(SiteRule a, SiteRule b) =>
    a.action == b.action &&
    a.allowRealIp == b.allowRealIp &&
    a.serverKey == b.serverKey &&
    a.insecureScheme == b.insecureScheme;

/// Применить план: добавить новые, спорные — перезаписать или оставить.
///
/// ⚠️ Порядок существующих записей сохраняется, новые дописываются в конец.
/// Импорт, перетасовавший список, человек читает как «он всё переделал».
List<SiteRule> applySiteMerge(List<SiteRule> current, RuleMergePlan<SiteRule> plan,
    {required bool overwriteConflicts}) {
  final out = [...current];
  if (overwriteConflicts) {
    for (final c in plan.conflicts) {
      final i = out.indexOf(c.current);
      if (i >= 0) out[i] = c.incoming;
    }
  }
  out.addAll(plan.added);
  return out;
}

// ── Приложения ──────────────────────────────────────────────────────────────

/// Текстовый список правил приложений.
///
/// Правило «по имени» пишется именем файла, «по полному пути» — путём: способ
/// сопоставления читается обратно из самой строки, отдельного слова не нужно.
String encodeAppRules(List<AppRule> apps,
    {String? Function(String serverKey)? exitNameOf}) {
  final out = StringBuffer();
  var first = true;
  for (final action in AppAction.values) {
    final group = apps.where((a) => a.action == action).toList();
    if (group.isEmpty) continue;
    if (!first) out.writeln();
    first = false;
    out.writeln('[${_sectionOf(action)}]');
    for (final a in group) {
      final head = a.byName ? a.name : a.path;
      out.write(head.contains(' ') ? '"$head"' : head);
      if (!a.enabled) out.write(' $_kOff');
      if (a.allowRealIp) out.write(' $_kRealIp');
      if (a.overrideSites) out.write(' $_kBeforeSites');
      final key = a.serverKey;
      if (key != null) {
        final name = exitNameOf?.call(key);
        if (name != null) out.write(_exitToken(name));
      }
      out.writeln();
    }
  }
  return out.toString();
}

/// Разбор текстового списка приложений.
///
/// ⚠️ Способ сопоставления выводится из строки: есть разделитель пути —
/// правило «по полному пути», нет — «по имени». Так же ведёт себя и ручное
/// добавление, и это важнее краткости: правило «по имени», записанное полным
/// путём, перестало бы узнавать программу после её обновления.
RuleTextParse<AppRule> parseAppRules(String text,
    {required AppAction defaultAction,
    String? Function(String exitName)? exitKeyOf}) {
  final rules = <AppRule>[];
  final bad = <String>[];
  final seen = <String>{};
  var action = defaultAction;

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final section = _asSection(line);
    if (section != null) {
      action = section;
      continue;
    }
    final parts = _splitLine(line);
    if (parts == null) continue;

    final head = parts.head.trim();
    if (head.isEmpty) {
      bad.add(line);
      continue;
    }
    final byName = !head.contains(r'\') && !head.contains('/');
    final rule = AppRule(
      head,
      byName: byName,
      action: action,
      enabled: !parts.flags.contains(_kOff),
      allowRealIp: parts.flags.contains(_kRealIp),
      overrideSites: parts.flags.contains(_kBeforeSites),
      serverKey: parts.exit == null ? null : exitKeyOf?.call(parts.exit!),
    );
    if (!seen.add(rule.matchKey)) continue;
    rules.add(rule);
  }
  return RuleTextParse(rules, bad);
}

/// План слияния списка приложений. Тождество — [AppRule.matchKey].
RuleMergePlan<AppRule> planAppMerge(
    List<AppRule> current, List<AppRule> incoming) {
  final have = {for (final a in current) a.matchKey: a};
  final added = <AppRule>[];
  final unchanged = <AppRule>[];
  final conflicts = <RuleConflict<AppRule>>[];
  for (final a in incoming) {
    final old = have[a.matchKey];
    if (old == null) {
      added.add(a);
    } else if (_sameApp(old, a)) {
      unchanged.add(a);
    } else {
      conflicts.add((current: old, incoming: a));
    }
  }
  return RuleMergePlan(
      added: added, unchanged: unchanged, conflicts: conflicts);
}

bool _sameApp(AppRule a, AppRule b) =>
    a.action == b.action &&
    a.enabled == b.enabled &&
    a.allowRealIp == b.allowRealIp &&
    a.overrideSites == b.overrideSites &&
    a.serverKey == b.serverKey &&
    a.byName == b.byName;

/// Применить план слияния приложений (см. [applySiteMerge]).
List<AppRule> applyAppMerge(List<AppRule> current, RuleMergePlan<AppRule> plan,
    {required bool overwriteConflicts}) {
  final out = [...current];
  if (overwriteConflicts) {
    for (final c in plan.conflicts) {
      final i = out.indexOf(c.current);
      if (i >= 0) out[i] = c.incoming;
    }
  }
  out.addAll(plan.added);
  return out;
}

/// Заголовок секции `[tunnel]` → действие, иначе `null`.
AppAction? _asSection(String line) {
  if (!line.startsWith('[') || !line.endsWith(']')) return null;
  return _actionOfSection(line.substring(1, line.length - 1).trim().toLowerCase());
}
