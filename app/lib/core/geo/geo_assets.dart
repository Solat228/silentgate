import 'dart:io';

import 'geo_bases.dart';

/// Гео-базы Xray (`geoip.dat` / `geosite.dat`) — наличие, размер, скачивание.
///
/// ⚠️ ЭТО ТОНКАЯ ОБЁРТКА НАД [GeoBases], А НЕ ВТОРАЯ РЕАЛИЗАЦИЯ. Раньше здесь
/// был свой загрузчик — со своими адресами (`v2fly/geoip` и
/// `v2fly/domain-list-community`), без сверки контрольной суммы, без резервной
/// копии и без проверки категорий. Он и уронил владельцу маршрутизацию
/// 15.08.2026: файлы «того же назначения» из другого проекта перезаписали
/// рабочие, и правила панели по российским категориям перестали совпадать.
/// Разбор — в комментарии к [GeoBase].
///
/// **Урок общий:** две дороги к одному файлу означают, что защита, написанная
/// на одной, не действует на второй. Оставлен только вход, всё поведение —
/// в [GeoBases].
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
class GeoAssets {
  /// Каталог для баз. Отдаётся ядру через переменную окружения
  /// `XRAY_LOCATION_ASSET`: другого способа указать путь у libXray нет —
  /// `RunXrayFromJSONRequest` принимает только сам конфиг (проверено по
  /// биндингу в `cores.aar`).
  static Future<Directory> dir() => GeoBases.dir();

  /// Обе базы на месте и читаемы.
  ///
  /// Проверяем именно ОБЕ: с одной половиной конфиг всё равно не соберётся,
  /// а «частично установлено» — состояние, которое пользователю не объяснить.
  static Future<bool> available() => GeoBases.available();

  /// Размер и дата — для строки в настройках.
  static Future<GeoAssetsStatus> status() async {
    final s = await GeoBases.status();
    return GeoAssetsStatus(
      present: s.ready,
      bytes: s.bytes,
      updatedAt: s.updatedAt,
    );
  }

  /// Скачать недостающие базы. Возвращает `null` при успехе, иначе — причину.
  ///
  /// Вся защита — сверка sha256, резерв прежнего файла и проверка категорий —
  /// живёт в [GeoBases.download]; здесь только пересчёт того, что качать.
  static Future<String?> download({
    void Function(String stage)? onProgress,
  }) async {
    final files = (await GeoBases.status()).needDownload;
    return GeoBases.download(
      files: files,
      onProgress: (p) => onProgress?.call(p.base.fileName),
    );
  }

  /// Удалить базы (освободить место / принудительно перекачать).
  static Future<void> remove() => GeoBases.remove();
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
