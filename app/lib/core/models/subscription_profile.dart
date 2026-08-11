import 'subscription_info.dart';

/// Одна подписка (профиль). Приложение держит их список и работает с активной.
///
/// Серверы хранятся ссылками — как и раньше; авторитетные конфиги панели,
/// пины, override и результаты пинга остаются ОБЩИМИ по ключу сервера:
/// один и тот же сервер в двух подписках — это буквально один сервер,
/// и разделять его пинги было бы неверно.
class SubscriptionProfile {
  final String id;
  final String url;
  final SubscriptionInfo info;

  /// Путь к кэшированной аватарке (у каждой подписки своя).
  final String? logoPath;

  /// Источник (URL) кэшированной аватарки. Нужен, чтобы при обновлении подписки
  /// не перекачивать картинку, если её адрес не изменился (и наоборот — заменить,
  /// если изменился).
  final String? logoUrl;

  /// Share-ссылки серверов этой подписки (порядок как пришёл от панели).
  final List<String> serverLinks;

  /// Когда подписку добавили.
  ///
  /// ⚠️ Это НЕ порядок показа. Порядок в меню задаёт сам список профилей —
  /// его можно переставить руками, и переставленный порядок обязан пережить
  /// перезапуск. Дата нужна для другого: новая подписка встаёт в КОНЕЦ (то
  /// есть по дате добавления), и старые файлы без этого поля получают
  /// осмысленную дату по своему месту в файле, а не «все одновременно».
  final DateTime? addedAt;

  const SubscriptionProfile({
    required this.id,
    required this.url,
    this.info = SubscriptionInfo.empty,
    this.logoPath,
    this.logoUrl,
    this.serverLinks = const [],
    this.addedAt,
  });

  /// Имя для UI: название от панели, иначе — узнаваемый кусок ссылки.
  String get title {
    final t = info.title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final last = u.pathSegments.isEmpty ? '' : u.pathSegments.last;
    return last.isEmpty ? u.host : '${u.host}/…$last';
  }

  /// Имя, которое можно показать НА ОБЩЕМ ЭКРАНЕ.
  ///
  /// ⚠️ ОТЛИЧАЕТСЯ ОТ [title] ОДНИМ, НО ВАЖНЫМ. Запасной вариант в [title] —
  /// `host/…<последний сегмент пути>`, а у Remnawave последний сегмент пути и
  /// есть СЕКРЕТ подписки. В меню переключателя, которое человек открывает сам,
  /// это ещё терпимо; на главном экране — уже нет: его шлют в поддержку
  /// скриншотом. Здесь при отсутствии названия от панели остаётся только хост.
  String get safeTitle {
    final t = info.title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final u = Uri.tryParse(url);
    final host = u?.host ?? '';
    return host.isEmpty ? '—' : host;
  }

  /// Стабильный идентификатор из URL: не зависит от порядка и переживает
  /// переименование подписки на панели.
  static String idFor(String url) {
    final normalized = url.trim().toLowerCase();
    var hash = 0;
    for (final code in normalized.codeUnits) {
      hash = 0x1fffffff & (hash + code);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return 'sub_${hash.toRadixString(16)}';
  }

  SubscriptionProfile copyWith({
    String? url,
    SubscriptionInfo? info,
    String? logoPath,
    String? logoUrl,
    bool clearLogo = false, // явно снять логотип (copyWith(logoPath:null) не снимает)
    List<String>? serverLinks,
    DateTime? addedAt,
  }) =>
      SubscriptionProfile(
        id: id,
        url: url ?? this.url,
        info: info ?? this.info,
        logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
        logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
        serverLinks: serverLinks ?? this.serverLinks,
        addedAt: addedAt ?? this.addedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'info': info.toJson(),
        'logoPath': logoPath,
        'logoUrl': logoUrl,
        'servers': serverLinks,
        'addedAt': addedAt?.toIso8601String(),
      };

  factory SubscriptionProfile.fromJson(Map<String, dynamic> j) {
    final url = '${j['url'] ?? ''}';
    return SubscriptionProfile(
      id: '${j['id'] ?? idFor(url)}',
      url: url,
      info: j['info'] is Map<String, dynamic>
          ? SubscriptionInfo.fromJson(j['info'] as Map<String, dynamic>)
          : SubscriptionInfo.empty,
      logoPath: j['logoPath'] as String?,
      logoUrl: j['logoUrl'] as String?,
      serverLinks: (j['servers'] as List?)?.cast<String>() ?? const [],
      addedAt: DateTime.tryParse('${j['addedAt'] ?? ''}'),
    );
  }
}
