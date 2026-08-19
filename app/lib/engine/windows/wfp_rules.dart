/// СОСТАВ БЛОКИРОВКИ: ЧИСТЫЙ ПОСТРОИТЕЛЬ, БЕЗ ЕДИНОГО ВЫЗОВА К СИСТЕМЕ.
///
/// ⚠️ РАЗДЕЛЕНИЕ ЗДЕСЬ — НЕ АККУРАТНОСТЬ, А ЕДИНСТВЕННЫЙ СПОСОБ ЭТО ПРОВЕРИТЬ.
/// Фильтры WFP действуют на сеть ВСЕЙ машины, а тесты гоняются на машине
/// владельца, где в это время идёт его работа. Значит «поставить и посмотреть»
/// нельзя в принципе. Зато список правил — обычные данные: его можно построить,
/// сравнить и разобрать по косточкам, ни разу не тронув систему.
///
/// ⚠️ СЛОЁВ РОВНО ЧЕТЫРЕ, И ЭТО ПРОВЕРЕННОЕ РЕШЕНИЕ, А НЕ НЕДОДЕЛКА.
/// `ALE_AUTH_LISTEN` не нужен: он про право слушать порт, а не про исходящие
/// соединения, и блокировка на нём ломает локальные сервисы, ничего не закрывая
/// снаружи. `OUTBOUND_IPPACKET` не нужен тем более: он ниже ALE, не знает ни
/// процесса, ни соединения, и правило там режет наши же служебные пакеты.
/// Ни WireGuard, ни Mullvad не ставят фильтров ни на том, ни на другом —
/// проверено по их исходникам. Не «улучшать» этот список.
library;

import 'dart:io';

import 'wfp_layout.dart';

/// Что именно перекрываем и что оставляем открытым.
class KillSwitchPlan {
  /// Адреса VPN-серверов. ⚠️ Всегда разрешены: иначе ядру некуда постучаться,
  /// туннель не поднимется заново, и блокировка станет вечной.
  final Set<String> allowServerIps;

  /// Разрешить своим бинарям (клиент и ядра) ходить мимо блокировки.
  final bool allowOwnBinaries;

  /// Полные пути своих бинарей. Пусто — правило не строится.
  final List<String> ownBinaryPaths;

  final bool allowLoopback;

  /// Локальная сеть: принтеры, NAS, шлюз. ⚠️ Публичный адрес это не раскрывает
  /// (пакеты не покидают сегмент), но лазейку в виде прокси на соседней машине
  /// открывает — поэтому решает пользователь, а не умолчание в коде.
  final bool allowLan;

  /// DHCP и соседи IPv6. ⚠️ ОТДЕЛЬНО ОТ [allowLan] И ПО УМОЛЧАНИЮ ВКЛЮЧЕНО:
  /// это не «доступ к локальной сети», а условие того, что у машины вообще
  /// останется адрес. Аренда DHCP истекает и во время блокировки; запретив
  /// продление, мы оставили бы человека без сети и ПОСЛЕ снятия защиты.
  final bool allowDhcpAndNdp;

  /// LUID адаптера туннеля. ⚠️ Без него блокировка режет и сам VPN: трафик
  /// приложений уходит В туннель, а туннель — это тоже интерфейс.
  /// В момент первого подъёма он ещё НЕ ИЗВЕСТЕН — адаптера не существует,
  /// пока ядро не запустилось. Поэтому здесь `null` — законное значение, а
  /// правило добавляется вторым заходом, когда туннель поднялся.
  final int? tunnelInterfaceLuid;

  /// Пути приложений, которым закрываем сеть (режим «только отмеченные»).
  final List<String> blockedAppPaths;

  /// Блокировать всё подряд (режимы «Всё через VPN» и «кроме отмеченных»).
  final bool blockAll;

  const KillSwitchPlan({
    required this.allowServerIps,
    required this.allowOwnBinaries,
    required this.allowLoopback,
    required this.allowLan,
    required this.blockedAppPaths,
    required this.blockAll,
    this.allowDhcpAndNdp = true,
    this.ownBinaryPaths = const [],
    this.tunnelInterfaceLuid,
  });

  /// Есть ли что блокировать вообще.
  bool get isEmpty => !blockAll && blockedAppPaths.isEmpty;

  /// Тот же план, но со списком своих бинарей.
  ///
  /// ⚠️ ПОДСТАВЛЯЕТ ПОМОЩНИК, А НЕ ИНТЕРФЕЙС. Он и есть `silentgate.exe`, а
  /// ядра лежат рядом с ним — передавать это файлом значило бы завести второй
  /// источник правды о том, что помощник знает точнее всех.
  KillSwitchPlan withOwnBinaries(List<String> paths) => KillSwitchPlan(
        allowServerIps: allowServerIps,
        allowOwnBinaries: allowOwnBinaries,
        allowLoopback: allowLoopback,
        allowLan: allowLan,
        blockedAppPaths: blockedAppPaths,
        blockAll: blockAll,
        allowDhcpAndNdp: allowDhcpAndNdp,
        ownBinaryPaths: paths,
        tunnelInterfaceLuid: tunnelInterfaceLuid,
      );

  /// Тот же план, но с известным теперь адаптером туннеля.
  KillSwitchPlan withTunnelLuid(int luid) => KillSwitchPlan(
        allowServerIps: allowServerIps,
        allowOwnBinaries: allowOwnBinaries,
        allowLoopback: allowLoopback,
        allowLan: allowLan,
        blockedAppPaths: blockedAppPaths,
        blockAll: blockAll,
        allowDhcpAndNdp: allowDhcpAndNdp,
        ownBinaryPaths: ownBinaryPaths,
        tunnelInterfaceLuid: luid,
      );
}

/// Вид значения условия. Разные виды кладутся в память по-разному, и путать их
/// нельзя: ядро прочитает по типу, а не по смыслу.
enum WfpValueKind {
  /// Полный путь к бинарю → `FWP_BYTE_BLOB` через `FwpmGetAppIdFromFileName0`.
  appId,

  /// IPv4-подсеть → `FWP_V4_ADDR_AND_MASK` (адрес и маска в ХОЗЯЙСКОМ порядке).
  v4Net,

  /// IPv6-подсеть → `FWP_V6_ADDR_AND_MASK` (16 байт адреса + длина префикса).
  v6Net,

  /// LUID интерфейса → `FWP_UINT64` (по указателю!).
  u64,

  /// Набор флагов условия → `FWP_UINT32`.
  u32,

  /// Номер порта или тип ICMP → `FWP_UINT16`.
  u16,

  /// Номер протокола → `FWP_UINT8`.
  u8,
}

/// Одно условие фильтра.
class WfpCondition {
  final WfpGuid field;
  final int matchType;
  final WfpValueKind kind;

  /// Для [WfpValueKind.appId] — путь; иначе не используется.
  final String path;

  /// Для сетей — адрес в разобранном виде; для чисел — само число.
  final List<int> bytes;
  final int number;

  const WfpCondition({
    required this.field,
    required this.matchType,
    required this.kind,
    this.path = '',
    this.bytes = const [],
    this.number = 0,
  });

  @override
  String toString() => '${fieldName(field)} ${_kindName()}';

  String _kindName() {
    switch (kind) {
      case WfpValueKind.appId:
        return 'appId($path)';
      case WfpValueKind.v4Net:
        return 'v4(${bytes.join('.')}/$number)';
      case WfpValueKind.v6Net:
        return 'v6(/$number)';
      case WfpValueKind.u64:
        return 'u64($number)';
      case WfpValueKind.u32:
        return 'u32(0x${number.toRadixString(16)})';
      case WfpValueKind.u16:
        return 'u16($number)';
      case WfpValueKind.u8:
        return 'u8($number)';
    }
  }

  /// Короткое имя поля — для журнала и тестов.
  static String fieldName(WfpGuid g) {
    if (identical(g, WfpConditions.aleAppId)) return 'appId';
    if (identical(g, WfpConditions.ipRemoteAddress)) return 'remoteAddr';
    if (identical(g, WfpConditions.ipLocalInterface)) return 'localIface';
    if (identical(g, WfpConditions.flags)) return 'flags';
    if (identical(g, WfpConditions.ipProtocol)) return 'proto';
    if (identical(g, WfpConditions.ipRemotePort)) return 'rport';
    if (identical(g, WfpConditions.ipLocalPortOrIcmpType)) return 'lport/icmp';
    return g.toString();
  }
}

/// Одно правило: действие + вес + слои + условия.
///
/// ⚠️ ПОВТОР ОДНОГО ПОЛЯ В УСЛОВИЯХ — ЭТО «ИЛИ», А НЕ ОШИБКА. Так устроен сам
/// WFP: идущие подряд условия с одинаковым `fieldKey` объединяются по «или»,
/// разные поля — по «и». На этом держится правило «порт 53 по UDP ИЛИ TCP».
class WfpRule {
  /// Человеческое имя — попадает в `displayData` и видно в `netsh wfp show state`.
  final String name;
  final int action;
  final int weight;
  final List<WfpGuid> layers;
  final List<WfpCondition> conditions;

  const WfpRule({
    required this.name,
    required this.action,
    required this.weight,
    required this.layers,
    this.conditions = const [],
  });

  bool get isBlock => action == WfpConst.actionBlock;

  /// Сколько фильтров породит правило: по одному на каждый слой.
  int get filterCount => layers.length;

  @override
  String toString() {
    final what = isBlock ? 'БЛОК' : 'ПУСК';
    final conds = conditions.map((c) => c.toString()).join(', ');
    return '$what w$weight [${layers.length} сл.] $name'
        '${conds.isEmpty ? '' : ' — $conds'}';
  }
}

/// Веса внутри нашего подслоя.
///
/// ⚠️ ПОРЯДОК ЗДЕСЬ — ЭТО И ЕСТЬ ЛОГИКА KILL SWITCH. В одном подслое побеждает
/// фильтр с бо́льшим весом. Лестница снизу вверх:
///
/// ```
///  0  блок всего
///  4  локальная сеть
///  5  блок конкретного приложения   ← ВЫШЕ локальной сети, и это важно
///  6  DHCP и соседи IPv6
///  8  адреса VPN-серверов
///  9  блок DNS                      ← ВЫШЕ локальной сети, и это важно
/// 10  интерфейс туннеля
/// 11  свои бинари
/// 12  loopback
/// ```
///
/// ⚠️ ДВА МЕСТА, ГДЕ ПОРЯДОК НЕОЧЕВИДЕН И РЕШАЕТ ВСЁ:
///  * блок приложения (5) стоит ВЫШЕ разрешения локальной сети (4). Иначе
///    приложение, которому мы закрыли сеть, продолжало бы ходить к роутеру — а
///    там и резолвер, и чей-нибудь прокси.
///  * блок DNS (9) стоит ВЫШЕ разрешения локальной сети (4), но НИЖЕ туннеля
///    (10) и своих бинарей (11). То есть DNS внутри туннеля жив, наш клиент
///    резолвит панель, а запрос к роутеру — не проходит.
///
/// Диапазон 0…15 задан самим WFP для веса типа `FWP_UINT8`.
class WfpWeights {
  static const int block = 0;
  static const int lan = 4;
  static const int blockApp = 5;
  static const int dhcpAndNdp = 6;
  static const int serverIps = 8;
  static const int blockDns = 9;
  static const int tunnelInterface = 10;
  static const int ownBinaries = 11;
  static const int loopback = 12;

  /// Потолок веса типа `FWP_UINT8` — больше ядро не примет.
  static const int max = 15;
}

/// Построить список правил по плану.
///
/// ⚠️ ПОРЯДОК В СПИСКЕ ЗНАЧЕНИЯ НЕ ИМЕЕТ — решает ВЕС. Список идёт «сначала
/// запреты, потом разрешения» только ради читаемости журнала и тестов.
List<WfpRule> buildWfpRules(KillSwitchPlan plan) {
  final rules = <WfpRule>[];
  if (plan.isEmpty) return rules;

  // ── ЧТО ЗАКРЫВАЕМ ─────────────────────────────────────────────────────────
  if (plan.blockAll) {
    rules.add(const WfpRule(
      name: 'SilentGate: блокировать весь трафик',
      action: WfpConst.actionBlock,
      weight: WfpWeights.block,
      layers: WfpLayers.all,
    ));

    // ⚠️ БЛОК DNS — ОТДЕЛЬНЫМ ПРАВИЛОМ, И ВОТ ПОЧЕМУ ОН ВООБЩЕ НУЖЕН.
    // Разрешение локальной сети выпускает запросы к роутеру, а роутер — это
    // резолвер провайдера. Пока туннель лежит между попытками, провайдер видел
    // бы ПОЛНЫЙ список посещаемых доменов, при том что интерфейс обещает
    // защиту. Общий блок этого не ловит: он легче разрешения локальной сети.
    //
    // Ставится ТОЛЬКО при полной блокировке. В режиме «только отмеченные»
    // неотмеченные приложения обязаны работать как обычно — включая их DNS.
    rules.add(WfpRule(
      name: 'SilentGate: блок DNS мимо туннеля',
      action: WfpConst.actionBlock,
      weight: WfpWeights.blockDns,
      // Только исходящие: входящих соединений на 53-й порт у клиента не бывает,
      // а фильтр на приёме мешал бы своему же резолверу.
      layers: const [WfpLayers.aleAuthConnectV4, WfpLayers.aleAuthConnectV6],
      conditions: [
        _remotePort(53),
        // Повтор поля «протокол» = «UDP ИЛИ TCP» (правило самого WFP).
        _proto(IpProto.udp),
        _proto(IpProto.tcp),
      ],
    ));
  } else {
    // Школа Mullvad: исключение из туннеля остаётся исключением и из
    // блокировки. Режем ровно те приложения, что шли через VPN, — остальным
    // пользователь сам сказал, что VPN им не нужен.
    for (final path in plan.blockedAppPaths) {
      rules.add(WfpRule(
        name: 'SilentGate: блок ${baseName(path)}',
        action: WfpConst.actionBlock,
        weight: WfpWeights.blockApp,
        layers: WfpLayers.all,
        conditions: [_appId(path)],
      ));
    }
  }

  // ── ЧТО ОСТАВЛЯЕМ ОТКРЫТЫМ ────────────────────────────────────────────────

  // ⚠️ Loopback — самым большим весом. Через 127.0.0.1 ходят локальные прокси
  // ядра, управляющий API и пробы; закрыв его, мы задушили бы само приложение.
  if (plan.allowLoopback) {
    rules.add(const WfpRule(
      name: 'SilentGate: loopback',
      action: WfpConst.actionPermit,
      weight: WfpWeights.loopback,
      layers: WfpLayers.all,
      conditions: [
        WfpCondition(
          field: WfpConditions.flags,
          matchType: WfpConst.matchFlagsAnySet,
          kind: WfpValueKind.u32,
          number: WfpConst.conditionFlagIsLoopback,
        ),
      ],
    ));
  }

  // ⚠️ Свои бинари. Без них клиент не проверит канал, не обновит подписку и не
  // объяснит человеку, что происходит: мёртвая сеть и молчащее окно. И они же
  // должны уметь резолвить имя сервера — поэтому стоят ВЫШЕ блока DNS.
  //
  // Цена честная, и её надо знать: пока блокировка поднята, эти запросы идут
  // под реальным адресом — но уходят они на панель, которая и так знает
  // владельца, и на его же серверы.
  //
  // ⚠️ Условия по ВЛАДЕЛЬЦУ процесса (`ALE_USER_ID`) здесь нет — сознательно.
  // WireGuard его ставит, чтобы чужой процесс, запущенный из того же файла, не
  // получил разрешение. У нас такого сценария нет: файл наш, и запускает его
  // тот же пользователь. Появится многопользовательский случай — добавить.
  if (plan.allowOwnBinaries) {
    for (final path in plan.ownBinaryPaths) {
      rules.add(WfpRule(
        name: 'SilentGate: свой ${baseName(path)}',
        action: WfpConst.actionPermit,
        weight: WfpWeights.ownBinaries,
        layers: WfpLayers.all,
        conditions: [_appId(path)],
      ));
    }
  }

  // ⚠️ САМ ТУННЕЛЬ. Трафик приложений уходит В адаптер туннеля, и без этого
  // правила блокировка резала бы ровно то, ради чего затевалась.
  final luid = plan.tunnelInterfaceLuid;
  if (luid != null) {
    rules.add(WfpRule(
      name: 'SilentGate: интерфейс туннеля',
      action: WfpConst.actionPermit,
      weight: WfpWeights.tunnelInterface,
      layers: WfpLayers.all,
      conditions: [
        WfpCondition(
          field: WfpConditions.ipLocalInterface,
          matchType: WfpConst.matchEqual,
          kind: WfpValueKind.u64,
          number: luid,
        ),
      ],
    ));
  }

  // ⚠️ Адреса серверов — иначе блокировка вечная: переподключиться не выйдет.
  // Адреса берём УЖЕ ОТРЕЗОЛВЛЕННЫМИ: резолв под поднятой блокировкой сам
  // уткнулся бы в неё (на Windows DNS-запрос принадлежит svchost.exe, а он не
  // наш бинарь и разрешения не получает).
  for (final ip in _sorted(plan.allowServerIps)) {
    final rule = _hostRule('SilentGate: сервер $ip', WfpWeights.serverIps, ip);
    if (rule != null) rules.add(rule);
  }

  // ⚠️ DHCP и соседи IPv6 — ВСЕГДА и НЕЗАВИСИМО от локальной сети. Аренда
  // адреса истекает и во время блокировки: запретив продление, мы оставили бы
  // машину без адреса и ПОСЛЕ снятия защиты. Задаются портами и типами ICMP, а
  // не адресами: у DHCP-ответа адрес отправителя заранее не известен.
  if (plan.allowDhcpAndNdp) {
    rules.addAll(_dhcpAndNdpRules());
  }

  // Локальная сеть: принтеры, NAS, шлюз.
  if (plan.allowLan) {
    for (final net in lanNets) {
      final rule =
          _netRule('SilentGate: локальная сеть $net', WfpWeights.lan, net);
      if (rule != null) rules.add(rule);
    }
  }

  return rules;
}

/// Правила DHCP и обнаружения соседей IPv6.
///
/// Раскладка снята с WireGuard for Windows (`tunnel/firewall/rules.go`) —
/// у них она обкатана годами, и выдумывать свою здесь незачем.
List<WfpRule> _dhcpAndNdpRules() {
  const w = WfpWeights.dhcpAndNdp;
  return [
    WfpRule(
      name: 'SilentGate: DHCPv4 запрос',
      action: WfpConst.actionPermit,
      weight: w,
      layers: const [WfpLayers.aleAuthConnectV4],
      conditions: [
        _proto(IpProto.udp),
        _localPort(68),
        _remotePort(67),
      ],
    ),
    WfpRule(
      name: 'SilentGate: DHCPv4 ответ',
      action: WfpConst.actionPermit,
      weight: w,
      layers: const [WfpLayers.aleAuthRecvAcceptV4],
      // ⚠️ БЕЗ УСЛОВИЯ ПО АДРЕСУ: сервер отвечает с адреса, которого мы ещё не
      // знаем (а при первой аренде у нас и своего адреса нет).
      conditions: [
        _proto(IpProto.udp),
        _localPort(68),
        _remotePort(67),
      ],
    ),
    WfpRule(
      name: 'SilentGate: DHCPv6 запрос',
      action: WfpConst.actionPermit,
      weight: w,
      layers: const [WfpLayers.aleAuthConnectV6],
      conditions: [
        _proto(IpProto.udp),
        _localPort(546),
        _remotePort(547),
      ],
    ),
    WfpRule(
      name: 'SilentGate: DHCPv6 ответ',
      action: WfpConst.actionPermit,
      weight: w,
      layers: const [WfpLayers.aleAuthRecvAcceptV6],
      conditions: [
        _proto(IpProto.udp),
        _localPort(546),
        _remotePort(547),
      ],
    ),
    // Обнаружение соседей: без него IPv6 в локальном сегменте не работает
    // вовсе — ни шлюз, ни адрес не находятся.
    // ⚠️ Тип ICMP лежит в поле ЛОКАЛЬНОГО ПОРТА: это не хитрость, а способ,
    // которым WFP описывает ICMP (замер показал, что `ICMP_TYPE` и
    // `IP_LOCAL_PORT` — один и тот же GUID).
    for (final type in const [133, 134, 135, 136, 137])
      WfpRule(
        name: 'SilentGate: соседи IPv6 (ICMPv6 $type)',
        action: WfpConst.actionPermit,
        weight: w,
        layers: WfpLayers.v6,
        conditions: [
          _proto(IpProto.icmpV6),
          _localPort(type),
        ],
      ),
  ];
}

/// Список локальных сетей одним местом — чтобы его было видно и можно было
/// обсуждать, а не выискивать по коду.
const lanNets = <String>[
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '169.254.0.0/16', // APIPA
  '224.0.0.0/4', // многоадресная рассылка
  '255.255.255.255/32', // широковещание
  'fe80::/10', // link-local IPv6
  'ff00::/8', // многоадресная рассылка IPv6
];

WfpCondition _appId(String path) => WfpCondition(
      field: WfpConditions.aleAppId,
      matchType: WfpConst.matchEqual,
      kind: WfpValueKind.appId,
      path: path,
    );

WfpCondition _proto(int p) => WfpCondition(
      field: WfpConditions.ipProtocol,
      matchType: WfpConst.matchEqual,
      kind: WfpValueKind.u8,
      number: p,
    );

WfpCondition _remotePort(int p) => WfpCondition(
      field: WfpConditions.ipRemotePort,
      matchType: WfpConst.matchEqual,
      kind: WfpValueKind.u16,
      number: p,
    );

/// Локальный порт — он же тип ICMP (см. [WfpConditions.ipLocalPortOrIcmpType]).
WfpCondition _localPort(int p) => WfpCondition(
      field: WfpConditions.ipLocalPortOrIcmpType,
      matchType: WfpConst.matchEqual,
      kind: WfpValueKind.u16,
      number: p,
    );

List<String> _sorted(Set<String> s) => s.toList()..sort();

/// Имя файла из полного пути — для человеческих имён правил.
String baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Правило на один конкретный адрес (маска целиком).
WfpRule? _hostRule(String name, int weight, String ip) {
  final addr = InternetAddress.tryParse(ip);
  if (addr == null) return null;
  final v4 = addr.type == InternetAddressType.IPv4;
  return _netRule(name, weight, '$ip/${v4 ? 32 : 128}');
}

/// Правило на подсеть. Возвращает `null`, если запись разобрать не удалось —
/// ⚠️ битая строка не имеет права уронить ВЕСЬ набор правил: без набора нет и
/// блокировки, то есть одна опечатка отключала бы защиту целиком.
WfpRule? _netRule(String name, int weight, String cidr) {
  final slash = cidr.indexOf('/');
  if (slash <= 0) return null;
  final addr = InternetAddress.tryParse(cidr.substring(0, slash));
  final bits = int.tryParse(cidr.substring(slash + 1));
  if (addr == null || bits == null || bits < 0) return null;

  final v4 = addr.type == InternetAddressType.IPv4;
  if (bits > (v4 ? 32 : 128)) return null;

  return WfpRule(
    name: name,
    action: WfpConst.actionPermit,
    weight: weight,
    layers: v4 ? WfpLayers.v4 : WfpLayers.v6,
    conditions: [
      WfpCondition(
        field: WfpConditions.ipRemoteAddress,
        matchType: WfpConst.matchEqual,
        kind: v4 ? WfpValueKind.v4Net : WfpValueKind.v6Net,
        bytes: addr.rawAddress,
        number: bits,
      ),
    ],
  );
}
