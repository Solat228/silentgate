import 'dart:convert';
import 'dart:io';

import '../net/api_ports.dart';
import '../settings/app_settings.dart';
import '../settings/split_tunnel.dart';
import 'api_exit_guard.dart';
import 'exit_tags.dart';

/// Параметры TUN-туннеля (всё, что настраивается пользователем + вычисляемое движком).
class TunOptions {
  /// Стек sing-box: 'system' | 'gvisor' | 'mixed'; null — дефолт ядра.
  final String? stack;
  final int mtu;
  final bool strictRoute;
  final bool ipv6;

  /// ⚠️ Есть ли IPv6 НАРУЖУ. Отличать от [ipv6] обязательно: это разные случаи
  /// с противоположным правильным поведением.
  ///
  ///  * пользователь ВЫКЛЮЧИЛ IPv6, а наружу он есть — адрес объявляем и
  ///    отказываем ВНУТРИ туннеля. Иначе IPv6-трафик уходит мимо VPN, под
  ///    реальным адресом: это была настоящая утечка, пойманная живым тестом;
  ///  * IPv6 наружу НЕТ — адрес не объявляем вовсе. Отказывать нечему и незачем:
  ///    система честно видит «только IPv4» и даже не пытается. Прежний вариант
  ///    (объявить адрес и отказать) заставлял КАЖДОЕ соединение сперва пробовать
  ///    IPv6 и получать отказ — задержка на каждом двустековом сайте, и отказ
  ///    прилетал в том числе службам Windows.
  final bool ipv6Upstream;
  final bool endpointIndependentNat;
  final bool bypassLan;
  final List<String> excludeCidrs;

  /// Режим «в туннель идут ТОЛЬКО эти подсети» (`route_address`).
  /// Пусто = обычный захват с маршрутом по умолчанию.
  final List<String> routeOnlyCidrs;

  final DnsMode dnsMode;
  final String dnsServer;
  final bool dnsHijack;
  final DnsStrategy dnsStrategy;
  final String logLevel;

  /// IP-адреса VPN-серверов: жёстко уводятся мимо туннеля, иначе трафик самого
  /// Xray к серверу вернётся в Xray — петля и мгновенная смерть сети.
  final List<String> serverIps;

  /// ДОМЕННЫЕ ИМЕНА нашей инфраструктуры: серверы подписки и хост самой подписки.
  /// Резолвятся ТОЛЬКО напрямую, мимо туннеля.
  ///
  /// ⚠️ Это вторая половина защиты от петли, и без неё первая бесполезна.
  /// Мимо туннеля уводятся АДРЕСА — но чтобы узнать адрес, надо сперва
  /// отрезолвить имя, а резолв по умолчанию идёт через туннель
  /// (`dns.final: dns-proxy`), то есть через сервер, к которому мы ещё не
  /// подключились. Замкнутый круг.
  ///
  /// В логе владельца это выглядело так, десятками строк подряд:
  ///   dns: exchange failed for ws-nl.silentgate.lol. IN A:
  ///        read tcp 127.0.0.1:58160->127.0.0.1:10808: forcibly closed
  /// Снаружи — «ничего не работает»: туннель поднят, а трафика нет.
  ///
  /// Правила «процессы ядра → direct» здесь НЕ ХВАТАЕТ: на Windows имена
  /// резолвит служба DNS-клиента внутри svchost.exe, а не наш процесс, поэтому
  /// совпадения по имени процесса не происходит вовсе.
  final List<String> serverDomains;

  /// Сообщать ли пользователю о заблокированных сайтах.
  ///
  /// ⚠️ ЭТО ВЛИЯЕТ НА DNS, И ВОТ ПОЧЕМУ. Блокируем мы действием `reject` на
  /// правиле МАРШРУТИЗАЦИИ. Чтобы туда дошло дело, соединение должно сперва
  /// возникнуть, а для этого имя обязано отрезолвиться. Если заодно резать
  /// домен и в DNS, браузер спотыкается раньше — ядро блокировки не видит,
  /// и сообщать нам не о чем.
  ///
  /// Поэтому при включённом уведомлении блок-домены РЕЗОЛВЯТСЯ (запрос имени
  /// уходит), но трафик к ним отвергается. Выключено — режем и в DNS, так
  /// тише и быстрее. Размен небольшой, но он есть, и молчать о нём нельзя.
  final bool blockNotice;

  /// Порт нашего локального DNS-форвардера с ЗАПАСНЫМ резолвером. 0 — выключен.
  ///
  /// ⚠️ ЗАЧЕМ ОН НУЖЕН И ПОЧЕМУ ЕГО НЕТ В ЯДРЕ. При «DNS всех приложений через
  /// туннель» имена для ВСЕГО трафика спрашиваются через VPN — включая тот, что
  /// идёт мимо него. Стоит туннельному резолверу споткнуться, и без имён
  /// остаётся весь прямой трафик: в журнале ядра сотни `dns: exchange failed …
  /// EOF`, а для пользователя «интернет пропал при подключённом VPN».
  /// Встроенного запаса у sing-box 1.11.15 НЕТ — `address_fallback`, `fallback`
  /// и список в `address` отвергаются с `FATAL decode config` (проверено
  /// прогоном настоящего ядра).
  ///
  /// ⚠️ Форвардер подставляется ТОЛЬКО в `dns.final`, то есть под трафик без
  /// собственного правила. Явные правила «в туннель» продолжают ходить прямо
  /// в `dns-proxy`: там запас не нужен, а лишнее звено в защищённом пути —
  /// лишний способ его сломать.
  final int fallbackDnsPort;

  /// Пользователь выбрал стек «авто» — подбирать стек и MTU перебором,
  /// пока туннель не поднимется (см. [TunAutotune]).
  final bool autotune;

  /// «Не выходить под реальным IP»: пользовательские правила «Прямо» (direct)
  /// уводятся ЧЕРЕЗ VPN (proxy). Инфраструктурный direct (IP серверов, процессы
  /// ядра, приватная сеть) остаётся direct — иначе туннель не поднимется.
  final bool noRealIp;

  /// Туннель создаёт платформа (Android `VpnService`), а не ядро.
  ///
  /// Меняет три вещи, каждая из которых иначе валит подключение:
  ///  * из TUN-инбаунда уходят `interface_name`, `auto_route`, `strict_route`
  ///    и `stack` — интерфейсом владеет система, ядро эти поля для
  ///    платформенного туннеля не принимает;
  ///  * появляются `include_package`/`exclude_package` — способ развести
  ///    приложения на Android (аналога process_name там нет);
  ///  * правила по именам процессов Windows не пишутся вовсе: `xray.exe` на
  ///    Android не совпадёт ни с чем.
  final bool platformTun;

  /// Пакет самого приложения — обязан идти мимо туннеля, иначе загрузка
  /// подписки и пинг уходят в собственный VPN (петля и ложные цифры).
  final String selfPackage;

  /// Файл, куда ядро пишет СВОЙ лог (`log.output`).
  ///
  /// ⚠️ Нужен на Android. Там ядро — библиотека в нашем же процессе, стандартный
  /// вывод перехватить нечем: `Libbox.redirectStderr` ловит ТОЛЬКО паники Go, а
  /// структурный лог sing-box туда не попадает. Живой запуск это подтвердил:
  /// при уровне `debug` файл оставался нулевого размера, и причину «туннель
  /// поднят, но трафика нет» посмотреть было негде.
  /// На Windows не нужен: там ядро — отдельный процесс, и его stdout читает
  /// `SingboxProcess`.
  final String? logOutput;

  /// Порт локальной страницы «сайт заблокирован». 0 — заглушки нет.
  ///

  /// Порт Clash API — счётчики трафика туннеля. 0 — не поднимать.
  ///
  /// ⚠️ Нужен на Android: там ядро — библиотека в нашем процессе, и другого
  /// способа узнать, сколько прошло через туннель, нет. Без него счётчик под
  /// кнопкой стоял на нуле, что бы ни происходило.
  ///
  /// ⚠️ `secret` ОБЯЗАТЕЛЕН. Без него sing-box пускает кого угодно и отдаёт
  /// метаданные соединений с CORS `*`: на телефоне этот порт видит любое
  /// приложение, а в браузере — любая открытая страница.
  final int clashApiPort;
  final String clashApiSecret;

  /// Отказывать в QUIC (UDP:443), возвращая браузеры на TLS поверх TCP.
  final bool blockQuic;

  /// Отказывать в DNS поверх HTTPS/TLS/QUIC, возвращая резолв под наш перехват.
  final bool blockEncryptedDns;

  /// Весь ли DNS вести через туннель.
  ///
  /// Имеет смысл только в режиме «только отмеченные»: там база трафика —
  /// `direct`, и вопрос «а куда девать DNS остальных приложений» становится
  /// содержательным. См. развёрнутое объяснение у `dns.final`.
  final bool tunnelDnsForAll;

  /// Туннель-заглушка для kill switch: маршруты на месте, весь трафик в reject.
  ///
  /// Нужен между попытками переподключения. Погасить ядро, оставив дескриптор,
  /// на Android нельзя — им владеет libbox, — поэтому «удержание захвата»
  /// делается перезагрузкой ядра вот таким конфигом: интерфейс не пересоздаётся
  /// (адреса, MTU и списки пакетов те же), а выхода наружу нет.
  final bool blackhole;

  /// Резолвер для доменов «Прямо» — ЯВНЫМ адресом (обычно DNS физического
  /// адаптера, снятый до подъёма туннеля).
  ///
  /// ⚠️ Почему нельзя оставлять `address: "local"`. На Windows это
  /// `getaddrinfo` → служба DNS-клиента → пакет уходит в TUN → попадает под
  /// `hijack-dns` → снова приходит в `dns-local`. Домен «Прямо» не резолвится
  /// вовсе: в логе `lookup <домен>: i/o timeout`, затем `name error`.
  /// Подтверждено живым тестом: сайт «Туннель» открывался, «Блок» блокировался,
  /// а «Прямо» — не открывался НИКАК. `detour: direct` тут не помогает:
  /// транспорт `local` вообще не дозванивается через outbound.
  /// Пусто → прежнее поведение (`local`).
  final String? directDnsUpstream;

  const TunOptions({
    this.stack,
    this.mtu = 1500,
    this.strictRoute = true,
    this.ipv6 = true,
    this.ipv6Upstream = true,
    this.endpointIndependentNat = true,
    this.bypassLan = true,
    this.excludeCidrs = const [],
    this.routeOnlyCidrs = const [],
    this.dnsMode = DnsMode.vpn,
    this.dnsServer = '1.1.1.1',
    this.dnsHijack = true,
    this.dnsStrategy = DnsStrategy.preferIpv4,
    this.logLevel = 'warn',
    this.serverIps = const [],
    this.serverDomains = const [],
    this.fallbackDnsPort = 0,
    this.blockNotice = false,
    this.autotune = false,
    this.noRealIp = false,
    this.platformTun = false,
    this.selfPackage = 'lol.silentgate',
    this.directDnsUpstream,
    this.logOutput,
    this.blackhole = false,
    // ⚠️ УМОЛЧАНИЕ ОБЯЗАНО СОВПАДАТЬ С `AppSettings.tunnelDnsForAll` (false).
    // Пока здесь стояло `true`, ручные дампы и тесты показывали безобидный
    // `dns-proxy`, а пользователь получал `dns-local` — то есть проверяли одно,
    // а работало другое.
    this.tunnelDnsForAll = false,
    this.clashApiPort = 0,
    this.clashApiSecret = '',
    this.blockQuic = false,
    this.blockEncryptedDns = false,
  });

  factory TunOptions.fromSettings(
    AppSettings s, {
    List<String> serverIps = const [],
    List<String> serverDomains = const [],
    int fallbackDnsPort = 0,
    bool blockNotice = false,
    bool android = false,
    String? directDnsUpstream,
    String? logOutput,
    int clashApiPort = 0,
    String clashApiSecret = '',
    bool ipv6Available = true,
  }) {
    return TunOptions(
      clashApiPort: clashApiPort,
      clashApiSecret: clashApiSecret,
      blockQuic: s.blockQuic,
      blockEncryptedDns: s.blockEncryptedDns,
      platformTun: android,
      directDnsUpstream: directDnsUpstream,
      logOutput: logOutput,
      stack: s.tunStack.singboxValue,
      mtu: s.tunMtu,
      strictRoute: s.tunStrictRoute,
      // ⚠️ IPv6 в туннеле включается, только если он есть НАРУЖУ.
      //
      // Иначе туннель объявляет себя IPv6-способным, приложения получают AAAA и
      // идут по IPv6, а ядро упирается в «unreachable network» на каждом
      // двустековом сайте. Снаружи это выглядит как «всё зависает, хотя блока
      // нет»: страницы открываются через секунды или не открываются вовсе.
      // Проверено живьём в VM без IPv6 — настоящий браузер получал
      // ERR_CONNECTION_RESET, а с выключенным IPv6 грузил страницу.
      ipv6: s.tunIpv6 && ipv6Available,
      ipv6Upstream: ipv6Available,
      endpointIndependentNat: s.tunEndpointIndependentNat,
      bypassLan: s.tunBypassLan,
      excludeCidrs: s.tunExcludeCidrs,
      routeOnlyCidrs: s.tunRouteOnlyCidrs,
      dnsMode: s.dnsMode,
      dnsServer: s.dnsMode == DnsMode.custom ? s.dnsCustomServer : '1.1.1.1',
      blockNotice: s.blockNoticeEnabled,
      dnsHijack: s.dnsHijack,
      dnsStrategy: s.dnsStrategy,
      logLevel: s.singboxLogLevel.name,
      serverIps: serverIps,
      serverDomains: serverDomains,
      fallbackDnsPort: fallbackDnsPort,
      // «Авто» = подбирать стек/MTU перебором; явный выбор пользователя уважаем.
      autotune: s.tunStack == TunStack.auto,
      noRealIp: s.noRealIp,
      tunnelDnsForAll: s.tunnelDnsForAll,
    );
  }

  /// Те же опции, но туннель никуда не ведёт (kill switch).
  ///
  /// Именно копия ЖИВЫХ опций, а не свежие дефолты: интерфейс обязан совпасть
  /// поле в поле, иначе система пересоздаст его и на этот миг выпустит трафик
  /// мимо VPN.
  TunOptions asBlackhole() => TunOptions(
        stack: stack,
        mtu: mtu,
        strictRoute: strictRoute,
        ipv6: ipv6,
        // ⚠️ БЕЗ ЭТОГО ПОЛЯ ЗАГЛУШКА МЕНЯЛА АДРЕСА ИНТЕРФЕЙСА.
        //
        // `ipv6Upstream` решает, объявлять ли адрес `fdfe:dcba:9876::1/126`.
        // Умолчание — `true`, поэтому потерянное поле означало: живой туннель
        // без IPv6 объявляет один адрес, а заглушка kill switch — два. Система
        // видит другой интерфейс и пересоздаёт его, а это ровно тот миг, ради
        // закрытия которого заглушка и существует.
        ipv6Upstream: ipv6Upstream,
        endpointIndependentNat: endpointIndependentNat,
        bypassLan: bypassLan,
        excludeCidrs: excludeCidrs,
        routeOnlyCidrs: routeOnlyCidrs,
        dnsMode: dnsMode,
        dnsServer: dnsServer,
        dnsHijack: dnsHijack,
        dnsStrategy: dnsStrategy,
        tunnelDnsForAll: tunnelDnsForAll,
        logLevel: logLevel,
        serverIps: serverIps,
        serverDomains: serverDomains,
        fallbackDnsPort: fallbackDnsPort,
        blockNotice: blockNotice,
        autotune: autotune,
        noRealIp: noRealIp,
        platformTun: platformTun,
        selfPackage: selfPackage,
        directDnsUpstream: directDnsUpstream,
        logOutput: logOutput,
          clashApiPort: clashApiPort,
        clashApiSecret: clashApiSecret,
        blockQuic: blockQuic,
        blockEncryptedDns: blockEncryptedDns,
        blackhole: true,
      );

  /// Копия с другими стеком/MTU — для перебора в автоподборе.
  ///
  /// ⚠️ Любое новое поле обязано попасть сюда. Автоподбор стека/MTU — это
  /// ДЕФОЛТ (`tunStack: auto`), и он пересоздаёт опции на каждой комбинации:
  /// забытое поле молча исчезает именно у большинства пользователей.
  /// Так уже терялись `platformTun` и `selfPackage` — на Android это ломало
  /// весь платформенный туннель при первом же переборе.
  TunOptions copyWith({String? stack, int? mtu}) => TunOptions(
        stack: stack ?? this.stack,
        mtu: mtu ?? this.mtu,
        strictRoute: strictRoute,
        ipv6: ipv6,
        ipv6Upstream: ipv6Upstream,
        endpointIndependentNat: endpointIndependentNat,
        bypassLan: bypassLan,
        excludeCidrs: excludeCidrs,
        routeOnlyCidrs: routeOnlyCidrs,
        dnsMode: dnsMode,
        dnsServer: dnsServer,
        dnsHijack: dnsHijack,
        dnsStrategy: dnsStrategy,
        logLevel: logLevel,
        serverIps: serverIps,
        serverDomains: serverDomains,
        fallbackDnsPort: fallbackDnsPort,
        blockNotice: blockNotice,
        autotune: autotune,
        noRealIp: noRealIp,
        platformTun: platformTun,
        selfPackage: selfPackage,
        directDnsUpstream: directDnsUpstream,
        logOutput: logOutput,
        blackhole: blackhole,
        tunnelDnsForAll: tunnelDnsForAll,
        clashApiPort: clashApiPort,
        clashApiSecret: clashApiSecret,
        blockQuic: blockQuic,
        blockEncryptedDns: blockEncryptedDns,
      );
}

/// Имена известных публичных DoH-резолверов.
///
/// Список заведомо неполон и полным быть не может — свой DoH поднимается за
/// вечер. Он закрывает НАСТРОЙКИ ПО УМОЛЧАНИЮ браузеров и системы, то есть тот
/// случай, когда пользователь про DoH даже не знает. Против сознательного
/// обхода это не защита, и обещать её нельзя.
const _dohHosts = <String>[
  'dns.google',
  'dns.google.com',
  'cloudflare-dns.com',
  'mozilla.cloudflare-dns.com',
  'one.one.one.one',
  'chrome.cloudflare-dns.com',
  'dns.quad9.net',
  'dns9.quad9.net',
  'dns.nextdns.io',
  'doh.opendns.com',
  'dns.adguard.com',
  'dns.adguard-dns.com',
  'doh.cleanbrowsing.org',
  'dns.sb',
  'doh.dns.sb',
  'dns.alidns.com',
  'doh.pub',
  'dot.pub',
  'dns.yandex.ru',
  'common.dot.dns.yandex.net',
];

/// Адреса тех же резолверов: браузер умеет ходить к ним по голому IP.
const _dohIps = <String>[
  '8.8.8.8/32',
  '8.8.4.4/32',
  '1.1.1.1/32',
  '1.0.0.1/32',
  '9.9.9.9/32',
  '149.112.112.112/32',
  '94.140.14.14/32',
  '94.140.15.15/32',
  '208.67.222.222/32',
  '208.67.220.220/32',
  '77.88.8.8/32',
  '77.88.8.1/32',
  '2001:4860:4860::8888/128',
  '2606:4700:4700::1111/128',
  '2620:fe::fe/128',
];

/// Строит конфиг sing-box для TUN-режима: sing-box держит TUN (wintun) и маршрутизацию
/// (по приложениям через process_*, по доменам через domain_suffix), а прокси-трафик
/// уходит в Xray через socks-outbound на локальный SOCKS Xray. Модель Happ.
///
/// Защита от петли — в три эшелона (по убыванию надёжности):
///   1. IP VPN-серверов → direct (не зависит от матчинга процессов);
///   2. собственные процессы ядра (xray/sing-box/silentgate) → direct;
///   3. приватные адреса → direct.
class SingboxConfigBuilder {
  final int xraySocksPort;

  /// Креды локального SOCKS соседнего Xray (Android). Пусто — без пароля.
  final String xraySocksUser;
  final String xraySocksPassword;

  /// Порт инбаунда `probe-in` — того, через который ходят сервис-чипы и проба
  /// активного сервера.
  ///
  /// ⚠️ ОТДЕЛЬНЫЙ от 10809. Когда поднимается панельный профиль «Авто», рядом
  /// стартует Xray, и его конфиг нормализуется так, что http-inbound встаёт
  /// РОВНО на 10809. Xray стартует первым и занимает порт; после этого
  /// `probe-in` не может забиндиться, а это фатально — ядро не запускается
  /// вовсе, и панельные профили не поднимаются НИКОГДА. 0 — не создавать.
  final int probePort;

  /// ⚠️ ЛОГИН/ПАРОЛЬ НА ПОРТ ПРОБ — ЭТО НЕ ПЕРЕСТРАХОВКА.
  ///
  /// Loopback на Android НЕ изолирован между приложениями: к `127.0.0.1:10811`
  /// подключается любое установленное приложение. А правило `probe-in → proxy`
  /// стоит ВЫШЕ пользовательских, в том числе выше блок-правил. То есть чужое
  /// приложение получало наш VPN целиком: выходной IP, квоту подписки и обход
  /// раздельного туннелирования — включая приложение, которому пользователь
  /// явно поставил «Блок».
  ///
  /// Дыра отраслевая (v2rayNG #5467, Hiddify #2120, FlClash #1934 — везде
  /// закрыто «not planned»), единственная реализованная починка в природе —
  /// amnezia-client PR #2453. Оттуда же правило: креды живут ТОЛЬКО в памяти,
  /// на диск и в логи не попадают.
  ///
  /// Пусто — инбаунд без аутентификации (Windows: там в него ходит системный
  /// прокси, а WinINET креденшелов не несёт).
  final String probeUser;
  final String probePassword;

  final TunOptions options;

  /// Готовый прокси-outbound вместо перехода в локальный SOCKS.
  ///
  /// Windows: `null` — туннель заворачивает трафик в SOCKS, где его принимает
  /// отдельный процесс Xray (или sing-box для hysteria2).
  /// Android: сюда кладётся outbound сервера, и ядро одно — оно держит и
  /// туннель, и само соединение. Причина в том, что две gomobile-библиотеки
  /// в одном приложении конфликтуют общим Go-рантаймом.
  final Map<String, dynamic>? proxyOutbound;

  /// Готовая ГРУППА outbound'ов — для «Авто (лучший сервер)» на Android.
  ///
  /// Автовыбор — это не один узел, а набор плюс `urltest`, который меряет их
  /// и переключается на быстрый. Тег `proxy` внутри группы уже проставлен
  /// базой (`buildSingboxJson`), поэтому список кладётся как есть.
  ///
  /// ⚠️ Без этого на Android автовыбор сводился к ПЕРВОМУ серверу списка:
  /// движок брал `servers.first` и выбрасывал собранный базой конфиг.
  final List<Map<String, dynamic>>? proxyOutboundGroup;

  /// Готовые outbound-ы дополнительных серверов — С УЖЕ ПРОСТАВЛЕННЫМИ тегами
  /// (см. [exitTagFor]).
  ///
  /// ⚠️ ЭТОТ СПИСОК — ЕДИНСТВЕННЫЙ ИСТОЧНИК ПРАВДЫ О ТОМ, КАКИЕ ВЫХОДЫ ЖИВЫ.
  /// Правило ссылается на выход по идентификатору, но тег в конфиг попадёт
  /// ТОЛЬКО если здесь есть outbound с таким тегом (см. [_liveExitIds]).
  /// Иначе получился бы висячий тег, а `sing-box check` его НЕ ловит: конфиг
  /// со ссылкой на несуществующий outbound принимается с кодом 0 и без единой
  /// строчки вывода — проверено настоящим ядром 1.11.15. Трафик такого правила
  /// молча уехал бы в `route.final`, то есть мимо выхода, который пользователь
  /// выбрал.
  final List<Map<String, dynamic>> exitOutbounds;

  /// Ключи серверов, которым выдаётся отдельный локальный порт (см. `ApiPorts`).
  final List<String> apiExitServerKeys;

  /// Ключи серверов, чей outbound собран ТОЛЬКО ради порта API. Правилам
  /// раздельного туннелирования эти теги НЕ видны.
  ///
  /// ⚠️ ЭТО НЕ ПРИДИРКА, А РЕГРЕССИЯ, КОТОРУЮ ЗДЕСЬ ЛЕЧАТ. Порт API для
  /// АКТИВНОГО сервера потребовал собрать ему собственный outbound (без него
  /// инбаунд не создавался, а `/v1/exits` порт публиковал). Но `exitOutbounds`
  /// — единственный источник правды о живых тегах, и правило «сайт через
  /// сервер X», где X и есть активный сервер, внезапно перестало идти тегом
  /// `proxy` и завело ВТОРОЕ соединение к тому же узлу: панель показывает
  /// удвоенный «онлайн», а сам канал — реконструкция sing-box из разобранных
  /// полей, а не панельный outbound Xray, то есть ведёт себя иначе основного.
  ///
  /// Поэтому источников два, и разводятся они здесь: тег в конфиге ЕСТЬ (порт
  /// работает), а для правил его как будто нет — они падают в `proxy`, ровно
  /// как до появления портов.
  final List<String> apiOnlyExitKeys;

  /// Токен API — он же пароль этих инбаундов. Пусто — инбаунды не создаются.
  final String apiToken;

  const SingboxConfigBuilder({
    this.xraySocksPort = 10808,
    this.xraySocksUser = '',
    this.xraySocksPassword = '',
    this.probePort = 0,
    this.probeUser = '',
    this.probePassword = '',
    this.options = const TunOptions(),
    this.proxyOutbound,
    this.proxyOutboundGroup,
    this.exitOutbounds = const [],
    this.apiExitServerKeys = const [],
    this.apiOnlyExitKeys = const [],
    this.apiToken = '',
  });

  // ── Правила, идущие через ОТДЕЛЬНЫЙ сервер ────────────────────────────────

  /// Теги, которые реально есть в конфиге.
  ///
  /// ⚠️ ЭТО ЕДИНСТВЕННЫЙ ИСТОЧНИК ПРАВДЫ. Правило ссылается на сервер по ключу,
  /// но тег попадёт в конфиг ТОЛЬКО если для него собран outbound. Сервер могли
  /// удалить из подписки, а его протокол может не подниматься вторым туннелем —
  /// оба случая обязаны привести к ОСНОВНОМУ туннелю, а не к висячему тегу:
  /// висячий `sing-box check` пропускает молча, и трафик уходит в `route.final`.
  Set<String> get _liveExitTags => {
        for (final o in exitOutbounds)
          if (o['tag'] is String) o['tag'] as String,
      };

  /// Теги, которыми разрешено пользоваться ПРАВИЛАМ раздельного
  /// туннелирования: живые минус собранные только ради порта API.
  ///
  /// ⚠️ РАЗНИЦА МЕЖДУ ЭТИМ НАБОРОМ И [_liveExitTags] — ЭТО РОВНО АКТИВНЫЙ
  /// СЕРВЕР. Он получает свой outbound ради порта API, но правило «через него»
  /// обязано остаться на теге `proxy`: второй канал к тому же узлу даёт панели
  /// удвоенный «онлайн» и идёт мимо панельного outbound'а Xray. Подробности —
  /// у поля [apiOnlyExitKeys].
  ///
  /// ⚠️ Инбаунды портов (`_apiExitInbounds`) и DNS-резолверы выходов считаются
  /// по-прежнему от [_liveExitTags]: порт обязан работать, а его резолвер —
  /// ходить тем же сервером.
  Set<String> get _ruleExitTags => _liveExitTags.difference({
        for (final k in apiOnlyExitKeys) exitTagFor(k),
      });

  /// Инбаунды отдельных портов: по одному на сервер из [apiExitServerKeys].
  ///
  /// ⚠️ ТОЛЬКО ЖИВЫЕ. Сервер, чей outbound не собрался, порта не получает —
  /// иначе правило сослалось бы на несуществующий тег, `sing-box check`
  /// пропустил бы это молча, и трафик скрипта ушёл бы в `route.final`, то есть
  /// мимо выбранного сервера. Источник правды — `_liveExitTags`.
  ///
  /// Сама сборка — в [buildApiExitInbounds] (`core/net/api_ports.dart`): ей же
  /// пользуется `ExitRouterConfigBuilder` (задача 3b, режим «Только прокси»).
  /// Разводить копии этой логики по двум файлам нельзя — разъедутся на первой
  /// же правке.
  List<Map<String, dynamic>> get _apiExitInbounds => buildApiExitInbounds(
        serverKeys: apiExitServerKeys,
        token: apiToken,
        liveExitTags: _liveExitTags,
      );

  /// Правила «этот порт — в этот сервер». Сборка — в [buildApiExitRules].
  List<Map<String, dynamic>> get _apiExitRules =>
      buildApiExitRules(_apiExitInbounds);

  /// Инбаунд порта «Прямо» — тот же гейт (пустой токен), но НЕ зависит от
  /// [apiExitServerKeys]/[exitOutbounds]: ведёт во встроенный `direct`,
  /// который есть в конфиге безусловно. Сборка — в [buildApiDirectInbound]
  /// (`core/net/api_ports.dart`), общая с [ExitRouterConfigBuilder].
  List<Map<String, dynamic>> get _apiDirectInbound =>
      buildApiDirectInbound(token: apiToken);

  /// Правило «порт «Прямо» → outbound `direct`». Сборка — в [buildApiDirectRule].
  List<Map<String, dynamic>> get _apiDirectRule =>
      buildApiDirectRule(_apiDirectInbound);

  /// «Блок» ПРИМЕНЯЕТСЯ и к трафику, пришедшему в порт конкретного сервера —
  /// иначе служебный вход стал бы способом обойти собственные запреты
  /// пользователя.
  ///
  /// ⚠️ ПОЗИЦИЯ ОБЯЗАТЕЛЬНА: этот guard и [_apiExitRules] стоят ВЫШЕ
  /// `_addSitePriorityRules`/`_addBlockRules`/`_addAppRules`. Те правила
  /// матчатся по домену/процессу БЕЗ привязки к `inbound` и несут не только
  /// «Блок», но и «Туннель через другой сервер»/«Прямо» — то есть запрос,
  /// пришедший в порт сервера X, мог бы молча уехать на другой выход, хотя
  /// вызывающий выбрал X явно, самим фактом обращения к порту. Инвариант
  /// «порт X → сервер X» обязан держаться БЕЗ исключений, кроме одного —
  /// блокировки пользователя, и она обязана сработать РАНЬШЕ маршрута на
  /// выход, иначе служебный вход обошёл бы собственный запрет пользователя.
  ///
  /// Гейт `_userRulesActive` — тот же, что у [_addBlockRules]: в режиме «Всё
  /// через VPN» пользовательских правил, включая блок, нет вовсе (они лежат
  /// сохранёнными, но не входят в конфиг), и здесь блокировать было бы нечему.
  void _addApiExitBlockGuard(
      List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    if (!_userRulesActive(split)) return;
    // Порт «Прямо» — ТОТ ЖЕ служебный вход, что и порты серверов: его тег
    // идёт в один общий список, и блок режет трафик независимо от того, в
    // какой из портов API он пришёл.
    final tags = [
      for (final i in _apiExitInbounds) '${i['tag']}',
      for (final i in _apiDirectInbound) '${i['tag']}',
    ];
    if (tags.isEmpty) return;
    // Сборка — в общем [apiExitBlockGuardRules] (задача 3b пользуется тем же).
    rules.addAll(apiExitBlockGuardRules(
      split: split,
      inboundTags: tags,
      platformTun: options.platformTun,
    ));
  }

  /// Тег сервера-адресата для правила, либо `null` — «основной туннель».
  ///
  /// ⚠️ Смысл ТОЛЬКО у действия «Туннель». «Прямо через Германию» —
  /// противоречие: прямо значит мимо всех туннелей, а «блок через Германию»
  /// и вовсе ничего не значит. Возвращая здесь `null`, мы не даём появиться
  /// классу правил, которые видно в интерфейсе и которые ничего не делают.
  String? _exitTagFor(String? serverKey, AppAction action) {
    if (action != AppAction.tunnel) return null;
    if (serverKey == null || serverKey.isEmpty) return null;
    final tag = exitTagFor(serverKey);
    // ⚠️ ИМЕННО [_ruleExitTags], А НЕ [_liveExitTags]: outbound активного
    // сервера живёт в конфиге ради порта API, но правилам он не адресат —
    // они идут тем же узлом через `proxy`. См. [apiOnlyExitKeys].
    return _ruleExitTags.contains(tag) ? tag : null;
  }

  /// Резолвер, соответствующий выходу маршрута. `null` → домен не резолвится.
  ///
  /// ⚠️ ЗДЕСЬ БЫЛО СРАВНЕНИЕ С ЛИТЕРАЛОМ (`outbound == 'proxy' ? 'dns-proxy'
  /// : 'dns-local'`). С появлением тегов `exit-<id>` оно давало `false` для
  /// КАЖДОГО выхода, и сайт «через Германию» молча уезжал резолвиться
  /// локальным резолвером — то есть провайдеру, ещё до соединения. Конфиг при
  /// этом валиден, ядро молчит, в интерфейсе всё правильно. Один из тех
  /// дефектов, которые не ловит ни компилятор, ни `check`.
  String? _dnsServerForOutbound(String? outbound) {
    if (outbound == null) return null;
    if (outbound == 'direct') return 'dns-local';
    if (outbound == 'proxy') return 'dns-proxy';
    // Тег выхода → его же резолвер. Соответствие держится на общем префиксе,
    // заданном в exit_tags.dart, и проверяется тестом.
    if (_liveExitTags.contains(outbound)) return 'dns-$outbound';
    // Неизвестный тег — резолвим через туннель. Локальный резолвер тут был бы
    // худшим из вариантов: это утечка, а не деградация.
    return 'dns-proxy';
  }

  /// Разложить правила по адресату: у правила ядра ровно ОДИН выход, поэтому
  /// сайты «через Германию» и «через США» обязаны разъехаться по разным
  /// правилам, даже когда действие у них одинаковое («Туннель»).
  ///
  /// Порядок групп детерминирован: без сортировки конфиг «дышал» бы между
  /// сборками, и сравнение готового конфига в тестах перестало бы работать.
  static List<MapEntry<String?, List<T>>> _byOutbound<T>(
      Iterable<T> items, String? Function(T) outboundOf) {
    final groups = <String?, List<T>>{};
    for (final it in items) {
      groups.putIfAbsent(outboundOf(it), () => []).add(it);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => (a ?? '').compareTo(b ?? ''));
    return [for (final k in keys) MapEntry(k, groups[k]!)];
  }

  String buildJson(SplitTunnelConfig split) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(split));

  Map<String, dynamic> buildMap(SplitTunnelConfig split) {
    final o = options;
    if (o.blackhole) return _blackholeMap(split);

    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      // ⚠️ ПОРЯДОК: loop-protection стоит ВЫШЕ перехвата DNS.
      //
      // Раньше `hijack-dns` был первым, и под него попадал в том числе DNS
      // НАШИХ ЖЕ ядер. Отсюда два подтверждённых живым тестом отказа:
      //  * прокси-ядро (hysteria2) не могло отрезолвить адрес своего сервера —
      //    запрос уходил в туннель и возвращался в это же ядро (взаимный
      //    дедлок: `lookup <сервер>: i/o timeout` в одном логе и
      //    `dns: exchange failed … EOF` в другом, секунда в секунду);
      //  * домен, помеченный «Прямо», не резолвился вовсе — `dns-local`
      //    закольцовывался на системный резолвер через тот же перехват.
      // Ценой этого DNS самих ядер идёт мимо туннеля — но именно это и значит
      // «прямо», а системный DNS остальных приложений перехватывается как был.
      //
      // 1-й эшелон: сам VPN-сервер.
      if (o.serverIps.isNotEmpty)
        _route({'ip_cidr': [for (final ip in o.serverIps) _asCidr(ip)]}, 'direct'),
      // 2-й эшелон: процессы ядра. На Android имён процессов нет — там свой
      // пакет уже исключён из туннеля на уровне ОС (exclude_package), а
      // process_name со значением 'xray.exe' не совпал бы ни с чем.
      if (!o.platformTun)
        _route({
          'process_name': ['xray.exe', 'sing-box.exe', 'silentgate.exe'],
        }, 'direct'),
      // ⚠️ Перехват DNS нужен ВСЕГДА, включая режим «системный».
      //
      // Раньше здесь стояло `&& o.dnsMode != DnsMode.system`, и в системном
      // режиме правила не было. Но туннель объявляет себя DNS-сервером
      // адаптера в любом режиме, поэтому запросы всё равно шли внутрь — и,
      // не перехваченные, попадали под «приватные адреса → напрямую», где
      // ядро пыталось честно отправить их на 172.19.0.2, где никто не слушает.
      // Результат: ни одно имя не резолвится, а сеть выглядит живой.
      if (o.dnsHijack)
        // Перехват UDP:53 — без него DNS уходит в final и «интернет пропадает»,
        // если UDP до сервера не проксируется.
        {'protocol': 'dns', 'action': 'hijack-dns'},
    ];

    // ── Закрытие обходных путей ────────────────────────────────────────────
    //
    // Оба правила стоят НИЖЕ защиты от петли (IP сервера и свои процессы уже
    // ушли в direct выше) и ВЫШЕ пользовательских. Порядок здесь не вкусовой: у
    // hysteria2 транспорт — QUIC на UDP:443, и запрет выше строки с IP сервера
    // убил бы собственное подключение целиком.
    if (!o.ipv6) {
      // ⚠️ Выключенный IPv6 в туннеле — это НЕ «IPv6 не используется», а
      // «IPv6 не захватывается». Интерфейс без inet6-адреса просто не получает
      // такой трафик, и тот уходит через физический адаптер — под реальным
      // адресом, мимо всех правил. На двустековой сети это половина запросов к
      // крупным сайтам.
      //
      // Поэтому вместо «не трогаем» — отказ. Сайты от этого не ломаются:
      // не получив IPv6, они переходят на IPv4, который идёт в туннель.
      //
      // Правило стоит НИЖЕ адреса сервера по той же причине, что и запрет QUIC:
      // сервер может быть доступен по IPv6, и наверху это отрезало бы само
      // подключение.
      // Отказ нужен ТОЛЬКО когда туннель объявил IPv6-адрес: тогда система
      // считает IPv6 рабочим и будет пробовать. Если адреса нет, отказывать
      // нечему — и правило превращалось в отказ службам Windows на ровном
      // месте (видно в логе владельца: svchost, ipv6.msftconnecttest.com).
      if (o.ipv6Upstream) {
        rules.add({'ip_version': 6, 'action': 'reject'});
      }
    }
    if (o.blockQuic || _needQuicBlock(split)) {
      // Доменные правила («Прямо», «Туннель», «Блок») применяются к ИМЕНИ, а имя
      // берётся из сниффинга. Браузер, ушедший на HTTP/3, имени не оставляет —
      // правило по домену молча не срабатывает, и пользователь видит, что
      // настройка «не работает». Отказ по UDP:443 возвращает браузер на TLS
      // поверх TCP, где имя видно; сайты от этого не ломаются — HTTP/3 для них
      // не обязателен, это оптимизация.
      //
      // ⚠️ Тумблер `blockQuic` — ЯВНОЕ желание пользователя, он глобальный.
      // Автоматический же запрет (от правил по сайтам) ограничен ИМЕННО теми
      // доменами, ради которых он включился: глобальный вариант рубил HTTP/3
      // всей машине, и это выглядело как «интернет пропал», а не как «правило
      // заработало».
      if (o.blockQuic) {
        rules.add({'network': 'udp', 'port': [443], 'action': 'reject'});
      } else {
        final domains = _quicBlockDomains(split);
        if (domains.isNotEmpty) {
          rules.add({
            'domain_suffix': domains,
            'network': 'udp',
            'port': [443],
            'action': 'reject',
          });
        }
      }
    }
    if (o.blockEncryptedDns) {
      // DNS поверх HTTPS/TLS/QUIC уходит мимо перехвата UDP:53. Тогда DNS-зеркало
      // split-правил не работает вовсе: домен «Прямо» резолвится через туннель,
      // домен «Блок» на DNS не режется.
      rules.add({'network': 'tcp', 'port': [853], 'action': 'reject'}); // DoT
      rules.add({'network': 'udp', 'port': [853], 'action': 'reject'}); // DoQ
      rules.add({'domain_suffix': _dohHosts, 'port': [443], 'action': 'reject'});
      // Браузер может пойти к резолверу по голому IP, минуя имя.
      rules.add({'ip_cidr': _dohIps, 'port': [443], 'action': 'reject'});
    }

    // Проба обязана идти ЧЕРЕЗ VPN. Без этого правила в режиме «только
    // выбранные» база — `direct` (наш пакет в include-список не попадает), и
    // сервис-чипы показывали бы зелёное по ПРЯМОМУ соединению при живом
    // туннеле. Ставим выше пользовательских правил: чужое «Прямо» не должно
    // перехватывать измерение.
    if (o.platformTun && probePort > 0) {
      rules.add({
        'inbound': ['probe-in'],
        'action': 'route',
        'outbound': 'proxy',
      });
    }

    // API: порт X → сервер X, порт «Прямо» → direct, БЕЗ ИСКЛЮЧЕНИЙ, кроме
    // блокировки пользователя.
    //
    // ⚠️ ОБЯЗАНЫ стоять ВЫШЕ _addSitePriorityRules/_addBlockRules/_addAppRules:
    // те правила матчат по домену/процессу БЕЗ привязки к inbound, и несут не
    // только «Блок», но и «Туннель через другой сервер»/«Прямо» — запрос,
    // пришедший в порт сервера X (или в порт «Прямо»), мог бы молча уехать на
    // другой выход, хотя вызывающий выбрал адресата явно, самим фактом
    // обращения к порту. Guard идёт ПЕРВЫМ (блок обязан сработать раньше
    // маршрута на выход), сами маршруты — сразу за ним; ниже них сайты/
    // приложения эти inbound-ы уже не увидят.
    _addApiExitBlockGuard(rules, split);
    rules.addAll(_apiExitRules);
    rules.addAll(_apiDirectRule);

    // #3 — явный БЛОК ставим ВЫШЕ bypassLan/excludeCidr: блокировка домена должна
    // побеждать удобные direct-исключения (иначе заблокированный домен, чей IP
    // попал в приватный диапазон или в excludeCidr, молча уходил бы напрямую).
    // Заглушка вместо «соединение сброшено»: http-порт заблокированного
    // домена уводим на локальную страницу с объяснением. Ставим ВЫШЕ обычного
    // блока — иначе reject сработает первым и объяснять будет нечему.
    //
    // ⚠️ Только 80. Для 443 подмены нет и быть не может без своего корневого
    // сертификата, поэтому https-запрос к тому же домену честно отвергается
    // правилом ниже. Обещать пользователю заглушку на https нельзя.

    // Выше блока намеренно: конфликт «родитель заблокирован, поддомен в
    // туннель» разрешается в пользу конкретного правила, как и все остальные.
    _addSitePriorityRules(rules, split);
    _addBlockRules(rules, split);
    if (o.bypassLan) rules.add(_route({'ip_is_private': true}, 'direct'));
    // Только ВАЛИДНЫЕ CIDR: один битый префикс (напр. «10.0.0.0/33») заставляет
    // sing-box отвергнуть ВЕСЬ конфиг, и туннель молча не поднимается.
    if (_validExcludeCidrs.isNotEmpty) {
      rules.add(_route({'ip_cidr': _validExcludeCidrs}, 'direct'));
    }

    // База: куда идёт всё, чему не задано действие вручную.
    //  all / exceptSelected → через VPN (proxy); onlySelected → напрямую.
    //
    final finalOutbound =
        split.mode == SplitMode.onlySelected ? 'direct' : 'proxy';
    _addAppRules(rules, split);
    // Режим «Всё через VPN»: сюда попадают ТОЛЬКО правила выбора выхода.
    _addExitOnlyRules(rules, split);

    final cfg = <String, dynamic>{
      'log': {
        'level': o.logLevel,
        'timestamp': true,
        if ((o.logOutput ?? '').isNotEmpty) 'output': o.logOutput,
      },
      // Счётчики трафика туннеля. У sing-box нет `statsquery`, зато есть Clash
      // API — тот же источник, из которого читает Windows-сборка.
      //
      // ⚠️ Без `secret` ядро пускает кого угодно и отдаёт метаданные соединений
      // с CORS `*`. На телефоне этот порт виден любому приложению, поэтому
      // пароль на сессию обязателен, а не желателен.
      if (o.clashApiPort > 0)
        'experimental': {
          'clash_api': {
            'external_controller': '127.0.0.1:${o.clashApiPort}',
            if (o.clashApiSecret.isNotEmpty) 'secret': o.clashApiSecret,
          },
        },
      'inbounds': [
        _tunInbound(split),
        // Локальный http-прокси на Android. Ядро здесь ОДНО и держит только
        // TUN, поэтому порта 10809 в системе не было вовсе — а на него ходят
        // сервис-чипы у кнопки Connect (`ProxyProbe`). Итог: сразу после
        // успешного подключения пользователь видел три красных чипа при
        // полностью рабочем VPN.
        //
        // Слушаем только петлю: наружу порт не выставляется. Трафик пробы
        // уходит тем же путём, что и весь остальной, — значит чип показывает
        // ФАКТИЧЕСКОЕ состояние канала, а не отдельную проверку.
        if (o.platformTun && probePort > 0)
          {
            'type': 'mixed',
            'tag': 'probe-in',
            'listen': '127.0.0.1',
            'listen_port': probePort,
            // Без users инбаунд открыт любому приложению устройства — см.
            // комментарий у probeUser.
            if (probeUser.isNotEmpty)
              'users': [
                {'username': probeUser, 'password': probePassword},
              ],
          },
        ..._apiExitInbounds,
        ..._apiDirectInbound,
      ],
      'outbounds': [
        // Тег 'proxy' обязан сохраниться: на него ссылаются ВСЕ правила
        // маршрутизации ниже, включая noRealIp и реврайт direct→VPN.
        //
        // Три случая: группа узлов (автовыбор `urltest` — там тег `proxy`
        // уже есть внутри), один готовый outbound, либо переход в локальный
        // SOCKS соседнего Xray.
        if (proxyOutboundGroup != null)
          ...proxyOutboundGroup!
        else if (proxyOutbound != null)
          {...proxyOutbound!, 'tag': 'proxy'}
        else
          {
            'type': 'socks',
            'tag': 'proxy',
            'server': '127.0.0.1',
            'server_port': xraySocksPort,
            'version': '5',
            // Пароль локального инбаунда Xray. Разойдись он с тем, что стоит на
            // инбаунде, — туннель поднимется, а трафик встанет: ровно та
            // поломка, которую словил v2rayNG (#5549).
            if (xraySocksUser.isNotEmpty) ...{
              'username': xraySocksUser,
              'password': xraySocksPassword,
            },
          },
        // Именованные выходы мульти-VPN. Приходят готовыми и с тегами — здесь
        // только раскладываются рядом с `proxy`.
        ...exitOutbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': finalOutbound,
        'rules': rules,
      },
    };

    final dns = _buildDns(finalOutbound, split);
    if (dns != null) cfg['dns'] = dns;
    return cfg;
  }

  /// DNS-секция. Без неё запросы идут от svchost.exe в `final` и режут интернет,
  /// когда UDP до сервера не проксируется (частый случай VLESS+Vision).
  Map<String, dynamic>? _buildDns(String finalOutbound, SplitTunnelConfig split) {
    final o = options;
    // ⚠️ РЕЖИМ «СИСТЕМНЫЙ» НЕ ОЗНАЧАЕТ «НЕ ТРОГАТЬ DNS» — под туннелем такого
    // выбора вообще нет.
    //
    // Раньше здесь стоял `return null`: конфиг оставался без DNS-секции, а
    // правило перехвата не добавлялось. Но туннель ВСЁ РАВНО объявляет себя
    // DNS-сервером адаптера (172.19.0.2 / fdfe:dcba:9876::2) — иначе система не
    // знала бы, куда слать запросы. Получалось, что запросы летят на адрес, где
    // никто не слушает: в логе ядра `sniffed packet protocol: dns` →
    // `ip_is_private=true => route(direct)` → `write udp …->[fdfe:dcba:9876::2]:53:
    // wsasendto: An invalid argument was supplied`.
    //
    // Ни одно имя не резолвится, при этом сеть формально «есть»: пакеты уходят,
    // маршруты на месте, блокировки нет. Снаружи это выглядит ровно как жалоба
    // владельца — «соединение ложится, всё зависает, прямого блока нет».
    //
    // Поэтому в системном режиме секция строится, просто ВЕСЬ резолв идёт через
    // апстрим самой системы (`dns-local` = DNS физического адаптера, мимо
    // туннеля), а не через прокси.
    final systemMode = o.dnsMode == DnsMode.system;

    // Резолвер туннеля: по TCP через прокси — работает даже там, где UDP не ходит.
    // Хост чистим: пустой/битый `dnsServer` дал бы `tcp://` и отказ всего конфига.
    final servers = <Map<String, dynamic>>[
      {
        'tag': 'dns-proxy',
        'address': 'tcp://${_dnsHost(o.dnsServer)}',
        'address_resolver': 'dns-local',
        'strategy': o.dnsStrategy.singboxValue,
        'detour': 'proxy',
      },
      // Явный апстрим вместо `local`: см. TunOptions.directDnsUpstream —
      // системный резолвер под TUN закольцовывается на самого себя, и домены
      // «Прямо» не резолвятся вовсе.
      {
        'tag': 'dns-local',
        'address': (o.directDnsUpstream ?? '').isNotEmpty
            ? 'udp://${o.directDnsUpstream}'
            : 'local',
        'detour': 'direct',
      },
      // Резолвер с ЗАПАСОМ — наш локальный форвардер (см. TunOptions.fallbackDnsPort).
      //
      // `detour: direct` обязателен: иначе запрос к 127.0.0.1 завернулся бы
      // в туннель, форвардер спросил бы туннель ещё раз, и получилась бы петля
      // ровно там, где чинили её отсутствие.
      if (o.fallbackDnsPort > 0)
        {
          'tag': 'dns-fallback',
          'address': 'udp://127.0.0.1:${o.fallbackDnsPort}',
          'strategy': o.dnsStrategy.singboxValue,
          'detour': 'direct',
        },
      // ⚠️ ПО РЕЗОЛВЕРУ НА КАЖДЫЙ ВЫХОД — ЭТО НЕ УКРАШЕНИЕ.
      //
      // Резолв обязан идти ТЕМ ЖЕ выходом, что и трафик. Иначе «сайт через
      // Германию» спросит имя у резолвера общего туннеля, CDN ответит адресом
      // ближайшего к ТОМУ выходу фронта, и трафик пойдёт по немецкому маршруту
      // на американский сервер. У нас такой баг уже был в 1.0.1 — тогда между
      // «Прямо» и «Туннель».
      //
      // `detour` принимает СТРОКУ, а не массив: массив ядро отвергает целиком
      // (`cannot unmarshal array into Go value of type string`) — проверено
      // sing-box 1.11.15.
      for (final tag in _liveExitTags)
        {
          'tag': 'dns-$tag',
          'address': 'tcp://${_dnsHost(o.dnsServer)}',
          'address_resolver': 'dns-local',
          'strategy': o.dnsStrategy.singboxValue,
          'detour': tag,
        },
    ];

    // Доменные правила ЗЕРКАЛЯТСЯ из маршрутов. Без них весь DNS уходил в
    // dns-proxy (`final`), и сайт, помеченный «Прямо», резолвился резолвером
    // выходного узла: CDN отдавал адрес в стране VPN, а сам запрос всё равно
    // раскрывался провайдеру туннеля. Правило `outbound: direct` ниже в
    // TUN-режиме не срабатывает никогда (назначение из TUN — всегда IP, имя
    // берётся только из сниффинга), поэтому одного его недостаточно.
    final rules = <Map<String, dynamic>>[
      // ⚠️ ПЕРВЫМ И БЕЗУСЛОВНО: имена нашей же инфраструктуры резолвим только
      // напрямую. Иначе выходит замкнутый круг — чтобы дойти до сервера, нужен
      // его адрес, а адрес спрашивается через туннель, который к этому серверу
      // ещё не построен. Правило стоит выше пользовательских намеренно: домен
      // сервера, случайно попавший под правило «Туннель», убил бы подключение.
      if (o.serverDomains.isNotEmpty)
        {
          'domain_suffix': o.serverDomains,
          'server': 'dns-local',
        },
      // Блок — выше остальных: заблокированный домен не должен даже резолвиться.
      //
      // ⚠️ ИСКЛЮЧЕНИЕ: когда включена страница-заглушка, домен обязан
      // отрезолвиться, иначе браузер споткнётся ещё на DNS и до правила
      // маршрутизации дело не дойдёт — показывать будет нечего. Блокировку это
      // не ослабляет: http уводится на локальную страницу, https отвергается
      // маршрутным правилом.
      // Конфликтующие поддомены — теми же правилами и в том же порядке, что в
      // маршрутах. Разойдись зеркало с маршрутом хоть здесь — и сайт шёл бы в
      // туннель, а его имя спрашивалось бы у резолвера провайдера.
      ..._dnsSitePriorityRules(split),
      if (!o.blockNotice) ..._dnsSiteRules(split, AppAction.block, null),
      ..._dnsSiteRules(split, AppAction.direct, 'dns-local', allowRealIp: true),
      ..._dnsSiteRules(split, AppAction.tunnel, 'dns-proxy'),
      if (o.noRealIp)
        // Возвращённые под защиту — резолвим через туннель, иначе прямой
        // резолв выдал бы реальную геолокацию ещё до соединения.
        ..._dnsSiteRules(split, AppAction.direct, 'dns-proxy', allowRealIp: false),
      // ⚠️ ЗЕРКАЛО ДЛЯ ПРАВИЛ ПРИЛОЖЕНИЙ. Его не было вовсе — и это ломало
      // ровно то, ради чего включают VPN.
      //
      // Трафик отмеченного приложения уходил в `proxy`, а ИМЯ ему резолвил
      // провайдер вне туннеля: правил про приложения в секции DNS не
      // существовало, зеркалились только сайты. Для доменов, ради которых VPN
      // и нужен, провайдер отдаёт подменённый или пустой ответ, и приложение
      // честно шло через туннель на мёртвый адрес. Снаружи — «отмеченные
      // приложения без интернета» при живом туннеле, зелёном чипе «Туннель» и
      // конфиге, который проходит `sing-box check`.
      //
      // Ниже правил по сайтам: сайт конкретнее, чем «всё приложение целиком» —
      // тот же порядок, что в маршрутах.
      ..._dnsAppRules(split, AppAction.tunnel, 'dns-proxy'),
      ..._dnsAppRules(split, AppAction.direct, 'dns-local', allowRealIp: true),
      if (o.noRealIp)
        ..._dnsAppRules(split, AppAction.direct, 'dns-proxy', allowRealIp: false),
      if (!o.blockNotice) ..._dnsAppRules(split, AppAction.block, null),
      // Зеркало для правил выбора выхода в режиме «Всё через VPN».
      ..._dnsExitOnlyRules(split),
      {
        'outbound': ['direct'],
        'server': 'dns-local',
      },
    ];

    return {
      'servers': servers,
      'rules': rules,
      // ВСЕГДА dns-proxy по умолчанию: DNS через зашифрованный туннель не течёт
      // мимо VPN. Раньше в режиме onlySelected (finalOutbound=='direct') final
      // был dns-local, и DNS затуннелированных приложений резолвился локальным
      // (ISP) резолвером — утечка + отравление censorship. direct-домены всё так
      // же уходят в dns-local по правилу выше.
      // ⚠️ РАЗМЕН, у которого нет универсально верной стороны — поэтому это
      // настройка, а не наш выбор за пользователя.
      //
      // `dns-proxy` (умолчание): DNS не течёт провайдеру и не отравляется
      // цензурой. Цена — в режиме «только отмеченные» домены НЕотмеченных
      // приложений тоже резолвятся через туннель, CDN отдаёт адрес в стране
      // выхода, и такое приложение идёт напрямую, но на дальний сервер: у
      // владельца это выглядело как «Discord почему-то через VPN».
      //
      // `dns-local`: неотмеченные приложения получают близкий CDN и работают
      // быстро, но DNS отмеченных уходит к провайдеру — то есть видно, КУДА
      // ходит защищаемое приложение, и запрос можно подменить.
      // В системном режиме весь резолв идёт апстримом самой системы: это и
      // означает «системный DNS». Важно, что он всё равно ТЕРМИНИРУЕТСЯ внутри
      // туннеля — иначе отвечать на запросы к 172.19.0.2 некому.
      // ⚠️ ЗДЕСЬ ЖИВЁТ ПРИЧИНА ЖАЛОБЫ «ПРЯМОЙ ТРАФИК ОТВАЛИВАЕТСЯ».
      //
      // Под `final` попадает всё, чему пользователь правила не задал, — то есть
      // в режиме «только отмеченные» это ВЕСЬ прямой трафик. Отправляя его
      // резолв в `dns-proxy`, мы ставим работу прямого трафика в зависимость от
      // живости VPN, который ему не нужен: туннельный резолвер споткнулся —
      // имена перестали резолвиться у всего.
      //
      // Поэтому при живом форвардере сюда идёт `dns-fallback`: он спрашивает
      // туннель ПЕРВЫМ (защита сохраняется), а локальный резолвер трогает
      // только когда туннель не ответил.
      'final': systemMode
          ? 'dns-local'
          : (split.mode == SplitMode.onlySelected && !o.tunnelDnsForAll)
              ? 'dns-local'
              : (o.fallbackDnsPort > 0 ? 'dns-fallback' : 'dns-proxy'),
      'strategy': o.dnsStrategy.singboxValue,
      'independent_cache': true,
    };
  }

  /// DNS-зеркало для конфликтующих поддоменов (см. [_sitesNeedingPriority]).
  ///
  /// Правила С ПОРТОМ пропускаются по той же причине, что и в группах: резолв
  /// идёт ДО выбора порта, и правило «блокировать example.com:8443» убило бы
  /// резолв всего домена.
  List<Map<String, dynamic>> _dnsSitePriorityRules(SplitTunnelConfig split) {
    final out = <Map<String, dynamic>>[];
    for (final s in _sitesNeedingPriority(split)) {
      if (s.port != null) continue;
      final domain = s.domain.trim();
      if (domain.isEmpty) continue;
      final outbound = _siteOutbound(s);
      if (outbound == null) {
        out.add({
          'domain_suffix': [domain],
          'action': 'reject',
        });
        continue;
      }
      out.add({
        'domain_suffix': [domain],
        'server': _dnsServerForOutbound(outbound),
      });
    }
    return out;
  }

  /// DNS-правила для сайтов с действием [action]: домены резолвит [server]
  /// (null → `action: reject`, домен не резолвится вовсе).
  ///
  /// ⚠️ Правила С ПОРТОМ в зеркало НЕ попадают. Резолв идёт ДО выбора порта, а
  /// `domain_suffix` в DNS-правиле про порт ничего не знает — правило вида
  /// «блокировать example.com:8443» убило бы резолв ВСЕГО домена, хотя маршрут
  /// блокирует только один порт (то же и для «Прямо»: резолв всего домена
  /// уехал бы к локальному резолверу). Маршрутизация таких правил по-прежнему
  /// точная, страдает только зеркалирование — и это верный размен.
  List<Map<String, dynamic>> _dnsSiteRules(
      SplitTunnelConfig split, AppAction action, String? server,
      {bool? allowRealIp, bool force = false}) {
    // Зеркало обязано повторять маршруты: в режиме «Всё через VPN» правил в
    // маршрутах нет, значит и в DNS их быть не должно (иначе домен «Прямо»
    // резолвился бы локально при затуннелированном трафике).
    //
    // [force] — единственное исключение, и оно ровно про выходы: в том же
    // режиме маршрут «в какой выход» ВСЁ ЖЕ строится (см. [_addExitOnlyRules]),
    // а значит и зеркало обязано быть, иначе резолв уедет чужим выходом.
    if (!force && !_userRulesActive(split)) return const [];
    var matched = split.sites.where((s) => s.action == action && s.port == null);
    if (allowRealIp != null && options.noRealIp) {
      matched = matched.where((s) => s.allowRealIp == allowRealIp);
    }
    // ⚠️ Зеркало обязано разводиться по выходам ТОЧНО ТАК ЖЕ, как маршруты.
    // Сложи мы домены разных выходов в одно DNS-правило — имя спросилось бы у
    // резолвера чужого выхода, и CDN отдал бы адрес не той страны. Снаружи это
    // выглядит как «правило не работает», хотя трафик идёт правильным выходом.
    final out = <Map<String, dynamic>>[];
    for (final group in _byOutbound(
        matched,
        (s) => _dnsServerForOutbound(_exitTagFor(s.serverKey, action)) ?? server)) {
      // Пустой домен свалил бы весь конфиг: ядро отвергает его целиком.
      final domains = group.value
          .map((s) => s.domain.trim())
          .where((d) => d.isNotEmpty)
          .toSet()
          .toList();
      if (domains.isEmpty) continue;
      out.add({
        'domain_suffix': domains,
        if (group.key == null) 'action': 'reject' else 'server': group.key,
      });
    }
    return out;
  }

  /// Валидные CIDR из настроек (битые отбрасываем — иначе sing-box рвёт весь конфиг).
  List<String> get _validExcludeCidrs =>
      options.excludeCidrs.where(_isValidCidr).toList();

  /// Подсети режима «в туннель только эти» — с той же защитой от битой записи.
  ///
  /// ⚠️ Отбрасывать молча тут ОПАСНЕЕ, чем в исключениях: если единственная
  /// подсеть окажется битой, список станет пустым и туннель тихо вернётся к
  /// «захватываю всё» — то есть настройка перевернётся в противоположность.
  /// Поэтому UI обязан проверять ввод, а движок — писать в лог, что отбросил
  /// (см. `SingboxRouterWindows`).
  List<String> get _validRouteOnlyCidrs =>
      options.routeOnlyCidrs.where(_isValidCidr).toList();

  /// Проверка «ip/префикс»: IPv4 (0..32) или IPv6 (0..128), адрес разбирается.
  static bool _isValidCidr(String cidr) {
    final parts = cidr.trim().split('/');
    if (parts.length != 2) return false;
    final addr = InternetAddress.tryParse(parts[0]);
    if (addr == null) return false;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0) return false;
    final max = addr.type == InternetAddressType.IPv6 ? 128 : 32;
    return prefix <= max;
  }

  /// Хост для DNS-резолвера. Пустой/битый → фолбэк 1.1.1.1; из URL/схемы берём хост.
  /// Тот же разбор адреса резолвера, что уходит в конфиг ядра — но доступный
  /// снаружи.
  ///
  /// ⚠️ ЗАЧЕМ ПУБЛИЧНЫЙ ДОСТУП. Запасной DNS-форвардер должен спрашивать РОВНО
  /// тот резолвер, что записан в `dns-proxy`. Пока движки чистили адрес сами,
  /// строки расходились: построитель принимал `tcp://1.1.1.1`, а форвардеру
  /// доставалась сырая строка, на которой рукопожатие SOCKS молча падало, — и
  /// весь DNS уходил провайдеру при внешне исправной работе.
  static String dnsHostOf(String raw) => _dnsHost(raw);

  static String _dnsHost(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '1.1.1.1';
    // Пользователь мог вписать 'https://dns.google/...' или 'tcp://1.1.1.1'.
    s = s.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    s = s.split('/').first.split(RegExp(r'\s')).first;
    if (s.isEmpty) return '1.1.1.1';
    return s;
  }

  /// Правила по действиям приложений и сайтов. ПОРЯДОК = приоритет (первое
  /// совпадение выигрывает):
  ///  1) БЛОК (и приложения, и сайты) — всегда важнее всего. Иначе
  ///     «Туннель»-приложение перекрывало бы блок сайта: заблокированный сайт,
  ///     открытый в туннель-приложении, не блокировался (#3.5).
  ///  2) доменные правила (конкретнее, чем «всё приложение целиком»);
  ///  3) правила приложений; дальше — база (final).
  /// «Прямо» (direct): при [TunOptions.noRealIp] уводится ЧЕРЕЗ VPN (proxy),
  /// чтобы ничего не уходило под реальным IP; иначе — direct.
  /// БЛОК-правила (reject) — отдельно от остальных, чтобы поставить их выше
  /// bypassLan/excludeCidr (#3). Блок — через action: reject (в 1.11 outbound
  /// «block» устарел). Порядок: приложения, затем сайты.
  ///
  /// ⚠️ Блок НЕ фильтруется по «важнее правил сайтов». Раньше фильтровался — по
  /// умолчанию параметра, — и приложение с действием «Блок» и поднятой галочкой
  /// пропадало из конфига ЦЕЛИКОМ: ни выше сайтов, ни ниже. Трафик уходил в
  /// базу (в «Только отмеченные» — напрямую, в полный интернет под реальным IP),
  /// а интерфейс всё это время рисовал красный значок блокировки. На Android
  /// было хуже: пакет всё равно заводился в туннель ради reject-правила,
  /// которого не существовало.
  ///
  /// Галочка «важнее правил сайтов» для блока и не имеет смысла: блок стоит
  /// выше всех правил по построению.
  void _addBlockRules(List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    if (!_userRulesActive(split)) return;
    _addActionRule(rules, split, AppAction.block, null, overrideSites: null);
    _addSiteRule(rules, split, AppAction.block, null);
  }

  /// В режиме «Всё через VPN» пользовательские правила НЕ применяются.
  ///
  /// Интерфейс в этом режиме прячет списки приложений и сайтов и обещает, что
  /// весь трафик идёт в туннель. Правила при этом сохраняются (переключение
  /// режима их не теряет), но в конфиг попадать не должны: иначе сохранённое
  /// «Прямо» продолжало бы прорезать дыру в туннеле — трафик и DNS уходили бы
  /// мимо VPN, а пользователь об этом не узнал бы, потому что правил не видно.
  /// Особенно остро после 1.0.1, где «Прямо» снова означает именно «прямо».
  /// Нужно ли глушить QUIC, даже если пользователь этого не просил.
  ///
  /// ⚠️ ЭТО ЗАКРЫТИЕ УТЕЧКИ, А НЕ УДОБСТВО. Правило по САЙТУ срабатывает только
  /// если ядро узнало имя, а имя берётся из сниффинга TLS. Браузер, ушедший на
  /// HTTP/3 (QUIC, UDP:443), имени не оставляет — правило не матчится, и
  /// соединение уходит по маршруту «всё остальное». В режиме «только отмеченные
  /// через VPN» это направление — НАПРЯМУЮ, то есть сайт, помеченный
  /// «Туннель», молча выходит под реальным IP. Симптом ровно такой, каким его
  /// видит пользователь: «иногда трафик всё же идёт мимо туннеля» — часть
  /// запросов идёт по TCP и туннелируется, часть по QUIC и утекает.
  ///
  /// Поэтому запрет включается сам, как только есть хоть одно правило по сайту.
  /// Правил по ПРИЛОЖЕНИЯМ это не касается: они матчатся по процессу, и
  /// протокол им безразличен.
  ///
  /// Честная граница: от ECH (зашифрованный ClientHello) это не спасает — там
  /// имя не видно и в TLS поверх TCP. Пока ECH не массовый, но лечится он не
  /// здесь, а маршрутизацией по адресу, полученному из нашего же DNS.
  /// ⚠️ ЗАПРЕТ QUIC СУЖЕН ДО ДОМЕНОВ, КОТОРЫМ ОН НУЖЕН.
  ///
  /// Раньше любое правило по сайту добавляло ГЛОБАЛЬНОЕ
  /// `{network: udp, port: 443, action: reject}` — без привязки к домену,
  /// приложению и направлению. В режиме «только отмеченные» база маршрутизации
  /// — `direct`, то есть через это правило проходит ВЕСЬ трафик машины: у
  /// Google, YouTube и всего за Cloudflare отваливался HTTP/3. Снаружи это
  /// «добавил сайт — интернет пропал», и понять причину нельзя: тумблер
  /// «Запрещать QUIC» в интерфейсе при этом ВЫКЛЮЧЕН.
  ///
  /// Смысл запрета — заставить браузер вернуться на TCP, чтобы сниффер увидел
  /// ИМЯ и правило сматчилось. Значит он нужен только там, где имя решает
  /// судьбу соединения: «Туннель» и «Блок». Правилу «Прямо» сниффинг не нужен
  /// вовсе — оно совпадает с базой в большинстве режимов.
  bool _needQuicBlock(SplitTunnelConfig split) =>
      _userRulesActive(split) &&
      split.sites.any((s) =>
          s.action == AppAction.tunnel || s.action == AppAction.block);

  /// Домены, ради которых QUIC и глушится: только они, а не вся машина.
  List<String> _quicBlockDomains(SplitTunnelConfig split) => split.sites
      .where((s) => s.action == AppAction.tunnel || s.action == AppAction.block)
      .map((s) => s.domain)
      .toSet()
      .toList();

  // Гейт вынесен в `api_exit_guard.dart` (`userRulesActive`) — им же пользуется
  // ExitRouterConfigBuilder (задача 3b), и предикат обязан быть ОДНИМ на оба
  // построителя, а не двумя копиями, которые могут разъехаться.
  bool _userRulesActive(SplitTunnelConfig split) => userRulesActive(split);

  /// Есть ли правила по сайтам, которые обязаны выигрывать у «Прямо»-приложений.
  /// Правила «Прямо» по сайту терять не жалко — приложение и так идёт прямо.
  bool _sitesOutrankDirectApps(SplitTunnelConfig split) => split.sites.any(
      (s) => s.action == AppAction.tunnel || s.action == AppAction.block);

  /// Сайты, которые обязаны стоять ВЫШЕ своих групп действий.
  ///
  /// ⚠️ ЭТО ЗАКРЫТИЕ УТЕЧКИ, А НЕ НАВЕДЕНИЕ ПОРЯДКА. Правила сайтов
  /// группируются по ДЕЙСТВИЮ (блок → «Прямо» → «Туннель»), а `domain_suffix` в
  /// sing-box — обычное суффиксное совпадение: `example.com` матчит и
  /// `secure.example.com`. Значит родитель, чья группа выписана раньше,
  /// поглощает поддомен из более поздней группы, и правило поддомена мертво.
  /// Пара «example.com = Прямо» + «secure.example.com = Туннель» давала ровно
  /// это: сайт, помеченный туннелем, выходил под РЕАЛЬНЫМ IP, его имя ещё и
  /// резолвилось резолвером провайдера (DNS-зеркало повторяло ту же ошибку), а
  /// чип в интерфейсе показывал «Туннель».
  ///
  /// Обратная пара (родитель «Туннель» + поддомен «Прямо») работала верно —
  /// но лишь потому, что «Прямо» стоит в списке групп раньше. Корректность была
  /// случайной, и полагаться на неё нельзя.
  ///
  /// Экран правил сам рисует сайты деревом «родитель → поддомен», то есть прямо
  /// приглашает задавать их так.
  ///
  /// Поднимаем ТОЛЬКО конфликтующие: если действие у родителя и поддомена
  /// одинаковое, порядок ничего не меняет, а лишние правила раздувают конфиг.
  List<SiteRule> _sitesNeedingPriority(SplitTunnelConfig split) {
    if (!_userRulesActive(split)) return const [];
    final sites = split.sites;
    // ⚠️ РАЗНЫЙ ВЫХОД — ТАКОЙ ЖЕ КОНФЛИКТ, КАК РАЗНОЕ ДЕЙСТВИЕ.
    //
    // Раньше конфликтом считалось только несовпадение действий. С выходами
    // появился второй вид: «example.com через Германию» и «sub.example.com через США»
    // имеют ОДНО действие («Туннель»), но разных адресатов. Группы собираются
    // по адресату, `domain_suffix` суффиксный, и родитель из группы, попавшей
    // выше, молча поглотил бы поддомен — сайт уехал бы в чужую страну. Ни
    // компилятор, ни `sing-box check` такого не видят: конфиг валиден.
    bool conflicts(SiteRule a, SiteRule b) =>
        a.action != b.action || (a.serverKey ?? '') != (b.serverKey ?? '');
    bool shadows(SiteRule parent, SiteRule child) =>
        conflicts(parent, child) &&
        child.domain.length > parent.domain.length &&
        child.domain.toLowerCase().endsWith('.${parent.domain.toLowerCase()}');
    final out = sites.where((c) => sites.any((p) => shadows(p, c))).toList();
    // От конкретного к общему: вложенность бывает глубже двух уровней, и
    // поднятый родитель не должен перекрыть свой же поднятый поддомен.
    out.sort((a, b) => b.domain.length.compareTo(a.domain.length));
    return out;
  }

  /// Куда идёт один сайт с учётом «не выходить под реальным IP».
  /// null → reject (блок).
  String? _siteOutbound(SiteRule s) {
    switch (s.action) {
      case AppAction.block:
        return null;
      case AppAction.tunnel:
        return _exitTagFor(s.serverKey, s.action) ?? 'proxy';
      case AppAction.direct:
        return (options.noRealIp && !s.allowRealIp) ? 'proxy' : 'direct';
    }
  }

  /// Конфликтующие поддомены — отдельными правилами выше всех групп.
  void _addSitePriorityRules(
      List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    for (final s in _sitesNeedingPriority(split)) {
      final domain = s.domain.trim();
      if (domain.isEmpty) continue;
      rules.add(_action({
        'domain_suffix': [domain],
        if (s.port != null) 'port': [s.port],
      }, _siteOutbound(s)));
    }
  }

  /// Правила выбора ВЫХОДА в режиме «Всё через VPN».
  ///
  /// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ПУТЬ, А НЕ СНЯТИЕ ГЕЙТА `_userRulesActive`.
  ///
  /// В режиме «Всё через VPN» пользовательские правила намеренно не
  /// применяются: там нет ни «прямо», ни «блока» — всё идёт в туннель, а
  /// правила лежат сохранёнными до смены режима. Выход же отвечает не на вопрос
  /// «идёт ли в туннель» (идёт, как и всё остальное), а на вопрос «в КАКОЙ».
  /// Поэтому такие правила уместны и здесь — но ТОЛЬКО они. Снять гейт целиком
  /// значило бы включить в этом режиме блокировки и прямые выходы, которых
  /// пользователь тут не просил, — молча поменять смысл режима.
  void _addExitOnlyRules(
      List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    final only = _exitRulesOnly(split);
    if (only == null) return;
    // Сайты выше приложений — тот же инвариант, что и в основном пути.
    _addSiteRule(rules, only, AppAction.tunnel, 'proxy');
    _addActionRule(rules, only, AppAction.tunnel, 'proxy', overrideSites: null);
  }

  /// DNS-зеркало для [_addExitOnlyRules] — по той же причине и в том же порядке.
  List<Map<String, dynamic>> _dnsExitOnlyRules(SplitTunnelConfig split) {
    final only = _exitRulesOnly(split);
    if (only == null) return const [];
    return [
      ..._dnsSiteRules(only, AppAction.tunnel, 'dns-proxy', force: true),
      ..._dnsAppRules(only, AppAction.tunnel, 'dns-proxy', force: true),
    ];
  }

  /// Только правила с ЖИВЫМ выходом — и только когда основной путь выключен.
  /// `null` = делать нечего.
  ///
  /// Отбор обязателен: без него режим «Всё через VPN» получил бы правила и для
  /// сайтов без выхода. Они указывали бы на `proxy`, то есть ровно туда же,
  /// куда ведёт `route.final`, — поведение то же, а конфиг у КАЖДОГО
  /// пользователя стал бы другим. Тихо менять конфиг там, где ничего не
  /// просили, — способ получить необъяснимый отчёт через полгода.
  SplitTunnelConfig? _exitRulesOnly(SplitTunnelConfig split) {
    // ⚠️ Спрашиваем [_ruleExitTags], а не [_liveExitTags]: выход, живущий
    // только ради порта API, правил не порождает (см. [apiOnlyExitKeys]), и
    // ответ «теги есть» здесь означал бы разбор пустого набора правил.
    if (_userRulesActive(split) || _ruleExitTags.isEmpty) return null;
    final sites = split.sites
        .where((s) => _exitTagFor(s.serverKey, s.action) != null)
        .toList();
    final apps = split.apps
        .where((a) => a.enabled && _exitTagFor(a.serverKey, a.action) != null)
        .toList();
    if (sites.isEmpty && apps.isEmpty) return null;
    return split.copyWith(sites: sites, apps: apps);
  }

  void _addAppRules(List<Map<String, dynamic>> rules, SplitTunnelConfig split) {
    if (!_userRulesActive(split)) return;
    // «Прямо» при включённом noRealIp расходится надвое: правила с поднятой
    // галочкой «разрешить реальный IP» идут действительно напрямую (пользователь
    // задал их явно), остальные возвращаются под защиту — через VPN.
    //
    // ⚠️ ИНВАРИАНТ: ВСЕ доменные правила стоят выше ВСЕХ правил приложений
    // (#3.5) — правило сайта конкретнее, чем «всё приложение целиком», а
    // sing-box берёт ПЕРВОЕ совпадение. Разделение «Прямо» надвое обязано его
    // сохранять: если дописать «возвращённые под защиту» в хвост, такой сайт
    // проиграет любому приложению с действием «Прямо» и уйдёт под реальным IP —
    // ровно то, от чего пользователь защищался, снимая галочку.
    // Внутри каждой группы порядок безразличен: наборы правил не пересекаются
    // (фильтр по allowRealIp разводит их по разным подмножествам).
    // Приложения с поднятой галочкой «важнее правил сайтов» идут ПЕРВЫМИ —
    // выше доменных. Умолчание обратное (сайт конкретнее), но бывает нужно
    // ровно наоборот: мессенджер обязан ходить только через VPN, что бы ни
    // стояло в списке сайтов.
    _addActionRule(rules, split, AppAction.direct, 'direct',
        allowRealIp: true, overrideSites: true);
    if (options.noRealIp) {
      _addActionRule(rules, split, AppAction.direct, 'proxy',
          allowRealIp: false, overrideSites: true);
    }
    _addActionRule(rules, split, AppAction.tunnel, 'proxy',
        overrideSites: true);

    _addSiteRule(rules, split, AppAction.direct, 'direct', allowRealIp: true);
    if (options.noRealIp) {
      _addSiteRule(rules, split, AppAction.direct, 'proxy', allowRealIp: false);
    }
    _addSiteRule(rules, split, AppAction.tunnel, 'proxy');

    _addActionRule(rules, split, AppAction.direct, 'direct', allowRealIp: true);
    if (options.noRealIp) {
      _addActionRule(rules, split, AppAction.direct, 'proxy', allowRealIp: false);
    }
    _addActionRule(rules, split, AppAction.tunnel, 'proxy');
  }

  /// DNS-правила для ПРИЛОЖЕНИЙ — зеркало `_addActionRule` в маршрутах.
  ///
  /// [server] == null → `action: reject` (блок): имя не резолвится вовсе.
  ///
  /// ⚠️ СОПОСТАВЛЕНИЕ ОБЯЗАНО СОВПАДАТЬ С МАРШРУТАМИ ПОЛЕ В ПОЛЕ.
  ///
  /// Здесь стояло `process_name: [a.path]` — то есть в поле, куда ядро ждёт
  /// ИМЯ ФАЙЛА, уезжал ПОЛНЫЙ ПУТЬ (`C:\Telegram Desktop\Telegram.exe`).
  /// Такое правило не совпадает ни с чем и никогда: ядро сравнивает его с
  /// `Telegram.exe`. В конфиге правило при этом видно, `sing-box check` его
  /// принимает, интерфейс показывает «Туннель» — а DNS отмеченного приложения
  /// продолжает резолвиться по `final`, то есть ровно та утечка, ради закрытия
  /// которой зеркало и добавлялось. Найдено сверкой с настоящим конфигом,
  /// снятым с работающего туннеля.
  ///
  /// Поэтому ветвление ровно как в [_addActionRule]: Android — имя пакета,
  /// Windows — `process_name` для правил «по имени» и `process_path_regex`
  /// для правил «по пути».
  List<Map<String, dynamic>> _dnsAppRules(
      SplitTunnelConfig split, AppAction action, String? server,
      {bool? allowRealIp, bool force = false}) {
    // [force] — см. оговорку в [_dnsSiteRules].
    if (!force && !_userRulesActive(split)) return const [];
    var apps = split.apps.where((a) => a.enabled && a.action == action);
    if (allowRealIp != null && options.noRealIp) {
      apps = apps.where((a) => a.allowRealIp == allowRealIp);
    }

    Map<String, dynamic> withAction(Map<String, dynamic> match, String? srv) {
      if (srv == null) return {...match, 'action': 'reject'};
      return {...match, 'server': srv};
    }

    final out = <Map<String, dynamic>>[];
    // Те же группы, что в маршрутах, — см. оговорку в [_dnsSiteRules].
    for (final group in _byOutbound(
        apps,
        (a) => _dnsServerForOutbound(_exitTagFor(a.serverKey, action)) ?? server)) {
      final srv = group.key;
      if (options.platformTun) {
        final pkgs = group.value
            .map((a) => a.path.trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();
        if (pkgs.isNotEmpty) out.add(withAction({'package_name': pkgs}, srv));
        continue;
      }

      final byName = group.value
          .where((a) => a.byName)
          .map((a) => a.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      final byPath = group.value
          .where((a) => !a.byName)
          .map((a) => a.path.trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
      if (byName.isNotEmpty) out.add(withAction({'process_name': byName}, srv));
      if (byPath.isNotEmpty) {
        out.add(withAction({
          'process_path_regex': [
            for (final p in byPath) '(?i)^${escapeForSingboxRegex(p)}\$'
          ],
        }, srv));
      }
    }
    return out;
  }

  /// Домены с действием [action]. Сайты без порта — одним правилом; сайты с
  /// портом — отдельным правилом на каждый порт (domain_suffix + port вместе
  /// = совпадение по домену И порту). [outbound] == null → reject.
  ///
  /// [allowRealIp] отбирает подмножество правил «Прямо» при включённом
  /// `noRealIp`; при выключенном отбор не нужен — прямое правило и так прямое.
  ///
  /// [inbound] — если задан, каждое сгенерированное правило матчится ТОЛЬКО с
  /// перечисленных inbound-ов (используется API-портами для scoped-блока, см.
  /// [_addApiExitBlockGuard]); `null` — без ограничения (как раньше).
  void _addSiteRule(List<Map<String, dynamic>> rules, SplitTunnelConfig split,
      AppAction action, String? outbound,
      {bool? allowRealIp, List<String>? inbound}) {
    var matched = split.sites.where((s) => s.action == action);
    if (allowRealIp != null && options.noRealIp) {
      matched = matched.where((s) => s.allowRealIp == allowRealIp);
    }
    // ⚠️ СНАЧАЛА РАЗВОДИМ ПО ВЫХОДАМ, ПОТОМ ПО ПОРТАМ. У правила ядра ровно
    // один адресат: сложи мы сайты «через Германию» и «через США» в одно
    // правило — все они уехали бы в тот выход, чей тег туда попал.
    for (final group
        in _byOutbound(matched, (s) => _exitTagFor(s.serverKey, action) ?? outbound)) {
      final target = group.key;
      final noPort =
          group.value.where((s) => s.port == null).map((s) => s.domain).toList();
      if (noPort.isNotEmpty) {
        rules.add(_action({
          'domain_suffix': noPort,
          if (inbound != null) 'inbound': inbound,
        }, target));
      }
      // Группируем по порту: один порт — одно правило с его доменами.
      final byPort = <int, List<String>>{};
      for (final s in group.value.where((s) => s.port != null)) {
        byPort.putIfAbsent(s.port!, () => []).add(s.domain);
      }
      final ports = byPort.keys.toList()..sort();
      for (final port in ports) {
        rules.add(_action({
          'domain_suffix': byPort[port]!,
          'port': [port],
          if (inbound != null) 'inbound': inbound,
        }, target));
      }
    }
  }

  /// Одно правило для всех приложений с действием [action]. [outbound] == null →
  /// reject (блок). Приложения «по имени» и «по пути» — разными матчерами.
  ///
  /// [inbound] — см. комментарий у [_addSiteRule].
  void _addActionRule(List<Map<String, dynamic>> rules, SplitTunnelConfig split,
      AppAction action, String? outbound,
      {bool? allowRealIp, bool? overrideSites = false, List<String>? inbound}) {
    // Выключенные правила не применяются (галочка снята).
    var apps = split.apps.where((a) => a.enabled && a.action == action);
    if (allowRealIp != null && options.noRealIp) {
      apps = apps.where((a) => a.allowRealIp == allowRealIp);
    }
    // Приложения делятся на две группы: «важнее сайтов» выписываются ВЫШЕ
    // доменных правил, остальные — ниже. Каждое приложение попадает ровно в
    // одну группу, поэтому дублей не возникает.
    // `null` = не делить вовсе (блок: он и так выше всех правил, а деление
    // роняло половину блок-правил в никуда).
    if (overrideSites != null) {
      apps = apps.where((a) => a.overrideSites == overrideSites);
    }
    // ⚠️ Android ищет приложение по ИМЕНИ ПАКЕТА: полей process_name и
    // process_path на нём нет вовсе (ядро получает от VpnService только uid и
    // отдаёт его как package_name). Раньше ветки по платформе не было, поэтому
    // в конфиг уезжали 'chrome.exe' и regex по путям Windows — они не совпадали
    // НИ С ЧЕМ. Правила приложений на Android не работали в принципе, а «Блок»
    // при этом молча пропускал трафик, хотя интерфейс показывал блокировку.
    // Как и у сайтов: приложения одного действия, но разных выходов не могут
    // ехать одним правилом.
    for (final group
        in _byOutbound(apps, (a) => _exitTagFor(a.serverKey, action) ?? outbound)) {
      final target = group.key;
      if (options.platformTun) {
        final pkgs = group.value
            .map((a) => a.path.trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();
        if (pkgs.isNotEmpty) {
          rules.add(_action({
            'package_name': pkgs,
            if (inbound != null) 'inbound': inbound,
          }, target));
        }
        continue;
      }

      final byName = group.value.where((a) => a.byName).map((a) => a.name).toList();
      final byPath = group.value.where((a) => !a.byName).map((a) => a.path).toList();
      if (byName.isNotEmpty) {
        rules.add(_action({
          'process_name': byName,
          if (inbound != null) 'inbound': inbound,
        }, target));
      }
      if (byPath.isNotEmpty) {
        // process_path сравнивается ядром побайтово (регистр, короткие пути
        // Windows) — правило могло молча не срабатывать. process_path_regex
        // с (?i) — надёжно.
        rules.add(_action({
          'process_path_regex': [
            for (final p in byPath) '(?i)^${escapeForSingboxRegex(p)}\$'
          ],
          if (inbound != null) 'inbound': inbound,
        }, target));
      }
    }
  }

  /// Правило маршрутизации в синтаксисе sing-box 1.11+ (`outbound` в правиле — deprecated).
  static Map<String, dynamic> _route(Map<String, dynamic> match, String outbound) =>
      {...match, 'action': 'route', 'outbound': outbound};

  /// route на [outbound], либо reject, если [outbound] == null (блокировка).
  static Map<String, dynamic> _action(
          Map<String, dynamic> match, String? outbound) =>
      outbound == null
          ? {...match, 'action': 'reject'}
          : _route(match, outbound);

  /// Одиночный IP → /32 или /128 (sing-box ждёт CIDR).
  static String _asCidr(String ip) {
    if (ip.contains('/')) return ip;
    return ip.contains(':') ? '$ip/128' : '$ip/32';
  }

  /// Пакеты, идущие МИМО туннеля (действие «Прямо»).
  ///
  /// ⚠️ При `noRealIp` пользовательские «Прямо»-приложения сюда НЕ попадают:
  /// исключённый на уровне ОС пакет ядро не увидит, и его трафик пойдёт под
  /// реальным IP — ровно та утечка, которую чинили на Windows (0.12.0).
  /// Там они остаются в туннеле, а правило `package_name → proxy` уводит их
  /// через VPN.
  List<String> _excludePackages(SplitTunnelConfig split, TunOptions o) {
    final out = <String>{o.selfPackage};
    // ⚠️ Режим «Всё через VPN» обязан быть здесь ТОЖЕ.
    //
    // Это была настоящая дыра: правила из маршрутов мы вырезали
    // (`_userRulesActive`), а из пакетных списков — нет. Сохранённое
    // «Прямо»-приложение продолжало уезжать в `exclude_package`, и
    // `VpnService` выводил его из туннеля НА УРОВНЕ ОС — трафик шёл под
    // реальным IP. Заметить было нельзя ничем: правил в конфиге нет, списки
    // в интерфейсе скрыты, схема маршрута рисует простую цепочку.
    if (!_userRulesActive(split)) return out.toList();
    if (o.noRealIp) return out.toList();
    if (split.mode == SplitMode.onlySelected) return out.toList();
    // ⚠️ Правила по САЙТАМ проигрывают исключению на уровне ОС, а не по
    // приоритету — их просто некому применить. Пакет из `exclude_package`
    // `VpnService` выводит из туннеля целиком: ядро его трафика не видит, и ни
    // одно доменное правило по нему не срабатывает, хотя в конфиге оно лежит и
    // выглядит рабочим. Пара «Chrome = Прямо» + «youtube.com = Туннель» давала
    // ровно это: YouTube из Chrome шёл под реальным IP, а «ads.example = Блок»
    // спокойно открывался. Та же настройка на Windows отрабатывала ВЕРНО
    // (доменное правило выше process_name) — то есть платформы расходились при
    // одинаковых настройках.
    //
    // Поэтому при живых правилах «Туннель»/«Блок» по сайтам приложения «Прямо»
    // остаются ВНУТРИ туннеля, а мимо VPN их уводит правило
    // `package_name → direct`, стоящее ниже доменных. Цена — трафик такого
    // приложения проходит через ядро; выигрыш — обещанный приоритет
    // «сайты выше приложений» соблюдается на обеих платформах.
    // Приложения с поднятой галочкой «важнее правил сайтов» исключать можно и
    // при живых сайтах: они и так обязаны выигрывать у доменных правил.
    final sitesWin = _sitesOutrankDirectApps(split);
    for (final a in split.apps) {
      if (!a.enabled || a.action != AppAction.direct) continue;
      if (sitesWin && !a.overrideSites) continue;
      if (a.path.trim().isEmpty) continue;
      out.add(a.path.trim());
    }
    return out.toList();
  }

  /// Пакеты, которые единственные идут В туннель (режим «только выбранные»).
  ///
  /// Списки include и exclude в `VpnService.Builder` несовместимы: наличие
  /// хотя бы одного include уводит всё остальное мимо VPN. Поэтому здесь
  /// либо один, либо другой.
  /// Пакетные списки для `VpnService.Builder` — ровно ОДИН из двух.
  ///
  /// Непустой include побеждает: в туннель идут только перечисленные, всё
  /// остальное (включая наш собственный пакет) остаётся снаружи само собой.
  /// Пустой include в режиме «только выбранные» означал бы «в туннель не идёт
  /// никто», а `VpnService` без allowed-списка тянет туда ВСЁ, — поэтому там
  /// возвращаемся к exclude, чтобы хотя бы себя из туннеля вынуть.
  Map<String, dynamic> _packageLists(SplitTunnelConfig split, TunOptions o) {
    final include = _includePackages(split, o);
    if (include.isNotEmpty) return {'include_package': include};
    return {'exclude_package': _excludePackages(split, o)};
  }

  List<String> _includePackages(SplitTunnelConfig split, TunOptions o) {
    if (split.mode != SplitMode.onlySelected) return const [];
    // ⚠️ ЗЕРКАЛО ТОЙ ЖЕ УТЕЧКИ, ЧТО ЧИНИЛИ ДЛЯ `exclude_package`.
    //
    // Список include означает «в туннель идут ТОЛЬКО эти пакеты» — всё
    // остальное `VpnService` оставляет снаружи на уровне ОС. Значит правило по
    // САЙТУ для неотмеченного приложения применить некому: ядро его трафика не
    // видит. Пара «отмечен только мессенджер» + «youtube.com = Туннель» давала
    // ровно это — YouTube в браузере шёл под реальным IP вместе со своим DNS,
    // хотя правило лежало в конфиге, принималось ядром и рисовалось на схеме
    // маршрута внутри цепочки «через VPN».
    //
    // Лечение — отдать решение маршрутизации, она это выражает полностью: без
    // include в туннель заходит всё, доменные правила стоят выше правил
    // приложений, а неотмеченные приложения выпускает наружу `final: direct`,
    // то есть смысл режима «только отмеченные» сохраняется. Цена та же, что и
    // в зеркальном случае: их трафик проходит через ядро.
    //
    // Приложения с галочкой «важнее правил сайтов» тут ничего не меняют: сайтов
    // они не отменяют, а лишь встают выше них в маршрутах.
    if (_sitesOutrankDirectApps(split)) return const [];
    final out = <String>{};
    for (final a in split.apps) {
      if (!a.enabled) continue;
      // ⚠️ «Блок» обязан попасть в туннель. Раньше он тут пропускался — и
      // заблокированное приложение оказывалось ВНЕ туннеля: ядро его трафика
      // не видело, правило `package_name → reject` совпасть не могло, и блок
      // молча разрешал соединение. Ровно тот дефект, который чинили для
      // остальных режимов, только в «только выбранных».
      // Внутри туннеля его убивает reject-правило — оно стоит выше всего
      // пользовательского.
      final pkg = a.path.trim();
      if (pkg.isNotEmpty) out.add(pkg);
    }
    return out.toList();
  }


  /// TUN-инбаунд. ОДИН на живой конфиг и на заглушку kill switch: если они
  /// разойдутся хоть одним полем (MTU, адреса, списки пакетов), `VpnService`
  /// пересоздаст интерфейс — и на этот миг трафик пойдёт мимо VPN.
  Map<String, dynamic> _tunInbound(SplitTunnelConfig split) {
    final o = options;
    return
      {
        'type': 'tun',
        'tag': 'tun-in',
        // Имя интерфейса, автомаршруты, strict_route и выбор стека имеют смысл
        // только когда туннель создаёт САМО ядро. На Android его создаёт
        // VpnService, и эти поля ядро для платформенного туннеля не принимает.
        if (!o.platformTun) ...{
          'interface_name': 'silentgate-tun',
          'auto_route': true,
          'strict_route': o.strictRoute,
          if (o.stack != null) 'stack': o.stack,
        },
        // ⚠️ Стек указываем и на Android — он про ОБРАБОТКУ пакетов из
        // дескриптора, а не про то, кто создал интерфейс.
        //
        // По умолчанию ядро берёт стек, который на Android пытается привязать
        // форвардер к интерфейсу (`SO_BINDTODEVICE`), а это требует прав,
        // которых у приложения нет. В логе: «bind forwarder to interface:
        // operation not permitted», и TCP-соединения не форвардятся вовсе,
        // хотя DNS (UDP) при этом работает. gVisor обрабатывает всё в
        // пользовательском пространстве, привязка ему не нужна.
        //
        // ⚠️ И потому же выбор пользователя тут НЕ уважается: на Android
        // работает ровно один стек. `system` привязывает форвардер и умирает,
        // `mixed` гонит по нему TCP — то есть тоже. Пока стояло `o.stack ??
        // 'gvisor'`, пользователь мог выбрать любой из них на экране TUN,
        // получить «Подключено» и полностью мёртвый интернет без единой ошибки.
        // Экран теперь этих вариантов не предлагает, а здесь стоит страховка:
        // настройка могла приехать из файла, с Windows-машины или из старой
        // версии.
        if (o.platformTun) 'stack': 'gvisor',
        // ⚠️ IPv6-адрес туннеля ставится ВСЕГДА, даже когда пользователь
        // выключил IPv6.
        //
        // Раньше при выключенной настройке адреса не было — а значит не было и
        // маршрута ::/0 в туннель. Это не «IPv6 не используется», это «IPv6
        // идёт МИМО VPN»: такой трафик уходил через физический адаптер, под
        // реальным адресом и мимо всех правил. На двустековой сети это половина
        // запросов к крупным сайтам, а снаружи всё выглядит как рабочий VPN.
        //
        // Теперь IPv6 всегда ЗАХВАТЫВАЕТСЯ, а выключенная настройка означает
        // отказ уже внутри туннеля (правило `ip_version: 6` → reject). Разница
        // принципиальная: отказ приходит мгновенно, и клиент сразу переходит на
        // IPv4, тогда как при утечке в сеть без работающего IPv6 он ждал
        // таймаута — сайт «Прямо» просто не открывался. Поймано живым тестом.
        'address': [
          '172.19.0.1/30',
          // Объявляем IPv6-адрес, только если IPv6 существует НАРУЖУ.
          // Подробности и цена ошибки — у `ipv6Upstream`.
          if (o.ipv6Upstream) 'fdfe:dcba:9876::1/126',
        ],
        'mtu': o.mtu,
        'endpoint_independent_nat': o.endpointIndependentNat,
        // ⚠️ РЕЖИМ «В ТУННЕЛЬ ТОЛЬКО ЭТИ ПОДСЕТИ» — здесь и больше нигде.
        //
        // Обычно `auto_route` вешает на туннель `0.0.0.0/0` с метрикой 0, и в
        // него заходит ВЕСЬ трафик машины; «Прямо» разбирается уже внутри ядра.
        // С непустым `route_address` маршрута по умолчанию туннель не получает
        // вовсе: система сама отправляет всё прочее физическим адаптером, а
        // ядро этого трафика не видит и не может ему помешать — в том числе
        // когда зависло.
        //
        // ⚠️ Правила по приложениям и сайтам в этом режиме действуют ТОЛЬКО
        // для адресов из списка: то, что в туннель не зашло, ядру не показали.
        // Обещать «блок сайта» здесь нельзя, если его адрес вне подсетей.
        if (_validRouteOnlyCidrs.isNotEmpty)
          'route_address': _validRouteOnlyCidrs,
        if (_validExcludeCidrs.isNotEmpty)
          'route_exclude_address': _validExcludeCidrs,
        // Разведение приложений на Android идёт пакетами, а не процессами.
        //
        // ⚠️ include_package и exclude_package ВЗАИМОИСКЛЮЧАЮЩИЕ. Раньше при
        // «только выбранные» отдавались ОБА: exclude всегда содержал хотя бы
        // свой пакет. `VpnService.Builder` такого не принимает —
        // addDisallowedApplication после addAllowedApplication бросает
        // UnsupportedOperationException, и туннель не поднимался вовсе.
        // Когда список include непуст, exclude не нужен по построению: в
        // туннель идут ТОЛЬКО перечисленные, всё прочее (включая нас) и так
        // мимо.
        if (o.platformTun) ..._packageLists(split, o),
      };
  }

  /// Туннель-заглушка для kill switch: интерфейс ТОТ ЖЕ, наружу не выходит ничего.
  ///
  /// ⚠️ Три ошибки, на которых первая версия этой заглушки не работала бы вовсе
  /// (найдено ревью, `sing-box check` их НЕ ловит — он возвращает 0 и на
  /// висячем теге outbound):
  ///
  ///  1. ВИСЯЧИЕ ССЫЛКИ. Оставлять обычные правила и секцию DNS нельзя: они
  ///     ссылаются на `proxy` и `direct`, которых в заглушке нет. Ядро
  ///     отвергает такой конфиг целиком — то есть туннель СНИМАЕТСЯ, и трафик
  ///     идёт напрямую всё время попыток. Ровно наоборот тому, зачем это
  ///     делалось. Поэтому здесь ни одного правила, кроме catch-all reject.
  ///  2. ТИП `block` УДАЛЁН. Outbound `{'type':'block'}` объявлен устаревшим в
  ///     1.11 и убран в 1.13, а на Android у нас libbox 1.13.14. Блокируем
  ///     маршрутным `action: reject` — он поддерживается.
  ///  3. ИНТЕРФЕЙС ПЕРЕСОЗДАВАЛСЯ. Заглушка строилась из ДЕФОЛТНЫХ опций, а
  ///     живой конфиг — из пользовательских: другой MTU, другой набор
  ///     `include_package`/`exclude_package`. Разные списки = `VpnService`
  ///     строит НОВЫЙ интерфейс, и на этот миг трафик идёт мимо VPN — то самое
  ///     окно утечки, ради закрытия которого заглушка и нужна. Теперь inbound
  ///     собирается из тех же опций и того же split.
  Map<String, dynamic> _blackholeMap(SplitTunnelConfig split) => {
        'log': {
          'level': options.logLevel,
          'timestamp': true,
          if ((options.logOutput ?? '').isNotEmpty) 'output': options.logOutput,
        },
        'inbounds': [_tunInbound(split)],
        // Ровно один outbound, и на него никто не ссылается: `final` до него не
        // доходит — всё съедает reject выше.
        'outbounds': [
          {'type': 'direct', 'tag': 'direct'},
        ],
        'route': {
          'auto_detect_interface': true,
          // Ничего, кроме отказа. Ни DNS, ни LAN, ни правил пользователя:
          // правило «Прямо» выпустило бы трафик наружу — это и запрещает
          // kill switch.
          'rules': [
            {'action': 'reject'},
          ],
          'final': 'direct',
        },
      };
}
