import 'dart:convert';

import '../models/vpn_server.dart';
import 'country_flag.dart';

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

/// Привязка серверов к страновым профилям «Авто» по флагу страны (и составным
/// подпрофилям по outbound'у).
///
/// Правила (обновлено по решению владельца 10.11.2026):
///  * НЕподписанные страновые автосерверы («🇳🇱 🚀Нидерланды», «🇵🇱 🚀Польша»,
///    «🇷🇺🏳️ Москва», «🇩🇪 🚀Германия» и т.д.) собирают под себя ВСЕ обычные
///    серверы своего флага страны;
///  * если у одной страны есть дополнительный узкий подпрофиль (например,
///    «🇵🇱 Польша игровой» на 1 узел), узел с совпадающим outbound'ом идёт
///    в самый узкий профиль, а все остальные серверы этого флага — в основной
///    страновой автосервер;
///  * тематические профили без флага страны («🎬 Авто (YouTube)», «🏳️ Авто
///    Белые списки», «✈️ Авто Telegram») стоят сверху и локации в себя не
///    собирают;
///  * нижние именные авто-профили вида «🇳🇱🏳️ Авто The Netherlands»
///    ([isBottomNamedAutoProfile]) в группировку не входят и остаются внизу
///    списка в порядке панели;
///  * мосты ([isBridgeName]) в страновые профили не входят и собираются
///    отдельно в папку «🌉 Мосты» внизу списка.
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
    final plainIndices = <int>[];
    final sigOf = <int, String>{};
    final serverCountry = <int, List<String>>{};
    for (var i = 0; i < servers.length; i++) {
      final s = servers[i];
      if (s.isPanelProfile || s.isNotice || skip.contains(i)) continue;
      if (isBridgeName(s.displayName)) continue;
      plainIndices.add(i);
      serverCountry[i] = FlagUtil.isoCodesFromName(s.remark);
      final sig = serverSignature(s);
      if (sig != null) sigOf[i] = sig;
    }
    if (plainIndices.isEmpty) return AutoBinding.empty;

    final exactFound = <int, Set<int>>{};
    final flagFound = <int, Set<int>>{};
    final size = <int, int>{};
    for (var p = 0; p < servers.length; p++) {
      if (skip.contains(p)) continue;
      final s = servers[p];
      if (!s.isPanelProfile || s.isNotice) continue;
      if (isNonGroupProfileName(s.displayName)) continue;
      if (isBridgeName(s.displayName)) continue;
      if (isBottomNamedAutoProfile(s.remark)) continue;
      final pCountry = FlagUtil.isoCodesFromName(s.remark);
      if (pCountry.length > 1) continue;
      final sigs = profileSignatures(s.rawPanelConfig ?? '');
      if (sigs.isEmpty) continue;

      final exact = {
        for (final i in plainIndices)
          if (sigOf[i] != null &&
              sigs.contains(sigOf[i]!) &&
              _sameCountryScope(pCountry, serverCountry[i]!))
            i
      };
      final byFlag = pCountry.length == 1
          ? {
              for (final i in plainIndices)
                if (_sameCountryScope(pCountry, serverCountry[i]!)) i
            }
          : exact;

      if (byFlag.isEmpty && exact.isEmpty) continue;
      if (exact.isNotEmpty) exactFound[p] = exact;
      if (byFlag.isNotEmpty) flagFound[p] = byFlag;
      size[p] = sigs.length;
    }
    if (flagFound.isEmpty) return AutoBinding.empty;

    final heads = [
      for (final p in flagFound.keys)
        if (!_isUmbrella(p, exactFound.isNotEmpty ? exactFound : flagFound)) p
    ]..sort();

    final ownerOf = <int, int>{};
    for (final i in plainIndices) {
      int? best;
      // 1. Точное совпадение по outbound — чтобы узкий подпрофиль той же страны
      //    («Польша игровой») забрал свои узлы у общего профиля страны.
      for (final p in heads) {
        final exact = exactFound[p];
        if (exact == null || !exact.contains(i)) continue;
        if (best == null || size[p]! < size[best]!) best = p;
      }
      // 2. Все остальные серверы этого флага страны идут в основной страновой
      //    автосервер того же флага (первый/широкий профиль этой страны).
      if (best == null) {
        for (final p in heads) {
          final byFlag = flagFound[p];
          if (byFlag == null || !byFlag.contains(i)) continue;
          if (best == null || size[p]! > size[best]!) best = p;
        }
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
  static bool isBridgeName(String name) => _bridge.hasMatch(name);

  static final RegExp _bridge = RegExp(
      r'(?<![а-яёa-z])(мост|bridge)(?![а-яёa-z])|->|→|=>',
      caseSensitive: false,
      unicode: true);

  /// Профили белых списков никогда не собирают под себя локации в списке.
  static bool isNonGroupProfileName(String name) =>
      _nonGroupProfile.hasMatch(name);

  static final RegExp _nonGroupProfile = RegExp(
      r'бел(ые|ых|ый)\s*спис|whitelist',
      caseSensitive: false,
      unicode: true);

  /// Нижние именные авто-профили вида «🇳🇱🏳️ Авто The Netherlands»,
  /// «🇨🇦🏳️ Авто Canada» (содержат и флаг страны, и слово «Авто»/«Auto»).
  ///
  /// В отличие от неподписанных страновых автосерверов («🇳🇱 🚀Нидерланды»,
  /// «🇵🇱 🚀Польша», «🇷🇺🏳️ Москва»), они стоят внизу списка в порядке панели
  /// и не собирают в себя страновые локации.
  static bool isBottomNamedAutoProfile(String name) =>
      FlagUtil.isoCodesFromName(name).isNotEmpty && _autoWord.hasMatch(name);

  static final RegExp _autoWord = RegExp(
      r'(?<![а-яёa-z])(авто|auto)(?![а-яёa-z])',
      caseSensitive: false,
      unicode: true);

  /// Глобальный/сервисный профиль «Авто» без флага страны («🎬 Авто (YouTube)»,
  /// «🏳️ Авто Белые списки», «✈️ Авто Telegram» и т.д.).
  static bool isGlobalAutoProfile(VpnServer s) =>
      s.isPanelProfile &&
      !s.isNotice &&
      !isBridgeName(s.displayName) &&
      FlagUtil.isoCodesFromName(s.remark).isEmpty;

  /// Неподписанный страновой автосервер («🇳🇱 🚀Нидерланды», «🇵🇱 🚀Польша»,
  /// «🇷🇺🏳️ Москва», «🇫🇮 🚀Финляндия» и т.д.), который должен стоять в верхнем
  /// блоке автосерверов и собирать под себя все локации своего флага.
  static bool isCountryAutoProfile(VpnServer s) =>
      s.isPanelProfile &&
      !s.isNotice &&
      !isNonGroupProfileName(s.displayName) &&
      !isBridgeName(s.displayName) &&
      !isBottomNamedAutoProfile(s.remark) &&
      FlagUtil.isoCodesFromName(s.remark).length == 1 &&
      profileSignatures(s.rawPanelConfig ?? '').isNotEmpty;

  /// Совместимы ли страна профиля и страна сервера: сервер с флагом страны
  /// может лечь только под профиль с ТЕМ ЖЕ единственным флагом страны
  /// (белый флаг `🏳️` кодом страны не является и даёт пустой список).
  static bool _sameCountryScope(List<String> profileIso, List<String> serverIso) {
    if (serverIso.isEmpty && profileIso.isEmpty) return true;
    return profileIso.length == 1 &&
        serverIso.length == 1 &&
        profileIso.first == serverIso.first;
  }

  /// Зонтик — профиль, строго содержащий серверы ДВУХ непересекающихся
  /// профилей («Авто YouTube» содержит и Польшу, и Германию).
  static bool _isUmbrella(int p, Map<int, Set<int>> found) {
    final mine = found[p];
    if (mine == null || mine.isEmpty) return false;
    final inner = [
      for (final q in found.entries)
        if (q.key != p &&
            q.value.isNotEmpty &&
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
  /// `dns`, `loopback`) не считаются.
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
  /// ключами. У hysteria — адрес, порт и пароль.
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

  /// JSON с ключами по алфавиту на всех уровнях.
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
