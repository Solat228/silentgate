import '../models/vpn_server.dart';
import 'country_flag.dart';

/// Поиск по списку серверов: свободный текст по имени, адресу, порту, протоколу
/// и тегам конфига.
///
/// Возвращает **исходные индексы**, а не отфильтрованный список: выбор сервера в UI
/// идёт по индексу в `AppState.servers`, и при фильтрации он иначе «уехал» бы
/// на соседний сервер.
class ServerSearch {
  /// Индексы серверов, подходящих под запрос. Пустой запрос — все, по порядку.
  static List<int> matchIndices(List<VpnServer> servers, String query) {
    final q = _norm(query);
    if (q.isEmpty) return List.generate(servers.length, (i) => i);
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final result = <int>[];
    for (var i = 0; i < servers.length; i++) {
      final hay = _haystack(servers[i]);
      // Все слова запроса должны найтись — «ru grpc» находит российские GRPC-серверы.
      if (terms.every(hay.contains)) result.add(i);
    }
    return result;
  }

  static String _haystack(VpnServer s) {
    final parts = <String>[
      s.remark,
      FlagUtil.strip(s.remark), // имя без флаг-эмодзи
      FlagUtil.isoFromName(s.remark) ?? '', // код страны: «nl», «ru»
      s.address,
      '${s.port}',
      s.protocol,
      s.network,
      s.security,
      ...s.configTags,
      if (s.isPanelProfile) 'авто auto профиль',
    ];
    return _norm(parts.join(' '));
  }

  /// Регистр и «ё» → «е», чтобы поиск не зависел от раскладки набора.
  static String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е').trim();
}
