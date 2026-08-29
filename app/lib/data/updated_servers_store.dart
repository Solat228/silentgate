import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';
import 'atomic_file.dart';

/// Персистентная пометка «сервер обновился при последнем обновлении подписки».
///
/// Источник правды — [SubscriptionSyncResult.keyChanges]
/// (`core/models/subscription_sync.dart`): там уже посчитано, какие серверы
/// сохранили тождество, но сменили ключ, и какими полями отличается новая
/// запись. Второй расчёт здесь не заводится — только персистентность,
/// пережившая перезапуск приложения (иначе значок гас бы уже при следующем
/// открытии окна, а не при следующем обновлении подписки).
///
/// ⚠️ ПОЧЕМУ ВЕСЬ СПИСОК ПЕРЕЗАПИСЫВАЕТСЯ ЦЕЛИКОМ, А НЕ ДОПОЛНЯЕТСЯ. Значок
/// отвечает на вопрос «что изменилось В ПОСЛЕДНЕМ обновлении», а не копит
/// историю. Явное «пользователь посмотрел на этот сервер» здесь намеренно НЕ
/// заведено: список пролистывают, не открывая каждую строку, и такая метка
/// почти никогда бы не снималась — то есть перестала бы что-либо значить.
/// Следующее обновление подписки — уже существующая и понятная граница (тот
/// же момент, когда пересчитывается баннер «+2 · −1» и журнальная строка
/// «Ключ сервера сменился»), поэтому решает именно она: обновили подписку —
/// старые пометки снялись, актуальные встали на их место.
///
/// Ключ записи — [VpnServer.key] сервера ПОСЛЕ обновления (`ServerKeyChange.newKey`),
/// а не [VpnServer.identityKey]: тождество нигде не показывается в UI, а по
/// актуальному ключу карточка сервера ищет себя напрямую.
class UpdatedServersStore {
  static const _fileName = 'updated_servers.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// Ключ сервера → имена полей, которыми отличается новая запись (пустой
  /// список — сменилась только запись ссылки, поля совпали).
  Future<Map<String, List<String>>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final data = jsonDecode(await f.readAsString());
      if (data is! Map) return {};
      final out = <String, List<String>>{};
      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || key.isEmpty) continue;
        if (value is! List) continue;
        out[key] = value.whereType<String>().toList();
      }
      return out;
    } catch (_) {
      // Битый файл — не более чем потерянные значки «обновлён»: не роняем
      // список серверов из-за него.
      return {};
    }
  }

  Future<void> save(Map<String, List<String>> byKey) async {
    try {
      final f = await _file();
      await AtomicFile.writeString(f, jsonEncode(byKey));
    } catch (_) {}
  }
}
