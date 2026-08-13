import '../util/b64.dart';

/// Метаданные подписки из заголовков ответа панели (Remnawave/Marzban-совместимо).
///
/// Заголовки, которые уже потребляют Happ и v2RayTun:
///  - profile-title            → название подписки (может быть base64)
///  - subscription-userinfo    → upload=…; download=…; total=…; expire=… (байты, unix-время)
///  - profile-update-interval  → часы автообновления
///  - announce / announce-url  → объявление провайдера
class SubscriptionInfo {
  final String? title;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final DateTime? expiresAt;
  final int? updateIntervalHours;
  final String? announce;
  final String? announceUrl;
  final String? supportUrl;

  /// URL логотипа из заголовка ответа панели (`x-logo-url` / `profile-logo-url`).
  /// Настраивается в Remnawave: Response Rules → responseModifications.headers.
  /// Нужен потому, что страница подписки — SPA: в статическом HTML логотипа нет.
  final String? logoUrl;

  const SubscriptionInfo({
    this.title,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expiresAt,
    this.updateIntervalHours,
    this.announce,
    this.announceUrl,
    this.supportUrl,
    this.logoUrl,
  });

  static const empty = SubscriptionInfo();

  int? get usedBytes {
    if (uploadBytes == null && downloadBytes == null) return null;
    return (uploadBytes ?? 0) + (downloadBytes ?? 0);
  }

  /// Трафик без лимита.
  ///
  /// Remnawave кодирует безлимит нулём — так же, как `expire=0` означает
  /// «бессрочно». Отличать это состояние обязательно: иначе интерфейс рисует
  /// шкалу «израсходовано X из 0» и — поскольку доля неизвестна — крутит
  /// БЕСКОНЕЧНУЮ полосу прогресса, которая выглядит как вечно идущее
  /// обновление подписки.
  bool get unlimitedTraffic => totalBytes == null || totalBytes! <= 0;

  /// Истекла ли подписка К МОМЕНТУ [now].
  ///
  /// ⚠️ ДВЕ ЛОВУШКИ, И ОБЕ В ЭТОМ ПРОЕКТЕ УЖЕ СРАБАТЫВАЛИ.
  ///
  /// 1. **Пусто — это «бессрочно», а не «истекла».** Панель кодирует
  ///    бессрочность нулём (`expire=0`), и [fromHeaders] превращает такой ноль в
  ///    `null` — иначе интерфейс показывал бы 1970 год (фикс 0.4.0). Считать
  ///    `null` истёкшим значило бы перечеркнуть ВСЕ бессрочные подписки; то же
  ///    у профиля, сохранённого версией, которая метаданных ещё не писала.
  /// 2. **Сравнивается МОМЕНТ ВРЕМЕНИ, а не календарный день.** Подписка,
  ///    истекающая сегодня вечером, ещё работает — усечение до даты пометило бы
  ///    её истёкшей с самого утра. [DateTime.isAfter] сравнивает абсолютное
  ///    время, поэтому хранение в UTC и показ в локальной зоне на вердикт не
  ///    влияют: сравнивать «UTC с локальным» здесь безопасно.
  bool isExpiredAt(DateTime now) {
    final e = expiresAt;
    return e != null && !e.isAfter(now);
  }

  /// То же на текущий момент.
  bool get isExpired => isExpiredAt(DateTime.now());

  /// Доля использованного трафика 0..1 (null если total неизвестен/безлимит).
  double? get usedFraction {
    final u = usedBytes, t = totalBytes;
    if (u == null || t == null || t <= 0) return null;
    return (u / t).clamp(0.0, 1.0);
  }

  /// Сериализация для локального сохранения (#5): карточка подписки должна быть
  /// полной сразу после запуска, не дожидаясь ручного «Обновить».
  Map<String, dynamic> toJson() => {
        'title': title,
        'uploadBytes': uploadBytes,
        'downloadBytes': downloadBytes,
        'totalBytes': totalBytes,
        // UTC с суффиксом Z: локальное время без offset'а «поплыло» бы при смене TZ.
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'updateIntervalHours': updateIntervalHours,
        'announce': announce,
        'announceUrl': announceUrl,
        'supportUrl': supportUrl,
        'logoUrl': logoUrl,
      };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> j) => SubscriptionInfo(
        title: j['title'] as String?,
        uploadBytes: (j['uploadBytes'] as num?)?.toInt(),
        downloadBytes: (j['downloadBytes'] as num?)?.toInt(),
        totalBytes: (j['totalBytes'] as num?)?.toInt(),
        expiresAt: j['expiresAt'] != null
            ? DateTime.tryParse('${j['expiresAt']}')?.toLocal()
            : null,
        updateIntervalHours: (j['updateIntervalHours'] as num?)?.toInt(),
        announce: j['announce'] as String?,
        announceUrl: j['announceUrl'] as String?,
        supportUrl: j['supportUrl'] as String?,
        logoUrl: j['logoUrl'] as String?,
      );

  factory SubscriptionInfo.fromHeaders(Map<String, String> headers) {
    // http нормализует ключи в нижний регистр.
    String? h(String k) => headers[k.toLowerCase()];

    String? title = h('profile-title');
    if (title != null && title.startsWith('base64:')) {
      title = B64.tryDecodeToString(title.substring(7)) ?? title;
    }

    int? up, down, total;
    DateTime? expire;
    final userinfo = h('subscription-userinfo');
    if (userinfo != null) {
      for (final part in userinfo.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length != 2) continue;
        final key = kv[0].trim();
        final value = int.tryParse(kv[1].trim());
        if (value == null) continue;
        switch (key) {
          case 'upload':
            up = value;
            break;
          case 'download':
            down = value;
            break;
          case 'total':
            total = value;
            break;
          case 'expire':
            // expire=0 (или отрицательный) у панели означает «бессрочно» — не показываем 1970.
            if (value > 0) {
              expire = DateTime.fromMillisecondsSinceEpoch(value * 1000);
            }
            break;
        }
      }
    }

    String? announce = h('announce');
    if (announce != null && announce.startsWith('base64:')) {
      announce = B64.tryDecodeToString(announce.substring(7)) ?? announce;
    }

    return SubscriptionInfo(
      title: title,
      uploadBytes: up,
      downloadBytes: down,
      totalBytes: total,
      expiresAt: expire,
      updateIntervalHours: int.tryParse(h('profile-update-interval') ?? ''),
      announce: announce,
      announceUrl: h('announce-url'),
      supportUrl: h('support-url'),
      logoUrl: h('x-logo-url') ?? h('profile-logo-url') ?? h('logo-url'),
    );
  }
}
