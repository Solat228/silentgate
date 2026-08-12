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

  /// Явное правило «Прямо» сильнее глобального «Не выходить под реальным IP».
  /// Смысл — только у [AppAction.direct] и только при включённом `noRealIp`:
  /// снятая галочка возвращает это правило под защиту (пойдёт через VPN).
  /// См. [SiteRule.allowRealIp].
  final bool allowRealIp;

  /// Это приложение важнее правил по сайтам.
  ///
  /// По умолчанию правило сайта конкретнее и потому сильнее: «весь Telegram в
  /// туннель» + «nalog.ru напрямую» = налоговая из Telegram идёт напрямую.
  /// Обычно так и надо. Но бывает наоборот: приложение целиком обязано ходить
  /// одним путём, и исключения по сайтам ему только вредят — например,
  /// мессенджер, который должен работать ТОЛЬКО через VPN, что бы ни было в
  /// списке сайтов. Галочка поднимает правило этого приложения ВЫШЕ доменных.
  final bool overrideSites;

  /// ЧЕРЕЗ КАКОЙ СЕРВЕР идёт это приложение. `null` — через тот, что выбран
  /// на главном экране (обычное поведение и умолчание).
  ///
  /// ⚠️ Смысл ТОЛЬКО у [AppAction.tunnel]. «Прямо через Германию» — это
  /// противоречие: прямо значит мимо всех туннелей. Поэтому поле намеренно не
  /// участвует в выборе адресата для `direct` и `block` — иначе появился бы
  /// класс правил, которые видно в интерфейсе и которые ничего не делают.
  ///
  /// Хранится КЛЮЧ сервера (`VpnServer.key`, то есть share-ссылка), а не имя и
  /// не индекс: список серверов перестраивается при каждом обновлении
  /// подписки, и индекс уехал бы на соседа — ровно та поломка, которую уже
  /// ловили с пинами и оверрайдами. Сервер, которого больше нет в подписке,
  /// трактуется как `null` (основной туннель): висячий тег в конфиге опаснее,
  /// потому что `sing-box check` его НЕ ловит и трафик молча уходит
  /// в `route.final`.
  final String? serverKey;

  const AppRule(this.path,
      {this.byName = false,
      this.action = AppAction.direct,
      this.enabled = true,
      this.allowRealIp = false,
      this.overrideSites = false,
      this.serverKey});

  /// Имя для СОПОСТАВЛЕНИЯ, а не для показа.
  ///
  /// ⚠️ ЭТА СТРОКА УХОДИТ В `process_name` КОНФИГА ЯДРА (см.
  /// `singbox_config_builder`: правила приложений и их зеркало в DNS). Подставь
  /// сюда человеческое имя — «Google Chrome» вместо `chrome.exe`, — и все
  /// правила «по имени» на Windows молча перестанут срабатывать: правило видно
  /// в интерфейсе, лежит в конфиге, ядро конфиг принимает, а совпадения нет.
  /// Тот самый почерк, за который в этом проекте уже платили.
  ///
  /// Для показа есть `ui/widgets/app_label.dart` — он спрашивает метку у
  /// системы и к сопоставлению отношения не имеет.
  String get name => path.split(r'\').last;

  /// Ключ, по которому запись считается ТОЙ ЖЕ САМОЙ.
  ///
  /// ⚠️ ЭТО НЕ `path`, И В ЭТОМ БЫЛ БАГ. Правило «по имени» сопоставляется с
  /// процессом по имени файла, а искалось и хранилось — по ПОЛНОМУ ПУТИ.
  /// Программа обновилась, путь сменился
  /// (`…anthropic.claude-code-2.1.222-win32…` → `…2.1.227-win32…`) — и та же
  /// самая программа заводилась ЗАНОВО. У владельца так набралось четыре
  /// строки `claude.exe`, внешне неразличимых, и после каждого обновления
  /// настройка «ломалась»: срабатывала не та запись, которую он правил.
  ///
  /// Правило: **ключ тождественности обязан совпадать с тем, ПО ЧЕМУ идёт
  /// сопоставление.** Иначе список живёт своей жизнью, а ядро — своей.
  String get matchKey => byName ? name.toLowerCase() : path.toLowerCase();

  /// Покрывает ли это правило программу по указанному пути.
  ///
  /// ⚠️ Спрашивать надо ИМЕННО ЭТО, а не сравнивать пути снаружи: правило «по
  /// имени» обязано узнавать программу после её обновления, когда путь уже
  /// другой. Проверено тестом `app_rule_identity_test.dart` — он краснеет,
  /// если вернуть сравнение путей.
  bool matches(String candidatePath) => byName
      ? candidatePath.split(r'\').last.toLowerCase() == name.toLowerCase()
      : candidatePath.toLowerCase() == path.toLowerCase();

  AppRule copyWith(
          {bool? byName,
          AppAction? action,
          bool? enabled,
          bool? allowRealIp,
          bool? overrideSites,
          String? serverKey,
          bool clearServer = false}) =>
      AppRule(
        path,
        byName: byName ?? this.byName,
        action: action ?? this.action,
        enabled: enabled ?? this.enabled,
        allowRealIp: allowRealIp ?? this.allowRealIp,
        overrideSites: overrideSites ?? this.overrideSites,
        serverKey: clearServer ? null : (serverKey ?? this.serverKey),
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'byName': byName,
        'action': action.name,
        'enabled': enabled,
        'allowRealIp': allowRealIp,
        'overrideSites': overrideSites,
        if (serverKey != null) 'serverKey': serverKey,
      };

  factory AppRule.fromJson(Object? j, {AppAction fallback = AppAction.direct}) {
    if (j is String) return AppRule(j, action: fallback); // самый старый формат
    if (j is Map) {
      return AppRule(
        j['path'] as String? ?? '',
        byName: j['byName'] as bool? ?? false,
        action: _actionFrom(j['action'], fallback),
        enabled: j['enabled'] as bool? ?? true,
        // Старые правила заводились ДО появления галочки, когда noRealIp молча
        // перекрывал их. Поднимаем им флаг: пользователь ставил «Прямо» именно
        // ради прямого выхода.
          // ⚠️ Умолчание FALSE — защита выигрывает. «Не выходить под реальным
          // IP» стоит выше всех правил и не перебивается: правило «Прямо»
          // уходит напрямую, ТОЛЬКО если пользователь явно это разрешил.
        allowRealIp: j['allowRealIp'] as bool? ?? false,
        // Умолчание false — прежний порядок: правило сайта конкретнее и
        // потому сильнее. Старые правила своего смысла не меняют.
        overrideSites: j['overrideSites'] as bool? ?? false,
        // Ключа нет во всех настройках, записанных до мульти-VPN, и это ровно
        // то, что нужно: null = основной туннель = прежнее поведение.
        // `exitId` — промежуточный формат первой редакции мульти-VPN; он
        // переводится в ключ сервера уровнем выше (AppSettings.fromJson),
        // здесь принимаем оба, чтобы правила не потерялись.
        serverKey: _serverKeyFrom(j['serverKey']) ?? _serverKeyFrom(j['exitId']),
      );
    }
    return const AppRule('');
  }
}

/// Ключ сервера из JSON: пустая строка равнозначна отсутствию.
///
/// Разделять «нет ключа» и «ключ с пустой строкой» смысла нет, а вот пустая
/// строка, доехавшая до построителя, дала бы тег без сервера — валидный для
/// ядра и ни на что не ссылающийся.
String? _serverKeyFrom(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
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

  /// Явное правило «Прямо» сильнее глобального «Не выходить под реальным IP».
  ///
  /// Раньше `noRealIp` молча переписывал КАЖДОЕ «Прямо» в «через VPN»: сайт,
  /// помеченный пользователем как прямой, всё равно уходил в туннель, а
  /// интерфейс продолжал показывать чип «Прямо» — управлять сайтами по
  /// отдельности было невозможно. Теперь явное правило выигрывает, а снятая
  /// галочка возвращает конкретный сайт под защиту (пойдёт через VPN).
  /// Смысл — только у [AppAction.direct] и только при включённом `noRealIp`.
  final bool allowRealIp;

  /// Через какой сервер идёт этот сайт. `null` — через основной.
  /// См. [AppRule.serverKey]: смысл только у [AppAction.tunnel], хранится ключ
  /// сервера, исчезнувший сервер трактуется как `null`.
  final String? serverKey;

  /// Пользователь ввёл адрес ЯВНО как `http://`.
  ///
  /// ⚠️ Хранится ровно потому, что [normalizeDomain] схему срезает: после
  /// нормализации `http://site.com` и `site.com` неразличимы, а разница для
  /// пользователя есть. Мы показываем такому правилу красный открытый замок —
  /// как это делает браузер: незашифрованное соединение видно провайдеру
  /// целиком, включая путь и параметры запроса.
  ///
  /// Признак ТОЛЬКО отображательный: на маршрутизацию не влияет, потому что
  /// правило работает по имени и порту, а не по схеме.
  final bool insecureScheme;

  const SiteRule(this.domain,
      {this.port,
      this.action = AppAction.direct,
      this.allowRealIp = false,
      this.serverKey,
      this.insecureScheme = false});

  /// Отображаемая метка: домен и, если задан, порт (`example.com:8443`).
  String get label => port == null ? domain : '$domain:$port';

  SiteRule copyWith(
          {AppAction? action,
          int? port,
          bool clearPort = false,
          bool? allowRealIp,
          String? serverKey,
          bool clearServer = false,
          bool? insecureScheme}) =>
      SiteRule(domain,
          port: clearPort ? null : (port ?? this.port),
          action: action ?? this.action,
          allowRealIp: allowRealIp ?? this.allowRealIp,
          serverKey: clearServer ? null : (serverKey ?? this.serverKey),
          insecureScheme: insecureScheme ?? this.insecureScheme);

  Map<String, dynamic> toJson() => {
        'domain': domain,
        if (port != null) 'port': port,
        'action': action.name,
        'allowRealIp': allowRealIp,
        if (serverKey != null) 'serverKey': serverKey,
        if (insecureScheme) 'insecureScheme': true,
      };

  factory SiteRule.fromJson(Object? j, {AppAction fallback = AppAction.direct}) {
    if (j is String) return SiteRule(j, action: fallback); // старый формат (список строк)
    if (j is Map) {
      final p = j['port'];
      return SiteRule(j['domain'] as String? ?? '',
          port: p is int ? p : (p is String ? int.tryParse(p) : null),
          action: _actionFrom(j['action'], fallback),
          // Правила, заведённые до появления галочки, чинятся сами: «Прямо»
          // снова означает «прямо».
          allowRealIp: j['allowRealIp'] as bool? ?? false,
          serverKey:
              _serverKeyFrom(j['serverKey']) ?? _serverKeyFrom(j['exitId']),
          // Ключа нет у всех правил, заведённых раньше: молчание означает
          // «схему не указывали», и замок им не рисуется. Это верно — мы не
          // знаем, что человек вводил тогда, и выдумывать за него нельзя.
          insecureScheme: j['insecureScheme'] as bool? ?? false);
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

  /// Есть ли уже правило, покрывающее эту программу.
  ///
  /// ⚠️ Спрашивает у САМОГО ПРАВИЛА (`AppRule.matches`), а не сравнивает пути.
  /// Раньше сравнивались пути — и пикер «Из запущенных» прятал запись по пути,
  /// тогда как правило ловило процесс по имени. После обновления программы путь
  /// менялся, пикер снова предлагал уже добавленное, и в списке копились дубли.
  bool containsApp(String path) => appRuleFor(path) != null;

  /// Правило, покрывающее эту программу, или `null`.
  AppRule? appRuleFor(String path) {
    for (final a in apps) {
      if (a.matches(path)) return a;
    }
    return null;
  }

  /// Свернуть записи, которые ссылаются на одну и ту же программу.
  ///
  /// ⚠️ НУЖНО ПРИ ЧТЕНИИ СТАРЫХ НАСТРОЕК: до 1.4.1 дубли накапливались сами
  /// (см. [AppRule.matchKey]), и у владельца их четыре штуки на одну программу.
  /// Раньше из них побеждала не первая в списке, а та, у кого лексикографически
  /// меньше тег выхода, — предсказать было нельзя.
  ///
  /// ⚠️ ПОЧЕМУ НЕ ПРОСТО «ОСТАВИТЬ ПЕРВУЮ». Это МИГРАЦИЯ ЧУЖИХ НАСТРОЕК, и
  /// выбор вслепую здесь молча меняет поведение: первой могла оказаться запись
  /// со снятой галочкой (пользователь её сознательно отключил) — тогда
  /// исчезала бы работающая; либо запись «Туннель» перед «Блоком» — и
  /// заблокированная программа получала бы доступ в сеть. Второе опаснее:
  /// пользователь ставил «Блок» намеренно и о его снятии не узнает.
  ///
  /// Правило выбора, от сильного к слабому:
  ///   1. включённые важнее выключенных — выключенное правило пользователь
  ///      припарковал сам;
  ///   2. среди включённых «Блок» важнее прочих — ошибка в сторону запрета
  ///      заметна и обратима, ошибка в сторону доступа молча открывает сеть;
  ///   3. при прочих равных — первая по списку.
  static List<AppRule> dedupeApps(List<AppRule> apps) {
    final byKey = <String, AppRule>{};
    final order = <String>[];
    for (final a in apps) {
      final k = a.matchKey;
      final have = byKey[k];
      if (have == null) {
        byKey[k] = a;
        order.add(k);
        continue;
      }
      if (_strongerRule(a, have)) byKey[k] = a;
    }
    return [for (final k in order) byKey[k]!];
  }

  /// Правда ли [candidate] должен вытеснить [current] при свёртке дублей.
  static bool _strongerRule(AppRule candidate, AppRule current) {
    if (candidate.enabled != current.enabled) return candidate.enabled;
    if (candidate.action == current.action) return false;
    return candidate.action == AppAction.block;
  }

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
      // ⚠️ Свёртка дублей — это МИГРАЦИЯ, а не гигиена. В настройках, записанных
      // до 1.4.1, на одну программу могло лежать несколько записей (правило «по
      // имени» опознавалось по полному пути, и каждое обновление программы
      // заводило новую). Чиним при чтении, иначе пользователь так и остаётся с
      // четырьмя строками `claude.exe`, из которых работает непредсказуемая.
      apps: dedupeApps(((j['apps'] as List?) ?? const [])
          .map((e) => AppRule.fromJson(e, fallback: fallback))
          .where((a) => a.path.isNotEmpty)
          .toList()),
      sites: rawSites
          .map((e) => SiteRule.fromJson(e, fallback: fallback))
          .where((s) => s.domain.isNotEmpty)
          .toList(),
    );
  }
}

/// Ввёл ли пользователь адрес ЯВНО как `http://`.
///
/// `https://` и адрес без схемы — не считается: во втором случае браузер сам
/// пойдёт в https, и пугать замком не за что.
bool hasInsecureScheme(String input) =>
    RegExp(r'^\s*http://', caseSensitive: false).hasMatch(input);
