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
