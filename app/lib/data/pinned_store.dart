import 'dart:convert';
import 'dart:io';

import '../core/parser/share_link_parser.dart';
import '../core/platform/app_paths.dart';
import '../core/util/key_migration.dart';
import 'atomic_file.dart';

/// Одна запись закреплённого сервера.
///
/// [sourceSubscriptionId] — id подписки, из которой сервер был реально
/// закреплён (см. `AppState._sourceSubscriptionIdFor`). Пустая строка значит
/// «источник неизвестен»: либо запись пришла из СТАРОГО формата файла (просто
/// список ссылок, без источника), либо сервер добавлен вручную (одиночная
/// ссылка / `json://` конфиг) и ни в одной подписке никогда не лежал.
class PinnedEntry {
  final String link;
  final String sourceSubscriptionId;

  const PinnedEntry(this.link, {this.sourceSubscriptionId = ''});

  Map<String, dynamic> toJson() => {'link': link, 'sub': sourceSubscriptionId};
}

/// Хранилище закреплённых/правленых серверов. Переживает удаление подписки.
///
/// ⚠️ ФОРМАТ ФАЙЛА РАСШИРЕН, СТАРЫЙ ЧИТАЕТСЯ БЕЗ МИГРАЦИИ. До появления значка
/// «чужая подписка» на закреплённых серверах файл хранил просто
/// `["vless://...", ...]`. Переписывать его при первом же чтении опасно: если
/// новая версия окажется с багом, откат на предыдущую должен видеть все пины
/// как раньше, а не терять половину из-за формата, который она не понимает.
/// Поэтому старый список строк как читался, так и читается — просто без
/// источника (см. [PinnedEntry.sourceSubscriptionId]).
class PinnedStore {
  static const _fileName = 'pinned_servers.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<List<PinnedEntry>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return [];

      // Пары (ссылка, источник) до канонизации ключа. Плохие элементы (не
      // строка и не объект с полем `link`) просто пропускаем — один битый
      // элемент не должен ронять остальные закрепления.
      final rawLinks = <String>[];
      final rawSubs = <String>[];
      for (final entry in data) {
        if (entry is String) {
          if (entry.isEmpty) continue;
          rawLinks.add(entry);
          rawSubs.add('');
        } else if (entry is Map) {
          final link = entry['link'];
          if (link is! String || link.isEmpty) continue;
          rawLinks.add(link);
          final sub = entry['sub'];
          rawSubs.add(sub is String ? sub : '');
        }
      }
      if (rawLinks.isEmpty) return [];

      // ⚠️ Ключи приводим к каноническому виду ПРИ ЧТЕНИИ (та же миграция, что
      // была для старого формата, — см. `KeyMigration`), но переписываем её
      // руками вместо вызова `remapList`: тот дедуплицирует голый список строк
      // и порядок пар (ссылка, источник) после дедупа теряется.
      final out = <PinnedEntry>[];
      final seenCanon = <String>{};
      for (var i = 0; i < rawLinks.length; i++) {
        var canon = ShareLinkParser.canonicalKey(rawLinks[i]);
        final alias = KeyMigration.panelAliasOf(canon);
        if (alias != null) canon = alias;
        if (seenCanon.add(canon)) {
          out.add(PinnedEntry(canon, sourceSubscriptionId: rawSubs[i]));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<PinnedEntry> entries) async {
    try {
      final f = await _file();
      await AtomicFile.writeString(
          f, jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
