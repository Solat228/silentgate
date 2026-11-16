import '../models/vpn_server.dart';
import '../xray/xray_config_builder.dart';
import 'auto_groups.dart';
import 'country_flag.dart';

/// Строка списка серверов: заголовок группы страны либо сам сервер.
sealed class ServerListEntry {
  const ServerListEntry();
}

/// Заголовок сворачиваемой группы серверов одной страны (или папки мостов).
class ServerGroupHeader extends ServerListEntry {
  /// Ключ группы: ISO-код страны (`DE`) либо [ServerGroups.bridgesCountryKey] (`BRIDGES`).
  final String country;

  /// Подпись группы — общее начало имён (`Германия`), `Мосты` или сам ключ.
  final String label;

  /// Сколько серверов в группе.
  final int count;

  final bool collapsed;

  /// Исходные индексы серверов группы — для «пинга группы», выбора и подсчётов.
  final List<int> indices;

  const ServerGroupHeader({
    required this.country,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.indices,
  });
}

/// Группа профиля «Авто»: сама строка профиля служит её шапкой.
class AutoGroupInfo {
  /// Ключ состояния «раскрыта» (см. [ServerGroups.autoGroupKey]).
  final String key;

  /// Сколько серверов привязано к профилю.
  final int count;

  final bool collapsed;

  /// Исходные индексы серверов группы.
  final List<int> members;

  const AutoGroupInfo({
    required this.key,
    required this.count,
    required this.collapsed,
    required this.members,
  });
}

/// Сервер; [index] — ИСХОДНЫЙ индекс в `AppState.servers` (выбор идёт по нему).
class ServerRowEntry extends ServerListEntry {
  final int index;

  /// Строка внутри группы (рисуется с отступом).
  final bool grouped;

  /// Строка — профиль «Авто» и шапка своей группы.
  final AutoGroupInfo? auto;

  /// Строка внутри группы профиля «Авто» (отступ под шевроном шапки).
  final bool autoMember;

  const ServerRowEntry(this.index,
      {this.grouped = false, this.auto, this.autoMember = false});
}

/// Группировка и упорядочивание списка серверов.
///
/// Порядок списка (решение владельца 10.11.2026):
///  1. Закреплённые серверы (`pinned`) всегда наверху.
///  2. Глобальные профили «Авто» без флага страны («🎬 Авто (YouTube)»,
///     «🏳️ Авто Белые списки», «✈️ Авто Telegram» и т.д.).
///  3. Неподписанные страновые автосерверы («🇳🇱 🚀Нидерланды», «🇵🇱 🚀Польша»,
///     «🇷🇺🏳️ Москва», «🇩🇪 🚀Германия», «🇫🇮 🚀Финляндия» и т.д.) — сразу под
///     каждым идут все обычные серверы его флага страны ([AutoGroups]).
///  4. Обычные серверы стран, у которых НЕТ своего странового автосервера
///     (группируются в сворачиваемый [ServerGroupHeader] от 2 штук, причём
///     сам заголовок тоже можно выбрать как виртуальный автосервер страны).
///  5. Нижние именные профили `АВТО_ИМЯ_АВТО` («🇳🇱🏳️ Авто The Netherlands»…)
///     — в исходном порядке панели, без группировки.
///  6. Все мосты (`->`, `→`, `(мост)`) — в самом низу списка в свёрнутой по
///     умолчанию папке «🌉 Мосты», заголовок которой также выбирается как
///     виртуальный автосервер по всем мостам.
abstract final class ServerGroups {
  /// Ключ отдельной свёрнутой папки мостов внизу списка.
  static const String bridgesCountryKey = 'BRIDGES';

  /// Ключ раскрытия папки мостов в `expandedAutoGroups` (по умолчанию свёрнута).
  static const String bridgesGroupKey = 'group:BRIDGES';

  /// Подпись папки мостов по умолчанию.
  static const String bridgesDefaultLabel = 'Мосты';

  /// Префикс ключа виртуального автосервера для заголовка группы ([ServerGroupHeader]).
  static const String virtualGroupPrefix = 'group://';

  /// Ключ виртуального автосервера для группы [country] (`group://DE`, `group://BRIDGES`).
  static String virtualGroupKey(String country) =>
      '$virtualGroupPrefix$country';

  static bool isVirtualGroupKey(String? key) =>
      key != null && key.startsWith(virtualGroupPrefix);

  static String? countryFromVirtualGroupKey(String? key) =>
      isVirtualGroupKey(key) ? key!.substring(virtualGroupPrefix.length) : null;

  /// Ключ страны сервера или `null`, если сервер в группы не входит.
  static String? countryOf(VpnServer s) {
    if (s.isPanelProfile || s.isNotice) return null;
    final codes = FlagUtil.isoCodesFromName(s.remark);
    return codes.isEmpty ? null : codes.join('-');
  }

  /// Перемешан ли список: одна страна встречается в нескольких местах.
  ///
  /// Серверы, собранные под профилем «Авто» ([auto]), и мосты не считаются:
  /// их место задано правилами раскладки.
  static bool isJumbled(List<VpnServer> servers,
      {Set<int> pinned = const {}, AutoBinding auto = AutoBinding.empty}) {
    final finished = <String>{};
    String? current;
    for (var i = 0; i < servers.length; i++) {
      if (pinned.contains(i) || auto.ownerOf.containsKey(i)) continue;
      if (AutoGroups.isBridgeName(servers[i].displayName)) continue;
      final c = countryOf(servers[i]);
      if (c == current) continue;
      if (current != null) finished.add(current);
      if (c != null && finished.contains(c)) return true;
      current = c;
    }
    return false;
  }

  /// Порядок показа: [shown] (исходные индексы), с поднятием страновых
  /// автосерверов в верхний блок и уводом мостов в самый низ.
  static List<int> order(
    List<VpnServer> servers,
    List<int> shown, {
    required bool sortByCountry,
    Set<int> pinned = const {},
    AutoBinding auto = AutoBinding.empty,
  }) {
    final shownSet = shown.toSet();
    // Привязка действует, только если сам профиль тоже в списке.
    final bound = {
      for (final i in shown)
        if (auto.ownerOf[i] case final p? when shownSet.contains(p)) i
    };
    final base = [for (final i in shown) if (!bound.contains(i)) i];

    // Отделяем закреплённые, верхние автосерверы (глобальные + страновые),
    // середину (обычные страны без автосервера + нижние АВТО_ИМЯ_АВТО) и мосты.
    final pinnedHead = <int>[];
    final topAuto = <int>[];
    final middle = <int>[];
    final bridges = <int>[];

    // Если sortByCountry выключен и нет ни авто-профилей, ни мостов,
    // сохраняем 100% исходный порядок (важно для чистых списков без панели).
    final hasAutoOrBridges = bound.isNotEmpty ||
        base.any((i) =>
            !pinned.contains(i) &&
            (AutoGroups.isGlobalAutoProfile(servers[i]) ||
                AutoGroups.isCountryAutoProfile(servers[i]) ||
                auto.members.containsKey(i) ||
                AutoGroups.isBridgeName(servers[i].displayName)));

    if (!sortByCountry && !hasAutoOrBridges) {
      return base;
    }

    for (final i in base) {
      if (pinned.contains(i)) {
        pinnedHead.add(i);
        continue;
      }
      final s = servers[i];
      if (AutoGroups.isBridgeName(s.displayName)) {
        bridges.add(i);
      } else if (AutoGroups.isGlobalAutoProfile(s) ||
          AutoGroups.isCountryAutoProfile(s) ||
          auto.members.containsKey(i)) {
        topAuto.add(i);
      } else {
        middle.add(i);
      }
    }

    List<int> orderedMiddle = middle;
    if (sortByCountry && middle.isNotEmpty) {
      final buckets = <String, List<int>>{};
      for (final i in middle) {
        final c = countryOf(servers[i]) ?? '\u0000$i';
        (buckets[c] ??= []).add(i);
      }
      orderedMiddle = [for (final b in buckets.values) ...b];
    }

    final combined = [
      ...pinnedHead,
      ...topAuto,
      ...orderedMiddle,
      ...bridges,
    ];

    if (bound.isEmpty) return combined;
    return [
      for (final i in combined) ...[
        i,
        ...?auto.members[i]?.where(bound.contains),
      ]
    ];
  }

  /// Ключ состояния группы профиля «Авто» — по имени профиля.
  static String autoGroupKey(VpnServer profile) =>
      'auto:${profile.remark.trim()}';

  /// Строки списка из порядка [ordered].
  ///
  /// [selected] — выбранный сервер: внутри свёрнутой группы он всё равно
  /// показывается под заголовком, иначе выбор «пропадал» бы из списка.
  static List<ServerListEntry> build(
    List<VpnServer> servers,
    List<int> ordered, {
    Set<String> collapsed = const {},
    int selected = -1,
    Set<int> pinned = const {},
    AutoBinding auto = AutoBinding.empty,
    Set<String> expandedAuto = const {},
  }) {
    final out = <ServerListEntry>[];
    var i = 0;
    while (i < ordered.length) {
      final idx = ordered[i];
      final own = auto.members[idx];
      if (own != null) {
        // Серверы группы стоят сразу за профилем (см. [order]).
        final ownSet = own.toSet();
        var j = i + 1;
        while (j < ordered.length && ownSet.contains(ordered[j])) {
          j++;
        }
        final run = ordered.sublist(i + 1, j);
        if (run.isNotEmpty) {
          final key = autoGroupKey(servers[idx]);
          final isCollapsed = !expandedAuto.contains(key);
          out.add(ServerRowEntry(idx,
              auto: AutoGroupInfo(
                key: key,
                count: run.length,
                collapsed: isCollapsed,
                members: run,
              )));
          for (final k in run) {
            if (!isCollapsed || k == selected) {
              out.add(ServerRowEntry(k, grouped: true, autoMember: true));
            }
          }
          i = j;
          continue;
        }
      }

      // Незакреплённые мосты всегда прячутся в отдельную свёрнутую по умолчанию
      // папку «🌉 Мосты».
      if (!pinned.contains(idx) &&
          !servers[idx].isPanelProfile &&
          !servers[idx].isNotice &&
          AutoGroups.isBridgeName(servers[idx].displayName)) {
        var j = i + 1;
        while (j < ordered.length &&
            !pinned.contains(ordered[j]) &&
            !servers[ordered[j]].isPanelProfile &&
            !servers[ordered[j]].isNotice &&
            AutoGroups.isBridgeName(servers[ordered[j]].displayName)) {
          j++;
        }
        final run = ordered.sublist(i, j);
        final isCollapsed = !expandedAuto.contains(bridgesGroupKey) &&
            !collapsed.contains('!$bridgesCountryKey');
        out.add(ServerGroupHeader(
          country: bridgesCountryKey,
          label: bridgesDefaultLabel,
          count: run.length,
          collapsed: isCollapsed,
          indices: run,
        ));
        for (final k in run) {
          if (!isCollapsed || k == selected) {
            out.add(ServerRowEntry(k, grouped: true));
          }
        }
        i = j;
        continue;
      }

      final c = pinned.contains(idx) ? null : countryOf(servers[idx]);
      var j = i + 1;
      if (c != null) {
        while (j < ordered.length &&
            !pinned.contains(ordered[j]) &&
            !AutoGroups.isBridgeName(servers[ordered[j]].displayName) &&
            countryOf(servers[ordered[j]]) == c) {
          j++;
        }
      }
      final run = ordered.sublist(i, j);
      if (c == null || run.length < 2) {
        out.addAll(run.map(ServerRowEntry.new));
      } else {
        final isCollapsed = collapsed.contains(c);
        out.add(ServerGroupHeader(
          country: c,
          label: labelFor([for (final k in run) servers[k].remark], c),
          count: run.length,
          collapsed: isCollapsed,
          indices: run,
        ));
        for (final k in run) {
          if (!isCollapsed || k == selected) {
            out.add(ServerRowEntry(k, grouped: true));
          }
        }
      }
      i = j;
    }
    return out;
  }

  /// Собирает виртуальный сервер-балансировщик (`leastPing` + `burstObservatory`)
  /// для заголовка группы [group] (страна без собственного автосервера либо
  /// папка «🌉 Мосты»).
  static VpnServer? virtualServerFor(
      ServerGroupHeader group, List<VpnServer> servers) {
    final members = [
      for (final idx in group.indices)
        if (idx >= 0 && idx < servers.length) servers[idx]
    ];
    final usable = members
        .where((s) =>
            !s.isNotice &&
            !s.isUnsupported &&
            !s.usesWhitelistRelay &&
            s.address.trim().isNotEmpty)
        .toList();
    if (usable.isEmpty) return null;

    final String remark;
    if (group.country == bridgesCountryKey) {
      remark = '🌉 ${group.label}';
    } else {
      final emoji = _isoToFlagEmoji(group.country);
      remark = emoji.isEmpty ? group.label : '$emoji ${group.label}';
    }

    final xrayMembers =
        usable.where((s) => s.core == ProxyCore.xray).toList();
    if (xrayMembers.isEmpty) {
      return usable.first.copyWith(
        remark: remark,
        rawLink: virtualGroupKey(group.country),
      );
    }

    final first = xrayMembers.first;
    final panelJson = const XrayConfigBuilder().buildBalancerJson(xrayMembers);
    return VpnServer(
      protocol: 'vless',
      remark: remark,
      address: first.address,
      port: first.port,
      id: first.id,
      rawLink: virtualGroupKey(group.country),
      rawPanelConfig: panelJson,
    );
  }

  /// Разрешает ключ `group://<country>` (например `group://DE` или
  /// `group://BRIDGES`) в виртуальный сервер-балансировщик по текущему списку
  /// [servers].
  static VpnServer? resolveVirtualGroupKey(
      String? key, List<VpnServer> servers) {
    final country = countryFromVirtualGroupKey(key);
    if (country == null || country.isEmpty || servers.isEmpty) return null;
    if (country == bridgesCountryKey) {
      final indices = <int>[
        for (var i = 0; i < servers.length; i++)
          if (!servers[i].isPanelProfile &&
              !servers[i].isNotice &&
              AutoGroups.isBridgeName(servers[i].displayName))
            i
      ];
      if (indices.isEmpty) return null;
      return virtualServerFor(
        ServerGroupHeader(
          country: bridgesCountryKey,
          label: bridgesDefaultLabel,
          count: indices.length,
          collapsed: true,
          indices: indices,
        ),
        servers,
      );
    }
    final indices = <int>[
      for (var i = 0; i < servers.length; i++)
        if (!servers[i].isPanelProfile &&
            !servers[i].isNotice &&
            !AutoGroups.isBridgeName(servers[i].displayName) &&
            countryOf(servers[i]) == country)
          i
    ];
    if (indices.isEmpty) return null;
    final label = labelFor([for (final k in indices) servers[k].remark], country);
    return virtualServerFor(
      ServerGroupHeader(
        country: country,
        label: label,
        count: indices.length,
        collapsed: false,
        indices: indices,
      ),
      servers,
    );
  }

  /// Находит сервер в [servers] по [serverKey] либо строит виртуальный
  /// автосервер группы (`group://…`).
  static VpnServer? findOrResolveServer(
      List<VpnServer> servers, String? serverKey) {
    if (serverKey == null || serverKey.isEmpty) return null;
    for (final s in servers) {
      if (s.key == serverKey) return s;
    }
    if (isVirtualGroupKey(serverKey)) {
      return resolveVirtualGroupKey(serverKey, servers);
    }
    return null;
  }

  static String _isoToFlagEmoji(String countryKey) {
    final parts = countryKey.split('-');
    final buf = StringBuffer();
    for (final code in parts) {
      final upper = code.trim().toUpperCase();
      if (upper.length != 2) continue;
      final c1 = upper.codeUnitAt(0);
      final c2 = upper.codeUnitAt(1);
      if (c1 < 0x41 || c1 > 0x5A || c2 < 0x41 || c2 > 0x5A) continue;
      buf.writeCharCode(0x1F1E6 + (c1 - 0x41));
      buf.writeCharCode(0x1F1E6 + (c2 - 0x41));
    }
    return buf.toString();
  }

  /// Подпись группы: общее начало имён без флагов, номеров и знаков.
  static String labelFor(List<String> names, String fallback) {
    final words = [
      for (final n in names)
        FlagUtil.strip(n).split(' ').where((w) => w.isNotEmpty).toList()
    ];
    if (words.isEmpty) return fallback;
    final common = <String>[];
    for (var k = 0;; k++) {
      if (words.any((w) => w.length <= k)) break;
      final w = words.first[k];
      if (words.any((x) => x[k] != w)) break;
      common.add(w);
    }
    final letter = RegExp(r'\p{L}', unicode: true);
    while (common.isNotEmpty && !letter.hasMatch(common.last)) {
      common.removeLast();
    }
    final label = common.join(' ').trim();
    return label.isEmpty ? fallback : label;
  }
}
