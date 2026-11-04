import 'dart:io';

import '../settings/app_settings.dart';
import '../settings/split_rule_layout.dart';
import '../settings/split_tunnel.dart';
import 'live_connections.dart';

/// Как превращать выделенные открытые соединения в правила раздельного туннелирования.
enum LiveRuleTargetMode {
  /// Умный выбор: браузеры и общие хосты -> по доменам ([SiteRule]);
  /// отдельные программы с голыми IP или множеством шардов -> по процессу ([AppRule]).
  auto,

  /// Только доменные правила ([SiteRule]).
  sites,

  /// Только правила для программ ([AppRule]).
  apps,

  /// Одновременно и домены, и программы.
  both,
}

/// Целевая программа для создания или обновления [AppRule].
class PlannedAppTarget {
  /// Путь к `.exe` (если известен) либо имя процесса / имя пакета Android.
  final String rulePath;

  /// Короткое имя для предпросмотра (`Telegram.exe` или `org.telegram.messenger`).
  final String displayName;

  const PlannedAppTarget({
    required this.rulePath,
    required this.displayName,
  });
}

/// Результат планирования правил по выделенным живым соединениям.
class LiveConnectionRulePlan {
  final LiveRuleTargetMode mode;

  /// Нормализованные домены для [SiteRule] (без дублей, в порядке обхода).
  final List<String> domains;

  /// Программы для [AppRule] (без дублей по ключу сопоставления).
  final List<PlannedAppTarget> apps;

  /// Имена браузеров/общих процессов, чьи голые IP-соединения без домена были
  /// намеренно пропущены в режиме [LiveRuleTargetMode.auto], чтобы не перехватить
  /// весь браузер целиком.
  final List<String> skippedSharedBareIpProcesses;

  /// Сколько выделенных соединений не содержали домена (актуально для [LiveRuleTargetMode.sites]).
  final int skippedNoDomainCount;

  /// Сколько выделенных соединений не содержали имени процесса (актуально для [LiveRuleTargetMode.apps]).
  final int skippedNoProcessCount;

  const LiveConnectionRulePlan({
    required this.mode,
    required this.domains,
    required this.apps,
    this.skippedSharedBareIpProcesses = const [],
    this.skippedNoDomainCount = 0,
    this.skippedNoProcessCount = 0,
  });

  bool get isEmpty => domains.isEmpty && apps.isEmpty;
  int get totalRules => domains.length + apps.length;
}

/// Итог применения [LiveConnectionRulePlan] к [AppSettings].
class AppliedLiveRulesResult {
  final AppSettings settings;
  final int addedSites;
  final int updatedSites;
  final int addedApps;
  final int updatedApps;
  final bool switchedModeFromAll;

  /// Первый домен (или имя программы) для показа в диалоге перезагрузки туннеля.
  final String primarySubject;

  const AppliedLiveRulesResult({
    required this.settings,
    required this.addedSites,
    required this.updatedSites,
    required this.addedApps,
    required this.updatedApps,
    required this.switchedModeFromAll,
    required this.primarySubject,
  });

  int get totalTouched => addedSites + updatedSites + addedApps + updatedApps;
}

/// Планировщик правил раздельного туннелирования из открытых соединений.
class LiveConnectionRulesPlanner {
  const LiveConnectionRulesPlanner._();

  /// Порог числа различных доменов у одного выделенного (не браузерного) процесса,
  /// начиная с которого в режиме [LiveRuleTargetMode.auto] выгоднее создать одно
  /// правило приложения вместо россыпи CDN-поддоменов.
  static const int autoPromoteDomainThreshold = 4;

  /// Браузеры, системные службы и универсальные среды запуска: создавать для них
  /// [AppRule] в автоматическом режиме нельзя, иначе один выбранный сайт потянет
  /// за собой весь трафик браузера или оболочки.
  static const Set<String> _sharedHostProcesses = <String>{
    // Десктопные браузеры и WebView
    'chrome.exe',
    'msedge.exe',
    'msedgewebview2.exe',
    'firefox.exe',
    'brave.exe',
    'opera.exe',
    'opera_gx.exe',
    'vivaldi.exe',
    'yandex.exe',
    'browser.exe',
    'arc.exe',
    'waterfox.exe',
    'librewolf.exe',
    'tor.exe',
    'iexplore.exe',
    'maxthon.exe',
    'centbrowser.exe',
    'whale.exe',
    'chromium.exe',
    'safari',
    // Мобильные браузеры и системный WebView (Android)
    'com.android.chrome',
    'com.chrome.beta',
    'com.chrome.dev',
    'com.chrome.canary',
    'org.mozilla.firefox',
    'org.mozilla.fenix',
    'org.mozilla.focus',
    'com.opera.browser',
    'com.opera.mini.native',
    'com.opera.gx',
    'com.brave.browser',
    'com.microsoft.emmx',
    'com.yandex.browser',
    'com.sec.android.app.sbrowser',
    'com.kiwibrowser.browser',
    'com.vivaldi.browser',
    'com.duckduckgo.mobile.android',
    'com.google.android.webview',
    'com.android.webview',
    // Системные процессы, оболочки, рантаймы и IDE
    'svchost.exe',
    'system',
    'explorer.exe',
    'searchhost.exe',
    'searchapp.exe',
    'sihost.exe',
    'taskhostw.exe',
    'rundll32.exe',
    'dllhost.exe',
    'conhost.exe',
    'powershell.exe',
    'pwsh.exe',
    'cmd.exe',
    'wsl.exe',
    'wslhost.exe',
    'curl.exe',
    'curl',
    'python.exe',
    'pythonw.exe',
    'python3',
    'node.exe',
    'node',
    'deno.exe',
    'bun.exe',
    'java.exe',
    'javaw.exe',
    'dotnet.exe',
    'git.exe',
    'git-remote-https.exe',
    'code.exe',
    'devenv.exe',
    'idea64.exe',
    'studio64.exe',
    'language_server.exe',
    'language_server_windows_x64.exe',
    'android.process.media',
    'com.google.android.gms',
  };

  /// Является ли [processName] браузером или общим системным хост-процессом.
  static bool isSharedHostProcess(String processName) {
    final norm = _shortProcessName(processName).toLowerCase();
    if (norm.isEmpty) return false;
    return _sharedHostProcesses.contains(norm);
  }

  /// Извлекает нормализованный домен из [entry], отбрасывая голые IP-литералы.
  static String extractValidDomain(LiveConnectionEntry entry) {
    final raw = entry.host.trim();
    if (raw.isEmpty) return '';
    final clean = normalizeDomain(raw);
    if (clean.isEmpty || !clean.contains('.')) return '';
    final unbracketed = clean.startsWith('[') && clean.endsWith(']')
        ? clean.substring(1, clean.length - 1)
        : clean;
    if (InternetAddress.tryParse(unbracketed) != null) return '';
    return clean;
  }

  /// Строит план правил для выбранных соединений [entries] в режиме [mode].
  static LiveConnectionRulePlan plan(
    Iterable<LiveConnectionEntry> entries, {
    LiveRuleTargetMode mode = LiveRuleTargetMode.auto,
  }) {
    final list = entries.toList();
    if (list.isEmpty) {
      return LiveConnectionRulePlan(
        mode: mode,
        domains: const [],
        apps: const [],
      );
    }

    switch (mode) {
      case LiveRuleTargetMode.sites:
        final domains = <String>[];
        final seenDomains = <String>{};
        var skippedNoDomain = 0;
        for (final e in list) {
          final d = extractValidDomain(e);
          if (d.isEmpty) {
            skippedNoDomain++;
            continue;
          }
          if (seenDomains.add(d)) domains.add(d);
        }
        return LiveConnectionRulePlan(
          mode: mode,
          domains: domains,
          apps: const [],
          skippedNoDomainCount: skippedNoDomain,
        );

      case LiveRuleTargetMode.apps:
        final apps = <PlannedAppTarget>[];
        final seenApps = <String>{};
        var skippedNoProcess = 0;
        for (final e in list) {
          final target = _extractAppTarget(e);
          if (target == null) {
            skippedNoProcess++;
            continue;
          }
          final key = target.displayName.toLowerCase();
          if (seenApps.add(key)) apps.add(target);
        }
        return LiveConnectionRulePlan(
          mode: mode,
          domains: const [],
          apps: apps,
          skippedNoProcessCount: skippedNoProcess,
        );

      case LiveRuleTargetMode.both:
        final domains = <String>[];
        final seenDomains = <String>{};
        final apps = <PlannedAppTarget>[];
        final seenApps = <String>{};
        for (final e in list) {
          final d = extractValidDomain(e);
          if (d.isNotEmpty && seenDomains.add(d)) {
            domains.add(d);
          }
          final target = _extractAppTarget(e);
          if (target != null && seenApps.add(target.displayName.toLowerCase())) {
            apps.add(target);
          }
        }
        return LiveConnectionRulePlan(
          mode: mode,
          domains: domains,
          apps: apps,
        );

      case LiveRuleTargetMode.auto:
        return _planAuto(list);
    }
  }

  static LiveConnectionRulePlan _planAuto(List<LiveConnectionEntry> list) {
    // 1. Собираем статистику по каждому выделенному (не браузерному) процессу:
    // есть ли у него соединения по голому IP и сколько разных доменов выбрано.
    final dedicatedHasBareIp = <String, bool>{};
    final dedicatedDomains = <String, Set<String>>{};
    final dedicatedTarget = <String, PlannedAppTarget>{};

    for (final e in list) {
      final target = _extractAppTarget(e);
      if (target == null) continue;
      if (isSharedHostProcess(target.displayName)) continue;

      final procKey = target.displayName.toLowerCase();
      dedicatedTarget.putIfAbsent(procKey, () => target);
      // Если в одном из соединений встретился полный путь к exe, сохраняем его
      // ради настоящей иконки в списке правил.
      if (target.rulePath.contains(r'\') &&
          !dedicatedTarget[procKey]!.rulePath.contains(r'\')) {
        dedicatedTarget[procKey] = target;
      }

      final domain = extractValidDomain(e);
      if (domain.isEmpty) {
        dedicatedHasBareIp[procKey] = true;
      } else {
        (dedicatedDomains[procKey] ??= <String>{}).add(domain);
      }
    }

    // 2. Продвигаем в AppRule те отдельные программы, у которых есть хотя бы
    // одно соединение без домена (например Telegram / голосовые UDP-сокеты игр)
    // ИЛИ выбрано >= 4 разных поддоменов сразу.
    final promotedProcKeys = <String>{};
    final apps = <PlannedAppTarget>[];
    for (final entry in dedicatedTarget.entries) {
      final procKey = entry.key;
      final hasBareIp = dedicatedHasBareIp[procKey] ?? false;
      final domainCount = dedicatedDomains[procKey]?.length ?? 0;
      if (hasBareIp || domainCount >= autoPromoteDomainThreshold) {
        promotedProcKeys.add(procKey);
        apps.add(entry.value);
      }
    }

    // 3. Для всех остальных соединений создаём доменные правила (SiteRule),
    // а голые IP браузеров/системных процессов отмечаем в предупреждении,
    // чтобы не уводить весь браузер одним правилом без ведома пользователя.
    final domains = <String>[];
    final seenDomains = <String>{};
    final skippedShared = <String>[];
    final seenSkippedShared = <String>{};
    var skippedNoDomain = 0;

    for (final e in list) {
      final target = _extractAppTarget(e);
      if (target != null &&
          promotedProcKeys.contains(target.displayName.toLowerCase())) {
        continue;
      }

      final domain = extractValidDomain(e);
      if (domain.isNotEmpty) {
        if (seenDomains.add(domain)) domains.add(domain);
      } else {
        skippedNoDomain++;
        if (target != null && isSharedHostProcess(target.displayName)) {
          if (seenSkippedShared.add(target.displayName.toLowerCase())) {
            skippedShared.add(target.displayName);
          }
        }
      }
    }

    return LiveConnectionRulePlan(
      mode: LiveRuleTargetMode.auto,
      domains: domains,
      apps: apps,
      skippedSharedBareIpProcesses: skippedShared,
      skippedNoDomainCount: skippedNoDomain,
    );
  }

  /// Применяет [plan] с выбранным действием [action] (и необязательным [serverKey]
  /// для [AppAction.tunnel]) к [current], возвращая обновлённые настройки и статистику.
  static AppliedLiveRulesResult applyToSettings(
    AppSettings current,
    LiveConnectionRulePlan plan, {
    required AppAction action,
    String? serverKey,
  }) {
    final effectiveServer = action == AppAction.tunnel ? serverKey : null;
    final st = current.splitTunnel;

    final nextSites = <SiteRule>[...st.sites];
    var addedSites = 0;
    var updatedSites = 0;

    for (final domain in plan.domains) {
      final idx = nextSites.indexWhere(
        (s) => s.domain.toLowerCase() == domain.toLowerCase() && s.port == null,
      );
      if (idx >= 0) {
        nextSites[idx] = nextSites[idx].copyWith(
          action: action,
          serverKey: effectiveServer,
          clearServer: effectiveServer == null,
        );
        updatedSites++;
      } else {
        nextSites.add(
          SiteRule(
            domain,
            action: action,
            serverKey: effectiveServer,
          ),
        );
        addedSites++;
      }
    }

    final nextApps = <AppRule>[...st.apps];
    var addedApps = 0;
    var updatedApps = 0;

    for (final target in plan.apps) {
      final candidate = AppRule(
        target.rulePath,
        byName: true,
        enabled: true,
        action: action,
        serverKey: effectiveServer,
      );
      final idx = nextApps.indexWhere(
        (a) => a.matchKey == candidate.matchKey || a.matches(target.rulePath),
      );
      if (idx >= 0) {
        nextApps[idx] = nextApps[idx].copyWith(
          enabled: true,
          action: action,
          serverKey: effectiveServer,
          clearServer: effectiveServer == null,
        );
        updatedApps++;
      } else {
        nextApps.add(candidate);
        addedApps++;
      }
    }

    // В режиме «Все через VPN» пользовательские списки скрыты и правила Прямо/Блок
    // намеренно не попадают в конфиг. Переключение на «Отмеченные - мимо VPN»
    // сохраняет базу `proxy` для всего остального трафика и включает созданные правила.
    final switchedModeFromAll =
        st.mode == SplitMode.all && (plan.domains.isNotEmpty || plan.apps.isNotEmpty);
    final nextMode = switchedModeFromAll ? SplitMode.exceptSelected : st.mode;

    var nextCollapsed = current.splitCollapsed;
    for (final domain in plan.domains) {
      nextCollapsed = expandCollapsedForSite(
        currentCollapsed: nextCollapsed,
        allSites: nextSites,
        domain: domain,
        action: action,
      );
    }
    if (plan.apps.isNotEmpty) {
      final appGroup = splitGroupKey('apps', action);
      nextCollapsed = nextCollapsed.where((k) => k != appGroup).toList();
    }

    final primarySubject = plan.domains.isNotEmpty
        ? plan.domains.first
        : (plan.apps.isNotEmpty ? plan.apps.first.displayName : '');

    final nextSettings = current.copyWith(
      splitSitesCollapsed:
          plan.domains.isNotEmpty ? false : current.splitSitesCollapsed,
      splitAppsCollapsed:
          plan.apps.isNotEmpty ? false : current.splitAppsCollapsed,
      splitCollapsed: nextCollapsed,
      splitTunnel: st.copyWith(
        mode: nextMode,
        sites: nextSites,
        apps: nextApps,
      ),
    );

    return AppliedLiveRulesResult(
      settings: nextSettings,
      addedSites: addedSites,
      updatedSites: updatedSites,
      addedApps: addedApps,
      updatedApps: updatedApps,
      switchedModeFromAll: switchedModeFromAll,
      primarySubject: primarySubject,
    );
  }

  static PlannedAppTarget? _extractAppTarget(LiveConnectionEntry entry) {
    final rawKey = entry.appRuleKey;
    final short = _shortProcessName(
      entry.process.isNotEmpty ? entry.process : rawKey,
    );
    if (short.isEmpty) return null;

    var normalizedPath = rawKey.isNotEmpty ? rawKey : short;
    // AppRule.name делит путь по обратному слешу Windows (`\`). Если десктопный
    // путь пришёл с прямыми слешами, приводим к обратному слешу.
    if (normalizedPath.contains('/') &&
        normalizedPath.toLowerCase().endsWith('.exe')) {
      normalizedPath = normalizedPath.replaceAll('/', r'\');
    }

    return PlannedAppTarget(
      rulePath: normalizedPath,
      displayName: short,
    );
  }

  static String _shortProcessName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final norm = trimmed.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }
}
