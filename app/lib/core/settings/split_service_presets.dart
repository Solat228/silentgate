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
      'generativelanguage.googleapis.com',
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
}

