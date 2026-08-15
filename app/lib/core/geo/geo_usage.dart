import 'dart:io';

import '../platform/app_paths.dart';

/// Какие категории гео-баз приложение реально использует.
///
/// ⚠️ ЗАЧЕМ. Обновление гео-баз может ЗАБРАТЬ категорию: файл из другого
/// проекта, урезанная сборка, переименование. Ядру это ничего не говорит —
/// Xray не запустится с правилом на несуществующую категорию
/// (`docs/RU_ROUTING_SOURCES.md`), а если правило пришло из панельного профиля,
/// то до этого молча перестанет совпадать целый пласт маршрутов. Владелец
/// 15.08.2026 получил ровно это: российский трафик поехал через VPN, и искал он
/// причину в серверах.
///
/// Поэтому перед заменой файла спрашиваем: какие `geosite:`/`geoip:` вообще
/// упоминаются в наших данных — и если хоть одной из них в новом файле нет,
/// замену не делаем.
enum GeoRefKind {
  /// `geoip:ru` — файл `geoip.dat`.
  ip,

  /// `geosite:category-ru` — файл `geosite.dat`.
  site,
}

/// Одна ссылка на категорию: из какого файла и как называется.
class GeoRef {
  final GeoRefKind kind;

  /// Имя категории БЕЗ префикса, отрицания и атрибута: `geosite:!category-ru@ads`
  /// → `category-ru`.
  final String name;

  const GeoRef(this.kind, this.name);

  String get prefix => kind == GeoRefKind.ip ? 'geoip' : 'geosite';

  /// Как это выглядит в конфиге — для показа человеку.
  String get label => '$prefix:$name';

  @override
  bool operator ==(Object other) =>
      other is GeoRef && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => label;
}

/// Сбор ссылок на категории из наших данных.
class GeoUsage {
  GeoUsage._();

  /// ⚠️ ИЩЕМ ПО ТЕКСТУ, А НЕ ПО СТРУКТУРЕ. Ссылка на категорию встречается в
  /// панельном конфиге (`routing.rules[].domain`, `.ip`), в правилах DNS, в
  /// пользовательском JSON-override и в правилах раздельного туннелирования —
  /// это четыре разных формата, каждый со своей схемой, и разбирать их по
  /// отдельности значит забыть пятый. Строка `geosite:xxx` выглядит одинаково
  /// везде, а лишнее совпадение стоит нам ровно ничего: проверим категорию,
  /// которая и так на месте.
  ///
  /// Форма: `geosite:category-ru`, с отрицанием `geoip:!cn`, с атрибутом
  /// `geosite:category-ru@ads`. Внешние файлы (`geosite:ext:my.dat:tag`)
  /// пропускаем: они лежат отдельно и к нашим базам отношения не имеют.
  static final _ref = RegExp(r'geo(site|ip):(!?)([A-Za-z0-9_.\-]+)');

  static Set<GeoRef> extract(String text) {
    final out = <GeoRef>{};
    for (final m in _ref.allMatches(text)) {
      final name = m.group(3)!;
      // `ext` — не категория, а признак внешнего файла.
      if (name.toLowerCase() == 'ext') continue;
      out.add(GeoRef(
        m.group(1) == 'ip' ? GeoRefKind.ip : GeoRefKind.site,
        name.toLowerCase(),
      ));
    }
    return out;
  }

  /// Файл больше этого не читаем: ссылки на категории живут в конфигах и
  /// настройках — это десятки килобайт. Читать многомегабайтный файл целиком
  /// ради поиска строки на телефоне незачем.
  static const _maxFileBytes = 8 * 1024 * 1024;

  /// Пройти по каталогу данных и собрать всё, на что ссылаются наши конфиги.
  ///
  /// ⚠️ ЧИТАЕМ ВСЕ `*.json` КАТАЛОГА, А НЕ ПЕРЕЧЕНЬ ИЗВЕСТНЫХ ИМЁН. Хранилищ
  /// девять, и список имён в отдельном месте устареет на первом же новом —
  /// причём молча, а цена молчания здесь — пропущенная категория и снова
  /// сломанная маршрутизация.
  ///
  /// Отказ чтения — не ошибка: вернём то, что успели собрать. Пустой ответ
  /// означает «ссылок не нашли», и тогда проверять при замене нечего.
  static Future<Set<GeoRef>> fromDataDir([Directory? dir]) async {
    final out = <GeoRef>{};
    try {
      final d = dir ?? await AppPaths.supportDir();
      if (!await d.exists()) return out;
      await for (final e in d.list(followLinks: false)) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.json')) continue;
        try {
          if (await e.length() > _maxFileBytes) continue;
          out.addAll(extract(await e.readAsString()));
        } catch (_) {
          // Битая кодировка, файл занят — пропускаем именно его.
        }
      }
    } catch (_) {}
    return out;
  }

  /// Только те ссылки, что относятся к указанному файлу.
  static Set<String> namesFor(Iterable<GeoRef> refs, GeoRefKind kind) =>
      {for (final r in refs) if (r.kind == kind) r.name};
}
