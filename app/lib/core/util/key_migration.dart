import '../parser/share_link_parser.dart';
import '../platform/app_log.dart';

/// Перевод сохранённых данных на канонические ключи серверов.
///
/// ⚠️ ЗАЧЕМ ЭТО НУЖНО И ЧТО БЫЛО БЕЗ НЕГО. Ключ сервера — его share-ссылка, и
/// по ключу лежат пин, ручная правка и результат пинга. Одни и те же данные
/// приходят в разных написаниях: у gRPC имя сервиса бывает `serviceName=`, а
/// бывает `path=`. Разбор понимал оба, сборка писала одно — и ключ зависел от
/// того, каким форматом ответила панель (Remnawave выбирает его по
/// `User-Agent`). Стоило формату смениться, как ВСЕ gRPC-серверы получали новые
/// ключи, а сохранённое по старым осиротевало.
///
/// Замерено на живых данных владельца 13.08.2026: из 374 результатов пинга
/// осиротели 273, из них 190 gRPC.
///
/// Канонизацию ключа чинит парсер; здесь — перенос УЖЕ СОХРАНЁННОГО.
///
/// ⚠️ Функции чистые и идемпотентные: повторный прогон ничего не портит.
/// Это важно, потому что зовутся они при каждой загрузке, а не один раз.
class KeyMigration {
  /// Перенести ключи словаря на канонические.
  ///
  /// [merge] решает столкновение, когда два старых ключа сводятся в один
  /// канонический (так бывает, если сервер лежал в обоих написаниях сразу).
  /// По умолчанию побеждает ПЕРВЫЙ: у него больше шансов быть тем, что
  /// пользователь видел последним в списке.
  static Map<String, T> remapMap<T>(
    Map<String, T> src, {
    T Function(T existing, T incoming)? merge,
    String? logLabel,
  }) {
    if (src.isEmpty) return src;
    final out = <String, T>{};
    var moved = 0;
    src.forEach((key, value) {
      final canon = ShareLinkParser.canonicalKey(key);
      if (canon != key) moved++;
      final have = out[canon];
      out[canon] = have == null ? value : (merge?.call(have, value) ?? have);
    });
    _report(logLabel, moved, src.length, out.length);
    return out;
  }

  /// Перенести список ключей (пины) на канонические, сохранив ПОРЯДОК.
  ///
  /// ⚠️ Порядок здесь — пользовательский: пины показываются сверху списка
  /// именно в нём. Дубли после сведения убираем, оставляя первое вхождение.
  static List<String> remapList(List<String> src, {String? logLabel}) {
    if (src.isEmpty) return src;
    final out = <String>[];
    final seen = <String>{};
    var moved = 0;
    for (final key in src) {
      final canon = ShareLinkParser.canonicalKey(key);
      if (canon != key) moved++;
      if (seen.add(canon)) out.add(canon);
    }
    _report(logLabel, moved, src.length, out.length);
    return out;
  }

  static void _report(String? label, int moved, int before, int after) {
    if (label == null || moved == 0) return;
    // Пишем в журнал ТОЛЬКО счётчики: сами ключи — это ссылки с учётными
    // данными, им в логе не место (тот же запрет, что для токена подписки).
    final lost = before - after;
    AppLog.i('Миграция ключей ($label): приведено $moved из $before'
        '${lost > 0 ? ', сведено дублей: $lost' : ''}');
  }
}
