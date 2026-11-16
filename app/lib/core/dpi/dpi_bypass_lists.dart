import 'dart:io';

import '../platform/app_log.dart';
import '../platform/app_paths.dart';
import '../settings/app_settings.dart';
import '../settings/split_tunnel.dart';

/// Специальный ключ `serverKey` для правил раздельного туннелирования:
/// трафик идёт напрямую с домашнего IP через встроенный локальный
/// TLS-фрагментатор (`LocalDpiBypassProxy`), без расхода трафика VPN.
const String kDpiBypassDirectKey = 'dpi://zapret-direct';

/// Специальный ключ `serverKey` для совместного режима «Zapret → VPN»:
/// сначала пробует прямой обход DPI (TLS-фрагментацию с реального IP),
/// а при сбросе соединения / таймауте / блокировке ТСПУ на 16–20 КБ
/// автоматически перенаправляет поток в активный VPN-туннель.
const String kDpiBypassFallbackKey = 'dpi://zapret-fallback';

/// Является ли [serverKey] одним из встроенных режимов обхода DPI.
bool isDpiBypassServerKey(String? serverKey) =>
    serverKey == kDpiBypassDirectKey || serverKey == kDpiBypassFallbackKey;

/// Встроенные и обновляемые списки доменов для обхода DPI (технология GDPI / Zapret).
///
/// Объединяет проверенные домены из `Flowseal/zapret-discord-youtube`
/// (`list-general.txt`, `list-google.txt`) и `itdoginfo/allow-domains`.
class DpiBypassLists {
  DpiBypassLists._();

  /// URL публичных баз `Flowseal/zapret-discord-youtube` для фонового обновления.
  static const String flowsealGoogleUrl =
      'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists/list-google.txt';
  static const String flowsealGeneralUrl =
      'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists/list-general.txt';

  /// Домены YouTube / Google Video (`list-google.txt`).
  static const List<String> youtubeDomains = [
    'youtube.com',
    'googlevideo.com',
    'ytimg.com',
    'yt3.ggpht.com',
    'youtu.be',
    'ggpht.com',
    'googleapis.com',
    'googleusercontent.com',
    'gstatic.com',
    'youtubei.googleapis.com',
    'youtubekids.com',
    'youtube-nocookie.com',
    'widevine.com',
  ];

  /// Домены Discord (`list-general.txt`).
  static const List<String> discordDomains = [
    'discord.com',
    'discordapp.com',
    'discordapp.net',
    'discord.gg',
    'discord.media',
    'discordcdn.com',
    'discordstatus.com',
    'dis.gd',
    'discord-attachments-uploads-prd.storage.googleapis.com',
  ];

  /// Дополнительные домены из `list-general.txt` (трекеры, форумы, сервисы без гео-блока).
  static const List<String> generalDomains = [
    'rutracker.org',
    'rutracker.net',
    'ntc.party',
    '7tv.app',
    '7tv.io',
    'betterttv.net',
    'frankerfacez.com',
  ];

  /// Ключевые домены быстрого пресета YouTube + Discord для экрана раздельного туннелирования.
  static const List<String> quickPresetDomains = [
    'youtube.com',
    'googlevideo.com',
    'ytimg.com',
    'youtu.be',
    'ggpht.com',
    'discord.com',
    'discordapp.com',
    'discordapp.net',
    'discord.gg',
    'discord.media',
    'discordcdn.com',
  ];

  /// Полный встроенный список доменов по умолчанию.
  static List<String> get builtInDomains => {
        ...youtubeDomains,
        ...discordDomains,
        ...generalDomains,
      }.toList(growable: false);

  static List<String>? _cachedGoogleExternal;
  static List<String>? _cachedGeneralExternal;

  /// Количество доменов во внешнем кэше `Flowseal` (0 — используются только встроенные).
  static int get cachedExternalCount =>
      (_cachedGoogleExternal?.length ?? 0) + (_cachedGeneralExternal?.length ?? 0);

  /// Собрать итоговый набор доменов с учётом выбранных категорий в [settings].
  static Set<String> selectedDomainsFor(
    AppSettings settings, {
    Iterable<String>? extraDomains,
  }) {
    final out = <String>{};
    if (settings.dpiListsYoutube) {
      out.addAll(youtubeDomains);
      if (_cachedGoogleExternal != null) out.addAll(_cachedGoogleExternal!);
    }
    if (settings.dpiListsDiscord) {
      out.addAll(discordDomains);
    }
    if (settings.dpiListsGeneral) {
      out.addAll(generalDomains);
      if (_cachedGeneralExternal != null) out.addAll(_cachedGeneralExternal!);
    }
    for (final raw in settings.dpiCustomDomains) {
      final d = normalizeDomain(raw.trim().toLowerCase());
      if (d.isNotEmpty && d.contains('.') && !d.contains(' ')) {
        out.add(d);
      }
    }
    if (extraDomains != null) {
      for (final raw in extraDomains) {
        final d = normalizeDomain(raw.trim().toLowerCase());
        if (d.isNotEmpty && d.contains('.') && !d.contains(' ')) {
          out.add(d);
        }
      }
    }
    return out;
  }

  /// Прочитать локально кэшированные списки из `<supportDir>/dpi_lists/`,
  /// объединённые со встроенным набором.
  static Future<List<String>> loadEffectiveDomains([AppSettings? settings]) async {
    if (_cachedGoogleExternal == null && _cachedGeneralExternal == null) {
      try {
        final dir = await _listsDir();
        final gFile = File('${dir.path}${Platform.pathSeparator}list-google.txt');
        if (gFile.existsSync()) {
          _cachedGoogleExternal =
              parseDomainList(await gFile.readAsString());
        }
        final genFile =
            File('${dir.path}${Platform.pathSeparator}list-general.txt');
        if (genFile.existsSync()) {
          _cachedGeneralExternal =
              parseDomainList(await genFile.readAsString());
        }
      } catch (_) {}
    }
    if (settings != null) {
      return selectedDomainsFor(settings).toList(growable: false);
    }
    return {
      ...builtInDomains,
      if (_cachedGoogleExternal != null) ..._cachedGoogleExternal!,
      if (_cachedGeneralExternal != null) ..._cachedGeneralExternal!,
    }.toList(growable: false);
  }

  /// Обновить списки доменов из публичного репозитория `Flowseal/zapret-discord-youtube`.
  /// Возвращает количество загруженных уникальных доменов (или 0 при ошибке сети).
  static Future<int> refreshPublicLists({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final dir = await _listsDir();
      final loaded = <String>{};
      for (final entry in const {
        'list-google.txt': flowsealGoogleUrl,
        'list-general.txt': flowsealGeneralUrl,
      }.entries) {
        try {
          final req = await client.getUrl(Uri.parse(entry.value)).timeout(timeout);
          final resp = await req.close().timeout(timeout);
          if (resp.statusCode == 200) {
            final body = await resp
                .transform(const SystemEncoding().decoder)
                .join()
                .timeout(timeout);
            final parsed = parseDomainList(body);
            if (parsed.isNotEmpty) {
              loaded.addAll(parsed);
              if (entry.key == 'list-google.txt') {
                _cachedGoogleExternal = parsed;
              } else {
                _cachedGeneralExternal = parsed;
              }
              final f = File('${dir.path}${Platform.pathSeparator}${entry.key}');
              await f.writeAsString(body, flush: true);
            }
          }
        } catch (e) {
          AppLog.w('DPI-списки: не удалось обновить ${entry.key}: $e');
        }
      }
      if (loaded.isNotEmpty) {
        AppLog.i('DPI-списки обновлены: ${loaded.length} доменов');
      }
      return loaded.length;
    } finally {
      client.close(force: true);
    }
  }

  /// Разбор текстового файла со списком доменов (формат Zapret `list-*.txt`).
  static List<String> parseDomainList(String raw) {
    final out = <String>{};
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim().toLowerCase();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('//')) {
        continue;
      }
      final d = normalizeDomain(trimmed);
      if (d.isNotEmpty && d.contains('.') && !d.contains(' ')) {
        out.add(d);
      }
    }
    return out.toList(growable: false);
  }

  /// Внедрить глобальные правила обхода DPI в [split], если включён
  /// [AppSettings.dpiBypassEnabled].
  ///
  /// Явные правила пользователя в `split.sites` всегда имеют приоритет и НЕ
  /// перезаписываются.
  static SplitTunnelConfig applyGlobalDpiRules(
    SplitTunnelConfig split,
    AppSettings settings, {
    Iterable<String>? extraDomains,
  }) {
    if (!settings.dpiBypassEnabled) return split;
    final targetKey = settings.dpiBypassAutoFallbackToVpn
        ? kDpiBypassFallbackKey
        : kDpiBypassDirectKey;
    final existing = {
      for (final s in split.sites)
        if (s.port == null) s.domain.trim().toLowerCase(),
    };
    final domains = selectedDomainsFor(settings, extraDomains: extraDomains);
    final added = <SiteRule>[];
    for (final raw in domains) {
      final d = raw.trim().toLowerCase();
      if (d.isEmpty || existing.contains(d)) continue;
      added.add(SiteRule(
        d,
        action: AppAction.tunnel,
        serverKey: targetKey,
      ));
    }
    if (added.isEmpty) return split;
    return split.copyWith(sites: [...split.sites, ...added]);
  }

  /// Нужен ли запуск локального прокси обхода DPI (`LocalDpiBypassProxy`)
  /// при данных настройках и правилах.
  static ({bool needsDirect, bool needsFallback}) requiredModes(
    SplitTunnelConfig split,
    AppSettings settings,
  ) {
    var needsDirect =
        settings.dpiBypassEnabled && !settings.dpiBypassAutoFallbackToVpn;
    var needsFallback =
        settings.dpiBypassEnabled && settings.dpiBypassAutoFallbackToVpn;
    for (final s in split.sites) {
      if (s.action != AppAction.tunnel) continue;
      if (s.serverKey == kDpiBypassDirectKey) needsDirect = true;
      if (s.serverKey == kDpiBypassFallbackKey) needsFallback = true;
    }
    for (final a in split.apps) {
      if (!a.enabled || a.action != AppAction.tunnel) continue;
      if (a.serverKey == kDpiBypassDirectKey) needsDirect = true;
      if (a.serverKey == kDpiBypassFallbackKey) needsFallback = true;
    }
    return (needsDirect: needsDirect, needsFallback: needsFallback);
  }

  static Future<Directory> _listsDir() async {
    final base = (await AppPaths.supportDir()).path;
    final dir = Directory('$base${Platform.pathSeparator}dpi_lists');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}
