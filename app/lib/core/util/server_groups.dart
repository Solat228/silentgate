import '../models/vpn_server.dart';
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

/// Сервер; [index] — ИСХОДНЫЙ индекс в `AppState.servers` (выбор идёт по нему).
class ServerRowEntry extends ServerListEntry {
  final int index;

  /// Строка внутри группы (рисуется с отступом).
  final bool grouped;

  const ServerRowEntry(this.index, {this.grouped = false});
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
  static bool isJumbled(List<VpnServer> servers, {Set<int> pinned = const {}}) {
    final finished = <String>{};
    String? current;
    for (var i = 0; i < servers.length; i++) {
      if (pinned.contains(i)) continue;
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
  static List<int> order(
    List<VpnServer> servers,
    List<int> shown, {
    required bool sortByCountry,
    Set<int> pinned = const {},
  }) {
    if (!sortByCountry) return shown;
    final head = [for (final i in shown) if (pinned.contains(i)) i];
    final buckets = <String?, List<int>>{};
    for (final i in shown) {
      if (pinned.contains(i)) continue;
      // Без страны — каждый сервер сам по себе: собирать «Авто» и
      // уведомления в одну кучу смысла нет, их место задал провайдер.
      final c = countryOf(servers[i]) ?? '\u0000$i';
      (buckets[c] ??= []).add(i);
    }
    return [...head, for (final b in buckets.values) ...b];
  }

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
  }) {
    final out = <ServerListEntry>[];
    var i = 0;
    while (i < ordered.length) {
      final idx = ordered[i];
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
