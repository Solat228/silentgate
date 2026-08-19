import 'dart:convert';

import '../models/vpn_server.dart';
// Гейт «действуют ли пользовательские правила вообще» — ОБЩИЙ с боевыми
// построителями. Своя копия условия разъехалась бы с ними на первой же правке.
import '../singbox/api_exit_guard.dart';
import '../settings/split_tunnel.dart';
import 'outbound_variant.dart';
import 'xray_outbound_factory.dart';

/// Порты проброс-харнесса (отдельный экземпляр Xray для пинга/проб).
class HarnessPorts {
  final int base;
  const HarnessPorts({this.base = 21000});
}

/// Кусок боевых настроек, который влияет на ДОСТИЖИМОСТЬ мишени пробы.
///
/// ⚠️ ЗАЧЕМ ЭТО ВООБЩЕ ЕСТЬ. Харнесс строился голым шаблоном: один
/// http-inbound на кандидата и его outbound, больше ничего. Проба через такой
/// конфиг проходила там, где боевое подключение не работает, — и плашка пинга
/// горела зелёным при полностью нерабочем канале, а сервис-чипы у кнопки
/// Connect (они ходят через ЖИВОЕ ядро) в тот же момент были красными.
/// Требование владельца: «настоящий пинг — как если бы юзер включил VPN, зашёл
/// на сайт, и у него загрузилось или нет».
///
/// Сюда попадает только то, что реально меняет судьбу запроса к мишени:
/// правила по САЙТАМ и DNS. Правила по ПРИЛОЖЕНИЯМ неприменимы по построению —
/// у соединения, пришедшего в локальный прокси, нет процесса-владельца, ядро
/// сопоставлять его не с чем (та же причина, по которой правила приложений не
/// работают у системного прокси Windows).
///
/// ⚠️ ЧЕСТНАЯ ГРАНИЦА: даже с этими правилами проба идёт через прокси-порт, а
/// не через TUN-адаптер. Если ломается именно TUN, харнесс этого не увидит —
/// увидит только проверка активного сервера через живое ядро.
class HarnessRealism {
  /// Сайты с действием «Блок»: в бою они не открываются вовсе.
  final List<SiteRule> blocked;

  /// Сайты с действием «Прямо»: в бою идут мимо VPN.
  final List<SiteRule> direct;

  /// Свой DNS-сервер пользователя (только режим «свой»); пусто — как в боевом
  /// конфиге по умолчанию.
  final String dnsServer;

  /// `queryStrategy` Xray (`UseIPv4`/`UseIPv6`); null — не задавать.
  final String? queryStrategy;

  const HarnessRealism({
    this.blocked = const [],
    this.direct = const [],
    this.dnsServer = '',
    this.queryStrategy,
  });

  /// Настроек, влияющих на пробу, нет — конфиг харнесса остаётся прежним.
  static const none = HarnessRealism();

  bool get isEmpty =>
      blocked.isEmpty &&
      direct.isEmpty &&
      dnsServer.isEmpty &&
      queryStrategy == null;

  /// Выжимка из боевых правил раздельного туннелирования.
  ///
  /// ⚠️ Режим «Всё через VPN» пользовательских правил НЕ применяет — ни блока,
  /// ни «Прямо» (они сохранены, но в боевой конфиг не входят). Гейт спрашиваем
  /// у [userRulesActive], того же, что решает это в боевых построителях:
  /// харнесс, блокирующий сайт там, где боевой конфиг его пропускает, врал бы
  /// в другую сторону — и это ничем не лучше.
  factory HarnessRealism.fromRules(
    SplitTunnelConfig split, {
    String dnsServer = '',
    String? queryStrategy,
  }) {
    final sites = userRulesActive(split) ? split.sites : const <SiteRule>[];
    return HarnessRealism(
      blocked: [
        for (final s in sites)
          if (s.action == AppAction.block) s,
      ],
      direct: [
        for (final s in sites)
          if (s.action == AppAction.direct) s,
      ],
      dnsServer: dnsServer,
      queryStrategy: queryStrategy,
    );
  }
}

/// Один кандидат в харнессе: сервер + вариация настроек.
class HarnessEntry {
  final String key; // стабильный ключ (обычно rawLink сервера + метка вариации)
  final VpnServer server;
  final OutboundVariant variant;

  /// Боевые настройки, влияющие на пробу (см. [HarnessRealism]).
  ///
  /// ⚠️ ЖИВЁТ ИМЕННО ЗДЕСЬ, А НЕ В ПОСТРОИТЕЛЕ, потому что построитель создаёт
  /// платформенный код харнесса (`XrayHarnessWindows`, `ProbeHarnessAndroid`),
  /// а настройки пользователя есть только у того, кто запускает прогон.
  /// Единственное, что доезжает от него до построителя, — список кандидатов.
  final HarnessRealism realism;

  const HarnessEntry({
    required this.key,
    required this.server,
    this.variant = OutboundVariant.none,
    this.realism = HarnessRealism.none,
  });
}

/// Настройки прогона: одни на весь харнесс, поэтому берём у первого кандидата,
/// который их принёс (остальные кандидаты того же прогона несут те же).
HarnessRealism realismOf(List<HarnessEntry> entries) {
  for (final e in entries) {
    if (!e.realism.isEmpty) return e.realism;
  }
  return HarnessRealism.none;
}

/// Строит конфиг проброс-харнесса: по одному http-inbound на кандидата,
/// маршрутизируемому на его outbound. Проба сервера i = HTTP-запрос через 127.0.0.1:(base+i).
///
/// Важно: харнесс НЕ содержит api/stats/policy и НЕ трогает системный прокси —
/// все inbound'ы слушают только 127.0.0.1. Dart HttpClient умеет ходить через http-прокси нативно.
class HarnessConfigBuilder {
  final HarnessPorts ports;

  /// Логин и пароль http-инбаундов харнесса.
  ///
  /// ⚠️ ЗАЧЕМ ОНИ ЗДЕСЬ. Инбаунд харнесса — это полноценный вход в туннель:
  /// кто к нему подключился, тот ходит через VPN-сервер кандидата. Живёт он
  /// недолго (только пока идёт прогон пинга или подбора), но всё это время был
  /// открыт ЛЮБОМУ процессу машины — а на Android ещё и любому приложению с
  /// разрешением INTERNET: loopback там между приложениями не изолирован.
  /// Ровно такую дыру закрывали в 1.3.0 для портов 10808/10809 — про харнесс
  /// тогда забыли, потому что страж `local_ports_closed_test` знал два пути
  /// сборки конфига из четырёх.
  ///
  /// Пусто — инбаунд БЕЗ ПАРОЛЯ. Так конфиг выглядел до 1.4.1 везде и до 1.4.2
  /// на Android: платформенный код там звал построитель без [withAuth], хотя
  /// этот комментарий уже утверждал, что «боевой путь всегда выдаёт креды».
  /// Утверждение стало правдой только в 1.4.2 — и теперь его стережёт не текст,
  /// а тест: `local_ports_closed_test` проверяет и построители, и МЕСТА ИХ
  /// ВЫЗОВА. Пустые креды остались возможными ради тестов и `tool/emit_*`,
  /// которые ничего не слушают, а печатают конфиг для валидации ядром.
  final String user;
  final String password;

  const HarnessConfigBuilder({
    this.ports = const HarnessPorts(),
    this.user = '',
    this.password = '',
  });

  HarnessConfigBuilder withAuth(String user, String password) =>
      HarnessConfigBuilder(ports: ports, user: user, password: password);

  /// Копия с другим базовым портом; логин и пароль сохраняются.
  ///
  /// ⚠️ ЗАЧЕМ. Windows держит всех кандидатов в ОДНОМ конфиге, и порты им
  /// раздаёт [portFor] по индексу. На Android так нельзя: `LibXray.ping`
  /// принимает ПУТЬ к конфигу и меряет ровно один outbound, поэтому конфиг там
  /// на каждого кандидата свой — и внутри каждого кандидат идёт под индексом 0,
  /// то есть все просят один и тот же порт. А замеры идут пачкой
  /// (`Pool(pingConcurrency)`, по умолчанию 8 одновременно), и второй бинд на
  /// занятый порт не проходит: кандидат получал «n/a» без всякой связи с самим
  /// сервером, плавающе — по тому, кто успел первым.
  HarnessConfigBuilder withPortBase(int base) => HarnessConfigBuilder(
      ports: HarnessPorts(base: base), user: user, password: password);

  bool get _hasAuth => user.isNotEmpty && password.isNotEmpty;

  /// Секция `settings` http-инбаунда: с аккаунтами либо пустая.
  ///
  /// ⚠️ ОДНА НА ОБЕ ВЕТКИ СБОРКИ. Инбаунд здесь строится в двух разных местах:
  /// в [buildMap] (обычные серверы подписки) и в [_tryOverrideMap] (профили
  /// панели «Авто …» и серверы с ручной правкой JSON) — вторая ветка собирает
  /// его своим кодом. Забыть в ней креды значило бы открытый вход в туннель
  /// ровно у тех серверов, которые есть в каждой подписке. Обе ветки берут
  /// ЭТОТ геттер, и что обе — проверяет `local_ports_closed_test`, а не текст
  /// этого комментария.
  Map<String, dynamic> get _httpSettings => _hasAuth
      ? {
          'accounts': [
            {'user': user, 'pass': password}
          ],
        }
      : <String, dynamic>{};

  int portFor(int index) => ports.base + index;

  Map<String, dynamic> buildMap(List<HarnessEntry> entries) {
    // #8.2 — сервер с полным JSON-override: поднимаем его собственный конфиг
    // (со всеми outbounds/balancers/burstObservatory), но заменяем inbounds на
    // единственный http-inbound харнесса и роутим его на цель исходного конфига.
    if (entries.length == 1) {
      // Полный конфиг: правка пользователя либо профиль-автовыбор от панели.
      final s = entries.first.server;
      final raw = (s.rawJsonOverride ?? '').isNotEmpty
          ? s.rawJsonOverride
          : s.rawPanelConfig;
      if (raw != null && raw.isNotEmpty) {
        final map = _tryOverrideMap(raw, portFor);
        if (map != null) return map;
      }
    }

    final realism = realismOf(entries);
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final inTag = 'in-$i';
      final outTag = 'out-$i';
      inbounds.add({
        'tag': inTag,
        'listen': '127.0.0.1',
        'port': portFor(i),
        'protocol': 'http',
        'settings': _httpSettings,
      });
      outbounds.addAll(
        XrayOutboundFactory.build(e.server, tag: outTag, variant: e.variant),
      );
      rules.add({
        'type': 'field',
        'inboundTag': [inTag],
        'outboundTag': outTag,
      });
    }

    outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
    outbounds.add({'protocol': 'blackhole', 'tag': 'block'});

    final dns = _dns(realism);
    return {
      'log': {'loglevel': 'warning'},
      if (dns != null) 'dns': dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      // ⚠️ ПОРЯДОК ПРАВИЛ: сайты пользователя ВЫШЕ правил кандидатов. Правило
      // кандидата (`inboundTag: in-i`) совпадает с ЛЮБЫМ запросом из своего
      // входа, поэтому всё, что стоит ниже него, не срабатывает никогда.
      // Внутри — тот же порядок, что в боевом конфиге: блок, затем «Прямо».
      //
      // domainStrategy остаётся AsIs (а не боевой IPIfNonMatch) намеренно:
      // IPIfNonMatch заставляет ядро резолвить имя ЛОКАЛЬНО перед сверкой с
      // IP-правилами, и этот резолв попал бы в измеряемую задержку, испортив
      // саму цифру пинга. Доменные правила при AsIs работают: им резолв не нужен.
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          ..._siteRules(realism.blocked, 'block'),
          ..._siteRules(realism.direct, 'direct'),
          ...rules,
        ],
      },
    };
  }

  /// Правила по сайтам в терминах Xray. `domain:foo.com` — домен и его
  /// поддомены (аналог `domain_suffix` в боевом конфиге sing-box).
  List<Map<String, dynamic>> _siteRules(List<SiteRule> sites, String outbound) =>
      [
        for (final s in sites)
          {
            'type': 'field',
            'domain': ['domain:${s.domain}'],
            // Правило с портом действует только на него — иначе сайт,
            // заблокированный на 8443, оказался бы закрыт целиком.
            if (s.port != null) 'port': '${s.port}',
            'outboundTag': outbound,
          },
      ];

  /// DNS-секция под настройки пользователя. `null` — не писать её вовсе: при
  /// умолчаниях конфиг харнесса обязан остаться в точности прежним, иначе
  /// правка задевала бы всех, включая тех, у кого никаких настроек нет.
  Map<String, dynamic>? _dns(HarnessRealism realism) {
    if (realism.dnsServer.isEmpty && realism.queryStrategy == null) return null;
    return {
      if (realism.queryStrategy != null) 'queryStrategy': realism.queryStrategy,
      // Пустой список ядро не примет: без своего сервера берём тот же запасной
      // набор, что стоит в боевом конфиге автовыбора.
      'servers': realism.dnsServer.isNotEmpty
          ? [realism.dnsServer]
          : ['1.1.1.1', '8.8.8.8'],
    };
  }

  String buildJson(List<HarnessEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(entries));

  /// Строит harness-конфиг из полного пользовательского JSON. Возвращает null,
  /// если JSON нераспарсиваемый или без outbounds (тогда откат на обычный путь).
  ///
  /// ⚠️ Правила [HarnessRealism] сюда НЕ добавляются: теги `direct`/`block` в
  /// чужом конфиге есть не всегда, а правило с несуществующим тегом Xray молча
  /// уводит трафик в другой outbound (тот же класс дефекта, что и висячий тег в
  /// sing-box). Профили «Авто …» и правки JSON проверяются как раньше.
  ///
  /// ⚠️ А ВОТ КРЕДЫ СЮДА ДОБАВЛЯЮТСЯ, и это не «на всякий случай»: инбаунд
  /// ниже собирается ОТДЕЛЬНЫМ от [buildMap] кодом, а ведёт он в туннель того
  /// самого профиля «Авто», который у владельца есть в каждой подписке. Пустой
  /// `settings` здесь означал бы, что закрыли только обычные серверы.
  Map<String, dynamic>? _tryOverrideMap(String raw, int Function(int) portFor) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cfg = Map<String, dynamic>.from(decoded);
      final outbounds = cfg['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) return null;

      final routing = cfg['routing'] is Map
          ? Map<String, dynamic>.from(cfg['routing'] as Map)
          : <String, dynamic>{};
      final tags = probeExitTags(routing, outbounds);
      if (tags.isEmpty) return null;
      // domainStrategy ФОРСИРУЕТСЯ, а не наследуется из профиля (там почти
      // всегда `IPIfNonMatch`). Причина та же, что в [buildMap]: IPIfNonMatch
      // заставляет ядро резолвить имя мишени ЛОКАЛЬНО, и этот резолв попадает
      // в измеряемую задержку. Единственное правило ниже сверяет `inboundTag`,
      // домен ему не нужен.
      routing['domainStrategy'] = 'AsIs';
      // ⚠️ БАЛАНСИРОВЩИКИ УБИРАЕМ ЦЕЛИКОМ — см. [probeExitTag]. Оставить их
      // «на всякий случай» нельзя: правил, которые бы на них ссылались, здесь
      // больше нет, а балансировщик со стратегией `leastPing` и без
      // наблюдателя — это ссылка на возможность, которой в конфиге не осталось.
      routing.remove('balancers');
      routing['rules'] = [
        for (var i = 0; i < tags.length; i++)
          {
            'type': 'field',
            'inboundTag': ['in-$i'],
            'outboundTag': tags[i],
          },
      ];

      cfg['log'] = {'loglevel': 'warning'};
      cfg['inbounds'] = [
        for (var i = 0; i < tags.length; i++)
          {
            'tag': 'in-$i',
            'listen': '127.0.0.1',
            'port': portFor(i),
            'protocol': 'http',
            'settings': _httpSettings,
          },
      ];
      cfg['routing'] = routing;
      cfg.remove('api');
      cfg.remove('stats');
      cfg.remove('policy');
      // ⚠️ НАБЛЮДАТЕЛЬ ТОЖЕ УБИРАЕТСЯ, И ЭТО ОТДЕЛЬНАЯ ПРИЧИНА, А НЕ СЛЕДСТВИЕ
      // ПРЕДЫДУЩЕЙ. `burstObservatory` начинает работу вместе с ядром и шлёт
      // свою пробу (у Remnawave это `https://www.youtube.com/generate_204`)
      // ЧЕРЕЗ КАЖДЫЙ узел профиля, по `sampling` раз на узел. На профиле из
      // семи десятков узлов это сотни одновременных TLS-сессий ровно в те
      // секунды, когда мы меряем задержку, — цифра получается про эту бурю, а
      // не про канал. Плюс трафик подписки за пробу, которой мы не просили.
      cfg.remove('observatory');
      cfg.remove('burstObservatory');
      return cfg;
    } catch (_) {
      return null;
    }
  }

  /// Тег outbound'а, ЧЕРЕЗ КОТОРЫЙ пойдёт проба. `null` — в конфиге нет ни
  /// одного outbound'а с тегом (мерить нечем, откат на обычный путь).
  ///
  /// ⚠️ ВСЕГДА КОНКРЕТНЫЙ УЗЕЛ, НИКОГДА БАЛАНСИРОВЩИК — вот из-за чего
  /// панельные профили «Авто …» пинговались плохо или не пинговались вовсе.
  /// Раньше правило харнесса вело на `balancerTag` исходного профиля, и это
  /// НЕ РАБОТАЕТ в харнессе по построению:
  ///
  ///   * балансировщик Remnawave стоит на стратегии `leastPing`, а она берёт
  ///     задержки у `burstObservatory` — то есть у наблюдателя, который
  ///     стартует ВМЕСТЕ С ЯДРОМ и первую пачку задержек получает через
  ///     секунды (проба идёт до внешнего адреса через каждый из десятков
  ///     узлов). Харнесс живёт ровно один замер: порт слушает через ~0,2 с,
  ///     проба уходит с таймаутом 3 с (`pingTimeoutMs`, на Android 5 с
  ///     нативных). Наблюдений к этому моменту нет;
  ///   * пустой выбор балансировщика Xray отдаёт в `fallbackTag`, а в
  ///     профилях панели это `direct`. То есть проба уходила МИМО сервера и
  ///     мерила прямой канал пользователя — «пинг» был, к серверу отношения
  ///     не имел. Без `fallbackTag` тот же случай даёт отказ соединения и
  ///     «n/a» на заведомо живом профиле.
  ///
  /// Поэтому выход выбираем САМИ и статически. Правило выбора — «тот узел,
  /// который пользователь видит в строке»: `XrayJsonSubscription` берёт для
  /// показа outbound с тегом `proxy` (иначе первый прокси), и цифра пинга
  /// обязана относиться к тому же адресу, что показан рядом с ней. Среди
  /// узлов сперва отбираем те, что попадают под `selector` балансировщика
  /// (Xray сверяет его ПРЕФИКСОМ тега) — иначе на профиле, где балансируется
  /// только часть узлов, мы измеряли бы узел, который профиль не использует.
  ///
  /// ⚠️ ЧЕСТНАЯ ГРАНИЦА: это задержка до ОДНОГО узла профиля, а не до того,
  /// который балансировщик выберет при подключении. Другого числа в пределах
  /// одного замера не существует: чтобы получить выбор балансировщика, надо
  /// дать наблюдателю обойти все узлы, а это и есть тот самый прогон пинга,
  /// только целиком и по каждому профилю отдельно.
  /// СКОЛЬКО КАНДИДАТОВ ПРОФИЛЯ ХАРНЕСС ВЫСТАВИТ НАРУЖУ.
  ///
  /// Нужно тому, кто ходит через харнесс: порты идут подряд от базового, и без
  /// этого числа пробующий не знает, сколько их пробовать.
  static int overrideCandidateCount(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return 0;
      final outbounds = decoded['outbounds'];
      if (outbounds is! List || outbounds.isEmpty) return 0;
      final routing = decoded['routing'] is Map
          ? Map<String, dynamic>.from(decoded['routing'] as Map)
          : <String, dynamic>{};
      return probeExitTags(routing, outbounds).length;
    } catch (_) {
      return 0;
    }
  }

  /// Сколько узлов профиля пробуем. ⚠️ ЧЕТЫРЕ — КОМПРОМИСС, А НЕ КРУГЛОЕ ЧИСЛО.
  /// Профиль «Авто» у владельца — балансировщик над сотней узлов; поднимать
  /// сотню инбаундов ради одной плашки нельзя, а один узел (как было до
  /// 19.08.2026) врёт, если именно он мёртв.
  static const overrideProbeCandidates = 4;

  /// Теги узлов, ЧЕРЕЗ КОТОРЫЕ пойдут пробы, в порядке предпочтения.
  ///
  /// ⚠️ ЗАЧЕМ ИХ НЕСКОЛЬКО. Профиль «Авто …» — это БАЛАНСИРОВЩИК: в реальной
  /// работе он берёт живой узел из сотни. Харнесс же с 1.4.3 мерил РОВНО ОДИН
  /// узел — первый, — и если именно он мёртв, профиль показывал «n/a» всегда.
  /// Проверено на данных владельца 19.08.2026: у профиля «Авто (YouTube)» узел
  /// с тегом `proxy` числится `failed` в его же результатах пинга, а профиль в
  /// каждом прогоне давал ноль рабочих. В журнале это выглядело как «рабочих 0
  /// из 1» — и так во всех прогонах: 77 из 107 при 24 профилях, 83 из 101 при
  /// 18 профилях, то есть НИ ОДИН профиль не прошёл ни разу.
  ///
  /// ⚠️ Балансировщик в харнесс по-прежнему не попадает (урок 1.4.3): у него
  /// нет данных наблюдателя, и он уводит пробу в `fallbackTag`, то есть в
  /// `direct` — цифра получалась про прямой канал пользователя.
  ///
  /// ⚠️ Кандидаты берутся С РАЗБЕГОМ по списку, а не подряд. Соседние узлы у
  /// панелей — обычно одна площадка: упала она, и четыре подряд взятых узла
  /// мертвы все четыре, а разбег даёт четыре разных места.
  static List<String> probeExitTags(
    Map<String, dynamic> routing,
    List outbounds, {
    int limit = overrideProbeCandidates,
  }) {
    final pool = _probePool(routing, outbounds);
    if (pool.isEmpty) return const [];
    final tags = [for (final o in pool) '${o['tag']}'];
    // Узел с тегом `proxy` — тот, чей адрес показан в строке сервера; он идёт
    // первым, чтобы привычная цифра осталась привычной.
    final first = tags.indexOf('proxy');
    final ordered = <String>[if (first >= 0) tags[first]];
    if (tags.length <= limit) {
      for (final t in tags) {
        if (!ordered.contains(t)) ordered.add(t);
      }
      return ordered;
    }
    final step = tags.length ~/ limit;
    for (var i = 0; ordered.length < limit && i < tags.length; i += step) {
      if (!ordered.contains(tags[i])) ordered.add(tags[i]);
    }
    return ordered;
  }

  /// Один тег — для мест, где кандидат нужен ровно один.
  static String? probeExitTag(Map<String, dynamic> routing, List outbounds) {
    final tags = probeExitTags(routing, outbounds, limit: 1);
    return tags.isEmpty ? null : tags.first;
  }

  static List<Map> _probePool(Map<String, dynamic> routing, List outbounds) {
    final proxies = [
      for (final o in outbounds)
        if (o is Map && _isProxyOutbound(o) && '${o['tag'] ?? ''}'.isNotEmpty)
          o,
    ];
    if (proxies.isEmpty) {
      // Конфиг без прокси-outbound'ов (чужая правка из одних freedom) — берём
      // первый тег, какой есть: измерять там нечего, но конфиг обязан остаться
      // валидным, иначе ядро не поднимется и вердикт станет выдуманным.
      for (final o in outbounds) {
        if (o is Map && '${o['tag'] ?? ''}'.isNotEmpty) return [o];
      }
      return const [];
    }

    final selectors = _balancerSelectors(routing);
    final matching = selectors.isEmpty
        ? proxies
        : [
            for (final o in proxies)
              if (selectors.any((p) => '${o['tag']}'.startsWith(p))) o,
          ];
    // Селектор не совпал ни с чем (профиль ссылается на теги, которых нет) —
    // мерим первый прокси, а не отказываемся: узлы-то в конфиге настоящие.
    return matching.isEmpty ? proxies : matching;
  }

  static bool _isProxyOutbound(Map o) {
    final proto = '${o['protocol']}';
    return proto != 'freedom' && proto != 'blackhole' && proto != 'dns';
  }

  /// `selector` балансировщика, на который ссылается первое правило профиля.
  /// Пусто — балансировщика нет либо он объявлен без селектора.
  static List<String> _balancerSelectors(Map<String, dynamic> routing) {
    String? balancerTag;
    final rules = routing['rules'];
    if (rules is List) {
      for (final r in rules) {
        if (r is Map && r['balancerTag'] != null) {
          balancerTag = '${r['balancerTag']}';
          break;
        }
      }
    }
    if (balancerTag == null) return const [];
    final balancers = routing['balancers'];
    if (balancers is! List) return const [];
    for (final b in balancers) {
      if (b is! Map || '${b['tag']}' != balancerTag) continue;
      final sel = b['selector'];
      if (sel is! List) return const [];
      return [
        for (final s in sel)
          if ('$s'.isNotEmpty) '$s',
      ];
    }
    return const [];
  }
}
