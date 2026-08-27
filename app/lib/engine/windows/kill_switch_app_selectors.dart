import '../../core/settings/split_tunnel.dart';

/// Чистый классификатор правил приложений для плана kill switch.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ТИП. `AppRule.byName` решает, ПО ЧЕМУ сопоставлять
/// процесс — по имени файла или по полному пути. Раньше движок клал в план
/// только `r.path` независимо от `byName`, и правило «по имени» на деле
/// сопоставлялось помощником по полному пути — то есть не срабатывало после
/// обновления программы (см. `AppRule.matchKey`). Здесь то же самое различие
/// применяется к плану блокировки: имя и путь — разные списки, смешивать их
/// нельзя.
class KillSwitchAppSelectors {
  /// Полные пути программ, которые блокировать (или пускать через VPN).
  final List<String> blockedAppPaths;

  /// Имена файлов программ (без пути) из блокирующих правил.
  final List<String> blockedAppNames;

  /// Полные пути программ, которым разрешён прямой доступ мимо блокировки.
  final List<String> allowedAppPaths;

  /// Имена файлов программ из разрешающих правил.
  final List<String> allowedAppNames;

  const KillSwitchAppSelectors({
    this.blockedAppPaths = const [],
    this.blockedAppNames = const [],
    this.allowedAppPaths = const [],
    this.allowedAppNames = const [],
  });

  /// Строит селекторы из настроек раздельного туннелирования.
  ///
  /// ⚠️ РЕЖИМ РЕШАЕТ, КАКОЙ СПИСОК ЗАПОЛНЯТЬ. `onlySelected` — блокируется всё,
  /// кроме отмеченных «Туннель»; в план идут именно они (`blocked*`).
  /// `exceptSelected` — блокируется всё, кроме отмеченных «Прямо»; в план идут
  /// они же, но как разрешённые (`allowed*`), потому что общий блок иначе
  /// отобрал бы у них ту прямую связь, которую попросил пользователь. Режим
  /// `all` — блокировка не различает приложения (`blockAll`), поэтому app
  /// selectors в неё не включаются вовсе.
  factory KillSwitchAppSelectors.fromSplitTunnel(SplitTunnelConfig config) {
    final blockedPaths = <String>[];
    final blockedNames = <String>[];
    final allowedPaths = <String>[];
    final allowedNames = <String>[];

    switch (config.mode) {
      case SplitMode.onlySelected:
        for (final r in config.apps) {
          if (!r.enabled || r.action != AppAction.tunnel) continue;
          if (r.byName) {
            if (r.name.isNotEmpty) blockedNames.add(r.name);
          } else {
            if (r.path.isNotEmpty) blockedPaths.add(r.path);
          }
        }
        break;
      case SplitMode.exceptSelected:
        for (final r in config.apps) {
          if (!r.enabled || r.action != AppAction.direct) continue;
          if (r.byName) {
            if (r.name.isNotEmpty) allowedNames.add(r.name);
          } else {
            if (r.path.isNotEmpty) allowedPaths.add(r.path);
          }
        }
        break;
      case SplitMode.all:
        // Блокировка не выбирает приложения — действует blockAll.
        break;
    }

    return KillSwitchAppSelectors(
      blockedAppPaths: blockedPaths,
      blockedAppNames: blockedNames,
      allowedAppPaths: allowedPaths,
      allowedAppNames: allowedNames,
    );
  }
}
