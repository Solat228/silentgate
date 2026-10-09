import '../models/server_override.dart';
import '../models/vpn_server.dart';
import '../settings/app_settings.dart';

/// Перенос сохранённого на НОВЫЙ ключ сервера, когда панель переписала его
/// ссылку, а сам сервер остался тем же.
///
/// ⚠️ ЗАЧЕМ ЭТО НУЖНО. Ключ сервера — его share-ссылка, и по ключу лежат пин,
/// ручная правка, результат пинга, выход в правиле раздельного туннелирования
/// и номер отдельного порта локального API. Панель владельца крутит у серверов
/// `sni`, `path`, `publicKey`, `shortId`, иногда адрес — за девять дней в его
/// журнале набралось около сорока строк «Ключ сервера сменился (сервер тот
/// же)». Приложение различие замечало, но только писало о нём, а данные
/// оставались на мёртвом ключе:
///
///  * закреплённый сервер оставался сверху СТАРОЙ ЗАПИСЬЮ — со старым
///    ключом REALITY, то есть нерабочим, — а рядом в списке появлялся он же,
///    уже рабочий, но без пина;
///  * правило «этот сайт через Германию» молча уходило в основной туннель:
///    выхода с таким ключом больше нет, а `sing-box check` висячую ссылку не
///    ловит;
///  * результаты пинга копились мусором (`ping_results.json` у владельца —
///    360 КБ).
///
/// В отличие от `KeyMigration` (там ОДИН сервер в разных написаниях ссылки),
/// здесь ссылки действительно разные: поменялось содержимое. Поэтому не всё
/// переносится вслепую — см. [overrides].
///
/// ⚠️ Функции чистые: на вход прежнее, на выход новое; ничего не пишут сами.
abstract final class ServerRekey {
  /// Закреплённые серверы: старая запись заменяется НОВОЙ на том же месте.
  ///
  /// Заменяется весь сервер, а не только ключ: в старой записи лежат старые
  /// учётные данные, с ними сервер не подключится. Если новая запись уже
  /// закреплена (человек успел закрепить её вручную), старая просто уходит —
  /// два одинаковых пина подряд ни к чему.
  static List<VpnServer> pins(
      List<VpnServer> pinned, Map<String, VpnServer> replacementByOldKey) {
    if (replacementByOldKey.isEmpty) return pinned;
    final out = <VpnServer>[];
    final seen = <String>{};
    for (final s in pinned) {
      final next = replacementByOldKey[s.key] ?? s;
      if (seen.add(next.key)) out.add(next);
    }
    return out;
  }

  /// Ручные правки сервера.
  ///
  /// ⚠️ ВАРИАЦИЯ ПЕРЕЕЗЖАЕТ, РУЧНОЙ JSON — НЕТ. Вариация (отпечаток TLS,
  /// фрагментация) накладывается ПОВЕРХ конфига сервера и от его ключей не
  /// зависит. Ручной JSON — это outbound целиком, со старым `publicKey`,
  /// `shortId`, uuid: перенеси его, и сервер с новыми данными подключался бы
  /// по старым — то есть не подключался бы вовсе, а виновата была бы правка,
  /// про которую человек давно забыл. Такая правка остаётся на старом ключе
  /// (её видно и можно снять, если сервер закреплён) и попадает в
  /// [RekeyedOverrides.droppedJson] — вызывающий говорит об этом в журнал.
  ///
  /// Если у нового ключа своя правка уже есть — она важнее переносимой.
  static RekeyedOverrides overrides(
      Map<String, ServerOverride> src, Map<String, String> rekey) {
    if (rekey.isEmpty || src.isEmpty) {
      return RekeyedOverrides(src, 0, 0);
    }
    final out = Map<String, ServerOverride>.of(src);
    var moved = 0;
    var droppedJson = 0;
    rekey.forEach((oldKey, newKey) {
      final o = src[oldKey];
      if (o == null || out.containsKey(newKey)) return;
      if ((o.rawJson ?? '').isNotEmpty) droppedJson++;
      final variant = o.variant;
      if (variant == null) return;
      out[newKey] = ServerOverride(variant: variant);
      moved++;
      // Остался только JSON — запись живёт на старом ключе, иначе убираем её:
      // вариация уже переехала, держать её копию на мёртвом ключе незачем.
      if ((o.rawJson ?? '').isEmpty) {
        out.remove(oldKey);
      } else {
        out[oldKey] = o.copyWith(clearVariant: true);
      }
    });
    return RekeyedOverrides(out, moved, droppedJson);
  }

  /// Словарь «ключ → значение» (результаты пинга, замеры скорости).
  ///
  /// Запись переезжает на новый ключ; если там уже есть своя, решает [merge]
  /// (для замеров — свежее). Старая запись убирается в любом случае: её ключ
  /// больше никто не спросит, она только копит мусор.
  static Map<String, T> map<T>(Map<String, T> src, Map<String, String> rekey,
      {T Function(T existing, T incoming)? merge}) {
    if (rekey.isEmpty || src.isEmpty) return src;
    final out = Map<String, T>.of(src);
    rekey.forEach((oldKey, newKey) {
      if (!out.containsKey(oldKey)) return;
      final value = out.remove(oldKey) as T;
      final have = out[newKey];
      out[newKey] =
          have == null ? value : (merge?.call(have, value) ?? have);
    });
    return out;
  }

  /// Настройки, ссылающиеся на сервер по ключу: выход у правил раздельного
  /// туннелирования и список серверов с отдельным портом локального API.
  ///
  /// Возвращает ТОТ ЖЕ объект, если ссылаться было не на что: правка
  /// настроек может перезапустить туннель (`reconnectReasons`), и дёргать его
  /// без изменений нельзя.
  static AppSettings settings(AppSettings s, Map<String, String> rekey) {
    if (rekey.isEmpty) return s;
    var changed = false;
    String? mapped(String? key) {
      if (key == null) return null;
      final next = rekey[key];
      if (next == null) return key;
      changed = true;
      return next;
    }

    final split = s.splitTunnel;
    final apps = [
      for (final r in split.apps)
        rekey.containsKey(r.serverKey)
            ? r.copyWith(serverKey: mapped(r.serverKey))
            : r,
    ];
    final sites = [
      for (final r in split.sites)
        rekey.containsKey(r.serverKey)
            ? r.copyWith(serverKey: mapped(r.serverKey))
            : r,
    ];
    final seen = <String>{};
    final apiKeys = <String>[];
    for (final k in s.apiExitServerKeys) {
      final m = mapped(k)!;
      if (seen.add(m)) apiKeys.add(m);
    }
    if (!changed) return s;
    return s.copyWith(
      splitTunnel: split.copyWith(apps: apps, sites: sites),
      apiExitServerKeys: apiKeys,
    );
  }
}

/// Итог [ServerRekey.overrides].
class RekeyedOverrides {
  final Map<String, ServerOverride> overrides;

  /// Сколько вариаций переехало на новый ключ.
  final int moved;

  /// Сколько ручных JSON-правок осталось на старом ключе (переносить их
  /// нельзя — см. [ServerRekey.overrides]).
  final int droppedJson;

  const RekeyedOverrides(this.overrides, this.moved, this.droppedJson);
}
