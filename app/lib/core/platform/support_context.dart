/// Данные о подключении для отчёта поддержки — заполняет UI (у него есть
/// `AppState`). Держим их отдельно, чтобы генератор не тянул зависимость
/// на state, а UI — на платформенную реализацию генератора.
class SupportContext {
  final String statusLine; // «Подключено» / «Отключено» и т.п.
  final String? subscriptionUrl; // будет замаскирован
  final int serverCount;
  final String activeServer; // имя выбранного сервера (без секретов)
  final String activeCore; // Xray / sing-box

  /// Локализованная «шапка» отчёта (заголовок + место под описание проблемы +
  /// поля + примечание). Собирается в UI из `AppLocalizations` — только эта часть
  /// переводится; техническая информация ниже остаётся как есть (единый язык
  /// для разбора обращений).
  final String header;

  const SupportContext({
    required this.statusLine,
    required this.subscriptionUrl,
    required this.serverCount,
    required this.activeServer,
    required this.activeCore,
    required this.header,
  });
}
