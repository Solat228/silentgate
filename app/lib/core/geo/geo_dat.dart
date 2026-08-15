import 'dart:io';

/// Чтение СПИСКА КАТЕГОРИЙ из `geoip.dat` / `geosite.dat`.
///
/// ⚠️ ЗАЧЕМ. 15.08.2026 обновление гео-баз молча сломало владельцу
/// маршрутизацию: новый `geosite.dat` пришёл из другого проекта и был в пять раз
/// меньше — категорий `category-ru`, `ok`, `vk`, `yandex` в нём попросту не
/// оказалось. Ядро при этом стартовало без единой жалобы (Xray ругается только
/// на категорию, которой нет, когда она есть в правиле; правила панели ушли в
/// «нет совпадения»), и весь российский трафик поехал через VPN. Поэтому файл
/// проверяется ДО того, как встанет на место рабочего: нет нужной категории —
/// не заменяем.
///
/// ⚠️ ФОРМАТ — ОБРЕЗАННЫЙ РАЗБОР PROTOBUF, И ЭТОГО ДОСТАТОЧНО.
/// Оба файла — сообщения v2ray:
/// ```
/// message GeoSiteList { repeated GeoSite entry = 1; }
/// message GeoSite  { string country_code = 1; repeated Domain domain = 2; }
/// message GeoIPList  { repeated GeoIP  entry = 1; }
/// message GeoIP    { string country_code = 1; repeated CIDR cidr = 2; … }
/// ```
/// То есть файл — последовательность записей `0x0A <длина> <тело>`, а первое
/// поле тела — имя категории (`0x0A <длина> <ASCII>`). Больше нам ничего не
/// нужно: домены и подсети мы не читаем, а перепрыгиваем по длине. Отсюда цена
/// проверки — сотня коротких чтений вместо 20 МБ в память телефона.
///
/// ⚠️ В ФАЙЛЕ ИМЕНА ЛЕЖАТ В ВЕРХНЕМ РЕГИСТРЕ (`CATEGORY-RU`, `PRIVATE`), а в
/// конфигах пишутся в нижнем (`geosite:category-ru`). Поэтому [GeoDatScan]
/// приводит к верхнему обе стороны: имена — при разборе, запрос — в
/// [GeoDatScan.has]. Сверка «как есть» не нашла бы ни одной категории.
class GeoDat {
  GeoDat._();

  /// Сколько байт читаем на запись: заголовок (тег + длина ≤ 5 байт) плюс имя.
  /// Имена категорий — единицы десятков символов, 128 байт покрывают всё с
  /// запасом; если вдруг не хватит, имя дочитывается отдельным чтением.
  static const _window = 128;

  /// Предохранитель от «файла», который разбирается в бесконечность.
  static const _maxRecords = 200000;

  /// Прочитать имена категорий.
  ///
  /// Возвращает [GeoDatScan.unreadable], если структура не разобралась: такой
  /// ответ означает «мы НЕ ЗНАЕМ, что внутри», и выдавать его за «категорий
  /// нет» нельзя — на этом и строится решение «не заменять».
  static Future<GeoDatScan> scan(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final total = await raf.length();
      if (total <= 0) return const GeoDatScan.unreadable();
      final names = <String>{};
      var pos = 0;
      var records = 0;
      while (pos < total) {
        await raf.setPosition(pos);
        final head = await raf.read(_window);
        if (head.isEmpty) return const GeoDatScan.unreadable();
        final r = _Bytes(head);
        // Верхний уровень — только `repeated entry = 1` (тег 0x0A). Всё
        // остальное значит, что это не гео-база.
        if (r.varint() != 0x0a) return const GeoDatScan.unreadable();
        final size = r.varint();
        if (size == null || size < 0) return const GeoDatScan.unreadable();
        final bodyAt = pos + r.offset;
        if (bodyAt + size > total) return const GeoDatScan.unreadable();

        // Первое поле записи — имя категории. Если это не оно, запись просто
        // остаётся безымянной: перебирать всё тело ради имени не нужно, а
        // порядок полей в реальных файлах именно такой.
        if (r.varint() == 0x0a) {
          final len = r.varint();
          if (len != null && len > 0 && len <= 255 && r.offset + len <= size) {
            List<int> raw;
            if (r.offset + len <= head.length) {
              raw = head.sublist(r.offset, r.offset + len);
            } else {
              await raf.setPosition(pos + r.offset);
              raw = await raf.read(len);
            }
            if (raw.length == len) {
              final name = String.fromCharCodes(raw).trim();
              if (name.isNotEmpty) names.add(name);
            }
          }
        }

        pos = bodyAt + size;
        if (++records > _maxRecords) return const GeoDatScan.unreadable();
      }
      if (names.isEmpty) return const GeoDatScan.unreadable();
      return GeoDatScan(names);
    } catch (_) {
      // Нет прав, файл занят, оборван на середине — снаружи это одно и то же:
      // содержимое неизвестно.
      return const GeoDatScan.unreadable();
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }
}

/// Что нашли внутри `.dat`.
class GeoDatScan {
  /// Имена категорий, приведённые к ВЕРХНЕМУ регистру — тому, в котором они и
  /// лежат в файле. Приводим при разборе, а не при сравнении: иначе каждая
  /// сверка пересобирала бы множество из тысячи имён.
  final Set<String> names;

  /// Файл разобрался. `false` — содержимое НЕИЗВЕСТНО (а не «пусто»).
  final bool readable;

  GeoDatScan(Iterable<String> raw)
      : names = {for (final n in raw) n.toUpperCase()},
        readable = true;

  const GeoDatScan.unreadable()
      : names = const {},
        readable = false;

  /// Есть ли такая категория. Регистр не значим: в файле `CATEGORY-RU`,
  /// в конфиге `geosite:category-ru`.
  bool has(String category) => names.contains(category.toUpperCase());
}

/// Чтение варинтов из буфера с запоминанием позиции.
class _Bytes {
  _Bytes(this.data);

  final List<int> data;
  int offset = 0;

  /// Следующий varint или `null`, если буфер кончился либо число не влезает
  /// в разумные рамки (пять байт — 32 бита, длин больше нам не бывает).
  int? varint() {
    var result = 0;
    var shift = 0;
    while (offset < data.length && shift <= 28) {
      final b = data[offset++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
    return null;
  }
}
