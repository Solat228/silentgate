import 'dart:io';

import '../platform/app_log.dart';
import '../platform/app_paths.dart';

/// Гео-базы Xray (`geoip.dat` / `geosite.dat`) — наличие, размер, скачивание.
///
/// ⚠️ ПОЧЕМУ ИХ НЕТ В ПОСТАВКЕ НА ANDROID. Вдвоём файлы весят около 30 МБ, а
/// APK и без них 76 МБ. Класть их внутрь — значит утроить вес обновления ради
/// того, что нужно не всем: обычному серверу гео-базы не нужны вовсе, они
/// нужны панельным профилям с российской маршрутизацией.
///
/// ⚠️ ЧТО БЫВАЕТ, КОГДА ИХ НЕТ. Xray отвергает конфиг ЦЕЛИКОМ, и VPN-сервис
/// останавливается:
/// `illegal ip rule: geoip:private > failed to open geoip.dat`.
/// Поэтому отсутствие файлов обязано быть НЕ ошибкой, а известным состоянием:
/// конфиг чистится (`stripGeodata`), пользователь получает объяснение, а
/// скачать их можно кнопкой в настройках.
///
/// На Windows файлы приезжают вместе с ядром (`tools/fetch-xray.ps1`
/// распаковывает их из релизного архива Xray), поэтому там всё это не нужно.
class GeoAssets {
  /// Откуда качаем. Те же файлы, что XTLS кладёт в свой релизный архив, —
  /// иначе набор категорий на Android разошёлся бы с Windows, и правило,
  /// работающее на компьютере, молча не сработало бы на телефоне.
  static const geoipUrl =
      'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
  static const geositeUrl =
      'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';

  /// Каталог для баз. Отдаётся ядру через переменную окружения
  /// `XRAY_LOCATION_ASSET`: другого способа указать путь у libXray нет —
  /// `RunXrayFromJSONRequest` принимает только сам конфиг (проверено по
  /// биндингу в `cores.aar`).
  static Future<Directory> dir() async {
    final base = await AppPaths.supportDir();
    final d = Directory('${base.path}${Platform.pathSeparator}geo');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _geoip() async =>
      File('${(await dir()).path}${Platform.pathSeparator}geoip.dat');

  static Future<File> _geosite() async =>
      File('${(await dir()).path}${Platform.pathSeparator}geosite.dat');

  /// Обе базы на месте и не пусты.
  ///
  /// Проверяем именно ОБЕ: с одной половиной конфиг всё равно не соберётся,
  /// а «частично установлено» — состояние, которое пользователю не объяснить.
  static Future<bool> available() async {
    try {
      final a = await _geoip();
      final b = await _geosite();
      return await a.exists() &&
          await b.exists() &&
          await a.length() > 0 &&
          await b.length() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Размер и дата — для строки в настройках.
  static Future<GeoAssetsStatus> status() async {
    try {
      final a = await _geoip();
      final b = await _geosite();
      if (!await a.exists() || !await b.exists()) {
        return const GeoAssetsStatus(present: false);
      }
      final sa = await a.stat();
      final sb = await b.stat();
      return GeoAssetsStatus(
        present: sa.size > 0 && sb.size > 0,
        bytes: sa.size + sb.size,
        updatedAt: sa.modified.isAfter(sb.modified) ? sa.modified : sb.modified,
      );
    } catch (_) {
      return const GeoAssetsStatus(present: false);
    }
  }

  /// Скачать обе базы. Возвращает `null` при успехе, иначе — причину отказа.
  ///
  /// ⚠️ Пишем во временный файл и переименовываем. Иначе оборванная закачка
  /// оставила бы обрезанный `geoip.dat`, который ядро принимает за настоящий:
  /// вместо честного «баз нет» получили бы неверную маршрутизацию, которую
  /// никто не заподозрит.
  static Future<String?> download({void Function(String stage)? onProgress}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'SilentGate';
    try {
      for (final item in [
        (url: geoipUrl, file: await _geoip(), name: 'geoip.dat'),
        (url: geositeUrl, file: await _geosite(), name: 'geosite.dat'),
      ]) {
        onProgress?.call(item.name);
        final tmp = File('${item.file.path}.part');
        final err = await _fetch(client, item.url, tmp);
        if (err != null) {
          if (await tmp.exists()) await tmp.delete();
          return '${item.name}: $err';
        }
        if (await item.file.exists()) await item.file.delete();
        await tmp.rename(item.file.path);
        AppLog.i('Гео-база ${item.name} обновлена: '
            '${(await item.file.length()) ~/ 1024} КБ');
      }
      return null;
    } catch (e) {
      return '$e';
    } finally {
      client.close(force: true);
    }
  }

  /// Скачивание одного файла с поддержкой переадресации.
  ///
  /// ⚠️ Переадресация обязательна: ссылка `releases/latest/download/…`
  /// отдаёт 302 на конкретный релиз. Без неё в файл лёг бы HTML-редирект —
  /// и снова «файл есть, но неверный».
  static Future<String?> _fetch(HttpClient client, String url, File to) async {
    var target = Uri.parse(url);
    for (var hop = 0; hop < 5; hop++) {
      final req = await client.getUrl(target);
      req.followRedirects = false;
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final sink = to.openWrite();
        try {
          await resp.pipe(sink);
        } finally {
          await sink.close();
        }
        return await to.length() > 0 ? null : 'пустой ответ';
      }
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (loc == null) return 'переадресация без адреса';
        target = target.resolve(loc);
        continue;
      }
      await resp.drain<void>();
      return 'HTTP ${resp.statusCode}';
    }
    return 'слишком много переадресаций';
  }

  /// Удалить базы (освободить место / принудительно перекачать).
  static Future<void> remove() async {
    for (final f in [await _geoip(), await _geosite()]) {
      if (await f.exists()) await f.delete();
    }
  }
}

class GeoAssetsStatus {
  final bool present;
  final int bytes;
  final DateTime? updatedAt;
  const GeoAssetsStatus({
    required this.present,
    this.bytes = 0,
    this.updatedAt,
  });
}
