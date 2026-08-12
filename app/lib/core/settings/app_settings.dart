import 'dart:convert';

import '../net/speed_test.dart';
// Намеренно НЕ '../update/app_update.dart': он тянет app_log → app_paths →
// path_provider → package:flutter → dart:ui, из-за чего `dart run tool/emit_*`
// переставал работать. Нужна отсюда только константа адреса обновлений.
import '../update/app_update_defaults.dart';
import 'split_tunnel.dart';

/// Как перехватывается трафик.
///
/// ⚠️ `proxyOnly` ДОБАВЛЯЕТСЯ В КОНЕЦ. Разбор идёт по имени (`pick(...)`), но
/// порядок значений всё равно менять нельзя: на него смотрят сравнения и
/// сортировки, а старые файлы настроек хранят имя.
///
/// * `systemProxy` — прописываем прокси в реестр WinINET, программы идут через
///   него сами;
/// * `tun` — виртуальный адаптер забирает весь трафик машины;
/// * `proxyOnly` — ядро поднято, локальные порты слушают, но машина НЕ в
///   туннеле: через VPN идёт только тот, кто явно целится в порт.
enum CaptureMode { systemProxy, tun, proxyOnly }

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

/// Сколько хранить логи и отчёты для поддержки.
///
/// ⚠️ ЗАВЕДЕНО ПО ЖИВЫМ ДАННЫМ ВЛАДЕЛЬЦА: 18 отчётов на 4,3 МБ, ни один
/// никогда не удалялся, а каждый следующий больше предыдущего (78 КБ в июле →
/// 525 КБ в августе) — отчёт включает логи целиком. Единственным ограничителем
/// до сих пор был порог 512 КБ, зашитый в код, и он не касался ни отчётов, ни
/// логов ядра.
enum LogRetention { day, twoWeeks, month, never }

extension LogRetentionAge on LogRetention {
  /// Возраст, старше которого файл удаляется. `null` — не удалять никогда.
  Duration? get maxAge {
    switch (this) {
      case LogRetention.day:
        return const Duration(days: 1);
      case LogRetention.twoWeeks:
        return const Duration(days: 14);
      case LogRetention.month:
        return const Duration(days: 30);
      case LogRetention.never:
        return null;
    }
  }
}

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

  /// Имеет ли kill switch смысл при текущем захвате.
  ///
  /// ⚠️ В режиме «только прокси» — нет. Kill switch удерживает трафик МАШИНЫ на
  /// время переподключения, а машина здесь и так ходит мимо туннеля. Тумблер,
  /// который виден и ничего не делает, хуже отсутствующего.
  bool get killSwitchApplies => captureMode != CaptureMode.proxyOnly;

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

  /// Пароль на ЛОКАЛЬНЫЕ прокси ядра (socks/http на 127.0.0.1). По умолчанию ВКЛ.
  ///
  /// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ НУЖНО. Локальный порт ядра — это полноценный прокси в
  /// ваш VPN. Без пароля к нему подключается что угодно на этой же машине и
  /// получает ваш туннель целиком: выходной IP, квоту подписки и обход вашего
  /// же раздельного туннелирования, включая приложения, которым вы поставили
  /// «Блок». На Android это особенно остро — loopback там не изолирован между
  /// приложениями, и порт видит любое установленное. Дыра отраслевая
  /// (v2rayNG #5467, Hiddify #2120, FlClash #1934 — везде закрыто «not
  /// planned»); единственная известная починка в природе — amnezia-client
  /// PR #2453.
  ///
  /// ⚠️ И ЗАЧЕМ ЭТО ВЫКЛЮЧАЕМО. В режиме системного прокси на Windows пароль
  /// поставить НЕЛЬЗЯ: туда смотрит WinINET, а он креденшелов не передаёт —
  /// интернет просто ляжет. Движок это учитывает сам, но настройка нужна и
  /// тем, кто ходит в наш прокси своими программами.
  final bool localProxyAuth;

  /// Логин и пароль локальных прокси. ПУСТО — генерировать заново на каждую
  /// сессию и держать только в памяти (рекомендуемый режим).
  ///
  /// ⚠️ Заданные вручную значения ЛОЖАТСЯ НА ДИСК в файл настроек. Это
  /// сознательный размен: свой пароль нужен, чтобы прописать прокси в стороннюю
  /// программу, но он переживает перезапуск и попадает в резервные копии.
  /// Случайный посессионный пароль такого следа не оставляет.
  final String localProxyUser;
  final String localProxyPassword;

  /// Локальный API для автоматизации: HTTP на 127.0.0.1 с токеном.
  ///
  /// ⚠️ ВЫКЛ ПО УМОЛЧАНИЮ И ЭТО НЕ ОСТОРОЖНИЧАНЬЕ. Управляющий порт опаснее
  /// прокси-порта: он умеет переключать сервер и читает состояние подписки.
  /// Кому он не нужен — у того ничего не слушает, и дыры нет.
  final bool apiEnabled;

  /// Токен API. Он же пароль портов отдельных серверов.
  ///
  /// ⚠️ ПУСТОЙ ТОКЕН ОЗНАЧАЕТ «КАНАЛ НЕ ПОДНИМАЕТСЯ», а не «поднимается без
  /// проверки». Полумера здесь опаснее отсутствия: порт, про который в
  /// интерфейсе написано «закрыт», а на деле пускающий кого угодно, хуже
  /// честно выключенного. То же правило уже закреплено для инбаундов ядра.
  ///
  /// ⚠️ Лежит на диске в открытом виде — это осознанный размен ради
  /// предсказуемого ключа между перезапусками, и он назван пользователю в
  /// интерфейсе. Тот же размен уже сделан для своих логина и пароля прокси.
  final String apiToken;

  /// Ключи серверов, которым выдан отдельный локальный порт.
  ///
  /// ⚠️ Отдельный список, а НЕ «все серверы подписки»: сотня серверов дала бы
  /// сотню инбаундов в конфиге ядра. И не «серверы из правил»: заводить
  /// фиктивное правило ради порта — костыль.
  final List<String> apiExitServerKeys;

  /// Применять ли раздельное туннелирование (только «Блок») к портам API в
  /// режиме «Только прокси» (задача 3b).
  ///
  /// ⚠️ УМОЛЧАНИЕ ВЫКЛЮЧЕНО, И ЭТО НЕ ОСТОРОЖНИЧАНЬЕ. В этом режиме раздельное
  /// туннелирование не действует ни для одной программы машины — ничего не
  /// перехватывается, порт получает только тот, кто явно в него обратился.
  /// Применять правила к одному лишь API-порту по умолчанию значило бы
  /// включить их там, где они больше нигде не работают, и удивить того, кто
  /// явно попросил конкретный сервер. Кому нужна защита от собственного
  /// скрипта — включает галочку сам.
  final bool applyRulesInProxyOnly;

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

  /// Показывать всплывающее уведомление, когда сайт заблокирован правилом.
  ///
  /// ⚠️ ЗАМЕНИЛО СТРАНИЦУ-ЗАГЛУШКУ, и вот почему её больше нет. Заглушка
  /// работала только для plain http: подменить ответ у `https://` без своего
  /// корневого сертификата невозможно, а ставить такой сертификат нельзя — он
  /// даёт читать весь TLS пользователя. На практике до неё вообще не доходило:
  /// браузеры идут в https сразу (HSTS переписывает адрес ДО отправки запроса),
  /// и человек видел `ERR_CONNECTION_RESET` вместо объяснения. Механизм,
  /// который срабатывает в одном случае из ста, хуже отсутствующего: он создаёт
  /// ожидание, которое не выполняется.
  ///
  /// Уведомление работает на любом протоколе и порту, ничего не подменяет и
  /// говорит главное — что сайт закрыт НАШИМ правилом, а не сломался.
  final bool blockNoticeEnabled;
  final DnsStrategy dnsStrategy;

  /// Уровень лога sing-box (`%APPDATA%\SilentGate\singbox.log`).
  final SingboxLogLevel singboxLogLevel;

  /// Срок хранения логов и отчётов поддержки. Проверяется при запуске.
  ///
  /// ⚠️ НАМЕРЕННО НЕ В [reconnectReasons]: чистка старых файлов на диске к
  /// конфигу ядра отношения не имеет, и предлагать из-за неё переподключиться
  /// значило бы рвать живой туннель на ровном месте.
  final LogRetention logRetention;

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

  /// Свёрнутые разделы экрана настроек — их ИДЕНТИФИКАТОРЫ.
  ///
  /// ⚠️ ПУСТОЙ СПИСОК = ВСЁ РАЗВЁРНУТО, и это умолчание задано владельцем
  /// явно: сворачивание — помощь тому, кто уже знает экран, а не способ
  /// спрятать настройки от того, кто открыл его впервые.
  ///
  /// ⚠️ Хранятся именно идентификаторы (`SettingsSectionIds`), а НЕ заголовки:
  /// заголовок переводится на десять языков, и на смене языка все свёрнутые
  /// разделы разворачивались бы сами — состояние молча терялось бы.
  ///
  /// ⚠️ НАМЕРЕННО НЕ В [reconnectReasons]: раскладка интерфейса в конфиг ядра
  /// не попадает, и предлагать из-за неё переподключиться значило бы рвать
  /// живой туннель из-за нажатия на заголовок.
  final List<String> collapsedSections;

  /// Код языка интерфейса (`ru`/`en`/`es`…). Пустая строка — следовать системе.
  final String languageCode;
  final bool closeToTray; // крестик: сворачивать в трей (true) / закрывать полностью (false)
  final bool dontAskOnClose; // не спрашивать при сворачивании
  final bool autoUpdateEnabled; // автообновление подписки

  /// Тянуть подписку при КАЖДОМ запуске приложения.
  ///
  /// ⚠️ Это НЕ то же самое, что [autoUpdateEnabled]: тот работает по таймеру
  /// (интервал в настройках, по умолчанию 12 часов) и между запусками ничего
  /// не гарантирует. Запустил приложение через сутки — список серверов и
  /// остаток трафика показывались прошлогодние, пока не подойдёт срок или
  /// пользователь не нажмёт «Обновить» руками.
  ///
  /// ⚠️ Обновление идёт ФОНОМ и его отказ НЕ роняет запуск: сети может не быть,
  /// панель может не ответить, а приложение обязано стартовать и подхватить
  /// живой туннель в любом случае.
  final bool updateSubscriptionOnStart;

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
    this.localProxyAuth = true,
    this.localProxyUser = '',
    this.localProxyPassword = '',
    this.apiEnabled = false,
    this.apiToken = '',
    this.apiExitServerKeys = const [],
    this.applyRulesInProxyOnly = false,
    this.tunWatchdogSeconds = 20,
    this.dnsMode = DnsMode.vpn,
    this.dnsCustomServer = '1.1.1.1',
    this.dnsHijack = true,
    this.tunnelDnsForAll = false,
    this.blockNoticeEnabled = true,
    this.speedInAutoSelect = false,
    this.myRulesOverridePanel = true,
    this.compactNotification = false,
    this.blockQuic = false,
    this.blockEncryptedDns = false,
    this.dnsStrategy = DnsStrategy.preferIpv4,
    this.singboxLogLevel = SingboxLogLevel.warn,
    // Месяц, а не меньше: короче — рискуем стереть лог раньше, чем человек
    // дойдёт до жалобы, а разбирать нечего будет уже навсегда.
    this.logRetention = LogRetention.month,
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
    this.collapsedSections = const [],
    this.languageCode = '',
    this.closeToTray = true,
    this.dontAskOnClose = false,
    this.autoUpdateEnabled = true,
    this.updateSubscriptionOnStart = true,
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
    bool? localProxyAuth,
    String? localProxyUser,
    String? localProxyPassword,
    bool? apiEnabled,
    String? apiToken,
    List<String>? apiExitServerKeys,
    bool? applyRulesInProxyOnly,
    int? tunWatchdogSeconds,
    DnsMode? dnsMode,
    String? dnsCustomServer,
    bool? dnsHijack,
    bool? tunnelDnsForAll,
    bool? blockNoticeEnabled,
    bool? speedInAutoSelect,
    bool? myRulesOverridePanel,
    bool? compactNotification,
    bool? blockQuic,
    bool? blockEncryptedDns,
    DnsStrategy? dnsStrategy,
    SingboxLogLevel? singboxLogLevel,
    LogRetention? logRetention,
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
    List<String>? collapsedSections,
    String? languageCode,
    bool? closeToTray,
    bool? dontAskOnClose,
    bool? autoUpdateEnabled,
    bool? updateSubscriptionOnStart,
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
      localProxyAuth: localProxyAuth ?? this.localProxyAuth,
      localProxyUser: localProxyUser ?? this.localProxyUser,
      localProxyPassword: localProxyPassword ?? this.localProxyPassword,
      apiEnabled: apiEnabled ?? this.apiEnabled,
      apiToken: apiToken ?? this.apiToken,
      apiExitServerKeys: apiExitServerKeys ?? this.apiExitServerKeys,
      applyRulesInProxyOnly:
          applyRulesInProxyOnly ?? this.applyRulesInProxyOnly,
      tunWatchdogSeconds: tunWatchdogSeconds ?? this.tunWatchdogSeconds,
      dnsMode: dnsMode ?? this.dnsMode,
      dnsCustomServer: dnsCustomServer ?? this.dnsCustomServer,
      dnsHijack: dnsHijack ?? this.dnsHijack,
      tunnelDnsForAll: tunnelDnsForAll ?? this.tunnelDnsForAll,
      blockNoticeEnabled: blockNoticeEnabled ?? this.blockNoticeEnabled,
      speedInAutoSelect: speedInAutoSelect ?? this.speedInAutoSelect,
      myRulesOverridePanel: myRulesOverridePanel ?? this.myRulesOverridePanel,
      compactNotification: compactNotification ?? this.compactNotification,
      blockQuic: blockQuic ?? this.blockQuic,
      blockEncryptedDns: blockEncryptedDns ?? this.blockEncryptedDns,
      dnsStrategy: dnsStrategy ?? this.dnsStrategy,
      singboxLogLevel: singboxLogLevel ?? this.singboxLogLevel,
      logRetention: logRetention ?? this.logRetention,
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
      collapsedSections: collapsedSections ?? this.collapsedSections,
      languageCode: languageCode ?? this.languageCode,
      closeToTray: closeToTray ?? this.closeToTray,
      dontAskOnClose: dontAskOnClose ?? this.dontAskOnClose,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      updateSubscriptionOnStart:
          updateSubscriptionOnStart ?? this.updateSubscriptionOnStart,
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
        'localProxyAuth': localProxyAuth,
        'localProxyUser': localProxyUser,
        'localProxyPassword': localProxyPassword,
        'apiEnabled': apiEnabled,
        'apiToken': apiToken,
        'apiExitServerKeys': apiExitServerKeys,
        'applyRulesInProxyOnly': applyRulesInProxyOnly,
        'tunWatchdogSeconds': tunWatchdogSeconds,
        'dnsMode': dnsMode.name,
        'dnsCustomServer': dnsCustomServer,
        'dnsHijack': dnsHijack,
        'tunnelDnsForAll': tunnelDnsForAll,
        'blockNoticeEnabled': blockNoticeEnabled,
        'speedInAutoSelect': speedInAutoSelect,
        'myRulesOverridePanel': myRulesOverridePanel,
        'compactNotification': compactNotification,
        'blockQuic': blockQuic,
        'blockEncryptedDns': blockEncryptedDns,
        'dnsStrategy': dnsStrategy.name,
        'singboxLogLevel': singboxLogLevel.name,
        'logRetention': logRetention.name,
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
        'collapsedSections': collapsedSections,
        'languageCode': languageCode,
        'closeToTray': closeToTray,
        'dontAskOnClose': dontAskOnClose,
        'autoUpdateEnabled': autoUpdateEnabled,
        'updateSubscriptionOnStart': updateSubscriptionOnStart,
        'autoUpdateIntervalHours': autoUpdateIntervalHours,
        'autoUpdatePreferSubscription': autoUpdatePreferSubscription,
        'appUpdateCheck': appUpdateCheck,
        'appUpdateUrl': appUpdateUrl,
      };

  /// Перевод правил из ПЕРВОЙ редакции мульти-VPN на прямую ссылку на сервер.
  ///
  /// В той редакции существовала отдельная сущность «выход» (`exits` в JSON), а
  /// правило ссылалось на её идентификатор (`exitId`). Владелец решил, что
  /// лишний уровень не нужен: правило должно указывать на СЕРВЕР напрямую.
  /// Здесь `exitId` разворачивается в ключ первого сервера того выхода.
  ///
  /// ⚠️ Не «почистить старый ключ», а именно перенести значение. Молча
  /// потерянное правило — это трафик, ушедший не в ту страну, причём без
  /// единого следа в интерфейсе: строка на месте, адресат исчез.
  static SplitTunnelConfig _migrateExits(
      SplitTunnelConfig split, Object? rawExits) {
    if (rawExits is! List || rawExits.isEmpty) return split;
    final firstServerOf = <String, String>{};
    for (final e in rawExits) {
      if (e is! Map) continue;
      final id = (e['id'] as String? ?? '').trim();
      final keys = (e['serverKeys'] as List?) ?? const [];
      if (id.isEmpty || keys.isEmpty) continue;
      final first = keys.first?.toString().trim() ?? '';
      if (first.isNotEmpty) firstServerOf[id] = first;
    }
    if (firstServerOf.isEmpty) return split;
    String? mapped(String? v) => v == null ? null : firstServerOf[v] ?? v;
    return split.copyWith(
      sites: [
        for (final r in split.sites)
          firstServerOf.containsKey(r.serverKey)
              ? r.copyWith(serverKey: mapped(r.serverKey))
              : r,
      ],
      apps: [
        for (final r in split.apps)
          firstServerOf.containsKey(r.serverKey)
              ? r.copyWith(serverKey: mapped(r.serverKey))
              : r,
      ],
    );
  }

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
          ? _migrateExits(SplitTunnelConfig.fromJson(j['splitTunnel'] as Map<String, dynamic>), j['exits'])
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
      // Умолчание ВКЛ: у всех, кто обновится, пароль появится сам.
      localProxyAuth: j['localProxyAuth'] as bool? ?? defaults.localProxyAuth,
      localProxyUser: j['localProxyUser'] as String? ?? '',
      localProxyPassword: j['localProxyPassword'] as String? ?? '',
      apiEnabled: j['apiEnabled'] as bool? ?? defaults.apiEnabled,
      apiToken: j['apiToken'] as String? ?? defaults.apiToken,
      apiExitServerKeys:
          (j['apiExitServerKeys'] as List?)?.cast<String>() ??
              defaults.apiExitServerKeys,
      applyRulesInProxyOnly: j['applyRulesInProxyOnly'] as bool? ??
          defaults.applyRulesInProxyOnly,
      tunWatchdogSeconds:
          (j['tunWatchdogSeconds'] as num?)?.toInt() ?? defaults.tunWatchdogSeconds,
      dnsMode: pick(DnsMode.values, j['dnsMode'], DnsMode.vpn),
      dnsCustomServer: j['dnsCustomServer'] as String? ?? '1.1.1.1',
      dnsHijack: j['dnsHijack'] as bool? ?? true,
      dnsStrategy: pick(DnsStrategy.values, j['dnsStrategy'], DnsStrategy.preferIpv4),
      singboxLogLevel:
          pick(SingboxLogLevel.values, j['singboxLogLevel'], SingboxLogLevel.warn),
      // ⚠️ Читается ОБЯЗАТЕЛЬНО: страж settings_roundtrip_test перебирает
      // булевы и числовые поля, а перечисления хранятся строкой и мимо него
      // проходят. Забытая строка здесь = «выбрал никогда не удалять, а после
      // перезапуска снова месяц», и заметить это со стороны интерфейса нельзя.
      logRetention: pick(LogRetention.values, j['logRetention'],
          defaults.logRetention),
      autoReconnect: j['autoReconnect'] as bool? ?? defaults.autoReconnect,
      killSwitch: j['killSwitch'] as bool? ?? defaults.killSwitch,
      noRealIp: j['noRealIp'] as bool? ?? defaults.noRealIp,
        // ⚠️ Оба поля обязаны ЧИТАТЬСЯ, а не только писаться: без строки здесь
        // настройка молча возвращается к умолчанию при каждом запуске, а в
        // файле при этом лежит выбор пользователя — расхождение, которое
        // невозможно заметить со стороны интерфейса.
        tunnelDnsForAll:
            j['tunnelDnsForAll'] as bool? ?? defaults.tunnelDnsForAll,
        // Старый ключ читаем как новый: кто выключал заглушку, тот не
        // хотел и уведомления — смысл настройки («объяснять блокировку»)
        // сохранился, поменялся только способ.
        blockNoticeEnabled: j['blockNoticeEnabled'] as bool? ??
            j['blockPageEnabled'] as bool? ??
            defaults.blockNoticeEnabled,
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
      // ⚠️ ЧИТАЕТСЯ ОБЯЗАТЕЛЬНО — иначе свёрнутые разделы разворачивались бы
      // при каждом запуске, хотя выбор пользователя лежит в файле (тот самый
      // класс «поле пишется, но не читается»; страж settings_roundtrip_test
      // перебирает только булевы и числовые поля, список мимо него проходит).
      //
      // `whereType`, а не `cast`: битый файл настроек не должен ронять экран
      // настроек при первой же прокрутке — лишний элемент просто игнорируем.
      collapsedSections: ((j['collapsedSections'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      languageCode: j['languageCode'] as String? ?? '',
      closeToTray: j['closeToTray'] as bool? ?? true,
      dontAskOnClose: j['dontAskOnClose'] as bool? ?? false,
      autoUpdateEnabled: j['autoUpdateEnabled'] as bool? ?? true,
      updateSubscriptionOnStart:
          j['updateSubscriptionOnStart'] as bool? ?? true,
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
    // ⚠️ Пароль локального прокси ЗАПЕКАЕТСЯ В КОНФИГ ядра при подъёме. Без
    // этих трёх строк тумблер срабатывал молча: человек включал защиту, видел
    // включённый переключатель и считал порт закрытым, а живое ядро продолжало
    // слушать 10808/10809 без пароля до ручного переподключения. Зеркальный
    // случай — вписал свои логин и пароль для сторонней программы, интерфейс
    // показывает новые, ядро работает со старыми, программа получает 407.
    diff('пароль на локальный прокси', localProxyAuth, other.localProxyAuth);
    diff('логин локального прокси', localProxyUser, other.localProxyUser);
    diff('пароль локального прокси', localProxyPassword,
        other.localProxyPassword);
    // Все три запекаются в конфиг ядра при подъёме: тумблер решает, поднимать
    // ли инбаунды серверов, токен становится их паролем, список — их составом.
    diff('API для автоматизации', apiEnabled, other.apiEnabled);
    diff('токен API', apiToken, other.apiToken);
    diff('серверы с отдельным портом', apiExitServerKeys.join(','),
        other.apiExitServerKeys.join(','));
    // Тоже запекается в конфиг маршрутизатора выходов при подъёме (задача 3b):
    // решает, добавлять ли туда блок-правила раздельного туннелирования.
    diff('правила раздельного туннелирования в «Только прокси»',
        applyRulesInProxyOnly, other.applyRulesInProxyOnly);
    diff('режим DNS', dnsMode, other.dnsMode);
    diff('свой DNS-сервер', dnsCustomServer, other.dnsCustomServer);
    diff('перехват DNS', dnsHijack, other.dnsHijack);
    diff('весь DNS через туннель', tunnelDnsForAll, other.tunnelDnsForAll);
    diff('уведомление о блокировке', blockNoticeEnabled,
        other.blockNoticeEnabled);
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

  /// Изменилось ли что-то из настроек локального API (тумблер/токен/список
  /// серверов с отдельным портом).
  ///
  /// ⚠️ НАРОЧНО ОТДЕЛЬНО ОТ [requiresReconnect]. Тот отвечает на вопрос «нужно
  /// ли поднимать ТУННЕЛЬ заново» и триггерится любым полем его конфига — в
  /// том числе MTU, DNS, стеком, которые к локальному API не имеют отношения.
  /// Использовать его же для решения «перезапускать ли API-сокет» значило бы
  /// гасить и поднимать заново слушатель на каждую не связанную с ним правку,
  /// обрывая тех, кто через API в этот момент работает (`AppState.
  /// applyApiSettings`, задача 5, раунд ревью 1). Список полей — РОВНО те три,
  /// что решают, поднимать ли слушатель и что он отдаёт.
  bool apiSettingsChanged(AppSettings other) =>
      apiEnabled != other.apiEnabled ||
      apiToken != other.apiToken ||
      apiExitServerKeys.join(',') != other.apiExitServerKeys.join(',');
}
