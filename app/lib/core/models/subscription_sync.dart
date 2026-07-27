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

  final DateTime at;

  const SubscriptionSyncResult({
    required this.total,
    required this.added,
    required this.removed,
    required this.withPanelConfig,
    required this.panelProfiles,
    required this.at,
  });

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

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
