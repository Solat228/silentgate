import '../dpi/dpi_bypass_lists.dart';
import 'app_settings.dart';
import 'split_tunnel.dart';

/// Готовый набор доменов сервиса для быстрого выбора в раздельном туннелировании.
///
/// Один бренд-домен почти никогда не покрывает весь сервис: видео YouTube идёт
/// с `googlevideo.com`, статика и вложения Discord - с `discordapp.com` и
/// `discord.media`, картинки Instagram - с `cdninstagram.com` и `fbcdn.net`, а
/// веб-интерфейс ChatGPT дергает `openai.com` и `oaistatic.com`. Пользователь,
/// вписавший вручную один `youtube.com` или выбравший галочку в «Проверках
/// сервисов», ожидает маршрутизации всего сервиса целиком.
class SplitServicePreset {
  final ProbeService service;
  final List<String> domains;

  /// Нужна ли подсказка добавить также само приложение в блок «Приложения».
  ///
  /// У мессенджеров со звонками, MTProto по голым IP и игровых клиентов часть
  /// трафика идёт по UDP или прямым IP-адресам без доменного имени (TLS SNI),
  /// поэтому одни только доменные правила поймают браузер и веб-версию, но не
  /// программу целиком.
  final bool needsAppRuleHint;

  const SplitServicePreset(
    this.service,
    this.domains, {
    this.needsAppRuleHint = false,
  });
}

/// Каталог и чистые операции переключения быстрых пресетов сервисов.
abstract final class SplitServicePresets {
  /// Порядок совпадает с `ServiceChecks.catalog`, чтобы ряды чипов в настройках
  /// и в раздельном туннелировании читались одинаково.
  static const catalog = <SplitServicePreset>[
    SplitServicePreset(ProbeService.youtube, [
      'youtube.com',
      'googlevideo.com',
      'ytimg.com',
      'youtu.be',
      'ggpht.com',
      'youtubei.googleapis.com',
      'yt3.googleusercontent.com',
      'jnn-pa.googleapis.com',
      'youtubeembeddedplayer.googleapis.com',
      'youtube-nocookie.com',
      'youtubekids.com',
      'withyoutube.com',
    ]),
    SplitServicePreset(ProbeService.chatgpt, [
      'chatgpt.com',
      'openai.com',
      'oaistatic.com',
      'oaiusercontent.com',
    ]),
    SplitServicePreset(
      ProbeService.telegram,
      [
        'telegram.org',
        't.me',
        'telegra.ph',
        'telesco.pe',
        'tdesktop.com',
      ],
      needsAppRuleHint: true,
    ),
    SplitServicePreset(ProbeService.instagram, [
      'instagram.com',
      'cdninstagram.com',
      'fbcdn.net',
    ]),
    SplitServicePreset(
      ProbeService.discord,
      [
        'discord.com',
        'discordapp.com',
        'discordapp.net',
        'discord.gg',
        'discord.media',
      ],
      needsAppRuleHint: true,
    ),
    SplitServicePreset(ProbeService.google, [
      'google.com',
      'googleapis.com',
      'gstatic.com',
      'googleusercontent.com',
    ]),
    SplitServicePreset(ProbeService.claude, [
      'claude.ai',
      'anthropic.com',
      'claudeusercontent.com',
    ]),
    SplitServicePreset(ProbeService.gemini, [
      'gemini.google.com',
      'aistudio.google.com',
      'makersuite.google.com',
      'generativelanguage.googleapis.com',
      'cloudaicompanion.googleapis.com',
      'daily-cloudcode-pa.googleapis.com',
      'antigravity.google',
      'antigravity-unleash.goog',
      'notebooklm.google.com',
      'deepmind.google',
      'labs.google',
    ]),
    SplitServicePreset(ProbeService.x, [
      'x.com',
      'twitter.com',
      'twimg.com',
      't.co',
    ]),
    SplitServicePreset(
      ProbeService.whatsapp,
      [
        'whatsapp.com',
        'whatsapp.net',
        'wa.me',
      ],
      needsAppRuleHint: true,
    ),
    SplitServicePreset(ProbeService.twitch, [
      'twitch.tv',
      'ttvnw.net',
      'jtvnw.net',
      'twitchcdn.net',
    ]),
    SplitServicePreset(ProbeService.spotify, [
      'spotify.com',
      'scdn.co',
      'spotifycdn.com',
    ]),
    SplitServicePreset(
      ProbeService.steam,
      [
        'steampowered.com',
        'steamcommunity.com',
        'steamstatic.com',
        'steamcontent.com',
        'steamgames.com',
      ],
      needsAppRuleHint: true,
    ),
    SplitServicePreset(ProbeService.github, [
      'github.com',
      'githubusercontent.com',
      'githubassets.com',
      'ghcr.io',
      'github.io',
    ]),
  ];

  /// Пакеты российских приложений на Android, сканирующих систему на наличие
  /// активного VPN (`TRANSPORT_VPN`, `tun0`, `queryIntentServices`, локальные
  /// порты) или блокирующих вход с зарубежных/VPN IP (см. `docs/research/VPN_DETECTION.md`).
  ///
  /// При добавлении через пресет «Анти-сканер РФ» получают:
  ///  * `action: AppAction.direct` (мимо туннеля, через `addDisallowedApplication`);
  ///  * `allowRealIp: true` (прямой выход даже при включённом `noRealIp`);
  ///  * `overrideSites: true` (приоритет выше доменных правил, чтобы `VpnService`
  ///    гарантированно исключал пакет на уровне ОС в `exclude_package`).
  static const ruAntiScannerAndroidPackages = <String>[
    'ru.ozon.app.android', // Ozon
    'com.wildberries.ru', // Wildberries
    'ru.rostel', // Госуслуги
    'ru.oneme.app', // MAX
    'com.idamob.tinkoff.android', // Т-Банк
    'ru.sberbankmobile', // СберБанк Онлайн
    'ru.vtb24.mobilebanking.android', // ВТБ Онлайн
    'ru.alfabank.mobile.android', // Альфа-Банк
    'com.gazpromneft.azs', // АЗС Газпромнефть
    'ru.gazpromneft.azs', // АЗС Газпромнефть (альт. пакет)
    'com.yandex.bank', // Яндекс Пэй
    'ru.yandex.taxi', // Яндекс Go
    'ru.yandex.mail', // Яндекс Почта
    'ru.mts.mymts', // Мой МТС
    'ru.megafon.mlk', // МегаФон
    'com.avito.android', // Авито
    'ru.pochta.app', // Почта России
    'ru.kinopoisk', // Кинопоиск
  ];

  /// Домены российских сервисов и госресурсов, не работающих или ограничивающих
  /// доступ при входе через зарубежный VPN IP.
  static const ruAntiScannerDomains = <String>[
    'gosuslugi.ru',
    'esia.gosuslugi.ru',
    'nalog.ru',
    'mos.ru',
    'ozon.ru',
    'ozone.ru',
    'wildberries.ru',
    'wb.ru',
    'max.ru',
    'oneme.ru',
    'tbank.ru',
    'tinkoff.ru',
    'sberbank.ru',
    'online.sberbank.ru',
    'vtb.ru',
    'alfabank.ru',
    'gpnbonus.ru',
    'azsgpn.ru',
    'pay.yandex.ru',
    'bank.yandex.ru',
    'avito.ru',
    'pochta.ru',
  ];

  /// Включён ли пресет «Анти-сканер РФ» для списка правил приложений [apps].
  static bool isRuAntiScannerAppsActive(List<AppRule> apps) {
    for (final pkg in ruAntiScannerAndroidPackages) {
      final match = apps.any(
        (a) =>
            a.enabled &&
            a.path.toLowerCase() == pkg.toLowerCase() &&
            a.action == AppAction.direct &&
            a.allowRealIp &&
            a.overrideSites,
      );
      if (!match) return false;
    }
    return true;
  }

  /// Переключить пресет «Анти-сканер РФ» в списке приложений [apps].
  ///
  /// Включает для всех пакетов из [ruAntiScannerAndroidPackages] прямой обход
  /// (`AppAction.direct`, `allowRealIp: true`, `overrideSites: true`), чтобы
  /// Android `VpnService.Builder.addDisallowedApplication` полностью выводил их
  /// из `tun0` на уровне ОС.
  static ({List<AppRule> apps, bool added}) toggleRuAntiScannerApps(
    List<AppRule> apps,
  ) {
    final pkgSet = {
      for (final p in ruAntiScannerAndroidPackages) p.toLowerCase()
    };

    if (isRuAntiScannerAppsActive(apps)) {
      final next = [
        for (final a in apps)
          if (!pkgSet.contains(a.path.toLowerCase())) a,
      ];
      return (apps: next, added: false);
    }

    final existingByPkg = <String, int>{};
    final next = [...apps];
    for (var i = 0; i < next.length; i++) {
      existingByPkg[next[i].path.toLowerCase()] = i;
    }

    for (final pkg in ruAntiScannerAndroidPackages) {
      final idx = existingByPkg[pkg.toLowerCase()];
      final rule = AppRule(
        pkg,
        byName: false,
        action: AppAction.direct,
        enabled: true,
        allowRealIp: true,
        overrideSites: true,
      );
      if (idx != null) {
        next[idx] = rule;
      } else {
        next.add(rule);
      }
    }
    return (apps: next, added: true);
  }

  /// Включён ли доменный пресет «Анти-сканер РФ» в списке сайтов [sites].
  static bool isRuAntiScannerSitesActive(List<SiteRule> sites) {
    for (final d in ruAntiScannerDomains) {
      final match = sites.any(
        (r) =>
            r.port == null &&
            r.domain.toLowerCase() == d &&
            r.action == AppAction.direct &&
            r.allowRealIp,
      );
      if (!match) return false;
    }
    return true;
  }

  /// Переключить доменный пресет «Анти-сканер РФ» (Госуслуги, Ozon, WB, MAX,
  /// банки РФ) в действие «Прямо» (`allowRealIp: true`).
  static ({List<SiteRule> sites, bool added}) toggleRuAntiScannerSites(
    List<SiteRule> sites,
  ) {
    final domainSet = {for (final d in ruAntiScannerDomains) d.toLowerCase()};

    if (isRuAntiScannerSitesActive(sites)) {
      final next = [
        for (final r in sites)
          if (!(r.port == null &&
              r.action == AppAction.direct &&
              domainSet.contains(r.domain.toLowerCase())))
            r,
      ];
      return (sites: next, added: false);
    }

    final existingByDomain = <String, int>{};
    final next = [...sites];
    for (var i = 0; i < next.length; i++) {
      final r = next[i];
      if (r.port == null) {
        existingByDomain[r.domain.toLowerCase()] = i;
      }
    }

    for (final d in ruAntiScannerDomains) {
      final idx = existingByDomain[d.toLowerCase()];
      if (idx != null) {
        next[idx] = next[idx].copyWith(
          action: AppAction.direct,
          allowRealIp: true,
        );
      } else {
        next.add(SiteRule(
          d,
          action: AppAction.direct,
          allowRealIp: true,
        ));
      }
    }
    return (sites: next, added: true);
  }

  static SplitServicePreset presetFor(ProbeService service) =>
      catalog.firstWhere((p) => p.service == service);

  /// Включён ли пресет [service] с действием [action] (все домены набора
  /// присутствуют в [sites] без ограничения по порту и с тем же действием).
  static bool isPresetActive(
    List<SiteRule> sites,
    ProbeService service,
    AppAction action,
  ) {
    final preset = presetFor(service);
    for (final d in preset.domains) {
      final match = sites.any(
        (r) =>
            r.port == null &&
            r.domain.toLowerCase() == d &&
            r.action == action,
      );
      if (!match) return false;
    }
    return true;
  }

  /// Переключить пресет [service] для действия [action].
  ///
  /// Возвращает обновлённый список [sites] и признак `added`: `true`, если
  /// домены сервиса были включены/добавлены, `false` - если сняты.
  static ({List<SiteRule> sites, bool added}) togglePreset(
    List<SiteRule> sites,
    ProbeService service, {
    required AppAction action,
  }) {
    final preset = presetFor(service);
    final domainSet = {for (final d in preset.domains) d.toLowerCase()};

    if (isPresetActive(sites, service, action)) {
      final next = [
        for (final r in sites)
          if (!(r.port == null &&
              r.action == action &&
              domainSet.contains(r.domain.toLowerCase())))
            r,
      ];
      return (sites: next, added: false);
    }

    final existingByDomain = <String, int>{};
    final next = [...sites];
    for (var i = 0; i < next.length; i++) {
      final r = next[i];
      if (r.port == null) {
        existingByDomain[r.domain.toLowerCase()] = i;
      }
    }

    for (final d in preset.domains) {
      final idx = existingByDomain[d.toLowerCase()];
      if (idx != null) {
        final cur = next[idx];
        if (cur.action != action) {
          next[idx] = cur.copyWith(action: action);
        }
      } else {
        next.add(SiteRule(d, action: action));
      }
    }
    return (sites: next, added: true);
  }

  /// Включён ли пресет обхода DPI (GDPI / Zapret) с указанным [serverKey]
  /// (`kDpiBypassFallbackKey` или `kDpiBypassDirectKey`) в списке [sites].
  static bool isDpiBypassPresetActive(
    List<SiteRule> sites, {
    String serverKey = kDpiBypassFallbackKey,
  }) {
    for (final d in DpiBypassLists.quickPresetDomains) {
      final match = sites.any(
        (r) =>
            r.port == null &&
            r.domain.toLowerCase() == d &&
            r.action == AppAction.tunnel &&
            r.serverKey == serverKey,
      );
      if (!match) return false;
    }
    return true;
  }

  /// Переключить быстрый пресет обхода DPI (YouTube + Discord) с выходом
  /// [serverKey] (`kDpiBypassFallbackKey` — «Zapret → VPN», либо
  /// `kDpiBypassDirectKey` — «Только Zapret без VPN»).
  static ({List<SiteRule> sites, bool added}) toggleDpiBypassPreset(
    List<SiteRule> sites, {
    String serverKey = kDpiBypassFallbackKey,
  }) {
    final domainSet = {
      for (final d in DpiBypassLists.quickPresetDomains) d.toLowerCase()
    };

    if (isDpiBypassPresetActive(sites, serverKey: serverKey)) {
      final next = [
        for (final r in sites)
          if (!(r.port == null &&
              r.action == AppAction.tunnel &&
              r.serverKey == serverKey &&
              domainSet.contains(r.domain.toLowerCase())))
            r,
      ];
      return (sites: next, added: false);
    }

    final existingByDomain = <String, int>{};
    final next = [...sites];
    for (var i = 0; i < next.length; i++) {
      final r = next[i];
      if (r.port == null) {
        existingByDomain[r.domain.toLowerCase()] = i;
      }
    }

    for (final d in DpiBypassLists.quickPresetDomains) {
      final idx = existingByDomain[d.toLowerCase()];
      if (idx != null) {
        next[idx] = next[idx].copyWith(
          action: AppAction.tunnel,
          serverKey: serverKey,
        );
      } else {
        next.add(SiteRule(
          d,
          action: AppAction.tunnel,
          serverKey: serverKey,
        ));
      }
    }
    return (sites: next, added: true);
  }

  /// Исполняемые файлы основных десктопных нейросетей и AI-IDE на Windows
  /// (добавляются по имени процесса `byName: true`, поэтому универсально
  /// подхватывают `.exe.old.*` и дочерние языковые серверы в своих каталогах).
  static const aiDesktopExeNames = <String>[
    'Antigravity.exe',
    'agy.exe',
    'Cursor.exe',
    'Windsurf.exe',
    'Claude.exe',
    'ChatGPT.exe',
    'codex.exe',
  ];

  /// Домены основных нейросетей и AI-ассистентов (ChatGPT, Claude, Gemini,
  /// Antigravity, Cursor, Windsurf, Copilot, DeepSeek, Grok, Perplexity).
  static const aiNetworkDomains = <String>[
    'chatgpt.com',
    'openai.com',
    'oaistatic.com',
    'oaiusercontent.com',
    'claude.ai',
    'anthropic.com',
    'claudeusercontent.com',
    'gemini.google.com',
    'aistudio.google.com',
    'makersuite.google.com',
    'generativelanguage.googleapis.com',
    'cloudaicompanion.googleapis.com',
    'daily-cloudcode-pa.googleapis.com',
    'antigravity.google',
    'antigravity-unleash.goog',
    'notebooklm.google.com',
    'deepmind.google',
    'labs.google',
    'cursor.com',
    'cursor.sh',
    'cursorapi.com',
    'codeium.com',
    'windsurf.com',
    'windsurf.ai',
    'githubcopilot.com',
    'copilot-proxy.githubusercontent.com',
    'deepseek.com',
    'chat.deepseek.com',
    'grok.com',
    'x.ai',
    'perplexity.ai',
    'pplx.ai',
  ];

  /// Включён ли пресет десктопных нейросетей в списке приложений [apps].
  static bool isAiAppsPresetActive(
    List<AppRule> apps, {
    AppAction action = AppAction.tunnel,
  }) {
    for (final exe in aiDesktopExeNames) {
      final lower = exe.toLowerCase();
      final match = apps.any(
        (a) =>
            a.enabled &&
            a.byName &&
            a.name.toLowerCase() == lower &&
            a.action == action,
      );
      if (!match) return false;
    }
    return true;
  }

  /// Переключить пресет десктопных нейросетей в списке приложений [apps].
  static ({List<AppRule> apps, bool added}) toggleAiAppsPreset(
    List<AppRule> apps, {
    AppAction action = AppAction.tunnel,
  }) {
    final exeSet = {for (final e in aiDesktopExeNames) e.toLowerCase()};

    if (isAiAppsPresetActive(apps, action: action)) {
      final next = [
        for (final a in apps)
          if (!(a.byName &&
              a.action == action &&
              exeSet.contains(a.name.toLowerCase())))
            a,
      ];
      return (apps: next, added: false);
    }

    final existingByName = <String, int>{};
    final next = [...apps];
    for (var i = 0; i < next.length; i++) {
      if (next[i].byName) {
        existingByName[next[i].name.toLowerCase()] = i;
      }
    }

    for (final exe in aiDesktopExeNames) {
      final idx = existingByName[exe.toLowerCase()];
      final rule = AppRule(
        exe,
        byName: true,
        action: action,
        enabled: true,
      );
      if (idx != null) {
        next[idx] = rule;
      } else {
        next.add(rule);
      }
    }
    return (apps: next, added: true);
  }

  /// Включён ли доменный пресет всех нейросетей в списке сайтов [sites].
  static bool isAiSitesPresetActive(
    List<SiteRule> sites, {
    AppAction action = AppAction.tunnel,
  }) {
    for (final d in aiNetworkDomains) {
      final match = sites.any(
        (r) =>
            r.port == null &&
            r.domain.toLowerCase() == d &&
            r.action == action,
      );
      if (!match) return false;
    }
    return true;
  }

  /// Переключить доменный пресет всех нейросетей в списке сайтов [sites].
  static ({List<SiteRule> sites, bool added}) toggleAiSitesPreset(
    List<SiteRule> sites, {
    AppAction action = AppAction.tunnel,
  }) {
    final domainSet = {for (final d in aiNetworkDomains) d.toLowerCase()};

    if (isAiSitesPresetActive(sites, action: action)) {
      final next = [
        for (final r in sites)
          if (!(r.port == null &&
              r.action == action &&
              domainSet.contains(r.domain.toLowerCase())))
            r,
      ];
      return (sites: next, added: false);
    }

    final existingByDomain = <String, int>{};
    final next = [...sites];
    for (var i = 0; i < next.length; i++) {
      final r = next[i];
      if (r.port == null) {
        existingByDomain[r.domain.toLowerCase()] = i;
      }
    }

    for (final d in aiNetworkDomains) {
      final idx = existingByDomain[d.toLowerCase()];
      if (idx != null) {
        next[idx] = next[idx].copyWith(action: action);
      } else {
        next.add(SiteRule(d, action: action));
      }
    }
    return (sites: next, added: true);
  }
}

