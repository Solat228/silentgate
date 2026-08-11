import '../settings/split_tunnel.dart';

/// Действуют ли пользовательские правила раздельного туннелирования вообще.
///
/// ⚠️ ОБЩИЙ ГЕЙТ ДЛЯ ДВУХ ПОСТРОИТЕЛЕЙ, ПО ТОЙ ЖЕ ПРИЧИНЕ, ЧТО И
/// [apiExitBlockGuardRules] НИЖЕ. В режиме «Всё через VPN» пользовательских
/// правил, включая блок, нет вовсе (они лежат сохранёнными, но не входят в
/// конфиг) — `SingboxConfigBuilder._userRulesActive` (TUN, задача 3) и
/// [ExitRouterConfigBuilder.buildMap] (маршрутизатор «Только прокси»,
/// задача 3b) обязаны решать это ОДИНАКОВО, иначе блок на портах серверов
/// включился бы там, где такой же блок в TUN-конфиге не действует —
/// расхождение как раз того класса, который в этом проекте дороже всего.
bool userRulesActive(SplitTunnelConfig split) => split.mode != SplitMode.all;

/// Блок-правила, ограниченные заданными тегами инбаундов API (см. `ApiPorts`).
///
/// ⚠️ ОБЩАЯ ЛОГИКА ДЛЯ ДВУХ КОНФИГОВ. Ей пользуются и TUN-построитель
/// (`SingboxConfigBuilder._addApiExitBlockGuard`, задача 3), и маршрутизатор
/// выходов режима «Только прокси» (`ExitRouterConfigBuilder`, задача 3b) —
/// поведение обязано быть одинаковым в обоих, а две копии разъехались бы на
/// первой же правке (урок уже случался в этом проекте, см. `CLAUDE.md`).
///
/// Строит ТОЛЬКО «Блок»: у явно открытого порта уже есть адресат — сам
/// сервер, которому он принадлежит, — и переопределять его правилами
/// «Прямо»/«Туннель через другой сервер» значило бы отменять выбор,
/// сделанный самим фактом обращения к порту. Поэтому здесь нет ни группировки
/// по выходу, ни фильтров `allowRealIp`/`overrideSites`: у блокировки их не
/// бывает (см. вызов в `_addApiExitBlockGuard`).
///
/// [platformTun] — Android `VpnService`: приложения там сопоставляются по
/// имени пакета, полей `process_name`/`process_path` нет вовсе. У «Только
/// прокси» (режим Windows-only) всегда `false`.
List<Map<String, dynamic>> apiExitBlockGuardRules({
  required SplitTunnelConfig split,
  required List<String> inboundTags,
  bool platformTun = false,
}) {
  if (inboundTags.isEmpty) return const [];
  final rules = <Map<String, dynamic>>[];

  // Сайты «Блок»: без порта — одним правилом на все домены, с портом — по
  // порту (та же группировка, что и у обычных доменных правил).
  final sites = split.sites.where((s) => s.action == AppAction.block);
  final noPortSites =
      sites.where((s) => s.port == null).map((s) => s.domain).toList();
  if (noPortSites.isNotEmpty) {
    rules.add({
      'domain_suffix': noPortSites,
      'inbound': inboundTags,
      'action': 'reject',
    });
  }
  final byPort = <int, List<String>>{};
  for (final s in sites.where((s) => s.port != null)) {
    byPort.putIfAbsent(s.port!, () => []).add(s.domain);
  }
  for (final port in byPort.keys.toList()..sort()) {
    rules.add({
      'domain_suffix': byPort[port]!,
      'port': [port],
      'inbound': inboundTags,
      'action': 'reject',
    });
  }

  // Приложения «Блок» (только включённые галочкой).
  final apps =
      split.apps.where((a) => a.enabled && a.action == AppAction.block);
  if (platformTun) {
    final pkgs = apps
        .map((a) => a.path.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    if (pkgs.isNotEmpty) {
      rules.add(
          {'package_name': pkgs, 'inbound': inboundTags, 'action': 'reject'});
    }
  } else {
    final byName = apps.where((a) => a.byName).map((a) => a.name).toList();
    final byPath = apps.where((a) => !a.byName).map((a) => a.path).toList();
    if (byName.isNotEmpty) {
      rules.add({
        'process_name': byName,
        'inbound': inboundTags,
        'action': 'reject',
      });
    }
    if (byPath.isNotEmpty) {
      // process_path сравнивается ядром побайтово (регистр, короткие пути
      // Windows) — правило могло молча не срабатывать. process_path_regex
      // с (?i) — надёжно (то же решение, что у обычных правил приложений).
      rules.add({
        'process_path_regex': [
          for (final p in byPath) '(?i)^${escapeForSingboxRegex(p)}\$'
        ],
        'inbound': inboundTags,
        'action': 'reject',
      });
    }
  }
  return rules;
}

/// Экранирование пути для RE2 (Go regexp в sing-box): только реальные
/// метасимволы — экранирование пробела и подобного RE2 считает ошибкой.
///
/// Общая для [apiExitBlockGuardRules] и `SingboxConfigBuilder._addActionRule`
/// (обычные правила приложений «по пути») — та же причина, что у остальных
/// функций этого файла: разойдись экранирование в двух местах, и правило в
/// одном из конфигов перестанет матчиться молча.
String escapeForSingboxRegex(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|\[\]\\]'), (m) => '\\${m[0]}');
