import 'dart:convert';

import '../models/vpn_server.dart';

/// Какие серверы подписки входят в какой профиль «Авто» панели.
///
/// [members]: индекс профиля → исходные индексы его серверов, в порядке
/// списка. [ownerOf]: индекс сервера → индекс профиля.
class AutoBinding {
  final Map<int, List<int>> members;
  final Map<int, int> ownerOf;

  const AutoBinding({this.members = const {}, this.ownerOf = const {}});

  static const empty = AutoBinding();

  bool get isEmpty => members.isEmpty;
}

/// Привязка серверов к страновым профилям «Авто» по их ВНУТРЕННЕМУ списку.
///
/// Решение владельца 10.10.2026. Панель отдаёт профиль «🇵🇱 🚀Польша» с
/// раздельным туннелированием и балансировщиком, а в нём — outbound'ы тех же
/// серверов, что лежат в подписке отдельными строками («Польша 1.x»,
/// «Польша 2.x»). Такие серверы показываются ПОД своим профилем, а не там, где
/// их поставил провайдер.
///
/// ⚠️ СРАВНЕНИЕ ПО САМОМУ OUTBOUND'У, А НЕ ПО ИМЕНИ ИЛИ ФЛАГУ. Требование
/// владельца: «чтобы ничего не перепутать». У одного узла панель держит
/// несколько входов с тем же адресом, портом и uuid, и они различаются только
/// sni, отпечатком или транспортом. Сравнение по адресу и логину склеивало бы
/// их: на подписке владельца так набиралось 36 «совпадений» на 13 узлов
/// профиля. Сравнение целого outbound'а без `tag` дало ровно 12 из 13, и
/// тринадцатым оказался hysteria2 (его сравниваем отдельно, см.
/// [outboundSignature]).
///
/// Правила:
///  * сервер идёт к САМОМУ УЗКОМУ профилю, где он есть (меньше всего
///    outbound'ов), при равенстве — к стоящему выше;
///  * профиль, который целиком содержит серверы других профилей («Авто
///    YouTube», «Белые списки» — там все 81 узел), группой не становится:
///    иначе в нём оказались бы остатки, не попавшие в страны, вроде мостов;
///  * серверов, которые в группу не попали, это не касается: они
///    группируются по странам, как раньше (`ServerGroups`).
///
/// Функция чистая, но разбор конфигов профилей тяжёлый (у владельца 25
/// профилей до 38 КБ), а зовут её на каждой перерисовке списка. Поэтому
/// последний результат кэшируется по ТОЖДЕСТВУ объектов серверов: `AppState`
/// пересоздаёт их только при пересборке списка.
abstract final class AutoGroups {
  static List<VpnServer>? _lastServers;
  static Set<int>? _lastSkip;
  static AutoBinding _lastResult = AutoBinding.empty;

  /// Привязка для [servers]. [skip] — индексы, которые не привязываются
  /// (закреплённые: они стоят сверху ради того, чтобы быть под рукой).
  static AutoBinding bind(List<VpnServer> servers, {Set<int> skip = const {}}) {
    final prev = _lastServers;
    if (prev != null &&
        prev.length == servers.length &&
        _sameSet(_lastSkip!, skip)) {
      var same = true;
      for (var i = 0; i < servers.length; i++) {
        if (!identical(prev[i], servers[i])) {
          same = false;
          break;
        }
      }
      if (same) return _lastResult;
    }
    final result = compute(servers, skip: skip);
    _lastServers = List.of(servers);
    _lastSkip = Set.of(skip);
    _lastResult = result;
    return result;
  }

  /// То же без кэша — для тестов.
  static AutoBinding compute(List<VpnServer> servers,
      {Set<int> skip = const {}}) {
    // Подпись каждого обычного сервера.
    final sigOf = <int, String>{};
    for (var i = 0; i < servers.length; i++) {
      final s = servers[i];
      if (s.isPanelProfile || s.isNotice || skip.contains(i)) continue;
      if (isBridgeName(s.displayName)) continue;
      final sig = serverSignature(s);
      if (sig != null) sigOf[i] = sig;
    }
    if (sigOf.isEmpty) return AutoBinding.empty;

    // Состав каждого профиля: видимые серверы и число outbound'ов.
    final found = <int, Set<int>>{};
    final size = <int, int>{};
    for (var p = 0; p < servers.length; p++) {
      final s = servers[p];
      if (!s.isPanelProfile) continue;
      final sigs = profileSignatures(s.rawPanelConfig ?? '');
      if (sigs.isEmpty) continue;
      final m = {
        for (final e in sigOf.entries)
          if (sigs.contains(e.value)) e.key
      };
      if (m.isEmpty) continue;
      found[p] = m;
      size[p] = sigs.length;
    }

    final heads = [
      for (final p in found.keys)
        if (!_isUmbrella(p, found)) p
    ]..sort();

    final ownerOf = <int, int>{};
    for (final i in sigOf.keys) {
      int? best;
      for (final p in heads) {
        if (!found[p]!.contains(i)) continue;
        if (best == null || size[p]! < size[best]!) best = p;
      }
      if (best != null) ownerOf[i] = best;
    }
    final members = <int, List<int>>{};
    for (final i in ownerOf.keys.toList()..sort()) {
      (members[ownerOf[i]!] ??= []).add(i);
    }
    return AutoBinding(members: members, ownerOf: ownerOf);
  }

  /// Мост: вход в одной стране, выход в другой («Мск 2 -> Германия 2 (мост)»).
  ///
  /// ⚠️ МОСТ ПОД СТРАНОВУЮ ШАПКУ НЕ ИДЁТ, ДАЖЕ ЕСЛИ ПАНЕЛЬ ПОЛОЖИЛА ЕГО В
  /// ПРОФИЛЬ СТРАНЫ (владелец, 13.10.2026). Под «Германией» он выглядит
  /// обычным немецким узлом, а подключение к нему идёт через Россию — человек
  /// выбирал бы не то, что видит. Узнаём по названию: другого признака в
  /// подписке нет, а слово «мост» и стрелку панель ставит сама.
  static bool isBridgeName(String name) => _bridge.hasMatch(name);

  static final RegExp _bridge = RegExp(
      r'(?<![а-яёa-z])(мост|bridge)(?![а-яёa-z])|->|→|=>',
      caseSensitive: false,
      unicode: true);

  /// Зонтик — профиль, строго содержащий серверы ДВУХ непересекающихся
  /// профилей («Авто YouTube» содержит и Польшу, и Германию).
  ///
  /// ⚠️ ИМЕННО ДВУХ. Если бы хватало одного вложенного, маленький профиль
  /// вроде «Польша игровой» из одного узла лишал бы группы всю «Польшу»:
  /// её остальные серверы рассыпались бы обратно по списку.
  static bool _isUmbrella(int p, Map<int, Set<int>> found) {
    final mine = found[p]!;
    final inner = [
      for (final q in found.entries)
        if (q.key != p &&
            q.value.length < mine.length &&
            mine.containsAll(q.value))
          q.value
    ];
    for (var a = 0; a < inner.length; a++) {
      for (var b = a + 1; b < inner.length; b++) {
        if (!inner[a].any(inner[b].contains)) return true;
      }
    }
    return false;
  }

  /// Подпись обычного сервера или `null`, если сравнивать не с чем.
  ///
  /// Серверу из ссылок (без outbound'а панели) подпись даётся только для
  /// hysteria2: её панель в XRAY_JSON отдельной строкой не присылает, а в
  /// профиле она есть. Остальным ссылкам совпадать не с чем — у таких
  /// подписок нет и профилей.
  static String? serverSignature(VpnServer s) {
    final raw = s.rawOutboundJson ?? '';
    if (raw.trim().isNotEmpty) {
      try {
        final o = jsonDecode(raw);
        if (o is Map) return outboundSignature(o);
      } on FormatException {
        return null;
      }
      return null;
    }
    if (s.protocol == 'hysteria2') {
      return _hySig(s.address, s.port, s.id);
    }
    return null;
  }

  /// Подписи прокси-outbound'ов профиля. Служебные (`freedom`, `blackhole`,
  /// `dns`, `loopback`) не считаются: они есть в каждом профиле и ни с каким
  /// сервером не совпадают.
  static Set<String> profileSignatures(String rawConfig) {
    if (rawConfig.trim().isEmpty) return const {};
    final Object? cfg;
    try {
      cfg = jsonDecode(rawConfig);
    } on FormatException {
      return const {};
    }
    if (cfg is! Map || cfg['outbounds'] is! List) return const {};
    return {
      for (final o in cfg['outbounds'] as List)
        if (o is Map && !_service.contains(o['protocol']))
          if (outboundSignature(o) case final sig?) sig
    };
  }

  static const _service = {'freedom', 'blackhole', 'dns', 'loopback'};

  /// Подпись outbound'а Xray: весь объект без `tag` с отсортированными
  /// ключами. У hysteria — адрес, порт и пароль: так её узнаёт и сервер из
  /// ссылки `hysteria2://`, у которого outbound'а нет.
  static String? outboundSignature(Map o) {
    final proto = o['protocol'];
    if (proto == 'hysteria' || proto == 'hysteria2') {
      final st = o['settings'];
      final ss = o['streamSettings'];
      final hs = ss is Map ? ss['hysteriaSettings'] : null;
      final auth = hs is Map ? hs['auth'] : (st is Map ? st['password'] : null);
      if (st is! Map || st['address'] == null || st['port'] == null) return null;
      return _hySig('${st['address']}', int.tryParse('${st['port']}') ?? -1,
          '${auth ?? ''}');
    }
    final copy = Map.of(o)..remove('tag');
    return 'ob|${canonicalJson(copy)}';
  }

  static String _hySig(String address, int port, String auth) =>
      'hy|${address.trim().toLowerCase()}|$port|$auth';

  /// JSON с ключами по алфавиту на всех уровнях: порядок ключей в двух
  /// копиях одного outbound'а не обязан совпадать.
  static String canonicalJson(Object? v) {
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return '{${entries.map((e) => '${jsonEncode('${e.key}')}:${canonicalJson(e.value)}').join(',')}}';
    }
    if (v is List) return '[${v.map(canonicalJson).join(',')}]';
    return jsonEncode(v);
  }

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}
