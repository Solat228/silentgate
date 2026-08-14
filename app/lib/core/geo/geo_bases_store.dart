import 'dart:convert';
import 'dart:io';

import '../platform/app_paths.dart';

/// Память про гео-базы: когда последний раз проверяли обновления, какая сумма
/// лежала в релизе и какая — у наших файлов.
///
/// ⚠️ ЖИВЁТ В КАТАЛОГЕ ДАННЫХ, А НЕ РЯДОМ С БАЗАМИ. На Windows базы лежат
/// рядом с `xray.exe`, то есть в `%ProgramFiles%\SilentGate` у установленной
/// копии — писать туда обычный пользователь не может. Положить память туда
/// значило бы, что у большинства она не сохраняется вовсе и «проверено вчера»
/// не показывается никогда.
///
/// ⚠️ ЗАЧЕМ КЭШ СУММ. Сумма нашего файла — это sha256 по 25 МБ. Считать её
/// заново на каждое открытие настроек незачем: файл не меняется сам, и пара
/// «размер + время правки» отвечает на вопрос «тот же ли это файл» точно
/// настолько, насколько нужно. Не совпало — считаем заново.
class GeoBasesStore {
  static const fileName = 'geo_bases.json';

  final File? _file;
  final Map<String, dynamic> _data;

  GeoBasesStore._(this._file, this._data);

  static Future<GeoBasesStore> load() async {
    try {
      final base = await AppPaths.supportDir();
      final f = File('${base.path}${Platform.pathSeparator}$fileName');
      if (!await f.exists()) return GeoBasesStore._(f, <String, dynamic>{});
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      return GeoBasesStore._(
          f, decoded is Map<String, dynamic> ? decoded : <String, dynamic>{});
    } catch (_) {
      // ⚠️ Сбой памяти НЕ смертелен: без неё просто пересчитаем хэш и не
      // покажем дату прошлой проверки. Ронять из-за этого скачивание баз —
      // менять неудобство на неработающую возможность.
      return GeoBasesStore._(null, <String, dynamic>{});
    }
  }

  DateTime? get lastCheckAt {
    final v = _data['checkedAt'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  Map<String, dynamic> _entry(String name) {
    final files = _data['files'];
    if (files is! Map) return const {};
    final e = files[name];
    return e is Map<String, dynamic> ? e : const {};
  }

  /// Сумма нашего файла, если файл с тех пор не менялся.
  String? cachedSum(String name, {required int size, required int mtimeMs}) {
    final e = _entry(name);
    if (e['size'] != size || e['mtimeMs'] != mtimeMs) return null;
    final sum = e['sum'];
    return sum is String && sum.isNotEmpty ? sum : null;
  }

  /// Сумма, которая лежала в релизе на момент последней проверки.
  String? remoteSum(String name) {
    final sum = _entry(name)['remoteSum'];
    return sum is String && sum.isNotEmpty ? sum : null;
  }

  Future<void> rememberSum(
    String name, {
    required int size,
    required int mtimeMs,
    required String sum,
  }) async {
    final files = _files();
    final e = Map<String, dynamic>.of(_entry(name));
    e['size'] = size;
    e['mtimeMs'] = mtimeMs;
    e['sum'] = sum;
    files[name] = e;
    await _persist();
  }

  Future<void> saveCheck({
    required DateTime at,
    required Map<String, String> remoteSums,
  }) async {
    _data['checkedAt'] = at.toIso8601String();
    final files = _files();
    for (final entry in remoteSums.entries) {
      final e = Map<String, dynamic>.of(_entry(entry.key));
      e['remoteSum'] = entry.value;
      files[entry.key] = e;
    }
    await _persist();
  }

  /// Забыть суммы (базы удалены — помнить нечего).
  Future<void> forgetSums() async {
    _data.remove('files');
    await _persist();
  }

  Map<String, dynamic> _files() {
    final existing = _data['files'];
    if (existing is Map<String, dynamic>) return existing;
    final fresh = <String, dynamic>{};
    _data['files'] = fresh;
    return fresh;
  }

  Future<void> _persist() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(_data), flush: true);
    } catch (_) {
      // См. комментарий в load(): память — удобство, а не условие работы.
    }
  }
}
