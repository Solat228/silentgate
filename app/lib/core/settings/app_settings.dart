import 'dart:convert';

import '../net/speed_test.dart';
// Намеренно НЕ '../update/app_update.dart': он тянет app_log → app_paths →
// path_provider → package:flutter → dart:ui, из-за чего `dart run tool/emit_*`
// переставал работать. Нужна отсюда только константа адреса обновлений.
import '../update/app_update_defaults.dart';
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

/// Прежние жёстко записанные адреса обновлений: их надо забыть, чтобы
/// заработал платформенный выбор (Android больше не ведёт на .exe).
const _legacyUpdateEndpoints = <String>{
  'https://silentgate.lol/api/app-version',
};

String _sanitizeUpdateUrl(String? raw) {
  final v = (raw ?? '').trim();
  return _legacyUpdateEndpoints.contains(v) ? '' : v;
}

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

  /// «В туннель идут ТОЛЬКО эти подсети» — список CIDR. Пусто = обычный режим.
  ///
  /// ⚠️ ЭТО ЕДИНСТВЕННЫЙ СПОСОБ НА WINDOWS СДЕЛАТЬ ТРАФИК НЕЗАВИСИМЫМ ОТ КЛИЕНТА.
  ///
  /// Обычно `auto_route` вешает на туннель маршрут `0.0.0.0/0` и метрику 0, то
  /// есть В ТУННЕЛЬ ЗАХОДИТ ВСЁ. Пометка «Прямо» разбирается уже ВНУТРИ ядра:
  /// оно принимает пакет своим стеком и открывает наружу новый сокет от своего
  /// имени. Наружу такой трафик выходит под реальным адресом — но живёт ровно
  /// столько, сколько живёт процесс ядра, и зависает вместе с ним.
  ///
  /// Здесь маршрут по умолчанию туннелю НЕ отдаётся: он забирает только
  /// перечисленные подсети (`route_address`), остальное система отправляет
  /// физическим адаптером, и клиент этого трафика не видит вовсе.
  ///
  /// ⚠️ ЦЕНА, О КОТОРОЙ ОБЯЗАНО ЗНАТЬ И ПРИЛОЖЕНИЕ, И ПОЛЬЗОВАТЕЛЬ: деление
  /// идёт ПО АДРЕСУ, а правила по приложениям и сайтам — по имени. Сайт, чей IP
  /// не попал в список, ядро не увидит НИ ОДНИМ правилом: он туда не заходит.
  /// Это ровно та же ловушка, что `exclude_package` на Android (см. CLAUDE.md).
  ///
  /// Аналога «исключить программу» на Windows у sing-box нет: поля
  /// `exclude_process_name`/`exclude_process_path` не существуют, а
  /// `exclude_package`/`exclude_uid`/`include_interface` ядро на Windows
  /// ПРИНИМАЕТ МОЛЧА (`check` даёт exit 0) и не применяет — проверено запуском
  /// настоящего sing-box 1.11.15. Не принимать их за рабочий рычаг.
  final List<String> tunRouteOnlyCidrs;

  /// Прописывать системный прокси ДОПОЛНИТЕЛЬНО к туннелю (гибрид как в Happ).
  ///
  /// Прокси-aware приложения (браузеры, Telegram) пойдут коротким путём на
  /// `127.0.0.1:<http>`, минуя пользовательский стек туннеля.
  ///
  /// ⚠️ НЕ ДЕЛАЕТ ИХ НЕЗАВИСИМЫМИ ОТ ЯДРА: они ходят через тот же процесс, и
  /// при его смерти теряют сеть так же. Единственное, что даёт независимость, —
  /// [tunRouteOnlyCidrs].
  final bool alsoSetSystemProxy;

  /// Сколько секунд ядру можно не отвечать, прежде чем считать его зависшим.
  /// 0 — не следить.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ НУЖНО. При ПАДЕНИИ ядра Windows убирает за ним сама:
  /// WFP-сессия динамическая, адаптер заведён через `SwDeviceCreate` — фильтры,
  /// маршруты и адаптер снимаются автоматически, сеть возвращается. А при
  /// ЗАВИСАНИИ не снимается ничего: адаптер с метрикой 0 и маршрутом
  /// `0.0.0.0/0` остаётся на месте и глотает весь трафик машины, включая
  /// помеченный «Прямо». Снаружи это «интернет пропал совсем», и сам по себе он
  /// не возвращается никогда.
  final int tunWatchdogSeconds;

  // ── TUN: DNS ──────────────────────────────────────────────────────────────
  final DnsMode dnsMode;
  final String dnsCustomServer;

  /// Перехватывать UDP:53 (без утечек и точные доменные правила).
  final bool dnsHijack;

  /// Вести через туннель DNS ВСЕХ приложений или только тех, что идут через VPN.
  ///
  /// Работает лишь в режиме «только отмеченные»: в остальных весь трафик и так
  /// в туннеле.
  ///
  /// ⚠️ УМОЛЧАНИЕ ИЗМЕНЕНО НА «выключено» — по измерениям, а не по вкусу.
  /// Независимая проверка сети у владельца: резолв нового домена через туннель
  /// занимал 194–487 мс, тот же резолв локальным резолвером — около 60 мс.
  /// Причина простая: DNS-запрос ехал на сервер выхода в США и обратно. В режиме
  /// «только отмеченные» база трафика — ПРЯМАЯ, то есть большинство запросов
  /// принадлежит соединениям, которые всё равно пойдут мимо туннеля: они платили
  /// за океан и получали адрес CDN в чужой стране, отчего прямое соединение шло
  /// на дальний узел. Снаружи это ощущается как «сначала всё быстро, потом
  /// подтормаживает» — первый заход на каждый новый домен дорогой.
  ///
  /// Цена выключения: домены становятся видны провайдеру. Для ПРЯМОГО трафика
  /// это ничего не меняет — он и так идёт открыто и провайдер видит адреса.
  /// Для отмеченных приложений цена реальна, поэтому настройка осталась: у
  /// размена нет универсально верной стороны, и явные правила по сайтам
  /// («Прямо»/«Туннель») продолжают перекрывать это решение подомённо.
  final bool tunnelDnsForAll;

  /// Учитывать скорость при автоподборе лучшего сервера.
  ///
  /// Замер стоит трафика ПОДПИСКИ: 5 МБ на свой канал плюс по 5 МБ на каждого
  /// из трёх лучших кандидатов, итого около 20 МБ за прогон. Поэтому выключено
  /// по умолчанию — за трафик платит пользователь, и решать ему.
  final bool speedInAutoSelect;

  /// Мои правила важнее правил панели.
  ///
  /// Панель отдаёт в конфиге СВОЁ разделение — обычно «российские сайты мимо
  /// VPN». Оно применяется ВНУТРИ Xray, уже после нашего решения, поэтому сайт,
  /// который пользователь пометил «Туннель», панель может выпустить наружу
  /// напрямую — под реальным IP, молча.
  ///
  /// Включено — переписываем панельный `direct` на выход через VPN: написано
  /// «туннель», значит туннель. Цена: российские сайты, которые панель ускоряла
  /// прямым выходом, пойдут кругом. Выключено — быстрее, но своё правило может
  /// не сработать.
  final bool myRulesOverridePanel;

  /// ⚠️ ВРЕМЕННЫЙ ПЕРЕКЛЮЧАТЕЛЬ — так и написано в интерфейсе.
  ///
  /// Заведён по просьбе владельца, чтобы сравнить две раскладки уведомления на
  /// живом телефоне и выбрать одну. Когда выбор сделан — оставить победившую
  /// раскладку и УБРАТЬ и поле, и переключатель, и строки перевода.
  final bool compactNotification;

  /// Отказывать в QUIC (UDP:443).
  ///
  /// Доменные правила применяются к ИМЕНИ сайта, а имя берётся из сниффинга.
  /// Браузер, ушедший на HTTP/3, имени не оставляет — и правило по домену молча
  /// не срабатывает. Отказ возвращает браузер на TLS поверх TCP, где имя видно.
  /// По умолчанию ВЫКЛЮЧЕНО: у кого правил по доменам нет, тому это только
  /// отнимет скорость видео.
  final bool blockQuic;

  /// Отказывать в DNS поверх HTTPS/TLS/QUIC.
  ///
  /// Такой DNS уходит мимо перехвата UDP:53, и DNS-зеркало правил не работает:
  /// домен «Прямо» резолвится через туннель, домен «Блок» на DNS не режется.
  /// По умолчанию ВЫКЛЮЧЕНО: если браузеру жёстко задан DoH-провайдер, он не
  /// откатится на обычный DNS, а просто перестанет резолвить.
  final bool blockEncryptedDns;

  /// Показывать страницу «сайт заблокирован» вместо ошибки соединения.
  ///
  /// Работает только для plain http (см. [BlockPageServer]); у https заглушку
  /// подменить нечем без своего корневого сертификата, и мы его не ставим.
  final bool blockPageEnabled;
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
  /// Адрес проверки обновлений. ПУСТО = «по умолчанию для этой платформы».
  ///
  /// ⚠️ Раньше сюда при первом сохранении записывалась константа, и значение
  /// ЗАМОРАЖИВАЛОСЬ: смена адреса в новой версии не доходила до уже
  /// установленных копий — они продолжали спрашивать старый эндпоинт. Пустая
  /// строка означает «спроси платформу», поэтому адрес обновляется вместе с
  /// приложением. Непустое значение — осознанная правка пользователя, её
  /// уважаем.
  final String appUpdateUrl;

  /// Фактический адрес: пользовательский, иначе платформенный по умолчанию.
  String get effectiveAppUpdateUrl {
    final v = appUpdateUrl.trim();
    return v.isEmpty ? kDefaultAppUpdateEndpoint : v;
  }

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
    this.tunRouteOnlyCidrs = const [],
    this.alsoSetSystemProxy = false,
    this.tunWatchdogSeconds = 20,
    this.dnsMode = DnsMode.vpn,
    this.dnsCustomServer = '1.1.1.1',
    this.dnsHijack = true,
    this.tunnelDnsForAll = false,
    this.blockPageEnabled = true,
    this.speedInAutoSelect = false,
    this.myRulesOverridePanel = true,
    this.compactNotification = false,
    this.blockQuic = false,
    this.blockEncryptedDns = false,
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
    this.appUpdateUrl = '',
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
    List<String>? tunRouteOnlyCidrs,
    bool? alsoSetSystemProxy,
    int? tunWatchdogSeconds,
    DnsMode? dnsMode,
    String? dnsCustomServer,
    bool? dnsHijack,
    bool? tunnelDnsForAll,
    bool? blockPageEnabled,
    bool? speedInAutoSelect,
    bool? myRulesOverridePanel,
    bool? compactNotification,
    bool? blockQuic,
    bool? blockEncryptedDns,
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
      tunRouteOnlyCidrs: tunRouteOnlyCidrs ?? this.tunRouteOnlyCidrs,
      alsoSetSystemProxy: alsoSetSystemProxy ?? this.alsoSetSystemProxy,
      tunWatchdogSeconds: tunWatchdogSeconds ?? this.tunWatchdogSeconds,
      dnsMode: dnsMode ?? this.dnsMode,
      dnsCustomServer: dnsCustomServer ?? this.dnsCustomServer,
      dnsHijack: dnsHijack ?? this.dnsHijack,
      tunnelDnsForAll: tunnelDnsForAll ?? this.tunnelDnsForAll,
      blockPageEnabled: blockPageEnabled ?? this.blockPageEnabled,
      speedInAutoSelect: speedInAutoSelect ?? this.speedInAutoSelect,
      myRulesOverridePanel: myRulesOverridePanel ?? this.myRulesOverridePanel,
      compactNotification: compactNotification ?? this.compactNotification,
      blockQuic: blockQuic ?? this.blockQuic,
      blockEncryptedDns: blockEncryptedDns ?? this.blockEncryptedDns,
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
        'tunRouteOnlyCidrs': tunRouteOnlyCidrs,
        'alsoSetSystemProxy': alsoSetSystemProxy,
        'tunWatchdogSeconds': tunWatchdogSeconds,
        'dnsMode': dnsMode.name,
        'dnsCustomServer': dnsCustomServer,
        'dnsHijack': dnsHijack,
        'tunnelDnsForAll': tunnelDnsForAll,
        'blockPageEnabled': blockPageEnabled,
        'speedInAutoSelect': speedInAutoSelect,
        'myRulesOverridePanel': myRulesOverridePanel,
        'compactNotification': compactNotification,
        'blockQuic': blockQuic,
        'blockEncryptedDns': blockEncryptedDns,
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
      tunRouteOnlyCidrs:
          ((j['tunRouteOnlyCidrs'] as List?)?.cast<String>()) ?? const [],
      alsoSetSystemProxy:
          j['alsoSetSystemProxy'] as bool? ?? defaults.alsoSetSystemProxy,
      tunWatchdogSeconds:
          (j['tunWatchdogSeconds'] as num?)?.toInt() ?? defaults.tunWatchdogSeconds,
      dnsMode: pick(DnsMode.values, j['dnsMode'], DnsMode.vpn),
      dnsCustomServer: j['dnsCustomServer'] as String? ?? '1.1.1.1',
      dnsHijack: j['dnsHijack'] as bool? ?? true,
      dnsStrategy: pick(DnsStrategy.values, j['dnsStrategy'], DnsStrategy.preferIpv4),
      singboxLogLevel:
          pick(SingboxLogLevel.values, j['singboxLogLevel'], SingboxLogLevel.warn),
      autoReconnect: j['autoReconnect'] as bool? ?? defaults.autoReconnect,
      killSwitch: j['killSwitch'] as bool? ?? defaults.killSwitch,
      noRealIp: j['noRealIp'] as bool? ?? defaults.noRealIp,
        // ⚠️ Оба поля обязаны ЧИТАТЬСЯ, а не только писаться: без строки здесь
        // настройка молча возвращается к умолчанию при каждом запуске, а в
        // файле при этом лежит выбор пользователя — расхождение, которое
        // невозможно заметить со стороны интерфейса.
        tunnelDnsForAll:
            j['tunnelDnsForAll'] as bool? ?? defaults.tunnelDnsForAll,
        blockPageEnabled:
            j['blockPageEnabled'] as bool? ?? defaults.blockPageEnabled,
        speedInAutoSelect:
            j['speedInAutoSelect'] as bool? ?? defaults.speedInAutoSelect,
        myRulesOverridePanel: j['myRulesOverridePanel'] as bool? ??
            defaults.myRulesOverridePanel,
        compactNotification: j['compactNotification'] as bool? ??
            defaults.compactNotification,
        blockQuic: j['blockQuic'] as bool? ?? defaults.blockQuic,
        blockEncryptedDns:
            j['blockEncryptedDns'] as bool? ?? defaults.blockEncryptedDns,
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
      // Наследие: раньше сюда писался ЖЁСТКИЙ адрес Windows-эндпоинта, и на
      // Android приложение предлагало скачать .exe. Такое значение считаем
      // отсутствующим — платформа подставит свой.
      appUpdateUrl: _sanitizeUpdateUrl(j['appUpdateUrl'] as String?),
    );
  }

  /// Отличается ли [other] полем, которое ЗАПЕКАЕТСЯ в конфиг ядра.
  ///
  /// ⚠️ Конфиг собирается ОДИН раз — в момент подъёма туннеля, и дальше ядро
  /// работает по нему, что бы пользователь ни менял. Правка правил при живом
  /// соединении не применяется молча: у владельца из-за этого удалённый сайт
  /// продолжал ходить напрямую, а он думал, что правило не работает.
  ///
  /// Список полей — ровно то, что читает `SingboxConfigBuilder`/`TunOptions`.
  /// Добавляя новую настройку, влияющую на конфиг, впиши её СЮДА, иначе
  /// пользователь снова получит «поменял, а эффекта нет».
  bool requiresReconnect(AppSettings other) =>
      reconnectReasons(other).isNotEmpty;

  /// Какие именно поля изменились — ИМЕНАМИ, для лога.
  ///
  /// ⚠️ Это единственный список; [requiresReconnect] спрашивает его же. Раньше
  /// перечисление жило в одном месте, а в журнал не попадало вовсе — и в логе
  /// владельца шесть подряд перезапусков туннеля выглядели как обрывы связи без
  /// причины. Причина была безобидной (он менял настройки), но узнать это по
  /// журналу было нельзя: строка «Автопереподключение: <причина>» пишется
  /// только на пути восстановления, а перезапуск по правке настроек идёт
  /// мимо него.
  ///
  /// Добавляя настройку, влияющую на конфиг ядра, впиши её СЮДА — и она
  /// одновременно начнёт требовать переподключения и называть себя в логе.
  List<String> reconnectReasons(AppSettings other) {
    final out = <String>[];
    void diff(String name, Object? a, Object? b) {
      if (a != b) out.add(name);
    }

    diff('способ захвата', captureMode, other.captureMode);
    diff('стек TUN', tunStack, other.tunStack);
    diff('MTU', tunMtu, other.tunMtu);
    diff('строгая маршрутизация', tunStrictRoute, other.tunStrictRoute);
    diff('IPv6 в туннеле', tunIpv6, other.tunIpv6);
    diff('endpoint-independent NAT', tunEndpointIndependentNat,
        other.tunEndpointIndependentNat);
    diff('обход LAN', tunBypassLan, other.tunBypassLan);
    diff('исключённые подсети', tunExcludeCidrs.join(','),
        other.tunExcludeCidrs.join(','));
    diff('в туннель только перечисленные подсети', tunRouteOnlyCidrs.join(','),
        other.tunRouteOnlyCidrs.join(','));
    // Захват трафика ставится один раз при подъёме, поэтому включение прокси
    // поверх туннеля «на живую» не сработало бы молча.
    diff('системный прокси вместе с туннелем', alsoSetSystemProxy,
        other.alsoSetSystemProxy);
    diff('режим DNS', dnsMode, other.dnsMode);
    diff('свой DNS-сервер', dnsCustomServer, other.dnsCustomServer);
    diff('перехват DNS', dnsHijack, other.dnsHijack);
    diff('весь DNS через туннель', tunnelDnsForAll, other.tunnelDnsForAll);
    diff('страница-заглушка', blockPageEnabled, other.blockPageEnabled);
    diff('блокировка QUIC', blockQuic, other.blockQuic);
    diff('блокировка шифрованного DNS', blockEncryptedDns,
        other.blockEncryptedDns);
    diff('стратегия DNS', dnsStrategy, other.dnsStrategy);
    diff('уровень лога ядра', singboxLogLevel, other.singboxLogLevel);
    diff('запрет реального IP', noRealIp, other.noRealIp);
    // Запекается в конфиг (`rerouteDirectThroughVpn` в engine_base): без этой
    // строки пользователь включал «Мои правила важнее правил панели» при живом
    // соединении, конфиг оставался прежним, и предложения переподключиться —
    // единственного признака, что настройка ещё не в силе, — не приходило.
    diff('приоритет своих правил над панелью', myRulesOverridePanel,
        other.myRulesOverridePanel);
    // Правила раздельного туннелирования — самая частая правка «на живую».
    diff('правила раздельного туннелирования',
        jsonEncode(splitTunnel.toJson()), jsonEncode(other.splitTunnel.toJson()));
    return out;
  }
}
