/// Базовый режим: что происходит с приложениями/сайтами, которым НЕ задано
/// действие вручную, и какое действие присваивается новым записям по умолчанию.
enum SplitMode {
  /// Всё через VPN. Новым записям по умолчанию — «Туннель».
  all,

  /// Через VPN идут только отмеченные «Туннель»; остальное напрямую.
  /// Новым записям по умолчанию — «Туннель».
  onlySelected,

  /// Отмеченные — мимо VPN, остальное через VPN. Новым записям — «Прямо».
  exceptSelected,
}

extension SplitModeLabel on SplitMode {
  String get label {
    switch (this) {
      case SplitMode.all:
        return 'Все — через VPN';
      case SplitMode.onlySelected:
        return 'Только отмеченные — через VPN';
      case SplitMode.exceptSelected:
        return 'Отмеченные — мимо VPN';
    }
  }
}

/// Что делать с трафиком конкретного приложения/сайта (модель v2raytun).
enum AppAction {
  /// Через VPN.
  tunnel,

  /// Напрямую, мимо VPN.
  direct,

  /// Заблокировать (нет сети вообще).
  block,
}

extension AppActionInfo on AppAction {
  String get label {
    switch (this) {
      case AppAction.tunnel:
        return 'Туннель';
      case AppAction.direct:
        return 'Прямо';
      case AppAction.block:
        return 'Блок';
    }
  }
}

/// Правило приложения: путь к exe + режим сопоставления (по имени/по пути, как в Happ)
/// + действие (туннель/прямо/блок).
class AppRule {
  final String path;
  final bool byName; // true = сопоставлять по имени exe, false = по полному пути
  final AppAction action;

  /// Правило включено. Выключенное показывается приглушённым и НЕ применяется
  /// в конфиге (как временно снятая галочка — не удаляя правило).
  final bool enabled;

  const AppRule(this.path,
      {this.byName = false, this.action = AppAction.direct, this.enabled = true});

  String get name => path.split(r'\').last;

  AppRule copyWith({bool? byName, AppAction? action, bool? enabled}) => AppRule(
        path,
        byName: byName ?? this.byName,
        action: action ?? this.action,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() =>
      {'path': path, 'byName': byName, 'action': action.name, 'enabled': enabled};

  factory AppRule.fromJson(Object? j, {AppAction fallback = AppAction.direct}) {
    if (j is String) return AppRule(j, action: fallback); // самый старый формат
    if (j is Map) {
      return AppRule(
        j['path'] as String? ?? '',
        byName: j['byName'] as bool? ?? false,
        action: _actionFrom(j['action'], fallback),
        enabled: j['enabled'] as bool? ?? true,
      );
    }
    return const AppRule('');
  }
}

/// Нормализует домен, введённый пользователем: убирает схему (`https://`),
/// путь/параметры, `www.`, ПОРТ (он живёт отдельным полем) и приводит к нижнему
/// регистру. `https://www.EXAMPLE.com:8443/lk?x=1` → `example.com`.
String normalizeDomain(String input) {
  var d = input.trim().toLowerCase();
  d = d.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), ''); // схема
  d = d.split('/').first.split('?').first.split('#').first; // путь/параметры
  d = d.split(':').first; // порт — отдельно (extractPort)
  if (d.startsWith('www.')) d = d.substring(4);
  return d;
}

/// Достаёт порт из строки вида `example.com:8443` (или полного URL). null — если
/// порт не указан или не в диапазоне 1..65535.
int? extractPort(String input) {
  var d = input.trim().toLowerCase();
  d = d.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');
  d = d.split('/').first.split('?').first.split('#').first;
  final i = d.indexOf(':');
  if (i < 0) return null;
  final p = int.tryParse(d.substring(i + 1));
  if (p == null || p < 1 || p > 65535) return null;
  return p;
}

/// Известные двухуровневые публичные суффиксы — чтобы дерево поддоменов
/// правильно определяло «корень» (`bbc.co.uk`, а не `co.uk`). Список короткий,
/// это лишь ВИЗУАЛЬНАЯ группировка, а не полный Public Suffix List.
const _twoLevelSuffixes = <String>{
  'co.uk', 'org.uk', 'gov.uk', 'ac.uk', 'me.uk', 'ltd.uk', 'plc.uk',
  'com.br', 'com.au', 'net.au', 'org.au', 'com.tr', 'com.cn', 'com.mx',
  'co.jp', 'or.jp', 'ne.jp', 'co.kr', 'com.ua', 'com.tw', 'co.in', 'co.za',
};

/// «Корневой» регистрируемый домен для группировки поддоменов в дерево.
/// `sub.example.com` → `example.com`; `www.bbc.co.uk` → `bbc.co.uk`.
String baseDomain(String domain) {
  final parts = domain.split('.').where((p) => p.isNotEmpty).toList();
  if (parts.length <= 2) return domain;
  final lastTwo = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  if (_twoLevelSuffixes.contains(lastTwo) && parts.length >= 3) {
    return parts.sublist(parts.length - 3).join('.');
  }
  return lastTwo;
}

/// Правило сайта: домен (суффикс) + необязательный порт + действие.
class SiteRule {
  final String domain;
  final int? port; // null = любой порт
  final AppAction action;

  const SiteRule(this.domain, {this.port, this.action = AppAction.direct});

  /// Отображаемая метка: домен и, если задан, порт (`example.com:8443`).
  String get label => port == null ? domain : '$domain:$port';

  SiteRule copyWith({AppAction? action, int? port, bool clearPort = false}) =>
      SiteRule(domain,
          port: clearPort ? null : (port ?? this.port),
          action: action ?? this.action);

  Map<String, dynamic> toJson() =>
      {'domain': domain, if (port != null) 'port': port, 'action': action.name};

  factory SiteRule.fromJson(Object? j, {AppAction fallback = AppAction.direct}) {
    if (j is String) return SiteRule(j, action: fallback); // старый формат (список строк)
    if (j is Map) {
      final p = j['port'];
      return SiteRule(j['domain'] as String? ?? '',
          port: p is int ? p : (p is String ? int.tryParse(p) : null),
          action: _actionFrom(j['action'], fallback));
    }
    return const SiteRule('');
  }
}

AppAction _actionFrom(Object? name, AppAction fallback) {
  if (name == null) return fallback;
  return AppAction.values
      .firstWhere((a) => a.name == name, orElse: () => fallback);
}

/// Конфигурация раздельного туннелирования: базовый режим + приложения + сайты.
class SplitTunnelConfig {
  final SplitMode mode;
  final List<AppRule> apps;
  final List<SiteRule> sites;

  const SplitTunnelConfig({
    this.mode = SplitMode.all,
    this.apps = const [],
    this.sites = const [],
  });

  bool get hasSelection => apps.isNotEmpty || sites.isNotEmpty;

  bool containsApp(String path) =>
      apps.any((a) => a.path.toLowerCase() == path.toLowerCase());

  bool containsSite(String domain, {int? port}) => sites.any((s) =>
      s.domain.toLowerCase() == domain.toLowerCase() && s.port == port);

  /// Действие по умолчанию для новых записей — «то, что выделено» текущим режимом:
  /// «Все через VPN»/«Только отмеченные» → «Туннель», «Отмеченные мимо VPN» → «Прямо».
  AppAction get defaultAction =>
      mode == SplitMode.exceptSelected ? AppAction.direct : AppAction.tunnel;

  SplitTunnelConfig copyWith({
    SplitMode? mode,
    List<AppRule>? apps,
    List<SiteRule>? sites,
  }) {
    return SplitTunnelConfig(
      mode: mode ?? this.mode,
      apps: apps ?? this.apps,
      sites: sites ?? this.sites,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'apps': apps.map((a) => a.toJson()).toList(),
        'sites': sites.map((s) => s.toJson()).toList(),
      };

  factory SplitTunnelConfig.fromJson(Map<String, dynamic> j) {
    final mode = SplitMode.values
        .firstWhere((m) => m.name == j['mode'], orElse: () => SplitMode.all);
    // Действие для старых записей без поля action выводим из прежнего режима:
    // onlySelected — шли через VPN → «Туннель»; exceptSelected — мимо → «Прямо».
    final fallback =
        mode == SplitMode.exceptSelected ? AppAction.direct : AppAction.tunnel;
    // Сайты: новый ключ `sites`, старый — `domains` (список строк).
    final rawSites = (j['sites'] as List?) ?? (j['domains'] as List?) ?? const [];
    return SplitTunnelConfig(
      mode: mode,
      apps: ((j['apps'] as List?) ?? const [])
          .map((e) => AppRule.fromJson(e, fallback: fallback))
          .where((a) => a.path.isNotEmpty)
          .toList(),
      sites: rawSites
          .map((e) => SiteRule.fromJson(e, fallback: fallback))
          .where((s) => s.domain.isNotEmpty)
          .toList(),
    );
  }
}
