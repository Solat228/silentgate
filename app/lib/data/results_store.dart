import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';
import '../core/util/key_migration.dart';
import 'atomic_file.dart';

/// Простое JSON-хранилище результатов (пинг, автонастройка) в каталоге поддержки приложения.
class ResultsStore {
  final String fileName;
  const ResultsStore(this.fileName);

  static const ping = ResultsStore('ping_results.json');
  static const autoConfig = ResultsStore('autoconfig_results.json');

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  Future<dynamic> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final s = await f.readAsString();
      if (s.trim().isEmpty) return null;
      final data = jsonDecode(s);
      // ⚠️ Ключи приводим к каноническому виду ПРИ ЧТЕНИИ: до 1.4.2 сервер мог
      // храниться в двух написаниях ссылки, и результат пинга осиротевал сразу
      // после смены формата ответа панели. На данных владельца так потерялось
      // 273 записи из 374.
      if (data is Map) {
        return migrate(data.cast<String, dynamic>(), logLabel: fileName);
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Приведение ключей + разрешение столкновений ПО СВЕЖЕСТИ.
  ///
  /// Вынесено из [load] отдельной чистой функцией, чтобы страж проверял тот же
  /// код, который работает в приложении, а не свою копию правила слияния.
  static Map<String, dynamic> migrate(Map<String, dynamic> data,
          {String? logLabel}) =>
      KeyMigration.remapMap<dynamic>(data, merge: fresher, logLabel: logLabel);

  /// Кто побеждает, когда два старых ключа сводятся в один канонический.
  ///
  /// ⚠️ ЗДЕСЬ — САМЫЙ СВЕЖИЙ ЗАМЕР, А НЕ ПЕРВЫЙ ВСТРЕЧЕННЫЙ. Умолчание
  /// `KeyMigration.remapMap` оставляет первое вхождение, а первым в файле лежит
  /// как раз САМОЕ СТАРОЕ измерение: словарь сохраняет порядок вставки,
  /// прочитанное с диска попадает в него раньше всего, а новые результаты
  /// дописываются в конец. То есть при сведении двух написаний одного сервера
  /// пользователю показалась бы позапрошлогодняя цифра — при живом свежем
  /// замере рядом. Дат нет у обеих записей — остаётся существующая: гадать не о
  /// чем, а порядок хотя бы предсказуем.
  static dynamic fresher(dynamic existing, dynamic incoming) {
    final a = _measuredAt(existing);
    final b = _measuredAt(incoming);
    if (b == null) return existing;
    if (a == null) return incoming;
    return b.isAfter(a) ? incoming : existing;
  }

  static DateTime? _measuredAt(dynamic value) {
    if (value is! Map) return null;
    final raw = value['measuredAt'];
    return raw == null ? null : DateTime.tryParse('$raw');
  }

  // ── Профили «Авто …»: чей это ключ ─────────────────────────────────────────
  //
  // ⚠️ ЗДЕСЬ ЧУЖИХ ФАЙЛОВ БОЛЬШЕ НЕ ЧИТАЕТСЯ, И СЛОВО «ВСЕГДА» СКАЗАТЬ НЕЛЬЗЯ.
  // Ключ профиля панели с 1.4.2 содержит отпечаток подписки
  // (`panel://<имя>?sub=…`); псевдоним старого написания заводит
  // `PanelOutboundsStore.load()` — единственное место, где сырой конфиг панели
  // и так на руках. Прежде это делало ЭТО хранилище, читая `panel_outbounds.json`
  // само, и держалось всё на порядке чтения: кто успел первым.
  //
  // Честное следствие: результаты пинга читает `ProbeController`, он поднимается
  // отдельно от `AppState`, и порядок между ними по-прежнему ничем не задан.
  // Прочитает раньше — сохранённый пинг профиля «Авто» останется по старому
  // ключу и профиль покажет «не проверен». Запись при этом ЦЕЛА: она уезжает на
  // новый ключ на той загрузке, где конфиги панели прочитаны раньше, либо её
  // заменяет новый замер. Теряется показ, а не данные, — и именно этим случай
  // отличается от конфига профиля, потеря которого была необратимой.

  Future<void> save(Object data) async {
    try {
      final f = await _file();
      await AtomicFile.writeString(f, jsonEncode(data));
    } catch (_) {}
  }
}
