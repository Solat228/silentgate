import 'vpn_server.dart';

/// «Сервер тот же, а ключ другой» — диагностика расхождения форматов ссылки.
///
/// ⚠️ ХРАНИТ ТОЛЬКО ИМЕНА ПОЛЕЙ, НИКОГДА — ЗНАЧЕНИЯ. Ключ сервера это его
/// share-ссылка, а в ней лежат учётные данные (uuid VLESS, пароль trojan/ss,
/// пароль обфускации hysteria2). Запись «было → стало» отправила бы их в
/// `app.log` и оттуда в отчёт поддержки, который владелец пересылает в чат.
class ServerKeyChange {
  /// Имя сервера, как его видит человек в списке.
  final String name;

  /// Имена полей, которыми отличаются старая и новая ссылки (без значений).
  /// Пусто — значит поля совпали, разошлась только ЗАПИСЬ ссылки: ровно так
  /// выглядел дефект gRPC (`serviceName=` против `path=`).
  final List<String> fields;

  const ServerKeyChange({required this.name, required this.fields});
}

/// Итог обновления подписки: что изменилось в составе серверов (как в NekoBox)
/// и сколько серверов пришло с конфигом от панели.
class SubscriptionSyncResult {
  final int total;
  final List<String> added;
  final List<String> removed;

  /// Серверов с авторитетным конфигом панели (формат XRAY_JSON).
  final int withPanelConfig;

  /// Из них — профилей «Авто …» с готовым балансировщиком.
  final int panelProfiles;

  /// Серверы, оставшиеся на месте, но сменившие ключ. В баннер НЕ идут —
  /// пользователю это ничего не говорит; нужны для журнала (см. [keyChangeReport]).
  final List<ServerKeyChange> keyChanges;

  final DateTime at;

  const SubscriptionSyncResult({
    required this.total,
    required this.added,
    required this.removed,
    required this.withPanelConfig,
    required this.panelProfiles,
    required this.at,
    this.keyChanges = const [],
  });

  /// Сравнение состава подписки ПО ТОЖДЕСТВУ СЕРВЕРА, а не по его ключу.
  ///
  /// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТО НАПИСАНО: раньше состав считался по
  /// [VpnServer.key], то есть по полной share-ссылке. Ссылка законно меняется,
  /// когда панель поправила серверу отпечаток, sni или путь, — и баннер писал
  /// «+1 · −1» у сервера «Москва 1. GRPC», который никуда не девался. Первая
  /// линия защиты — канонический ключ (`ShareLinkParser`), эта вторая: даже при
  /// будущем расхождении форматов баннер останется честным.
  ///
  /// Переименование сервера — намеренно добавление + удаление: человек узнаёт
  /// узел по имени, и «Москва 1» вместо «Москва 2» для него другой сервер.
  factory SubscriptionSyncResult.diff({
    required List<VpnServer> before,
    required List<VpnServer> after,
    required int withPanelConfig,
    required int panelProfiles,
    DateTime? at,
  }) {
    final beforeById = {for (final s in before) s.identityKey: s};
    final afterById = {for (final s in after) s.identityKey: s};

    final changes = <ServerKeyChange>[];
    for (final e in afterById.entries) {
      final old = beforeById[e.key];
      // Тождество сохранилось, а ключ другой — значит расходится ЗАПИСЬ
      // сервера. Именно это молча съедало пины и результаты пинга.
      if (old != null && old.key != e.value.key) {
        changes.add(ServerKeyChange(
          name: e.value.displayName,
          fields: changedFields(old, e.value),
        ));
      }
    }

    return SubscriptionSyncResult(
      total: after.length,
      added: [
        for (final e in afterById.entries)
          if (!beforeById.containsKey(e.key)) e.value.displayName,
      ],
      removed: [
        for (final e in beforeById.entries)
          if (!afterById.containsKey(e.key)) e.value.displayName,
      ],
      withPanelConfig: withPanelConfig,
      panelProfiles: panelProfiles,
      keyChanges: changes,
      at: at ?? DateTime.now(),
    );
  }

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

  /// Строки для журнала: чем именно отличается новая запись сервера.
  ///
  /// Одинаковые расхождения свёрнуты в одну строку с числом: у владельца
  /// gRPC-серверов было 190 — столько же строк в `app.log` сделали бы журнал
  /// нечитаемым и вытеснили бы из него всё остальное ротацией.
  ///
  /// ⚠️ ИМЕНА ПОЛЕЙ И ИМЕНА СЕРВЕРОВ — И БОЛЬШЕ НИЧЕГО. Значения полей и сами
  /// ключи не печатаются: там учётные данные (см. [ServerKeyChange]).
  List<String> get keyChangeReport {
    if (keyChanges.isEmpty) return const [];
    // Группируем по НАБОРУ полей, сохраняя порядок появления, — так строка
    // журнала отвечает на вопрос «что именно разошлось», а не «сколько всего».
    final groups = <String, List<String>>{};
    for (final c in keyChanges) {
      groups.putIfAbsent(c.fields.join(', '), () => <String>[]).add(c.name);
    }
    final lines = <String>[];
    for (final g in groups.entries) {
      final names = g.value;
      final sample = names.take(3).join(', ');
      final tail = names.length > 3 ? ' и ещё ${names.length - 3}' : '';
      final what = g.key.isEmpty
          ? 'изменилась только запись ссылки'
          : 'изменились поля: ${g.key}';
      lines.add('Ключ сервера сменился (сервер тот же): ${names.length} шт., '
          '$what; например: $sample$tail');
    }
    return lines;
  }

  /// Имена полей, которыми отличаются две записи одного и того же сервера.
  ///
  /// Список закрытый и перечислен руками: рефлексии в Dart нет, а автоматом по
  /// `toString()` пришлось бы печатать значения — то есть учётные данные.
  /// ⚠️ Добавили поле в [VpnServer] — добавьте его и сюда, иначе расхождение
  /// формата снова станет невидимым.
  static List<String> changedFields(VpnServer a, VpnServer b) {
    final diff = <String>[];
    void cmp(String name, Object? x, Object? y) {
      if (x != y) diff.add(name);
    }

    // Адрес входит в тождество, но там он приведён к нижнему регистру:
    // расхождение только в регистре ловится здесь.
    cmp('address', a.address, b.address);
    cmp('id', a.id, b.id);
    cmp('encryption', a.encryption, b.encryption);
    cmp('alterId', a.alterId, b.alterId);
    cmp('flow', a.flow, b.flow);
    cmp('network', a.network, b.network);
    cmp('security', a.security, b.security);
    cmp('sni', a.sni, b.sni);
    cmp('host', a.host, b.host);
    cmp('path', a.path, b.path);
    cmp('fingerprint', a.fingerprint, b.fingerprint);
    cmp('publicKey', a.publicKey, b.publicKey);
    cmp('shortId', a.shortId, b.shortId);
    cmp('spiderX', a.spiderX, b.spiderX);
    cmp('alpn', a.alpn, b.alpn);
    cmp('headerType', a.headerType, b.headerType);
    cmp('authority', a.authority, b.authority);
    cmp('xhttpMode', a.xhttpMode, b.xhttpMode);
    cmp('xPadding', a.xPadding, b.xPadding);
    cmp('obfs', a.obfs, b.obfs);
    cmp('obfsPassword', a.obfsPassword, b.obfsPassword);
    cmp('allowInsecure', a.allowInsecure, b.allowInsecure);
    cmp('hopPorts', a.hopPorts, b.hopPorts);
    return diff;
  }

  /// Короткая сводка для баннера: «7 серверов · +2 · −1» либо «без изменений».
  ///
  /// Локализованную версию строит UI — `syncSummary` в
  /// `core/i18n/enum_labels.dart`: плюрализация зависит от языка, а модель
  /// не имеет доступа к `AppLocalizations`. Здесь остаётся русский фолбэк
  /// для логов и отчёта поддержки, которые принципиально не переводятся.
  String get summary {
    final parts = <String>['$total ${_plural(total)}'];
    if (added.isNotEmpty) parts.add('+${added.length}');
    if (removed.isNotEmpty) parts.add('−${removed.length}');
    if (!hasChanges) parts.add('без изменений');
    return parts.join(' · ');
  }

  static String _plural(int n) {
    final n100 = n % 100, n10 = n % 10;
    if (n100 >= 11 && n100 <= 14) return 'серверов';
    if (n10 == 1) return 'сервер';
    if (n10 >= 2 && n10 <= 4) return 'сервера';
    return 'серверов';
  }
}
