import 'dart:typed_data';

/// Встроенный набор гео-баз: какие категории едут внутри приложения и как их
/// вырезать из полных файлов.
///
/// ⚠️ ЗАЧЕМ. Полные `geoip.dat` + `geosite.dat` весят около 30 МБ, и на чистой
/// установке их надо сначала скачать — до этого правила панели по странам и
/// категориям вычищаются из конфига, и российский трафик идёт через VPN.
/// Владелец 14.10.2026 наткнулся на это на свежей установке. А пользуются
/// панели крошечной частью файлов: на его подписке во всех профилях всего
/// двенадцать категорий, и почти все ссылки приходятся на восемь из них общим
/// весом около 0,4 МБ.
///
/// Набор выбран владельцем: «Россия + реклама», около 5 МБ (из них 4,3 МБ —
/// `category-ads-all`). `geoip:de` (1,2 МБ, две ссылки) в набор не вошёл: его
/// правила работают после закачки полных баз, а до неё вычищаются так же, как
/// сейчас вычищается всё.
///
/// ⚠️ ФАЙЛ БЕЗ ИМПОРТОВ FLUTTER. Его читает `tool/build_geo_mini.dart`
/// (`dart run`), а инструмент с `package:flutter` в цепочке падает на
/// «dart:ui is not available».
abstract final class GeoBundledSet {
  /// Категории `geoip.dat` во встроенном наборе (нижний регистр, как в конфигах).
  static const ip = <String>['private', 'ru', 'telegram'];

  /// Категории `geosite.dat` во встроенном наборе.
  static const site = <String>[
    'category-ru',
    'category-gov-ru',
    'yandex',
    'vk',
    'ok',
    'telegram',
    'youtube',
    'category-ads-all',
  ];

  /// Категории набора для файла по его имени (`geoip.dat` / `geosite.dat`).
  ///
  /// По имени файла, а не по `GeoRefKind`: тип живёт рядом с кодом, который
  /// тянет Flutter, а этот файл обязан собираться без него.
  static List<String> namesForFile(String fileName) =>
      fileName == 'geoip.dat' ? ip : site;

  /// Путь к файлу набора в ассетах приложения.
  ///
  /// ⚠️ ИМЕНА ФАЙЛОВ — ТЕ ЖЕ, ЧТО У ПОЛНЫХ БАЗ. Ядро ищет `geoip.dat` и
  /// `geosite.dat` по точным именам; набор копируется на их место как есть.
  static String assetPath(String fileName) => 'assets/geo/$fileName';

  /// Похож ли список категорий файла на встроенный набор.
  ///
  /// Признак — содержимое, а не отметка где-то в хранилище: отметку можно
  /// потерять (удалили данные, переставили приложение поверх), а состав файла
  /// всегда при нём. Полный файл содержит сотни категорий, набор — единицы, и
  /// все они из списка выше.
  static bool looksBundled(Set<String> upperNames, String fileName) {
    if (upperNames.isEmpty) return false;
    final allowed = {for (final n in namesForFile(fileName)) n.toUpperCase()};
    return upperNames.every(allowed.contains);
  }
}

/// Вырезать из полного `.dat` записи с указанными категориями.
///
/// Формат — `repeated entry = 1` верхнего уровня, у записи первое поле — имя
/// категории (подробно — в `geo_dat.dart`). Выходной файл — те же записи
/// байт в байт, в исходном порядке: это тоже корректный список, ядро читает его
/// так же, как полный.
///
/// Бросает [FormatException], если файл не разобрался или какой-то категории в
/// нём нет: набор без обещанной категории хуже, чем отсутствие набора, — правило
/// молча перестало бы совпадать.
Uint8List extractGeoCategories(Uint8List full, Iterable<String> names) {
  final want = {for (final n in names) n.toUpperCase()};
  final found = <String>{};
  final out = BytesBuilder(copy: false);
  var pos = 0;
  while (pos < full.length) {
    final start = pos;
    final tag = _varint(full, pos);
    if (tag == null || tag.value != 0x0a) {
      throw const FormatException('не гео-база: ожидалась запись entry = 1');
    }
    pos = tag.next;
    final size = _varint(full, pos);
    if (size == null) throw const FormatException('оборванная длина записи');
    final bodyAt = size.next;
    final end = bodyAt + size.value;
    if (end > full.length) throw const FormatException('запись за концом файла');
    final name = _entryName(full, bodyAt, end);
    if (name != null && want.contains(name)) {
      out.add(Uint8List.sublistView(full, start, end));
      found.add(name);
    }
    pos = end;
  }
  final lost = want.difference(found);
  if (lost.isNotEmpty) {
    throw FormatException('в файле нет категорий: ${(lost.toList()..sort()).join(', ')}');
  }
  return out.takeBytes();
}

String? _entryName(Uint8List b, int at, int end) {
  final tag = _varint(b, at);
  if (tag == null || tag.value != 0x0a) return null;
  final len = _varint(b, tag.next);
  if (len == null) return null;
  final nameEnd = len.next + len.value;
  if (nameEnd > end) return null;
  return String.fromCharCodes(b, len.next, nameEnd).trim().toUpperCase();
}

class _Varint {
  final int value;
  final int next;
  const _Varint(this.value, this.next);
}

_Varint? _varint(Uint8List b, int pos) {
  var result = 0;
  var shift = 0;
  while (pos < b.length && shift <= 28) {
    final c = b[pos++];
    result |= (c & 0x7f) << shift;
    if (c & 0x80 == 0) return _Varint(result, pos);
    shift += 7;
  }
  return null;
}
