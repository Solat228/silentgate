import '../core/models/server_override.dart';
import '../core/models/subscription_profile.dart';
import '../core/models/vpn_server.dart';
import '../data/panel_outbounds_store.dart';

/// Всё, что унесло удаление подписки, — для кнопки «Восстановить» в
/// уведомлении об удалении.
///
/// ⚠️ ХРАНИМ ТОЛЬКО УБЫВШЕЕ, А НЕ КОПИЮ ВСЕГО СОСТОЯНИЯ. За десять секунд,
/// пока висит уведомление, человек успевает закрепить сервер или поправить
/// JSON у другого; восстановление полной копией молча откатило бы и эти
/// правки. Поэтому возвращается ровно то, чего после удаления не стало, и
/// только если его не вернули другим путём (например, повторным импортом той
/// же ссылки).
class DeletedSubscription {
  /// Сам профиль — с логотипом, карточкой и ссылками серверов.
  final SubscriptionProfile profile;

  /// Место профиля в списке: порядок подписок — данные, а не сортировка, и
  /// восстановленная должна встать туда, где была.
  final int index;

  /// Была ли она открыта: тогда восстановление переключает обратно на неё.
  final bool wasActive;

  /// Какой сервер был выбран (ключ) — только для открытой подписки.
  final String? selectedKey;

  /// Снятые закрепления: позиция в списке закреплённых и сам сервер.
  final List<(int, VpnServer)> pinned;

  /// Источник снятых закреплений (ссылка → id подписки).
  final Map<String, String> pinnedSource;

  /// Снятые ручные правки серверов.
  final Map<String, ServerOverride> overrides;

  /// Убранные конфиги панели (профили «Авто …» восстанавливаются только из
  /// них — без конфига такой профиль после перезапуска пропал бы).
  final Map<String, PanelConfig> panelConfigs;

  const DeletedSubscription({
    required this.profile,
    required this.index,
    required this.wasActive,
    required this.selectedKey,
    required this.pinned,
    required this.pinnedSource,
    required this.overrides,
    required this.panelConfigs,
  });
}
