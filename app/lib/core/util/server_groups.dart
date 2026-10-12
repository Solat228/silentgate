import '../models/vpn_server.dart';
import 'auto_groups.dart';
import 'country_flag.dart';

/// Строка списка серверов: заголовок группы страны либо сам сервер.
sealed class ServerListEntry {
  const ServerListEntry();
}

/// Заголовок сворачиваемой группы серверов одной страны.
class ServerGroupHeader extends ServerListEntry {
  /// Ключ страны: ISO-коды флагов через дефис (`DE`, у моста — `RU-DE`).
  final String country;

  /// Подпись группы — общее начало имён (`Германия`) или сам ключ.
  final String label;

  /// Сколько серверов в группе.
  final int count;

  final bool collapsed;

  /// Исходные индексы серверов группы — для «пинга группы» и подсчётов.
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

/// Группировка списка серверов по странам.
///
/// Решения владельца (25.09.2026):
///  * порядок от провайдера НЕ трогается: группа — это серверы одной страны,
///    идущие ПОДРЯД, от двух штук. Две подряд — уже группа, а не «разнобой»;
///  * группы сворачиваются;
///  * пересортировка по странам — только по отдельной настройке, выключенной
///    по умолчанию; предлагать её есть смысл, лишь когда список действительно
///    вразнобой ([isJumbled]).
///
/// Закреплённые серверы стоят сверху и в группы не входят: человек закрепил
/// их ради того, чтобы они были под рукой, а не спрятаны в свёрнутой стране.
/// Серверы без флага в имени (профили «Авто», уведомления панели) тоже
/// остаются отдельными строками на своих местах.
///
/// Серверы, входящие в страновой профиль «Авто» панели, собираются ПОД этим
/// профилем (решение владельца 10.10.2026, см. [AutoGroups]): строка «Авто»
/// становится шапкой группы, группа по умолчанию свёрнута. Страны и
/// «разнобой» считаются только по оставшимся серверам.
///
/// Функции чистые: интерфейс подаёт список и состояние, получает строки.
abstract final class ServerGroups {
  /// Ключ страны сервера или `null`, если сервер в группы не входит.
  static String? countryOf(VpnServer s) {
    if (s.isPanelProfile || s.isNotice) return null;
    final codes = FlagUtil.isoCodesFromName(s.remark);
    return codes.isEmpty ? null : codes.join('-');
  }

  /// Перемешан ли список: одна страна встречается в нескольких местах.
  ///
  /// Только тогда настройку «Сортировать по странам» стоит показывать — у
  /// провайдера, который уже разложил серверы по странам, она ничего не
  /// изменит, а лишний переключатель путает.
  ///
  /// Серверы, собранные под профилем «Авто» ([auto]), не считаются: их место
  /// задаёт профиль, и сортировка по странам их не двигает.
  static bool isJumbled(List<VpnServer> servers,
      {Set<int> pinned = const {}, AutoBinding auto = AutoBinding.empty}) {
    final finished = <String>{};
    String? current;
    for (var i = 0; i < servers.length; i++) {
      if (pinned.contains(i) || auto.ownerOf.containsKey(i)) continue;
      final c = countryOf(servers[i]);
      if (c == current) continue;
      if (current != null) finished.add(current);
      if (c != null && finished.contains(c)) return true;
      current = c;
    }
    return false;
  }

  /// Порядок показа: [shown] (исходные индексы), при [sortByCountry] —
  /// незакреплённые собраны по странам.
  ///
  /// Сортировка УСТОЙЧИВАЯ и без алфавита: страны идут в порядке первого
  /// появления у провайдера, внутри страны — его же порядок. Провайдер обычно
  /// ставит лучшие страны выше, и алфавит этот порядок потерял бы.
  ///
  /// Серверы профилей «Авто» ([auto]) встают сразу за своим профилем, в
  /// порядке провайдера.
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
    var base = [for (final i in shown) if (!bound.contains(i)) i];
    if (sortByCountry) {
      final head = [for (final i in base) if (pinned.contains(i)) i];
      final buckets = <String?, List<int>>{};
      for (final i in base) {
        if (pinned.contains(i)) continue;
        // Без страны — каждый сервер сам по себе: собирать «Авто» и
        // уведомления в одну кучу смысла нет, их место задал провайдер.
        final c = countryOf(servers[i]) ?? '\u0000$i';
        (buckets[c] ??= []).add(i);
      }
      base = [...head, for (final b in buckets.values) ...b];
    }
    if (bound.isEmpty) return base;
    return [
      for (final i in base) ...[
        i,
        ...?auto.members[i]?.where(bound.contains),
      ]
    ];
  }

  /// Ключ состояния группы профиля «Авто» — по имени профиля, как и его
  /// тождество в подписке (`VpnServer.identityKey`).
  static String autoGroupKey(VpnServer profile) =>
      'auto:${profile.remark.trim()}';

  /// Строки списка из порядка [ordered].
  ///
  /// [selected] — выбранный сервер: внутри свёрнутой группы он всё равно
  /// показывается под заголовком, иначе выбор «пропадал» бы из списка.
  ///
  /// Группа «Авто» СВЁРНУТА ПО УМОЛЧАНИЮ (решение владельца 10.10.2026), поэтому
  /// для неё хранится обратное — раскрытые ([expandedAuto]).
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
      final c = pinned.contains(idx) ? null : countryOf(servers[idx]);
      var j = i + 1;
      if (c != null) {
        while (j < ordered.length &&
            !pinned.contains(ordered[j]) &&
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

  /// Подпись группы: общее начало имён без флагов, номеров и знаков.
  ///
  /// «🇩🇪 Германия 1» и «🇩🇪 Германия 2.5» → «Германия». Общего начала нет
  /// («Berlin», «Frankfurt») — ключ страны: названий стран у приложения нет,
  /// а выдумывать их по коду значило бы спорить с тем, как назвал провайдер.
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
    // Хвостовые номера и знаки («Германия 1» у всех одинаково не бывает, но
    // «Germany -» — бывает) отрезаем: подпись группы — это страна.
    // ⚠️ По наличию БУКВЫ (`\p{L}`), а не через `\W`: в регулярках Dart `\w`
    // только латинский, и «Германия» целиком считалась бы «знаками».
    final letter = RegExp(r'\p{L}', unicode: true);
    while (common.isNotEmpty && !letter.hasMatch(common.last)) {
      common.removeLast();
    }
    final label = common.join(' ').trim();
    return label.isEmpty ? fallback : label;
  }
}
