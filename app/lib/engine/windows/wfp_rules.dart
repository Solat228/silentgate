/// СОСТАВ БЛОКИРОВКИ: ЧИСТЫЙ ПОСТРОИТЕЛЬ, БЕЗ ЕДИНОГО ВЫЗОВА К СИСТЕМЕ.
///
/// ⚠️ РАЗДЕЛЕНИЕ ЗДЕСЬ — НЕ АККУРАТНОСТЬ, А ЕДИНСТВЕННЫЙ СПОСОБ ЭТО ПРОВЕРИТЬ.
/// Фильтры WFP действуют на сеть ВСЕЙ машины, а тесты гоняются на машине
/// владельца, где в это время идёт его работа. Значит «поставить и посмотреть»
/// нельзя в принципе. Зато список правил — обычные данные: его можно построить,
/// сравнить и разобрать по косточкам, ни разу не тронув систему.
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

  /// LUID адаптера туннеля. ⚠️ Без него блокировка режет и сам VPN: трафик
  /// приложений уходит В туннель, а туннель — это тоже интерфейс.
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
    this.ownBinaryPaths = const [],
    this.tunnelInterfaceLuid,
  });

  /// Есть ли что блокировать вообще.
  bool get isEmpty => !blockAll && blockedAppPaths.isEmpty;
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

  /// LUID интерфейса → `FWP_UINT64`.
  u64,

  /// Набор флагов условия → `FWP_UINT32`.
  u32,
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
    }
  }

  /// Короткое имя поля — для журнала и тестов.
  static String fieldName(WfpGuid g) {
    if (identical(g, WfpConditions.aleAppId)) return 'appId';
    if (identical(g, WfpConditions.ipRemoteAddress)) return 'remoteAddr';
    if (identical(g, WfpConditions.ipLocalInterface)) return 'localIface';
    if (identical(g, WfpConditions.flags)) return 'flags';
    return g.toString();
  }
}

/// Одно правило: действие + вес + слои + условия.
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
    return '$what w$weight [${layers.length} сл.] $name${conds.isEmpty ? '' : ' — $conds'}';
  }
}

/// Веса внутри нашего подслоя.
///
/// ⚠️ ПОРЯДОК ЗДЕСЬ — ЭТО И ЕСТЬ ЛОГИКА KILL SWITCH. В одном подслое побеждает
/// фильтр с бо́льшим весом, поэтому блок стоит на самом дне: любое разрешение
/// перекрывает его, и ни одно разрешение не может «случайно» оказаться ниже.
/// Диапазон 0…15 задан самим WFP для веса типа `FWP_UINT8`.
class WfpWeights {
  static const int block = 0;
  static const int lan = 4;
  static const int ownBinaries = 6;
  static const int serverIps = 8;
  static const int tunnelInterface = 10;
  static const int loopback = 12;

  /// Потолок веса типа `FWP_UINT8` — больше ядро не примет.
  static const int max = 15;
}

/// Построить список правил по плану.
///
/// ⚠️ ПОРЯДОК В СПИСКЕ ЗНАЧЕНИЯ НЕ ИМЕЕТ — решает ВЕС. Список идёт «сначала
/// блок, потом разрешения» только ради читаемости журнала и тестов.
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
  } else {
    // Школа Mullvad: исключение из туннеля остаётся исключением и из
    // блокировки. Режем ровно те приложения, что шли через VPN, — остальным
    // пользователь сам сказал, что VPN им не нужен.
    for (final path in plan.blockedAppPaths) {
      rules.add(WfpRule(
        name: 'SilentGate: блок ${baseName(path)}',
        action: WfpConst.actionBlock,
        weight: WfpWeights.block,
        layers: WfpLayers.all,
        conditions: [
          WfpCondition(
            field: WfpConditions.aleAppId,
            matchType: WfpConst.matchEqual,
            kind: WfpValueKind.appId,
            path: path,
          ),
        ],
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

  // ⚠️ Свои бинари. Без них клиент не проверит канал, не обновит подписку и не
  // объяснит человеку, что происходит: мёртвая сеть и молчащее окно.
  // Цена честная, и её надо знать: пока блокировка поднята, эти запросы идут
  // под реальным адресом — но уходят они на панель, которая и так знает
  // владельца, и на его же серверы.
  if (plan.allowOwnBinaries) {
    for (final path in plan.ownBinaryPaths) {
      rules.add(WfpRule(
        name: 'SilentGate: свой ${baseName(path)}',
        action: WfpConst.actionPermit,
        weight: WfpWeights.ownBinaries,
        layers: WfpLayers.all,
        conditions: [
          WfpCondition(
            field: WfpConditions.aleAppId,
            matchType: WfpConst.matchEqual,
            kind: WfpValueKind.appId,
            path: path,
          ),
        ],
      ));
    }
  }

  // Локальная сеть, DHCP и NDP. Широковещание и многоадресная рассылка входят
  // сюда же: DHCP-клиент шлёт на 255.255.255.255, а соседи IPv6 — на ff02::.
  if (plan.allowLan) {
    for (final net in lanNets) {
      final rule =
          _netRule('SilentGate: локальная сеть $net', WfpWeights.lan, net);
      if (rule != null) rules.add(rule);
    }
  }

  return rules;
}

/// Список локальных сетей одним местом — чтобы его было видно и можно было
/// обсуждать, а не выискивать по коду.
const lanNets = <String>[
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '169.254.0.0/16', // APIPA
  '224.0.0.0/4', // многоадресная рассылка
  '255.255.255.255/32', // широковещание, в том числе DHCP
  'fe80::/10', // link-local IPv6, там же NDP
  'ff00::/8', // многоадресная рассылка IPv6
];

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
