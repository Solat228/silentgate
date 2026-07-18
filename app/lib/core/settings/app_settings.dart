import '../net/speed_test.dart';
import '../update/app_update.dart';
import 'split_tunnel.dart';

/// Режим захвата трафика.
enum CaptureMode { systemProxy, tun }

/// Драйвер TUN (на Windows реально доступен только wintun).
enum TunProvider { wintun }

/// Сетевой стек TUN-инбаунда sing-box (наш TUN построен на sing-box):
/// auto — не задавать (дефолт ядра, сейчас mixed), system — стек ОС (быстрее),
/// gvisor — userspace-стек (совместимее), mixed — TCP через system + UDP через gvisor.
enum TunStack { auto, system, gvisor, mixed }

extension TunStackSingbox on TunStack {
  /// Значение для поля `stack` конфига sing-box; null — не писать поле (auto).
  String? get singboxValue => this == TunStack.auto ? null : name;
}

/// Откуда берётся DNS в TUN-режиме.
/// system — не трогаем (как раньше; возможен DNS-leak и «интернет пропал», если
/// UDP до сервера не проксируется), vpn — резолвим через туннель, custom — свой сервер.
enum DnsMode { system, vpn, custom }

/// Стратегия резолва (sing-box `strategy`).
enum DnsStrategy { preferIpv4, preferIpv6, ipv4Only, ipv6Only }

extension DnsStrategySingbox on DnsStrategy {
  String get singboxValue {
    switch (this) {
      case DnsStrategy.preferIpv4:
        return 'prefer_ipv4';
      case DnsStrategy.preferIpv6:
        return 'prefer_ipv6';
      case DnsStrategy.ipv4Only:
        return 'ipv4_only';
      case DnsStrategy.ipv6Only:
        return 'ipv6_only';
    }
  }
}

/// Уровень лога sing-box (для диагностики TUN).
enum SingboxLogLevel { warn, info, debug }

/// Способы пинга (как в Happ → Настройки → Пинг).
enum PingMethod { proxyGet, proxyHead, tcp, icmp }

/// Стратегия автонастройки.
enum AutoConfigStrategy { firstMatch, bestWithinBudget }

/// Сервисы, работоспособность которых проверяет автонастройка.
enum ProbeService {
  youtube,
  discord,
  telegram,
  chatgpt,
  claude,
  gemini,
  x,
  instagram,
  google,
}

/// Тема оформления.
enum AppThemeMode { system, light, dark }

/// Интервал автообновления подписки (#10). По умолчанию приоритет у значения
/// приложения ([fieldHours]); галочка «брать из подписки» → интервал панели
/// ([subscriptionHours]), а если панель его не прислала — фолбэк на поле.
int resolveAutoUpdateIntervalHours({
  required bool preferSubscription,
  required int? subscriptionHours,
  required int fieldHours,
}) =>
    preferSubscription ? (subscriptionHours ?? fieldHours) : fieldHours;

// Раздельное туннелирование вынесено в split_tunnel.dart.

extension ProbeServiceLabel on ProbeService {
  /// Отображаемое имя — бренд, не переводится.
  String get label {
    switch (this) {
      case ProbeService.youtube:
        return 'YouTube';
      case ProbeService.discord:
        return 'Discord';
      case ProbeService.telegram:
        return 'Telegram';
      case ProbeService.chatgpt:
        return 'ChatGPT';
      case ProbeService.claude:
        return 'Claude';
      case ProbeService.gemini:
        return 'Gemini';
      case ProbeService.x:
        return 'X';
      case ProbeService.instagram:
        return 'Instagram';
      case ProbeService.google:
        return 'Google';
    }
  }

  /// Домен для фавикона (бренд-иконка в списках проверок).
  String get domain {
    switch (this) {
      case ProbeService.youtube:
        return 'youtube.com';
      case ProbeService.discord:
        return 'discord.com';
      case ProbeService.telegram:
        return 'telegram.org';
      case ProbeService.chatgpt:
        return 'openai.com';
      case ProbeService.claude:
        return 'claude.ai';
      case ProbeService.gemini:
        return 'gemini.google.com';
      case ProbeService.x:
        return 'x.com';
      case ProbeService.instagram:
        return 'instagram.com';
      case ProbeService.google:
        return 'google.com';
    }
  }

  /// Сервис с гео-ограничением (ИИ): у него отдельно проверяется, не заблокирован
  /// ли он в стране выхода VPN (открывается, но «недоступно в вашем регионе»).
  bool get geoGated =>
      this == ProbeService.chatgpt ||
      this == ProbeService.claude ||
      this == ProbeService.gemini;
}

/// Настройки приложения. Иммутабельны; меняются через [copyWith].
class AppSettings {
  // ── Захват трафика ────────────────────────────────────────────────────────
  final CaptureMode captureMode;
  final TunProvider tunProvider;
  final TunStack tunStack;
  final int tunMtu;
  final SplitTunnelConfig splitTunnel;

  // ── TUN: маршрутизация ────────────────────────────────────────────────────
  /// Строгая маршрутизация sing-box: на Windows лечит DNS-leak и «network unreachable».
  final bool tunStrictRoute;

  /// Вести IPv6 внутрь туннеля (иначе IPv6-трафик уходит мимо VPN).
  final bool tunIpv6;

  /// endpoint-independent NAT — корректный UDP (игры, голос).
  final bool tunEndpointIndependentNat;

  /// Локальная сеть (частные адреса) — мимо VPN.
  final bool tunBypassLan;

  /// Дополнительные подсети мимо VPN (CIDR).
  final List<String> tunExcludeCidrs;

  // ── TUN: DNS ──────────────────────────────────────────────────────────────
  final DnsMode dnsMode;
  final String dnsCustomServer;

  /// Перехватывать UDP:53 (без утечек и точные доменные правила).
  final bool dnsHijack;
  final DnsStrategy dnsStrategy;

  /// Уровень лога sing-box (`%APPDATA%\SilentGate\singbox.log`).
  final SingboxLogLevel singboxLogLevel;

  // ── Как приложение представляется панели ──────────────────────────────────

  // ── Надёжность соединения ─────────────────────────────────────────────────
  /// Восстанавливать подключение, если ядро упало или сменилась сеть.
  final bool autoReconnect;

  /// Не выпускать трафик мимо VPN, пока туннель не поднялся заново
  /// (системный прокси остаётся прописанным, TUN не снимается).
  final bool killSwitch;

  /// «Не выходить под реальным IP»: даже при рабочем VPN весь `direct`-трафик
  /// (пользовательские «Прямо» + внутренний RU-routing панельного профиля)
  /// переписывается ЧЕРЕЗ VPN — ничего не уходит под настоящим IP. Приватная
  /// сеть (LAN) и адреса самих серверов остаются direct (иначе туннель не встанет).
  /// Имеет смысл только при включённом [killSwitch]. См. вариант B аудита.
  final bool noRealIp;

  /// Объём пробы теста скорости: трафик расходуется из подписки.
  final SpeedTestSize speedTestSize;

  // ── Пинг ──────────────────────────────────────────────────────────────────
  /// Двухфазный пинг: если основной метод не ответил — пробуем запасной через прокси.
  /// Выключено — работает только [pingPrimary].
  final bool pingTwoPhase;

  /// Основной метод (быстрый, без подъёма ядра): любой из четырёх.
  final PingMethod pingPrimary;

  /// Запасной метод — применяется, только если основной не ответил.
  /// Обычно через прокси: сервер может резать TCP/ICMP-пробы, но исправно проксировать.
  final PingMethod pingFallback;

  final String testUrl;
  final int pingTimeoutMs;
  final int pingConcurrency;

  // ── Автонастройка ─────────────────────────────────────────────────────────
  final bool autoConfigEnabled;
  final Set<ProbeService> autoConfigServices;
  final bool tryFragment;
  final List<String> fingerprints;
  final AutoConfigStrategy strategy;
  final int autoConfigBudgetSec;

  /// Закреплять найденные автонастройкой серверы сверху списка.
  /// Выключено — результаты видны только на экране автонастройки.
  final bool autoPinFound;

  /// Сколько сервисов должно пройти для принятия сервера. 0 = все включённые.
  final int acceptMinServices;

  // ── Импорт по ссылке ────────────────────────────────────────────────────────
  /// Подключаться к первому серверу сразу после импорта подписки по ссылке.
  final bool autoConnectAfterImport;

  // ── Оформление и поведение ─────────────────────────────────────────────────
  final AppThemeMode themeMode;

  /// Код языка интерфейса (`ru`/`en`/`es`…). Пустая строка — следовать системе.
  final String languageCode;
  final bool closeToTray; // крестик: сворачивать в трей (true) / закрывать полностью (false)
  final bool dontAskOnClose; // не спрашивать при сворачивании
  final bool autoUpdateEnabled; // автообновление подписки

  /// Интервал автообновления подписки в ЧАСАХ (наше значение). По приоритету
  /// ВЫШЕ интервала из подписки, если [autoUpdatePreferSubscription] выключен.
  final int autoUpdateIntervalHours;

  /// Брать интервал ИЗ ПОДПИСКИ вместо нашего (галочка «чтобы было не так»).
  final bool autoUpdatePreferSubscription;

  /// Проверять обновления самого приложения при запуске (скачивание — вручную).
  final bool appUpdateCheck;

  /// Эндпоинт проверки версии приложения (см. docs/APP_UPDATE.md).
  final String appUpdateUrl;

  const AppSettings({
    this.captureMode = CaptureMode.systemProxy,
    this.tunProvider = TunProvider.wintun,
    this.tunStack = TunStack.auto,
    this.tunMtu = 1500,
    this.splitTunnel = const SplitTunnelConfig(),
    this.tunStrictRoute = true,
    this.tunIpv6 = true,
    this.tunEndpointIndependentNat = true,
    this.tunBypassLan = true,
    this.tunExcludeCidrs = const [],
    this.dnsMode = DnsMode.vpn,
    this.dnsCustomServer = '1.1.1.1',
    this.dnsHijack = true,
    this.dnsStrategy = DnsStrategy.preferIpv4,
    this.singboxLogLevel = SingboxLogLevel.warn,
    this.autoReconnect = true,
    this.killSwitch = false,
    this.noRealIp = false,
    this.speedTestSize = SpeedTestSize.full,
    this.pingTwoPhase = true,
    this.pingPrimary = PingMethod.tcp,
    this.pingFallback = PingMethod.proxyGet,
    this.testUrl = 'https://www.gstatic.com/generate_204',
    this.pingTimeoutMs = 3000,
    this.pingConcurrency = 8,
    this.autoConfigEnabled = false,
    this.autoConfigServices = const {
      ProbeService.youtube,
      ProbeService.chatgpt,
      ProbeService.telegram,
    },
    this.tryFragment = true,
    this.fingerprints = const ['chrome'],
    this.strategy = AutoConfigStrategy.firstMatch,
    this.autoConfigBudgetSec = 60,
    this.autoPinFound = true,
    this.acceptMinServices = 0,
    this.autoConnectAfterImport = false,
    this.themeMode = AppThemeMode.system,
    this.languageCode = '',
    this.closeToTray = true,
    this.dontAskOnClose = false,
    this.autoUpdateEnabled = true,
    this.autoUpdateIntervalHours = 12,
    this.autoUpdatePreferSubscription = false,
    this.appUpdateCheck = true,
    this.appUpdateUrl = AppUpdate.defaultEndpoint,
  });

  static const AppSettings defaults = AppSettings();

  /// Сколько сервисов реально требуется (учитывая 0 = «все включённые»).
  int get requiredServices =>
      acceptMinServices > 0 ? acceptMinServices : autoConfigServices.length;

  AppSettings copyWith({
    CaptureMode? captureMode,
    TunProvider? tunProvider,
    TunStack? tunStack,
    int? tunMtu,
    SplitTunnelConfig? splitTunnel,
    bool? tunStrictRoute,
    bool? tunIpv6,
    bool? tunEndpointIndependentNat,
    bool? tunBypassLan,
    List<String>? tunExcludeCidrs,
    DnsMode? dnsMode,
    String? dnsCustomServer,
    bool? dnsHijack,
    DnsStrategy? dnsStrategy,
    SingboxLogLevel? singboxLogLevel,
    bool? autoReconnect,
    bool? killSwitch,
    bool? noRealIp,
    SpeedTestSize? speedTestSize,
    bool? pingTwoPhase,
    PingMethod? pingPrimary,
    PingMethod? pingFallback,
    String? testUrl,
    int? pingTimeoutMs,
    int? pingConcurrency,
    bool? autoConfigEnabled,
    Set<ProbeService>? autoConfigServices,
    bool? tryFragment,
    List<String>? fingerprints,
    AutoConfigStrategy? strategy,
    int? autoConfigBudgetSec,
    bool? autoPinFound,
    int? acceptMinServices,
    bool? autoConnectAfterImport,
    AppThemeMode? themeMode,
    String? languageCode,
    bool? closeToTray,
    bool? dontAskOnClose,
    bool? autoUpdateEnabled,
    int? autoUpdateIntervalHours,
    bool? autoUpdatePreferSubscription,
    bool? appUpdateCheck,
    String? appUpdateUrl,
  }) {
    return AppSettings(
      captureMode: captureMode ?? this.captureMode,
      tunProvider: tunProvider ?? this.tunProvider,
      tunStack: tunStack ?? this.tunStack,
      tunMtu: tunMtu ?? this.tunMtu,
      splitTunnel: splitTunnel ?? this.splitTunnel,
      tunStrictRoute: tunStrictRoute ?? this.tunStrictRoute,
      tunIpv6: tunIpv6 ?? this.tunIpv6,
      tunEndpointIndependentNat:
          tunEndpointIndependentNat ?? this.tunEndpointIndependentNat,
      tunBypassLan: tunBypassLan ?? this.tunBypassLan,
      tunExcludeCidrs: tunExcludeCidrs ?? this.tunExcludeCidrs,
      dnsMode: dnsMode ?? this.dnsMode,
      dnsCustomServer: dnsCustomServer ?? this.dnsCustomServer,
      dnsHijack: dnsHijack ?? this.dnsHijack,
      dnsStrategy: dnsStrategy ?? this.dnsStrategy,
      singboxLogLevel: singboxLogLevel ?? this.singboxLogLevel,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      killSwitch: killSwitch ?? this.killSwitch,
      noRealIp: noRealIp ?? this.noRealIp,
      speedTestSize: speedTestSize ?? this.speedTestSize,
      pingTwoPhase: pingTwoPhase ?? this.pingTwoPhase,
      pingPrimary: pingPrimary ?? this.pingPrimary,
      pingFallback: pingFallback ?? this.pingFallback,
      testUrl: testUrl ?? this.testUrl,
      pingTimeoutMs: pingTimeoutMs ?? this.pingTimeoutMs,
      pingConcurrency: pingConcurrency ?? this.pingConcurrency,
      autoConfigEnabled: autoConfigEnabled ?? this.autoConfigEnabled,
      autoConfigServices: autoConfigServices ?? this.autoConfigServices,
      tryFragment: tryFragment ?? this.tryFragment,
      fingerprints: fingerprints ?? this.fingerprints,
      strategy: strategy ?? this.strategy,
      autoConfigBudgetSec: autoConfigBudgetSec ?? this.autoConfigBudgetSec,
      autoPinFound: autoPinFound ?? this.autoPinFound,
      acceptMinServices: acceptMinServices ?? this.acceptMinServices,
      autoConnectAfterImport:
          autoConnectAfterImport ?? this.autoConnectAfterImport,
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      closeToTray: closeToTray ?? this.closeToTray,
      dontAskOnClose: dontAskOnClose ?? this.dontAskOnClose,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      autoUpdateIntervalHours: autoUpdateIntervalHours ?? this.autoUpdateIntervalHours,
      autoUpdatePreferSubscription: autoUpdatePreferSubscription ?? this.autoUpdatePreferSubscription,
      appUpdateCheck: appUpdateCheck ?? this.appUpdateCheck,
      appUpdateUrl: appUpdateUrl ?? this.appUpdateUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'captureMode': captureMode.name,
        'tunProvider': tunProvider.name,
        'tunStack': tunStack.name,
        'tunMtu': tunMtu,
        'splitTunnel': splitTunnel.toJson(),
        'tunStrictRoute': tunStrictRoute,
        'tunIpv6': tunIpv6,
        'tunEndpointIndependentNat': tunEndpointIndependentNat,
        'tunBypassLan': tunBypassLan,
        'tunExcludeCidrs': tunExcludeCidrs,
        'dnsMode': dnsMode.name,
        'dnsCustomServer': dnsCustomServer,
        'dnsHijack': dnsHijack,
        'dnsStrategy': dnsStrategy.name,
        'singboxLogLevel': singboxLogLevel.name,
        'autoReconnect': autoReconnect,
        'killSwitch': killSwitch,
        'noRealIp': noRealIp,
        'speedTestSize': speedTestSize.name,
        'pingTwoPhase': pingTwoPhase,
        'pingPrimary': pingPrimary.name,
        'pingFallback': pingFallback.name,
        'testUrl': testUrl,
        'pingTimeoutMs': pingTimeoutMs,
        'pingConcurrency': pingConcurrency,
        'autoConfigEnabled': autoConfigEnabled,
        'autoConfigServices': autoConfigServices.map((s) => s.name).toList(),
        'tryFragment': tryFragment,
        'fingerprints': fingerprints,
        'strategy': strategy.name,
        'autoConfigBudgetSec': autoConfigBudgetSec,
        'autoPinFound': autoPinFound,
        'acceptMinServices': acceptMinServices,
        'autoConnectAfterImport': autoConnectAfterImport,
        'themeMode': themeMode.name,
        'languageCode': languageCode,
        'closeToTray': closeToTray,
        'dontAskOnClose': dontAskOnClose,
        'autoUpdateEnabled': autoUpdateEnabled,
        'autoUpdateIntervalHours': autoUpdateIntervalHours,
        'autoUpdatePreferSubscription': autoUpdatePreferSubscription,
        'appUpdateCheck': appUpdateCheck,
        'appUpdateUrl': appUpdateUrl,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    T pick<T>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if ((v as Enum).name == name) return v;
      }
      return fallback;
    }

    final servicesJson = (j['autoConfigServices'] as List?) ?? const [];
    final services = servicesJson
        .map((n) => pick(ProbeService.values, n, ProbeService.youtube))
        .toSet();

    return AppSettings(
      captureMode: pick(CaptureMode.values, j['captureMode'], CaptureMode.systemProxy),
      tunProvider: pick(TunProvider.values, j['tunProvider'], TunProvider.wintun),
      tunStack: pick(TunStack.values, j['tunStack'], TunStack.auto),
      tunMtu: (j['tunMtu'] as num?)?.toInt() ?? 1500,
      splitTunnel: j['splitTunnel'] is Map<String, dynamic>
          ? SplitTunnelConfig.fromJson(j['splitTunnel'] as Map<String, dynamic>)
          : const SplitTunnelConfig(),
      tunStrictRoute: j['tunStrictRoute'] as bool? ?? true,
      tunIpv6: j['tunIpv6'] as bool? ?? true,
      tunEndpointIndependentNat: j['tunEndpointIndependentNat'] as bool? ?? true,
      tunBypassLan: j['tunBypassLan'] as bool? ?? true,
      tunExcludeCidrs:
          ((j['tunExcludeCidrs'] as List?)?.cast<String>()) ?? const [],
      dnsMode: pick(DnsMode.values, j['dnsMode'], DnsMode.vpn),
      dnsCustomServer: j['dnsCustomServer'] as String? ?? '1.1.1.1',
      dnsHijack: j['dnsHijack'] as bool? ?? true,
      dnsStrategy: pick(DnsStrategy.values, j['dnsStrategy'], DnsStrategy.preferIpv4),
      singboxLogLevel:
          pick(SingboxLogLevel.values, j['singboxLogLevel'], SingboxLogLevel.warn),
      autoReconnect: j['autoReconnect'] as bool? ?? defaults.autoReconnect,
      killSwitch: j['killSwitch'] as bool? ?? defaults.killSwitch,
      noRealIp: j['noRealIp'] as bool? ?? defaults.noRealIp,
      // Миграция со старых ключей: смысл фаз изменился (сначала быстрый метод,
      // прокси — только если он молчит), поэтому переносим значения по смыслу.
      speedTestSize:
          pick(SpeedTestSize.values, j['speedTestSize'], SpeedTestSize.full),
      pingTwoPhase: j['pingTwoPhase'] as bool? ??
          j['verifyViaProxyFirst'] as bool? ??
          defaults.pingTwoPhase,
      pingPrimary: pick(
          PingMethod.values, j['pingPrimary'] ?? j['latencyMethod'], PingMethod.tcp),
      pingFallback: pick(PingMethod.values,
          j['pingFallback'] ?? j['proxyCheckMethod'], PingMethod.proxyGet),
      testUrl: j['testUrl'] as String? ?? defaults.testUrl,
      pingTimeoutMs: (j['pingTimeoutMs'] as num?)?.toInt() ?? 3000,
      pingConcurrency: (j['pingConcurrency'] as num?)?.toInt() ?? 8,
      autoConfigEnabled: j['autoConfigEnabled'] as bool? ?? false,
      autoConfigServices:
          services.isEmpty ? defaults.autoConfigServices : services,
      tryFragment: j['tryFragment'] as bool? ?? true,
      fingerprints: ((j['fingerprints'] as List?)?.cast<String>()) ?? const ['chrome'],
      strategy: pick(AutoConfigStrategy.values, j['strategy'], AutoConfigStrategy.firstMatch),
      autoConfigBudgetSec: (j['autoConfigBudgetSec'] as num?)?.toInt() ?? 60,
      autoPinFound: j['autoPinFound'] as bool? ?? defaults.autoPinFound,
      acceptMinServices: (j['acceptMinServices'] as num?)?.toInt() ?? 0,
      autoConnectAfterImport: j['autoConnectAfterImport'] as bool? ?? false,
      themeMode: pick(AppThemeMode.values, j['themeMode'], AppThemeMode.system),
      languageCode: j['languageCode'] as String? ?? '',
      closeToTray: j['closeToTray'] as bool? ?? true,
      dontAskOnClose: j['dontAskOnClose'] as bool? ?? false,
      autoUpdateEnabled: j['autoUpdateEnabled'] as bool? ?? true,
      autoUpdateIntervalHours: (j['autoUpdateIntervalHours'] as num?)?.toInt() ?? 12,
      autoUpdatePreferSubscription: j['autoUpdatePreferSubscription'] as bool? ?? false,
      appUpdateCheck: j['appUpdateCheck'] as bool? ?? defaults.appUpdateCheck,
      appUpdateUrl: j['appUpdateUrl'] as String? ?? defaults.appUpdateUrl,
    );
  }
}
