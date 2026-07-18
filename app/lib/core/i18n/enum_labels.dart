import '../../l10n/gen/app_localizations.dart';
import '../settings/split_tunnel.dart';

/// Локализованные подписи enum-моделей. Сами модели держат русский фолбэк в
/// `.label` (для не-UI мест и диагностики); в интерфейсе используем эти хелперы
/// с `AppLocalizations`, чтобы подписи переводились.

String splitModeLabel(AppLocalizations l, SplitMode m) {
  switch (m) {
    case SplitMode.all:
      return l.enumSplitAll;
    case SplitMode.onlySelected:
      return l.enumSplitOnly;
    case SplitMode.exceptSelected:
      return l.enumSplitExcept;
  }
}

String appActionLabel(AppLocalizations l, AppAction a) {
  switch (a) {
    case AppAction.tunnel:
      return l.enumActionTunnel;
    case AppAction.direct:
      return l.enumActionDirect;
    case AppAction.block:
      return l.enumActionBlock;
  }
}
